import CoreHaptics

/// One tick of the trackpad's haptic engine per emitted step.
///
/// Uses `CoreHaptics` (`CHHapticEngine`) rather than `NSHapticFeedbackManager`, because the
/// latter requires the app to be the active application to produce output.  Ledge runs as an
/// `.accessory` (LSUIElement) menu bar app and is never frontmost, so `NSHapticFeedbackManager`
/// silently does nothing.  `CoreHaptics` has no such restriction: it talks directly to the
/// Taptic Engine and fires regardless of activation state.
///
/// The engine is started once and kept alive for the process lifetime.  If something external
/// stops it (e.g. the app enters the background on a device that suspends audio), the
/// `resetHandler` restarts it.
final class Haptics {
    private let preferences: Preferences
    private var engine: CHHapticEngine?

    /// How many haptic pulses have been fired since launch.  Diagnostics only.
    private(set) var pulseCount: Int = 0

    init(preferences: Preferences) {
        self.preferences = preferences
        prepareEngine()
    }

    /// Pulse once, unless the user has turned haptics off.
    ///
    /// The preference is read here rather than mirrored into a stored flag, so there is no second
    /// copy to keep in sync with the menu.
    func pulse() {
        guard preferences.hapticsEnabled else { return }
        fireTransient()
        pulseCount += 1
    }

    // MARK: - Engine lifecycle

    private func prepareEngine() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }

        do {
            let eng = try CHHapticEngine()
            eng.resetHandler = { [weak self] in
                // Called on an arbitrary queue when the engine needs restarting.
                try? self?.engine?.start()
            }
            eng.stoppedHandler = { _ in }
            try eng.start()
            engine = eng
        } catch {
            // Hardware may not support haptics (e.g. older Mac without Taptic Engine).
            engine = nil
        }
    }

    private func fireTransient() {
        guard let engine else { return }

        let event = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5),
            ],
            relativeTime: 0
        )

        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            // Non-fatal: a missed pulse is cosmetic. If the engine died, resetHandler will
            // restart it and the next pulse will succeed.
        }
    }
}
