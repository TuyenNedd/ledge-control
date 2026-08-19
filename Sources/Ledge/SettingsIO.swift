import Foundation
import LedgeCore

/// Serializes and deserializes all user-facing settings as JSON, for backup and sharing.
///
/// The format is versioned (`"version": 1`) so future changes can migrate gracefully. Every
/// field that `Preferences` exposes is included; fields that do not appear in an imported file
/// keep their current value, making the format forward-compatible.
enum SettingsIO {
    /// The current schema version written into every export.
    private static let currentVersion = 1

    /// Serialize all settings from the given preferences into JSON data.
    static func exportSettings(from preferences: Preferences) -> Data {
        let settings = preferences.gestureSettings
        let dict: [String: Any] = [
            "version": currentVersion,
            "edgeBandWidth": settings.edgeBandWidth,
            "stepDistance": settings.stepDistance,
            "activationDistance": settings.activationDistance,
            "maxDriftOutsideBand": settings.maxDriftOutsideBand,
            "bottomQuarterOnly": settings.bottomQuarterOnly,
            "typingLockout": settings.typingLockout,
            "gestureTimeout": settings.gestureTimeout,
            "fineControl": settings.fineControl,
            "swapSides": settings.swapSides,
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
    static func importSettings(from data: Data, into preferences: Preferences) {
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        var settings = preferences.gestureSettings

        if let v = dict["edgeBandWidth"] as? Double { settings.edgeBandWidth = v }
        if let v = dict["stepDistance"] as? Double { settings.stepDistance = v }
        if let v = dict["activationDistance"] as? Double { settings.activationDistance = v }
        if let v = dict["maxDriftOutsideBand"] as? Double { settings.maxDriftOutsideBand = v }
        if let v = dict["bottomQuarterOnly"] as? Bool { settings.bottomQuarterOnly = v }
        if let v = dict["typingLockout"] as? Double { settings.typingLockout = v }
        if let v = dict["gestureTimeout"] as? Double { settings.gestureTimeout = v }
        if let v = dict["fineControl"] as? Bool { settings.fineControl = v }
        if let v = dict["swapSides"] as? Bool { settings.swapSides = v }

        if let raw = dict["modifierKeyRequired"] as? String,
           let mode = ModifierKeyMode(rawValue: raw) {
            settings.modifierKeyRequired = mode
        }

        preferences.gestureSettings = settings

        if let v = dict["cursorFreezeEnabled"] as? Bool { preferences.cursorFreezeEnabled = v }
        if let v = dict["isEnabled"] as? Bool { preferences.isEnabled = v }
        if let raw = dict["modifierKeyRequired"] as? String,
           let mode = ModifierKeyMode(rawValue: raw) {
            preferences.modifierKeyRequired = mode
        }
        if let v = dict["excludedApps"] as? [String] { preferences.excludedApps = v }
    }
}
