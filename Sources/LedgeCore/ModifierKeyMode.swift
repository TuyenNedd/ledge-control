/// Which modifier key, if any, must be held for gestures to activate.
///
/// When a mode other than `.none` is active, the engine ignores touches unless the modifier is
/// reported as held — the same suppression as the typing lockout, except it is a deliberate gate
/// rather than a heuristic. Releasing the modifier mid-gesture ends it immediately, matching what
/// happens when the engine is disabled mid-slide.
public enum ModifierKeyMode: String, Sendable, Equatable, CaseIterable {
    case none
    case holdOption
    case holdFn
    case holdControl

    /// A human-readable label for use in settings UI.
    public var displayName: String {
        switch self {
        case .none: return "None"
        case .holdOption: return "Hold Option"
        case .holdFn: return "Hold Fn"
        case .holdControl: return "Hold Control"
        }
    }
}
