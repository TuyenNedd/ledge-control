import AppKit

/// One tick of the trackpad's haptic engine per emitted step.
///
/// `.alignment` is the lightest pattern available — the one the OS uses when a dragged guide
/// snaps. `GestureEngine` already emits exactly one `.step` per step, so this does no arithmetic
/// and no coalescing: pulse count and step count are the same number by construction.
final class Haptics {
    private let preferences: Preferences

    init(preferences: Preferences) {
        self.preferences = preferences
    }

    /// Pulse once, unless the user has turned haptics off.
    ///
    /// The preference is read here rather than mirrored into a stored flag, so there is no second
    /// copy to keep in sync with the menu.
    func pulse() {
        guard preferences.hapticsEnabled else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}
