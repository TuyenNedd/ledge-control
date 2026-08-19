import Foundation
import LedgeCore

/// Everything the user can change, persisted in `UserDefaults`.
///
/// This type stores and retrieves; it decides nothing. Every default value it seeds comes from
/// `GestureSettings()` — the tested type that owns what a sensible value is — so there is exactly
/// one place in the codebase where a default is written down, and it is the place that is under
/// test. The only defaults declared here are the ones with no `GestureSettings` counterpart.
///
/// The numeric tunables are persisted even though no menu item edits them. That is deliberate:
/// `docs/DESIGN.md` expects `edgeBandWidth`, `activationDistance` and `typingLockout` to need
/// retuning after real use, and having them in the defaults domain means that can be done with
/// `defaults write xyz.tuyennedd.ledge edgeBandWidth 0.08` and a relaunch, instead of a rebuild.
final class Preferences {
    private let defaults: UserDefaults

    /// Deliberately unprefixed, so `defaults read xyz.tuyennedd.ledge` is readable and
    /// `defaults write` is typeable. The defaults domain is already per-application.
    private enum Key {
        static let edgeBandWidth = "edgeBandWidth"
        static let stepDistance = "stepDistance"
        static let activationDistance = "activationDistance"
        static let maxDriftOutsideBand = "maxDriftOutsideBand"
        static let bottomQuarterOnly = "bottomQuarterOnly"
        static let typingLockout = "typingLockout"
        static let gestureTimeout = "gestureTimeout"
        static let fineControl = "fineControl"
        static let swapSides = "swapSides"

        static let cursorFreezeEnabled = "cursorFreezeEnabled"
        static let isEnabled = "isEnabled"
        static let useCoreAudioVolume = "useCoreAudioVolume"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Registering is not a nicety. `UserDefaults.bool(forKey:)` answers `false` for a key
        // that was never written, and `double(forKey:)` answers `0` — so on a first launch,
        // without this, `fineControl` would read false (turning off the entire reason the app
        // exists), `isEnabled` would read false (the app would do nothing at all), and every
        // threshold would read zero (`edgeBandWidth` of 0 classifies no edge, so no gesture could
        // ever arm). All four failures are silent.
        let seed = GestureSettings()
        defaults.register(defaults: [
            Key.edgeBandWidth: seed.edgeBandWidth,
            Key.stepDistance: seed.stepDistance,
            Key.activationDistance: seed.activationDistance,
            Key.maxDriftOutsideBand: seed.maxDriftOutsideBand,
            Key.bottomQuarterOnly: seed.bottomQuarterOnly,
            Key.typingLockout: seed.typingLockout,
            Key.gestureTimeout: seed.gestureTimeout,
            Key.fineControl: seed.fineControl,
            Key.swapSides: seed.swapSides,

            // No `GestureSettings` counterpart: these govern the adapter layer, not the gesture
            // logic. Cursor freeze is on because it is the behaviour the app is for; `isEnabled`
            // is on because an app that starts switched off looks broken; the CoreAudio backend is
            // off because it produces no HUD (see `VolumeController`).
            Key.cursorFreezeEnabled: true,
            Key.isEnabled: true,
            Key.useCoreAudioVolume: false,
        ])
    }

    /// The tunables, assembled from the defaults domain.
    ///
    /// Built by mutating a fresh `GestureSettings()` rather than by constructing one from
    /// scratch, so if a future setting is added to `LedgeCore` and forgotten here it silently
    /// keeps its tested default instead of becoming zero.
    var gestureSettings: GestureSettings {
        get {
            var settings = GestureSettings()
            settings.edgeBandWidth = defaults.double(forKey: Key.edgeBandWidth)
            settings.stepDistance = defaults.double(forKey: Key.stepDistance)
            settings.activationDistance = defaults.double(forKey: Key.activationDistance)
            settings.maxDriftOutsideBand = defaults.double(forKey: Key.maxDriftOutsideBand)
            settings.bottomQuarterOnly = defaults.bool(forKey: Key.bottomQuarterOnly)
            settings.typingLockout = defaults.double(forKey: Key.typingLockout)
            settings.gestureTimeout = defaults.double(forKey: Key.gestureTimeout)
            settings.fineControl = defaults.bool(forKey: Key.fineControl)
            settings.swapSides = defaults.bool(forKey: Key.swapSides)
            return settings
        }
        set {
            defaults.set(newValue.edgeBandWidth, forKey: Key.edgeBandWidth)
            defaults.set(newValue.stepDistance, forKey: Key.stepDistance)
            defaults.set(newValue.activationDistance, forKey: Key.activationDistance)
            defaults.set(newValue.maxDriftOutsideBand, forKey: Key.maxDriftOutsideBand)
            defaults.set(newValue.bottomQuarterOnly, forKey: Key.bottomQuarterOnly)
            defaults.set(newValue.typingLockout, forKey: Key.typingLockout)
            defaults.set(newValue.gestureTimeout, forKey: Key.gestureTimeout)
            defaults.set(newValue.fineControl, forKey: Key.fineControl)
            defaults.set(newValue.swapSides, forKey: Key.swapSides)
        }
    }

    /// Whether pointer movement is swallowed while a gesture owns a control, so a slide along the
    /// edge does not also drag the cursor up the screen.
    var cursorFreezeEnabled: Bool {
        get { defaults.bool(forKey: Key.cursorFreezeEnabled) }
        set { defaults.set(newValue, forKey: Key.cursorFreezeEnabled) }
    }

    /// The master switch, mirrored into `GestureEngine.setEnabled(_:)`.
    var isEnabled: Bool {
        get { defaults.bool(forKey: Key.isEnabled) }
        set { defaults.set(newValue, forKey: Key.isEnabled) }
    }

    /// Trade the system HUD for continuous volume control. Off by default — see
    /// `CoreAudioVolumeController`.
    var useCoreAudioVolume: Bool {
        get { defaults.bool(forKey: Key.useCoreAudioVolume) }
        set { defaults.set(newValue, forKey: Key.useCoreAudioVolume) }
    }

    /// Whether the user has completed the first-launch onboarding flow. Not registered as a
    /// default because `bool(forKey:)` returns `false` for an unset key, which is exactly what
    /// first launch needs: the onboarding will show.
    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Key.hasCompletedOnboarding) }
        set { defaults.set(newValue, forKey: Key.hasCompletedOnboarding) }
    }
}
