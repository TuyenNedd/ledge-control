import Foundation

/// Manages a list of bundle identifiers whose frontmost status should disable gesture detection.
///
/// A thin wrapper around a `[String]` that gives the rest of the app a vocabulary for exclusion
/// decisions without scattering array logic through unrelated types. The list is persisted by
/// `Preferences`; this type only provides the read/write interface and the lookup.
struct AppExclusionList {
    private var bundleIDs: [String]

    init(bundleIDs: [String] = []) {
        self.bundleIDs = bundleIDs
    }

    /// Whether a given bundle identifier is in the exclusion list.
    ///
    /// Returns `false` for a nil bundle ID, since an unknown app cannot be excluded.
    func isExcluded(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return bundleIDs.contains(bundleID)
    }

    /// Add a bundle identifier to the exclusion list. No-op if already present.
    mutating func add(_ bundleID: String) {
        guard !bundleIDs.contains(bundleID) else { return }
        bundleIDs.append(bundleID)
    }

    /// Remove a bundle identifier from the exclusion list. No-op if not present.
    mutating func remove(_ bundleID: String) {
        bundleIDs.removeAll { $0 == bundleID }
    }

    /// All excluded bundle identifiers, in insertion order.
    var allExcluded: [String] { bundleIDs }
}
