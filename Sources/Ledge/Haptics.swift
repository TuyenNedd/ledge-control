import AppKit

/// One tick of the trackpad's haptic engine per emitted step.
///
/// Uses `NSHapticFeedbackManager` with the `.generic` pattern, which produces a distinct
/// click through the Mac's Taptic Engine (Force Touch trackpad). The previous implementation
/// used `CoreHaptics` (`CHHapticEngine`), which is designed for iPhone/Watch haptic motors
/// and does NOT produce trackpad haptics on MacBooks — it requires a different hardware path.
///
/// `NSHapticFeedbackManager.defaultPerformer.perform(_:performanceTime:)` talks to the
/// trackpad's actuator directly and is the documented way to produce haptic feedback on Mac.
///
/// UNVERIFIED: whether `.generic` fires for an `.accessory` (LSUIElement) app that is never
/// the active application. Apple's documentation does not explicitly state an activation
/// requirement for `NSHapticFeedbackManager`. If haptics are still absent on-device, the
/// fallback would be the private `MTActuator` API via MultitouchSupport.framework.
final class Haptics {
    private let preferences: Preferences

    /// How many haptic pulses have been fired since launch. Diagnostics only.
    private(set) var pulseCount: Int = 0

    init(preferences: Preferences) {
        self.preferences = preferences
    }

    /// Pulse once, unless the user has turned haptics off.
    ///
    /// The preference is read here rather than mirrored into a stored flag, so there is no second
    /// copy to keep in sync with the menu.
    func pulse() {
        guard preferences.hapticsEnabled else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(
            .generic,
            performanceTime: .now
        )
        pulseCount += 1
    }
}
