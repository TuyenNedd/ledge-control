import CoreGraphics
import Foundation
import LedgeCore

/// Joins the touch source to the system controls, and owns the one `GestureEngine`.
///
/// This is a wire, not a brain. It contains no thresholds and makes no judgement about what the
/// user meant — every such decision was made in `LedgeCore` and arrives here as a
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
/// 4. **The engine is a `var` held in one place** and mutated in place — never copied into a
///    local, never passed to anything.
final class GestureController {
    private var engine: GestureEngine

    private let preferences: Preferences
    private let touchSource: TouchSource
    private let haptics: Haptics
    private let brightness: BrightnessController
    private let brightnessHUD: BrightnessHUD
    private let mediaKeyVolume: VolumeAdjusting
    private let coreAudioVolume: VolumeAdjusting

    /// Which control a gesture currently owns, if any. Maintained purely by pairing the engine's
    /// `.engaged`/`.disengaged` events, which the engine guarantees come in pairs.
    private(set) var engagedControl: Control?

    /// The most recent frame, and how many have arrived. Diagnostics only — nothing in the
    /// gesture path reads these, and the frame counter is what distinguishes "no touches" from
    /// "no events arriving at all", which are the two failure modes that look identical.
    private(set) var lastFrame: TouchFrame?
    private(set) var frameCount = 0
    private(set) var stepCount = 0

    init(preferences: Preferences, touchSource: TouchSource) {
        self.preferences = preferences
        self.touchSource = touchSource
        self.haptics = Haptics(preferences: preferences)
        self.brightness = BrightnessController()
        self.brightnessHUD = BrightnessHUD()
        self.mediaKeyVolume = VolumeController()
        self.coreAudioVolume = CoreAudioVolumeController()
        self.engine = GestureEngine(settings: preferences.gestureSettings)
    }

    /// - Returns: false if the touch source could not start, which means Accessibility permission
    ///   has not been granted.
    func start() -> Bool {
        touchSource.onFrame = { [weak self] frame in self?.receive(frame) }
        touchSource.onTyping = { [weak self] timestamp in self?.receiveTyping(at: timestamp) }
        touchSource.onInterrupted = { [weak self] in self?.interrupt() }
        applyPreferences()
        return touchSource.start()
    }

    func stop() {
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

    /// The world changed underneath us — the tap was disabled and re-enabled, so frames were
    /// missed. `cancel()` rather than `setEnabled(false)`, because the engine should still be
    /// listening for the next gesture.
    private func interrupt() {
        apply(engine.cancel())
    }

    private func apply(_ events: [GestureEvent]) {
        for event in events {
            switch event {
            case .engaged(let control):
                engagedControl = control
                if preferences.cursorFreezeEnabled {
                    CGAssociateMouseAndMouseCursorPosition(0)
                }
            case .disengaged:
                engagedControl = nil
                if preferences.cursorFreezeEnabled {
                    CGAssociateMouseAndMouseCursorPosition(1)
                }
            case .step(let control, let direction):
                perform(control, direction)
                stepCount += 1
                haptics.pulse()
            }
        }
        // Pushed rather than pulled so the tap callback does not have to reach back into the
        // engine on the hot path.
        touchSource.isGestureEngaged = engagedControl != nil
    }

    private func perform(_ control: Control, _ direction: StepDirection) {
        // Read per step rather than captured at engagement. `GestureEngine` snapshots its
        // settings for the life of a gesture, so a mid-slide menu change cannot alter how *often*
        // a step fires — but it can alter how big the OS considers that step, for the remainder of
        // the slide. Not worth a mechanism: changing a menu item requires using the trackpad,
        // which has already ended the gesture.
        let fine = engine.settings.fineControl
        switch control {
        case .volume: volumeBackend.adjust(direction, fine: fine)
        case .brightness:
            brightness.adjust(direction, fine: fine)
            if let level = brightness.currentBrightness() {
                brightnessHUD.show(brightness: level)
            }
        }
    }

    /// Which volume implementation is in force. A preference lookup, not a decision about
    /// behaviour — both backends do the same job with different trade-offs.
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
    var isCursorLocked: Bool { engagedControl != nil && preferences.cursorFreezeEnabled }
    var hapticPulseCount: Int { haptics.pulseCount }
    var brightnessHUDShowCount: Int { brightnessHUD.showCount }

    func currentVolumeScalar() -> Float? { volumeBackend.currentScalar() }
    func currentBrightness() -> Float? { brightness.currentBrightness() }
}
