import Foundation
import LedgeCore

/// Serializes and deserializes all user-facing settings as JSON, for backup and sharing.
///
/// The format is versioned (`"version": 2`) so future changes can migrate gracefully. Every
/// field that `Preferences` exposes is included; fields that do not appear in an imported file
/// keep their current value, making the format forward-compatible.
///
/// Version 2 introduces per-edge configuration (leftEdge, rightEdge, topEdge, bottomEdge) and
/// removes the old `edgeBandWidth` and `swapSides` fields. Importing a version 1 file maps
/// the old format to the new per-edge config automatically.
enum SettingsIO {
    /// The current schema version written into every export.
    private static let currentVersion = 2

    /// Serialize all settings from the given preferences into JSON data.
    static func exportSettings(from preferences: Preferences) -> Data {
        let settings = preferences.gestureSettings
        let dict: [String: Any] = [
            "version": currentVersion,
            // Per-edge configuration
            "leftEdge": encodeEdgeConfig(settings.leftEdge),
            "rightEdge": encodeEdgeConfig(settings.rightEdge),
            "topEdge": encodeEdgeConfig(settings.topEdge),
            "bottomEdge": encodeEdgeConfig(settings.bottomEdge),
            // Shared gesture settings
            "stepDistance": settings.stepDistance,
            "activationDistance": settings.activationDistance,
            "maxDriftOutsideBand": settings.maxDriftOutsideBand,
            "bottomQuarterOnly": settings.bottomQuarterOnly,
            "typingLockout": settings.typingLockout,
            "gestureTimeout": settings.gestureTimeout,
            "fineControl": settings.fineControl,
            // Adapter-layer settings
            "cursorFreezeEnabled": preferences.cursorFreezeEnabled,
            "isEnabled": preferences.isEnabled,
            "modifierKeyRequired": preferences.modifierKeyRequired.rawValue,
            "excludedApps": preferences.excludedApps,
        ]
        // JSONSerialization with .sortedKeys for reproducible output.
        // swiftlint:disable:next force_try
        return try! JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
    }

    /// Deserialize JSON data and write the values into the given preferences.
    ///
    /// Missing keys are silently skipped, so an older export still works after new settings are
    /// added. Unknown keys are ignored for the same reason in reverse.
    ///
    /// Version 1 imports are handled by mapping `edgeBandWidth`/`swapSides` to per-edge config.
    static func importSettings(from data: Data, into preferences: Preferences) {
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        let version = dict["version"] as? Int ?? 1
        var settings = preferences.gestureSettings

        if version >= 2 {
            // Version 2+: per-edge configuration
            if let edgeDict = dict["leftEdge"] as? [String: Any] {
                settings.leftEdge = decodeEdgeConfig(edgeDict, fallback: settings.leftEdge)
            }
            if let edgeDict = dict["rightEdge"] as? [String: Any] {
                settings.rightEdge = decodeEdgeConfig(edgeDict, fallback: settings.rightEdge)
            }
            if let edgeDict = dict["topEdge"] as? [String: Any] {
                settings.topEdge = decodeEdgeConfig(edgeDict, fallback: settings.topEdge)
            }
            if let edgeDict = dict["bottomEdge"] as? [String: Any] {
                settings.bottomEdge = decodeEdgeConfig(edgeDict, fallback: settings.bottomEdge)
            }
        } else {
            // Version 1 backward compatibility: map old format to per-edge config.
            let oldBandWidth = dict["edgeBandWidth"] as? Double ?? settings.leftEdge.bandWidth
            let oldSwapSides = dict["swapSides"] as? Bool ?? false

            let leftAction: EdgeAction = oldSwapSides ? .volume : .brightness
            let rightAction: EdgeAction = oldSwapSides ? .brightness : .volume

            settings.leftEdge = EdgeConfig(action: leftAction, bandWidth: oldBandWidth, isEnabled: true)
            settings.rightEdge = EdgeConfig(action: rightAction, bandWidth: oldBandWidth, isEnabled: true)
            // Top/bottom were not supported in v1: leave as disabled defaults.
            settings.topEdge = EdgeConfig(action: .none, bandWidth: oldBandWidth, isEnabled: false)
            settings.bottomEdge = EdgeConfig(action: .none, bandWidth: oldBandWidth, isEnabled: false)
        }

        // Shared gesture settings (present in both v1 and v2)
        if let v = dict["stepDistance"] as? Double { settings.stepDistance = v }
        if let v = dict["activationDistance"] as? Double { settings.activationDistance = v }
        if let v = dict["maxDriftOutsideBand"] as? Double { settings.maxDriftOutsideBand = v }
        if let v = dict["bottomQuarterOnly"] as? Bool { settings.bottomQuarterOnly = v }
        if let v = dict["typingLockout"] as? Double { settings.typingLockout = v }
        if let v = dict["gestureTimeout"] as? Double { settings.gestureTimeout = v }
        if let v = dict["fineControl"] as? Bool { settings.fineControl = v }

        if let raw = dict["modifierKeyRequired"] as? String,
           let mode = ModifierKeyMode(rawValue: raw) {
            settings.modifierKeyRequired = mode
        }

        preferences.gestureSettings = settings

        // Adapter-layer settings
        if let v = dict["cursorFreezeEnabled"] as? Bool { preferences.cursorFreezeEnabled = v }
        if let v = dict["isEnabled"] as? Bool { preferences.isEnabled = v }
        if let raw = dict["modifierKeyRequired"] as? String,
           let mode = ModifierKeyMode(rawValue: raw) {
            preferences.modifierKeyRequired = mode
        }
        if let v = dict["excludedApps"] as? [String] { preferences.excludedApps = v }
    }

    // MARK: - Edge Config Encoding

    private static func encodeEdgeConfig(_ config: EdgeConfig) -> [String: Any] {
        return [
            "action": config.action.rawValue,
            "bandWidth": config.bandWidth,
            "isEnabled": config.isEnabled,
        ]
    }

    private static func decodeEdgeConfig(_ dict: [String: Any], fallback: EdgeConfig) -> EdgeConfig {
        let actionRaw = dict["action"] as? String ?? fallback.action.rawValue
        let action = EdgeAction(rawValue: actionRaw) ?? fallback.action
        let bandWidth = dict["bandWidth"] as? Double ?? fallback.bandWidth
        let isEnabled = dict["isEnabled"] as? Bool ?? fallback.isEnabled
        return EdgeConfig(action: action, bandWidth: bandWidth, isEnabled: isEnabled)
    }
}
