/// Every tunable number and switch the gesture logic obeys, in one place.
///
/// These are the values that will be revised after real use, so they are gathered here rather
/// than scattered as literals through the engine: retuning the app should mean editing one
/// file, and every default should be defensible from its doc comment alone.
///
/// The properties are `var`, unlike the immutable value types elsewhere in `LedgeCore`,
/// because the menu bar flips `fineControl`, `swapSides` and `bottomQuarterOnly` at runtime.
/// It remains a value type, so a change made in one place cannot reach a copy held elsewhere.
public struct GestureSettings: Sendable, Equatable {
    /// How far in from a vertical edge a touch may start and still count, as a **fraction of
    /// trackpad width**.
    ///
    /// Default `0.10` ≈ 16 mm on a MacBook trackpad — wide enough to hit without aiming or
    /// looking down. Widening it costs false positives, since the edge is territory fingers
    /// cross constantly while scrolling; narrowing it costs missed gestures.
    public var edgeBandWidth: Double = 0.10

    /// Vertical travel required per step, as a **fraction of trackpad height**.
    ///
    /// Default `0.016` ≈ 1/64 of the height, matching the 64 sub-steps that fine volume mode
    /// provides, so one full-height slide spans the entire range exactly once. Shrinking it
    /// makes the control twitchy and overshoot; growing it means the range no longer fits in
    /// a single comfortable slide.
    public var stepDistance: Double = 0.016

    /// Vertical travel required before a gesture engages at all, as a **fraction of trackpad
    /// height**.
    ///
    /// A dead zone: default `0.02` has to be larger than the wobble of a finger resting at
    /// the edge, or the app fires when the user is holding still, but small enough that the
    /// gesture still feels immediate rather than needing a wind-up.
    public var activationDistance: Double = 0.02

    /// How far an already-engaged finger may stray beyond the band before the gesture is
    /// abandoned, as a **fraction of trackpad width**.
    ///
    /// Default `0.06` buys tolerance: a long vertical slide drifts sideways, and cutting it
    /// off mid-stroke feels broken. Too much tolerance and a finger that has genuinely moved
    /// on to pointing keeps driving the control.
    public var maxDriftOutsideBand: Double = 0.06

    /// Whether a gesture may only start in the bottom quarter of the trackpad.
    ///
    /// Default `false`. This is the strongest false-positive defence available, and also the
    /// most restrictive to use, so it ships off: it exists to be switched on from the menu if
    /// false positives turn out to persist in practice, rather than being imposed before
    /// there is evidence they do.
    public var bottomQuarterOnly: Bool = false

    /// How long after a keystroke gestures stay suppressed, in **seconds**.
    ///
    /// Default `0.6` s is chosen to span the pause between keystrokes, so a palm resting at
    /// the edge stays ignored *through* a sentence rather than being re-enabled in every gap
    /// between two keys. The cost is that a deliberate gesture right after typing is dropped.
    public var typingLockout: Double = 0.6

    /// How large a gap between touch frames abandons the gesture in progress, in **seconds**.
    ///
    /// Default `0.25` s. Frames stop arriving when a finger stops moving, and a gesture that
    /// resumed after a long pause would attribute travel to an intent the user no longer has.
    /// Shorter than the time a user would spend deciding, longer than any hardware hiccup.
    public var gestureTimeout: Double = 0.25

    /// Whether steps drive the OS's fine-grained sub-steps rather than its whole steps.
    ///
    /// Default `true`: quarter-step control is the entire reason the app exists. Off, the app
    /// still works, it just behaves like the hardware keys.
    public var fineControl: Bool = true

    /// Whether the edges swap which control they drive.
    ///
    /// Default `false`, meaning volume on the right, where a right hand already rests, and
    /// brightness on the left. Left-handed users, or anyone who disagrees, flip this.
    public var swapSides: Bool = false

    public init() {}

    /// Which edge, if any, a horizontal position falls in.
    ///
    /// Each band is **half-open**: it includes its outer limit and excludes its inner
    /// boundary, so a band spans exactly `edgeBandWidth` of the width, and an `edgeBandWidth`
    /// of `0` classifies nothing at all. Were the inner boundary inclusive instead, a
    /// zero-width band would still claim `x == 0`, and narrowing the setting could never
    /// switch edge detection off.
    ///
    /// If `edgeBandWidth` is ever set above `0.5` the two bands overlap; a position inside
    /// both resolves to the **nearer** edge, with an exact tie going to the left. Nearest-edge
    /// keeps widening the band monotone — it only ever adds positions to a band, never moves
    /// one from a band to nowhere — and it keeps the answer deterministic, so a finger held
    /// still cannot flicker between two controls.
    ///
    /// `x` is not range-checked, matching `NormalizedPoint`: an out-of-range value means the
    /// adapter is wrong, and it is left to classify as the edge it is beyond rather than being
    /// quietly absorbed here.
    public func edge(forX x: Double) -> TrackpadEdge? {
        let isInLeftBand = x < edgeBandWidth
        let isInRightBand = x > 1 - edgeBandWidth
        switch (isInLeftBand, isInRightBand) {
        case (true, false): return .left
        case (false, true): return .right
        case (true, true): return x <= 1 - x ? .left : .right
        case (false, false): return nil
        }
    }

    /// Which control an edge drives, honouring `swapSides`.
    public func control(for edge: TrackpadEdge) -> Control {
        switch edge {
        case .left: return swapSides ? .volume : .brightness
        case .right: return swapSides ? .brightness : .volume
        }
    }

    /// The travel required per step given `fineControl`, as a **fraction of trackpad height**.
    ///
    /// With fine control off, one step moves a whole OS step instead of a sub-step — 16 of
    /// them across the range rather than 64 — so the distance is multiplied by 4 to keep a
    /// full-height slide spanning the whole range either way. Without the multiplier, coarse
    /// mode would cross the entire range in a quarter of a slide.
    public var effectiveStepDistance: Double {
        fineControl ? stepDistance : stepDistance * 4
    }
}
