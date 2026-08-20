/// Every tunable number and switch the gesture logic obeys, in one place.
///
/// These are the values that will be revised after real use, so they are gathered here rather
/// than scattered as literals through the engine: retuning the app should mean editing one
/// file, and every default should be defensible from its doc comment alone.
///
/// The properties are `var`, unlike the immutable value types elsewhere in `LedgeCore`,
/// because the menu bar flips settings at runtime. It remains a value type, so a change made
/// in one place cannot reach a copy held elsewhere.
public struct GestureSettings: Sendable, Equatable {
    /// Configuration for the left edge. Default: brightness, 0.025 band, enabled.
    public var leftEdge: EdgeConfig = EdgeConfig(action: .brightness, bandWidth: 0.025, isEnabled: true)

    /// Configuration for the right edge. Default: volume, 0.025 band, enabled.
    public var rightEdge: EdgeConfig = EdgeConfig(action: .volume, bandWidth: 0.025, isEnabled: true)

    /// Configuration for the top edge. Default: none, 0.025 band, disabled.
    public var topEdge: EdgeConfig = EdgeConfig(action: .none, bandWidth: 0.025, isEnabled: false)

    /// Configuration for the bottom edge. Default: none, 0.025 band, disabled.
    public var bottomEdge: EdgeConfig = EdgeConfig(action: .none, bandWidth: 0.025, isEnabled: false)

    /// Vertical travel required per step, as a **fraction of trackpad height** (for vertical
    /// edges) or trackpad width (for horizontal edges).
    ///
    /// Default `0.016` approximates 1/64 of the height, matching the 64 sub-steps that fine
    /// volume mode provides.
    public var stepDistance: Double = 0.016

    /// Travel required before a gesture engages at all, as a **fraction of the relevant
    /// trackpad dimension**.
    ///
    /// A dead zone: default `0.02` has to be larger than the wobble of a finger resting at
    /// the edge, or the app fires when the user is holding still, but small enough that the
    /// gesture still feels immediate rather than needing a wind-up.
    public var activationDistance: Double = 0.02

    /// How far an already-engaged finger may stray beyond the band before the gesture is
    /// abandoned, as a **fraction of the relevant trackpad dimension**.
    ///
    /// Default `0.02` keeps drift tolerance narrower than the edge band.
    public var maxDriftOutsideBand: Double = 0.02

    /// Whether a gesture may only start in the bottom quarter of the trackpad.
    ///
    /// Default `false`. Only applies to vertical edges (left/right).
    public var bottomQuarterOnly: Bool = false

    /// How long after a keystroke gestures stay suppressed, in **seconds**.
    ///
    /// Default `0.6` s spans the pause between keystrokes.
    public var typingLockout: Double = 0.6

    /// How large a gap between touch frames abandons the gesture in progress, in **seconds**.
    ///
    /// Default `0.25` s.
    public var gestureTimeout: Double = 0.25

    /// Whether steps drive the OS's fine-grained sub-steps rather than its whole steps.
    ///
    /// Default `true`: quarter-step control is the entire reason the app exists.
    public var fineControl: Bool = true

    /// Which modifier key must be held for gestures to activate.
    ///
    /// Default `.none` means no modifier is required.
    public var modifierKeyRequired: ModifierKeyMode = .none

    public init() {}

    /// Get the `EdgeConfig` for a given edge.
    public func edgeConfig(for edge: TrackpadEdge) -> EdgeConfig {
        switch edge {
        case .left: return leftEdge
        case .right: return rightEdge
        case .top: return topEdge
        case .bottom: return bottomEdge
        }
    }

    /// Which edge, if any, a position falls in, considering all four edges and their enabled state.
    ///
    /// Priority: vertical edges (left/right) win over horizontal edges (top/bottom) when a
    /// position is in both bands (corner case). A disabled edge is never returned.
    ///
    /// For left/right edges, the band is measured as a fraction of trackpad width (x-axis).
    /// For top/bottom edges, the band is measured as a fraction of trackpad height (y-axis).
    ///
    /// If two edges on the same axis both claim the position (e.g. overlapping bands), the
    /// nearer edge wins, with ties going to left (for horizontal) or bottom (for vertical).
    public func edge(forPosition position: NormalizedPoint) -> TrackpadEdge? {
        // Check vertical edges first (they have priority)
        let verticalEdge = classifyVertical(x: position.x)
        if let edge = verticalEdge, edgeConfig(for: edge).isEnabled {
            return edge
        }

        // Then horizontal edges
        let horizontalEdge = classifyHorizontal(y: position.y)
        if let edge = horizontalEdge, edgeConfig(for: edge).isEnabled {
            return edge
        }

        return nil
    }

    /// Classify x-position into left/right edge, or nil.
    private func classifyVertical(x: Double) -> TrackpadEdge? {
        let leftBand = leftEdge.bandWidth
        let rightBand = rightEdge.bandWidth

        let isInLeftBand = x < leftBand
        let isInRightBand = x > 1 - rightBand
        switch (isInLeftBand, isInRightBand) {
        case (true, false): return .left
        case (false, true): return .right
        case (true, true):
            // Overlapping bands: resolve to nearer edge, ties go to left
            return x <= 1 - x ? .left : .right
        case (false, false): return nil
        }
    }

    /// Classify y-position into top/bottom edge, or nil.
    private func classifyHorizontal(y: Double) -> TrackpadEdge? {
        let bottomBand = bottomEdge.bandWidth
        let topBand = topEdge.bandWidth

        let isInBottomBand = y < bottomBand
        let isInTopBand = y > 1 - topBand
        switch (isInBottomBand, isInTopBand) {
        case (true, false): return .bottom
        case (false, true): return .top
        case (true, true):
            // Overlapping bands: resolve to nearer edge, ties go to bottom
            return y <= 1 - y ? .bottom : .top
        case (false, false): return nil
        }
    }

    /// The travel required per step given `fineControl`.
    ///
    /// With fine control off, one step moves a whole OS step instead of a sub-step, so the
    /// distance is multiplied by 4.
    public var effectiveStepDistance: Double {
        fineControl ? stepDistance : stepDistance * 4
    }
}
