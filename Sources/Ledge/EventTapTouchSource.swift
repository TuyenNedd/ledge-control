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

    /// How many events of *any* type the source has been handed. Diagnostics only — nothing in
    /// the gesture path reads it.
    ///
    /// Separate from the gesture-frame count on purpose: with an all-events tap, a total stuck at
    /// zero and a total climbing while no gesture frame ever arrives are completely different
    /// failures (dead tap versus gesture events not being delivered) that are indistinguishable
    /// from a gesture-frame counter alone.
    var eventCount: Int { get }

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

    /// Counts every event the callback is handed, whatever its type. An `Int` increment on the
    /// hot path, which is the whole of the cost the all-events mask adds to types we ignore.
    private(set) var eventCount = 0

    /// `NSEventTypeGesture` — event type 29.
    ///
    /// Taken from AppKit rather than written as a bare `29`, because AppKit *does* have a name for
    /// it (`NSEvent.EventType.gesture`) even though `CGEventType` does not:
    /// `CGEventType(rawValue: 29)` returns nil, so the value can neither be spelled as a
    /// `CGEventType` case nor matched in a `switch` over one. Every type comparison below
    /// therefore goes through `rawValue`, uniformly, rather than mixing enum cases and numbers.
    ///
    /// UNVERIFIED: that a session event tap is handed type-29 events at all. Holding this value in
    /// a `CGEventType` parameter is not the risk — `CGEventType` is imported from a non-frozen C
    /// enum, so it can carry a value with no matching case and `.rawValue` is only a load. The
    /// risk is upstream of that, in `eventMask`: if a finger touches the trackpad and *nothing*
    /// happens — no frames, no touch count, no steps — suspect the mask and the tap's willingness
    /// to deliver this type, not this constant.
    private static let gestureEventTypeRaw = UInt32(NSEvent.EventType.gesture.rawValue)

    /// Every event in the session, filtered by type inside `handle(type:event:)`.
    ///
    /// A deliberate retreat from a narrow, per-type mask. Subscribing by bit — including bit 29
    /// for gesture events — is reported to have stopped being honoured for gesture types around
    /// OS X 10.8: the tap is created successfully and delivers the ordinary types, but the gesture
    /// bit is silently ignored and no gesture event ever arrives. Since *everything* this app does
    /// is downstream of receiving type 29, a mask that might drop it is not a trade worth making,
    /// and the approach known to work is to tap all events and discriminate in the callback.
    ///
    /// Written as `~CGEventMask(0)` rather than `kCGEventMaskForAllEvents`, which is a
    /// cast-bearing C macro and so is unlikely to import into Swift at all.
    ///
    /// The cost is that every event in the session — every mouse move, every keystroke — reaches
    /// `handle(type:event:)`. That is why its `default:` branch does nothing but return the event
    /// it was given: no allocation, no bridging to `NSEvent`, no engine contact.
    ///
    /// UNVERIFIED, and the loudest assumption in the app: that a `CGEvent` tap delivers gesture
    /// events (type 29) *at all*, with an all-events mask or any other. If it does not, no
    /// arrangement of this mask helps and the private `MultitouchSupport.framework` is the only
    /// remaining route — see `docs/DESIGN.md`. The diagnostics window distinguishes this case from
    /// the tap being dead outright: total events climbing while gesture frames stay at zero.
    private static let eventMask: CGEventMask = ~CGEventMask(0)

    // The narrow mask this replaced, kept because it is the thing to try if an all-events tap
    // turns out to be too expensive — a callback on every mouse move is real work, and if the tap
    // starts being disabled by timeout under load (watch for `onInterrupted` firing repeatedly),
    // this is the first thing to put back. It is only worth trying together with a check that
    // gesture events still arrive; the whole reason it was abandoned is that they may not.
    //
    // private static let eventMask: CGEventMask = EventTapTouchSource.mask(forTypes: [
    //     EventTapTouchSource.gestureEventTypeRaw,
    //     CGEventType.keyDown.rawValue,
    //     CGEventType.flagsChanged.rawValue,
    //     CGEventType.mouseMoved.rawValue,
    //     CGEventType.leftMouseDragged.rawValue,
    // ])
    //
    // private static func mask(forTypes types: [UInt32]) -> CGEventMask {
    //     types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1)) }
    // }

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
        // Every event in the session reaches here, because `eventMask` subscribes to all of them.
        // Counted before anything else so the total is honest even for types handled below.
        eventCount += 1

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
            // Everything else in the session, which since the mask widened to all events means
            // most of what the machine does: scroll wheels, mouse buttons, tablet proximity,
            // `.systemDefined` — including the media keys this app itself posts, which is the
            // only reason posting them cannot feed back into the engine (see `MediaKeySender`).
            //
            // Deliberately allocation-free: one `Unmanaged.passUnretained`, which is a pointer
            // bitcast and nothing else. No `NSEvent(cgEvent:)` bridging, no array, no engine
            // contact. This branch is now on the path of every event in the session, and a tap
            // callback that is slow gets the tap disabled by timeout.
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
            // Two normalisations of what the OS means by "a touch", neither of them a decision:
            //
            // `.indirect` is a trackpad; `.direct` is a touchscreen. Filtering rather than
            // asserting because a Sidecar iPad can put `.direct` touches into the same stream.
            //
            // `.touching` — began, moved, stationary — is the set of phases in which a finger is
            // actually on the glass. AppKit keeps reporting a touch for the frame in which it
            // *ends*, with `.ended` or `.cancelled`, so without this filter the frame at lift
            // still contains one touch and `LedgeCore` never sees the empty frame that is its
            // normal signal that the finger left. Consequence, before the filter existed: a
            // gesture stayed engaged after lift until the stale-gesture timeout happened to fire,
            // and while engaged the tap kept deleting `mouseMoved` — so lifting a finger and
            // reaching for an external mouse left the pointer frozen.
            //
            // This belongs here and not in `LedgeCore`: it is a statement about AppKit's
            // vocabulary — a finger that has left is not a touch — not a judgement about what the
            // user meant. `LedgeCore` is entitled to assume a frame lists fingers currently down.
            //
            // UNVERIFIED: that a lifted finger is therefore absent from the frame this produces.
            // The claim rests on `NSTouch.phase` being `.ended`/`.cancelled` for exactly that
            // touch and on `NSTouch.Phase.touching` containing precisely began/moved/stationary.
            // How to tell: rest one finger on the trackpad, then lift it, and watch *Touch count*
            // in the diagnostics window. It must return to 0 promptly on lift. If it sticks at 1,
            // this filter is not doing what it claims and cursor freeze will strand the pointer.
            .filter { $0.type == .indirect && NSTouch.Phase.touching.contains($0.phase) }
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
