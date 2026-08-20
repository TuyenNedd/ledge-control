import Foundation
import LedgeCore

/// Everything the user can change, persisted in `UserDefaults`.
///
/// This type stores and retrieves; it decides nothing. Every default value it seeds comes from
/// `GestureSettings()` -- the tested type that owns what a sensible value is -- so there is exactly
/// one place in the codebase where a default is written down, and it is the place that is under
/// test. The only defaults declared here are the ones with no `GestureSettings` counterpart.
///
/// Per-edge configuration (action, bandWidth, isEnabled) is stored as individual keys per edge,
/// replacing the old single `edgeBandWidth` and `swapSides` keys. Migration from the old format
/// happens automatically on first read if old keys exist and new keys do not.
final class Preferences {
    private let defaults: UserDefaults

    /// Deliberately unprefixed, so `defaults read xyz.tuyennedd.ledge` is readable and
    /// `defaults write` is typeable. The defaults domain is already per-application.
    private enum Key {
        // Legacy keys (kept for migration detection, no longer written)
        static let edgeBandWidth = "edgeBandWidth"
        static let swapSides = "swapSides"

        // Per-edge configuration keys
        static let leftEdgeAction = "leftEdgeAction"
        static let leftEdgeBandWidth = "leftEdgeBandWidth"
        static let leftEdgeEnabled = "leftEdgeEnabled"

        static let rightEdgeAction = "rightEdgeAction"
        static let rightEdgeBandWidth = "rightEdgeBandWidth"
        static let rightEdgeEnabled = "rightEdgeEnabled"

        static let topEdgeAction = "topEdgeAction"
        static let topEdgeBandWidth = "topEdgeBandWidth"
        static let topEdgeEnabled = "topEdgeEnabled"

        static let bottomEdgeAction = "bottomEdgeAction"
        static let bottomEdgeBandWidth = "bottomEdgeBandWidth"
        static let bottomEdgeEnabled = "bottomEdgeEnabled"

        // Shared gesture settings
        static let stepDistance = "stepDistance"
        static let activationDistance = "activationDistance"
        static let maxDriftOutsideBand = "maxDriftOutsideBand"
        static let bottomQuarterOnly = "bottomQuarterOnly"
        static let typingLockout = "typingLockout"
        static let gestureTimeout = "gestureTimeout"
        static let fineControl = "fineControl"

        // Adapter-layer settings
        static let cursorFreezeEnabled = "cursorFreezeEnabled"
        static let isEnabled = "isEnabled"
        static let useCoreAudioVolume = "useCoreAudioVolume"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let modifierKeyRequired = "modifierKeyRequired"
        static let excludedApps = "excludedApps"

        /// Sentinel key: when present, per-edge migration has been performed.
        static let perEdgeMigrated = "perEdgeMigrated"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let seed = GestureSettings()
        defaults.register(defaults: [
            // Per-edge defaults
            Key.leftEdgeAction: seed.leftEdge.action.rawValue,
            Key.leftEdgeBandWidth: seed.leftEdge.bandWidth,
            Key.leftEdgeEnabled: seed.leftEdge.isEnabled,

            Key.rightEdgeAction: seed.rightEdge.action.rawValue,
            Key.rightEdgeBandWidth: seed.rightEdge.bandWidth,
            Key.rightEdgeEnabled: seed.rightEdge.isEnabled,

            Key.topEdgeAction: seed.topEdge.action.rawValue,
            Key.topEdgeBandWidth: seed.topEdge.bandWidth,
            Key.topEdgeEnabled: seed.topEdge.isEnabled,

            Key.bottomEdgeAction: seed.bottomEdge.action.rawValue,
            Key.bottomEdgeBandWidth: seed.bottomEdge.bandWidth,
            Key.bottomEdgeEnabled: seed.bottomEdge.isEnabled,

            // Shared gesture settings
            Key.stepDistance: seed.stepDistance,
            Key.activationDistance: seed.activationDistance,
            Key.maxDriftOutsideBand: seed.maxDriftOutsideBand,
            Key.bottomQuarterOnly: seed.bottomQuarterOnly,
            Key.typingLockout: seed.typingLockout,
            Key.gestureTimeout: seed.gestureTimeout,
            Key.fineControl: seed.fineControl,

            // Adapter-layer defaults (no GestureSettings counterpart)
            Key.cursorFreezeEnabled: true,
            Key.isEnabled: true,
            Key.useCoreAudioVolume: false,
        ])

        // Migrate from old single-edgeBandWidth / swapSides format if needed.
        migrateIfNeeded()
    }

    // MARK: - Migration

    /// If old keys (`edgeBandWidth`, `swapSides`) exist and per-edge keys have not been written,
    /// map old values to the new per-edge config.
    ///
    /// Old format: single `edgeBandWidth` for both edges, `swapSides` swaps volume/brightness.
    /// New format: each edge has its own action, bandWidth, and isEnabled.
    private func migrateIfNeeded() {
        // Already migrated: nothing to do.
        guard !defaults.bool(forKey: Key.perEdgeMigrated) else { return }

        // Only migrate if old keys were explicitly set (not just registered defaults).
        // `object(forKey:)` returns nil for unset keys, unlike `double(forKey:)` which returns 0.
        let hasOldBandWidth = defaults.object(forKey: Key.edgeBandWidth) != nil
        let hasOldSwapSides = defaults.object(forKey: Key.swapSides) != nil

        guard hasOldBandWidth || hasOldSwapSides else {
            // Fresh install: mark as migrated so we never check again.
            defaults.set(true, forKey: Key.perEdgeMigrated)
            return
        }

        let oldBandWidth = defaults.double(forKey: Key.edgeBandWidth)
        let oldSwapSides = defaults.bool(forKey: Key.swapSides)

        // Old convention: left = brightness, right = volume (swapSides flips them).
        let leftAction: EdgeAction = oldSwapSides ? .volume : .brightness
        let rightAction: EdgeAction = oldSwapSides ? .brightness : .volume

        // Write per-edge config from old values.
        defaults.set(leftAction.rawValue, forKey: Key.leftEdgeAction)
        defaults.set(oldBandWidth, forKey: Key.leftEdgeBandWidth)
        defaults.set(true, forKey: Key.leftEdgeEnabled)

        defaults.set(rightAction.rawValue, forKey: Key.rightEdgeAction)
        defaults.set(oldBandWidth, forKey: Key.rightEdgeBandWidth)
        defaults.set(true, forKey: Key.rightEdgeEnabled)

        // Top and bottom were not supported before: leave them at defaults (disabled).
        defaults.set(EdgeAction.none.rawValue, forKey: Key.topEdgeAction)
        defaults.set(oldBandWidth, forKey: Key.topEdgeBandWidth)
        defaults.set(false, forKey: Key.topEdgeEnabled)

        defaults.set(EdgeAction.none.rawValue, forKey: Key.bottomEdgeAction)
        defaults.set(oldBandWidth, forKey: Key.bottomEdgeBandWidth)
        defaults.set(false, forKey: Key.bottomEdgeEnabled)

        // Mark migration complete and remove old keys.
        defaults.set(true, forKey: Key.perEdgeMigrated)
        defaults.removeObject(forKey: Key.edgeBandWidth)
        defaults.removeObject(forKey: Key.swapSides)
    }

    // MARK: - Per-Edge Config Helpers

    private func readEdgeConfig(actionKey: String, bandWidthKey: String, enabledKey: String) -> EdgeConfig {
        let actionRaw = defaults.string(forKey: actionKey) ?? EdgeAction.none.rawValue
        let action = EdgeAction(rawValue: actionRaw) ?? .none
        let bandWidth = defaults.double(forKey: bandWidthKey)
        let isEnabled = defaults.bool(forKey: enabledKey)
        return EdgeConfig(action: action, bandWidth: bandWidth, isEnabled: isEnabled)
    }

    private func writeEdgeConfig(_ config: EdgeConfig, actionKey: String, bandWidthKey: String, enabledKey: String) {
        defaults.set(config.action.rawValue, forKey: actionKey)
        defaults.set(config.bandWidth, forKey: bandWidthKey)
        defaults.set(config.isEnabled, forKey: enabledKey)
    }

    // MARK: - Gesture Settings

    /// The tunables, assembled from the defaults domain.
    ///
    /// Built by mutating a fresh `GestureSettings()` rather than by constructing one from
    /// scratch, so if a future setting is added to `LedgeCore` and forgotten here it silently
    /// keeps its tested default instead of becoming zero.
    var gestureSettings: GestureSettings {
        get {
            var settings = GestureSettings()

            // Per-edge configuration
            settings.leftEdge = readEdgeConfig(
                actionKey: Key.leftEdgeAction,
                bandWidthKey: Key.leftEdgeBandWidth,
                enabledKey: Key.leftEdgeEnabled
            )
            settings.rightEdge = readEdgeConfig(
                actionKey: Key.rightEdgeAction,
                bandWidthKey: Key.rightEdgeBandWidth,
                enabledKey: Key.rightEdgeEnabled
            )
            settings.topEdge = readEdgeConfig(
                actionKey: Key.topEdgeAction,
                bandWidthKey: Key.topEdgeBandWidth,
                enabledKey: Key.topEdgeEnabled
            )
            settings.bottomEdge = readEdgeConfig(
                actionKey: Key.bottomEdgeAction,
                bandWidthKey: Key.bottomEdgeBandWidth,
                enabledKey: Key.bottomEdgeEnabled
            )

            // Shared gesture settings
            settings.stepDistance = defaults.double(forKey: Key.stepDistance)
            settings.activationDistance = defaults.double(forKey: Key.activationDistance)
            settings.maxDriftOutsideBand = defaults.double(forKey: Key.maxDriftOutsideBand)
            settings.bottomQuarterOnly = defaults.bool(forKey: Key.bottomQuarterOnly)
            settings.typingLockout = defaults.double(forKey: Key.typingLockout)
            settings.gestureTimeout = defaults.double(forKey: Key.gestureTimeout)
            settings.fineControl = defaults.bool(forKey: Key.fineControl)
            settings.modifierKeyRequired = modifierKeyRequired
            return settings
        }
        set {
            // Per-edge configuration
            writeEdgeConfig(newValue.leftEdge,
                actionKey: Key.leftEdgeAction,
                bandWidthKey: Key.leftEdgeBandWidth,
                enabledKey: Key.leftEdgeEnabled
            )
            writeEdgeConfig(newValue.rightEdge,
                actionKey: Key.rightEdgeAction,
                bandWidthKey: Key.rightEdgeBandWidth,
                enabledKey: Key.rightEdgeEnabled
            )
            writeEdgeConfig(newValue.topEdge,
                actionKey: Key.topEdgeAction,
                bandWidthKey: Key.topEdgeBandWidth,
                enabledKey: Key.topEdgeEnabled
            )
            writeEdgeConfig(newValue.bottomEdge,
                actionKey: Key.bottomEdgeAction,
                bandWidthKey: Key.bottomEdgeBandWidth,
                enabledKey: Key.bottomEdgeEnabled
            )

            // Shared gesture settings
            defaults.set(newValue.stepDistance, forKey: Key.stepDistance)
            defaults.set(newValue.activationDistance, forKey: Key.activationDistance)
            defaults.set(newValue.maxDriftOutsideBand, forKey: Key.maxDriftOutsideBand)
            defaults.set(newValue.bottomQuarterOnly, forKey: Key.bottomQuarterOnly)
            defaults.set(newValue.typingLockout, forKey: Key.typingLockout)
            defaults.set(newValue.gestureTimeout, forKey: Key.gestureTimeout)
            defaults.set(newValue.fineControl, forKey: Key.fineControl)
            modifierKeyRequired = newValue.modifierKeyRequired
        }
    }

    // MARK: - Adapter-Layer Settings

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

    /// Trade the system HUD for continuous volume control. Off by default -- see
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

    /// Which modifier key must be held for gestures to activate.
    ///
    /// Stored as the enum's raw value string. Defaults to `.none` (no modifier required).
    var modifierKeyRequired: ModifierKeyMode {
        get {
            guard let raw = defaults.string(forKey: Key.modifierKeyRequired),
                  let mode = ModifierKeyMode(rawValue: raw)
            else { return .none }
            return mode
        }
        set { defaults.set(newValue.rawValue, forKey: Key.modifierKeyRequired) }
    }

    /// Bundle identifiers of apps that should disable gesture detection when frontmost.
    ///
    /// Stored as a string array in UserDefaults. Defaults to empty (no apps excluded).
    var excludedApps: [String] {
        get { defaults.stringArray(forKey: Key.excludedApps) ?? [] }
        set { defaults.set(newValue, forKey: Key.excludedApps) }
    }
}
