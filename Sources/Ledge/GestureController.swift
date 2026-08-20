import AppKit
import CoreGraphics
import Foundation
import LedgeCore

/// Joins the touch source to the system controls, and owns the one `GestureEngine`.
///
/// This is a wire, not a brain. It contains no thresholds and makes no judgement about what the
/// user meant -- every such decision was made in `LedgeCore` and arrives here as a
/// `GestureEvent`. The `switch`es below translate vocabulary; if a threshold or a heuristic ever
/// appears in this file, it is in the wrong layer.
///
/// Four contracts from `GestureEngine`'s documentation are honoured here, and each would produce
/// a bug no test could catch if it were not:
///
/// 1. **One clock.** Both `receive(_:)` and `receiveTyping(at:)` take their time from
///    `NSEvent.timestamp`, supplied by `EventTapTouchSource`. Nothing in this file reads a clock.
/// 2. **Every return value is forwarded.** `process`, `noteTyping`, `setEnabled` and `cancel` all
///    return events and all can emit `.disengaged`; each call site here routes the result through
///    `apply(_:)`, so an open control cannot be leaked.
/// 3. **Frames arrive in order,** because the tap is on the main run loop and this object is only
///    ever touched from there.
/// 4. **The engine is a `var` held in one place** and mutated in place -- never copied into a
///    local, never passed to anything.
final class GestureController {
    private var engine: GestureEngine

    private let preferences: Preferences
    private let touchSource: TouchSource
    private let brightness: BrightnessController
    private let mediaKeyVolume: VolumeAdjusting
    private let coreAudioVolume: VolumeAdjusting

    /// Which edge a gesture currently owns, if any. Maintained purely by pairing the engine's
    /// `.engaged`/`.disengaged` events, which the engine guarantees come in pairs.
    private(set) var engagedEdge: TrackpadEdge?

    /// Which action the current gesture is driving, if any.
    private(set) var engagedAction: EdgeAction?

    /// Called on the main thread whenever the engagement state transitions.
    /// `true` means a gesture just engaged; `false` means it just disengaged.
    var onEngagementChanged: ((Bool) -> Void)?

    /// The most recent frame, and how many have arrived. Diagnostics only -- nothing in the
    /// gesture path reads these, and the frame counter is what distinguishes "no touches" from
    /// "no events arriving at all", which are the two failure modes that look identical.
    private(set) var lastFrame: TouchFrame?
    private(set) var frameCount = 0
    private(set) var stepCount = 0

    /// Tracks the previously frontmost app's bundle ID so we know when we leave an excluded app.
    private var previousFrontmostBundleID: String?
    /// The exclusion list, derived from preferences.
    private var exclusionList: AppExclusionList

    init(preferences: Preferences, touchSource: TouchSource) {
        self.preferences = preferences
        self.touchSource = touchSource
        self.brightness = BrightnessController()
        self.mediaKeyVolume = VolumeController()
        self.coreAudioVolume = CoreAudioVolumeController()
        self.engine = GestureEngine(settings: preferences.gestureSettings)
        self.exclusionList = AppExclusionList(bundleIDs: preferences.excludedApps)
    }

    /// - Returns: false if the touch source could not start, which means Accessibility permission
    ///   has not been granted.
    func start() -> Bool {
        touchSource.onFrame = { [weak self] frame in self?.receive(frame) }
        touchSource.onTyping = { [weak self] timestamp in self?.receiveTyping(at: timestamp) }
        touchSource.onInterrupted = { [weak self] in self?.interrupt() }
        touchSource.onModifierChanged = { [weak self] held in self?.receiveModifierChanged(held) }
        applyPreferences()

        // Observe frontmost app changes for per-app exclusion.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(frontmostAppChanged(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        return touchSource.start()
    }

    func stop() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        interrupt()
        touchSource.stop()
    }

    /// Re-read every preference into the engine and the touch source.
    ///
    /// Called after any menu change. Cheap enough to do wholesale, which avoids a per-toggle
    /// update path that could forget a field.
    func applyPreferences() {
        engine.settings = preferences.gestureSettings
        touchSource.cursorFreezeEnabled = preferences.cursorFreezeEnabled
        touchSource.requiredModifierKey = preferences.modifierKeyRequired
        exclusionList = AppExclusionList(bundleIDs: preferences.excludedApps)
        // Forwarded because switching off ends a gesture in flight, and that has to reach the
        // haptics and the cursor-freeze flag. Switching on returns nothing, so re-asserting the
        // current state is harmless.
        apply(engine.setEnabled(preferences.isEnabled))
    }

    private func receive(_ frame: TouchFrame) {
        lastFrame = frame
        frameCount += 1
        apply(engine.process(frame: frame))
    }

    private func receiveTyping(at timestamp: Double) {
        apply(engine.noteTyping(at: timestamp))
    }

    private func receiveModifierChanged(_ held: Bool) {
        apply(engine.setModifierHeld(held))
    }

    /// The world changed underneath us -- the tap was disabled and re-enabled, so frames were
    /// missed. `cancel()` rather than `setEnabled(false)`, because the engine should still be
    /// listening for the next gesture.
    private func interrupt() {
        apply(engine.cancel())
    }

    /// Called when the frontmost application changes. Disables gesture detection for excluded
    /// apps and re-enables it when switching away from one.
    @objc private func frontmostAppChanged(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        let newBundleID = app.bundleIdentifier

        let wasExcluded = exclusionList.isExcluded(previousFrontmostBundleID)
        let isExcluded = exclusionList.isExcluded(newBundleID)
        previousFrontmostBundleID = newBundleID

        if isExcluded && !wasExcluded {
            apply(engine.setEnabled(false))
        } else if !isExcluded && wasExcluded {
            // Restore the user's preference rather than unconditionally enabling.
            if preferences.isEnabled {
                apply(engine.setEnabled(true))
            }
        }
    }

    private func apply(_ events: [GestureEvent]) {
        for event in events {
            switch event {
            case .engaged(let edge, let action):
                engagedEdge = edge
                engagedAction = action
                onEngagementChanged?(true)
                if preferences.cursorFreezeEnabled {
                    // Save the current cursor position in CG coordinates (top-left origin).
                    touchSource.savedCursorPosition = CGEvent(source: nil)?.location ?? .zero
                }
            case .disengaged:
                touchSource.savedCursorPosition = nil
                engagedEdge = nil
                engagedAction = nil
                onEngagementChanged?(false)
            case .step(let edge, let action, let direction):
                perform(action, direction)
                stepCount += 1
            }
        }
        // Pushed rather than pulled so the tap callback does not have to reach back into the
        // engine on the hot path.
        touchSource.isGestureEngaged = engagedEdge != nil
    }

    /// Dispatch the appropriate system action for the given `EdgeAction` and direction.
    ///
    /// Each action is a direct translation from the engine's vocabulary into the OS-level call.
    /// The engine has already decided a step is due and which way it goes.
    private func perform(_ action: EdgeAction, _ direction: StepDirection) {
        let fine = engine.settings.fineControl
        switch action {
        case .volume:
            volumeBackend.adjust(direction, fine: fine)

        case .brightness:
            brightness.adjust(direction, fine: fine)
            // After DisplayServices sets the brightness, post a brightness media key event.
            // This may trigger the native brightness indicator on macOS 26 Tahoe.
            // UNVERIFIED: if this does not produce a native indicator, a custom HUD may need
            // to be restored.
            let key: MediaKey = direction == .up ? .brightnessUp : .brightnessDown
            MediaKeySender.post(key, fine: fine)

        case .zoom:
            // Synthesize Cmd+Plus (zoom in) or Cmd+Minus (zoom out) via CGEvent.
            // UNVERIFIED: CGEvent key code 24 is '=' (which becomes '+' with Shift on US layout),
            // key code 27 is '-'. Using Cmd flag only (no Shift) as Cmd+= is treated as zoom in
            // by most apps, same as Cmd+Plus.
            let keyCode: UInt16 = direction == .up ? 24 : 27  // '=' for zoom in, '-' for zoom out
            synthesizeKeyPress(keyCode: keyCode, flags: .maskCommand)

        case .nextPreviousTrack:
            // Synthesize media key NX_KEYTYPE_NEXT (key code 17) or NX_KEYTYPE_PREVIOUS (key code 18).
            // UNVERIFIED: These NX_KEYTYPE constants may differ across macOS versions. The values
            // 17 and 18 come from IOKit/hidsystem/ev_keymap.h.
            let mediaKey = direction == .up ? MediaKeyForTransport.next : MediaKeyForTransport.previous
            MediaKeyForTransport.post(mediaKey)

        case .scroll:
            // Synthesize scroll wheel events via CGEvent.
            // UNVERIFIED: The scroll delta value may need tuning for comfortable scrolling speed.
            let delta: Int32 = direction == .up ? 3 : -3
            synthesizeScrollEvent(deltaY: delta)

        case .none:
            // No-op: edge is configured to do nothing.
            break
        }
    }

    /// Synthesize a key press event with the given key code and modifier flags.
    ///
    /// UNVERIFIED: CGEvent(keyboardEventSource:virtualKey:keyDown:) behavior with specific
    /// modifier flags on all macOS versions.
    private func synthesizeKeyPress(keyCode: UInt16, flags: CGEventFlags) {
        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
        else { return }
        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    /// Synthesize a scroll wheel event with the given vertical delta.
    ///
    /// UNVERIFIED: CGEvent(scrollWheelEvent2Source:...) availability and behavior across macOS
    /// versions. Using `.line` units for discrete scroll steps.
    private func synthesizeScrollEvent(deltaY: Int32) {
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 1,
            wheel1: deltaY,
            wheel2: 0,
            wheel3: 0
        ) else { return }
        event.post(tap: .cghidEventTap)
    }

    /// Which volume implementation is in force. A preference lookup, not a decision about
    /// behaviour -- both backends do the same job with different trade-offs.
    private var volumeBackend: VolumeAdjusting {
        preferences.useCoreAudioVolume ? coreAudioVolume : mediaKeyVolume
    }

    // MARK: - Diagnostics

    var isTapEnabled: Bool { touchSource.isTapEnabled }
    /// Events of every type the tap has delivered. Read next to `frameCount`, the two of them
    /// separate "the tap is dead" from "the tap works but gesture events never arrive".
    var eventCount: Int { touchSource.eventCount }
    var isBrightnessAvailable: Bool { brightness.isAvailable }
    var isUsingCoreAudioVolume: Bool { preferences.useCoreAudioVolume }
    var isCursorLocked: Bool { engagedEdge != nil && preferences.cursorFreezeEnabled }

    func currentVolumeScalar() -> Float? { volumeBackend.currentScalar() }
    func currentBrightness() -> Float? { brightness.currentBrightness() }
}

// MARK: - Media Key for Transport Controls

/// Synthesizes transport media key events (next/previous track) via NSEvent system-defined events.
///
/// Uses the same mechanism as `MediaKeySender` but for transport control keys rather than
/// volume/brightness keys.
///
/// UNVERIFIED: NX_KEYTYPE_NEXT = 17 and NX_KEYTYPE_PREVIOUS = 18 values from
/// IOKit/hidsystem/ev_keymap.h. These are not modularized for Swift import.
private enum MediaKeyForTransport {
    static let next = 17
    static let previous = 18

    private static let auxControlButtonsSubtype: Int16 = 8
    private static let keyDownState = 0x0A00
    private static let keyUpState = 0x0B00

    /// Post one complete press (down + up) for a transport media key.
    static func post(_ key: Int) {
        send(key, isDown: true)
        send(key, isDown: false)
    }

    private static func send(_ key: Int, isDown: Bool) {
        let data1 = (key << 16) | (isDown ? keyDownState : keyUpState)
        // UNVERIFIED: NSEvent.otherEvent construction for transport keys may behave differently
        // than volume/brightness keys on some macOS versions.
        guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: auxControlButtonsSubtype,
            data1: data1,
            data2: -1
        ) else { return }
        event.cgEvent?.post(tap: .cghidEventTap)
    }
}
