/// Which edge of the trackpad a touch belongs to.
///
/// Named for a physical side rather than for what it does, because which side drives which
/// action is a user setting (per-edge `EdgeConfig`) and must not be baked into the vocabulary.
///
/// Left/right edges respond to vertical slides, top/bottom edges respond to horizontal slides.
public enum TrackpadEdge: Sendable, Equatable {
    case left
    case right
    case top
    case bottom
}

/// A system property a gesture can drive.
///
/// Each edge is independently assigned an action through `EdgeConfig`. An action of `.none`
/// means the edge is conceptually unused even if enabled; it will still arm and engage but
/// produce no visible output.
public enum EdgeAction: String, Sendable, Equatable, CaseIterable {
    case volume
    case brightness
    case zoom
    case nextPreviousTrack
    case scroll
    case none

    /// A human-readable label suitable for a settings UI.
    public var displayName: String {
        switch self {
        case .volume: return "Volume"
        case .brightness: return "Brightness"
        case .zoom: return "Zoom"
        case .nextPreviousTrack: return "Next/Previous Track"
        case .scroll: return "Scroll"
        case .none: return "None"
        }
    }
}

/// Per-edge configuration: which action it drives, how wide its band is, and whether it is
/// active at all.
///
/// A disabled edge (`isEnabled == false`) never arms or engages, regardless of its action or
/// band width. This lets a user keep an edge configured but temporarily switched off.
public struct EdgeConfig: Sendable, Equatable {
    /// The system property this edge controls.
    public var action: EdgeAction
    /// How far in from this edge a touch may start, as a fraction of the relevant trackpad
    /// dimension (width for left/right, height for top/bottom).
    public var bandWidth: Double
    /// Whether this edge is currently active.
    public var isEnabled: Bool

    public init(action: EdgeAction = .none, bandWidth: Double = 0.025, isEnabled: Bool = false) {
        self.action = action
        self.bandWidth = bandWidth
        self.isEnabled = isEnabled
    }
}

/// A system property a gesture can drive (legacy, kept for backward compatibility with macOS adapter).
public enum Control: Sendable, Equatable {
    case volume
    case brightness
}

/// Which way a single step moves the control.
///
/// Expressed as up/down rather than increase/decrease so it reads as the finger motion that
/// produced it. For vertical edges (left/right), sliding up the trackpad steps up. For
/// horizontal edges (top/bottom), sliding right steps up and sliding left steps down.
public enum StepDirection: Sendable, Equatable {
    case up
    case down
}
