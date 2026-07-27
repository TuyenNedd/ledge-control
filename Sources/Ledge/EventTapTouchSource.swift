import AppKit
import CoreGraphics
import Foundation
import LedgeCore

/// Somewhere touch frames come from.
///
/// A protocol for one reason only: `docs/DESIGN.md` rejects the private
/// `MultitouchSupport.framework` in favour of a public event tap, but records that if the tap
/// turns out not to deliver single-finger touches then the private route becomes necessary. This
/// is the seam that substitution would happen at, so that discovery costs one new file rather
/// than a rewrite of everything downstream.
protocol TouchSource: AnyObject {
    /// One frame per gesture event observed. Timestamps are on the `NSEvent.timestamp` clock,
    /// which is what `LedgeCore` requires — see `TouchFrame.timestamp`.
    var onFrame: ((TouchFrame) -> Void)? { get set }
    /// A keystroke was observed, at the same clock. Feeds `GestureEngine.noteTyping(at:)`.
    var onTyping: ((Double) -> Void)? { get set }
    /// Input delivery was interrupted and any gesture in flight is no longer trustworthy.
    var onInterrupted: (() -> Void)? { get set }

    /// Whether a gesture currently owns a control. Written by `GestureController`; read only to
    /// decide whether to swallow pointer movement.
    var isGestureEngaged: Bool { get set }
    /// Whether swallowing pointer movement during a gesture is wanted at all.
    var cursorFreezeEnabled: Bool { get set }

    /// Whether the tap exists and is live. Diagnostics reads this.
    var isTapEnabled: Bool { get }

    /// - Returns: false if the tap could not be created, which in practice means Accessibility
    ///   permission has not been granted.
    func start() -> Bool
    func stop()
}

/// Reads trackpad touches out of a session-level `CGEvent` tap.
///
/// **The single highest-risk component in the app.** Every other part is judged by whether it
/// does the right thing; this one is judged by whether it produces anything at all. If gesture
/// events do not carry single-finger touch data, nothing downstream matters — which is why the
/// diagnostics window exists and why on-device checklist item 1 comes first.
///
/// The tap is attached to the **main** run loop, so every callback — and therefore every
/// mutation of the `GestureEngine` downstream — happens on the main thread. That is what makes
/// the engine's "one owner, no copies, frames in order" contract hold without any locking.
final class EventTapTouchSource: TouchSource {
    var onFrame: ((TouchFrame) -> Void)?
    var onTyping: ((Double) -> Void)?
    var onInterrupted: (() -> Void)?

    var isGestureEngaged = false
    var cursorFreezeEnabled = true

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// `NSEventTypeGesture`.
    ///
    /// Kept as a raw number because `CGEventType` has no case for it — `CGEventType(rawValue: 29)`
    /// returns nil — so it can neither be named nor matched in a `switch` over `CGEventType`.
    /// Every type comparison below therefore goes through `rawValue`, uniformly, rather than
    /// mixing enum cases and numbers.
    ///
    /// UNVERIFIED: this relies on a `CGEventType` parameter being able to *hold* a value with no
    /// corresponding case. Every event tap in the wild does exactly this, and `.rawValue` is only
    /// a load, but if the app traps the instant a finger touches the trackpad, this is the first
    /// place to look.
    private static let gestureEventTypeRaw: UInt32 = 29

    private static let eventMask: CGEventMask = EventTapTouchSource.mask(forTypes: [
        EventTapTouchSource.gestureEventTypeRaw,
        CGEventType.keyDown.rawValue,
        CGEventType.flagsChanged.rawValue,
        CGEventType.mouseMoved.rawValue,
        CGEventType.leftMouseDragged.rawValue,
    ])

    private static func mask(forTypes types: [UInt32]) -> CGEventMask {
        types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1)) }
    }

    var isTapEnabled: Bool {
        guard let tap else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }

    func start() -> Bool {
        guard tap == nil else { return true }

        // Unretained on purpose: the tap's lifetime is bounded by this object's, since `stop()`
        // and `deinit` both tear it down. Retaining self here would make the pair immortal.
        let context = Unmanaged.passUnretained(self).toOpaque()

        // `.defaultTap` — not `.listenOnly` — because cursor freeze needs the ability to swallow
        // pointer movement. That is the only thing this tap ever suppresses.
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: Self.eventMask,
            callback: ledgeEventTapCallback,
            userInfo: context
        ) else {
            // Overwhelmingly the "not trusted for Accessibility" case. `Permissions` is what the
            // caller should consult; there is nothing more specific to learn here.
            return false
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        // Detached from the run loop first, so no callback can be in flight by the time the port
        // is invalidated.
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        runLoopSource = nil
        tap = nil
    }

    deinit {
        stop()
    }

    /// The whole of the tap's per-event behaviour.
    ///
    /// Reached from the C callback via the `userInfo` pointer, because a C function pointer
    /// cannot capture. `fileprivate` rather than `private` for exactly that reason: the callback
    /// is a file-scope value, not a member, so `private` would put this out of its reach.
    ///
    /// - Returns: the event to let through, or nil to swallow it.
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type.rawValue {
        case CGEventType.tapDisabledByTimeout.rawValue,
             CGEventType.tapDisabledByUserInput.rawValue:
            // macOS disables a tap that took too long in a callback, or that the user
            // interrupted. Re-enabling is not optional: without it the app goes silently and
            // permanently deaf after one hiccup, presents no symptom other than "it stopped
            // working", and is miserable to diagnose. Whatever gesture was in flight spans the
            // gap and must be abandoned, hence `onInterrupted`.
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            onInterrupted?()
            return nil

        case Self.gestureEventTypeRaw:
            emitFrame(from: event)
            return Unmanaged.passUnretained(event)

        case CGEventType.keyDown.rawValue, CGEventType.flagsChanged.rawValue:
            // `.flagsChanged` counts as typing as well as `.keyDown`, so holding a modifier to
            // use a keyboard shortcut suppresses gestures the same way letters do.
            if let nsEvent = NSEvent(cgEvent: event) {
                onTyping?(nsEvent.timestamp)
            }
            return Unmanaged.passUnretained(event)

        case CGEventType.mouseMoved.rawValue, CGEventType.leftMouseDragged.rawValue:
            // The one thing this tap suppresses, and only while a gesture actually owns a
            // control. Both flags are set from outside — whether a gesture is engaged is the
            // engine's judgement, and whether freezing is wanted is the user's — so there is no
            // decision being made here, only two answers being combined.
            //
            // UNVERIFIED: that deleting these events actually holds the cursor still. A session
            // tap at `.headInsertEventTap` sees them before any application does, but the pointer
            // is moved by WindowServer and it is not certain that a deleted event un-moves it. If
            // the cursor still drifts during a gesture, the fallback is to re-warp it with
            // `CGWarpMouseCursorPosition` to the position captured at engagement — which is
            // heavier, and is why it is not the first attempt.
            let shouldFreeze = isGestureEngaged && cursorFreezeEnabled
            return shouldFreeze ? nil : Unmanaged.passUnretained(event)

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    /// Turn one gesture event into a `TouchFrame`.
    ///
    /// UNVERIFIED, and this is the assumption the whole app rests on: that `NSEvent(cgEvent:)`
    /// succeeds for a type-29 event and that the resulting `NSEvent` answers `allTouches()` with
    /// live trackpad data. On-device checklist item 1 is precisely this check — watch the touch
    /// count and position in the diagnostics window with one finger resting on the trackpad. If
    /// they never move, the public event tap route is dead and `MultitouchSupport` is the
    /// remaining option (see `docs/DESIGN.md`).
    private func emitFrame(from event: CGEvent) {
        guard let nsEvent = NSEvent(cgEvent: event) else { return }

        let touches = nsEvent.allTouches()
            // `.indirect` is a trackpad; `.direct` is a touchscreen. Filtering rather than
            // asserting because a Sidecar iPad can put `.direct` touches into the same stream.
            .filter { $0.type == .indirect }
            .map { touch in
                TouchPoint(
                    // UNVERIFIED: `identity` is documented to be the same object for the life of
                    // one finger, so its hash should be stable across frames — but this is a hash
                    // of an opaque object, not a documented identifier. `LedgeCore` matches
                    // fingers between frames by this id, so if it is *not* stable then arming and
                    // stepping both break in ways no unit test can see: every frame looks like a
                    // new finger. The diagnostics window prints raw ids for this reason. They
                    // must stay constant while a finger stays down.
                    id: touch.identity.hash,
                    position: NormalizedPoint(
                        // `normalizedPosition` is already 0...1 with the origin at the lower
                        // left, which is the convention `NormalizedPoint` documents — so this is
                        // a type change, not a transform. No flipping belongs here.
                        x: Double(touch.normalizedPosition.x),
                        y: Double(touch.normalizedPosition.y)
                    )
                )
            }
            // `allTouches()` returns a Set, whose iteration order varies run to run. Sorting
            // makes the frame reproducible, which matters for reading the diagnostics window
            // without ids jumping around. The engine reads only the count and, for one touch,
            // that touch — it attaches no meaning to order.
            .sorted { $0.id < $1.id }

        // `NSEvent.timestamp` — seconds since boot — is the only clock `LedgeCore` may be fed,
        // and the same one `onTyping` reports. Substituting `Date()` here would break the typing
        // lockout silently, since both are `Double`.
        onFrame?(TouchFrame(timestamp: nsEvent.timestamp, touches: touches))
    }
}

/// The C entry point for the tap.
///
/// A file-scope, non-capturing closure so it converts to a C function pointer. It does nothing
/// but recover the owning object from `userInfo` and hand over; all behaviour lives in
/// `EventTapTouchSource.handle(type:event:)` where it can be read normally.
private let ledgeEventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let source = Unmanaged<EventTapTouchSource>.fromOpaque(userInfo).takeUnretainedValue()
    return source.handle(type: type, event: event)
}
