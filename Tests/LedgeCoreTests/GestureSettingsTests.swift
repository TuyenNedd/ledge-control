import Testing

// Plain import, not `@testable`, per the convention set in GeometryTests: this target is the
// only place a missing `public` can be caught.
import LedgeCore

@Test("x within the band classifies as an edge, the middle does not")
func edgeClassification() {
    let s = GestureSettings()
    #expect(s.edge(forX: 0.02) == .left)
    #expect(s.edge(forX: 0.98) == .right)
    #expect(s.edge(forX: 0.5) == nil)
}

@Test("the band is exactly edgeBandWidth wide, open at its inner boundary")
func edgeBandBoundary() {
    let s = GestureSettings()
    // Pins the default width behaviourally: 0.04 is inside a 0.05 band, 0.06 is not. A
    // hardcoded or mistyped width fails one of these.
    #expect(s.edge(forX: 0.04) == .left)
    #expect(s.edge(forX: 0.06) == nil)
    // Mirrored on the right: 0.96 is inside the outer 0.05, 0.94 is not.
    #expect(s.edge(forX: 0.96) == .right)
    #expect(s.edge(forX: 0.94) == nil)
    // The inner boundary itself is outside the band, on both sides.
    #expect(s.edge(forX: s.edgeBandWidth) == nil)
    #expect(s.edge(forX: 1 - s.edgeBandWidth) == nil)
    // The outer limit is inside it.
    #expect(s.edge(forX: 0) == .left)
    #expect(s.edge(forX: 1) == .right)
}

@Test("widening the band classifies x that a narrower band rejected")
func edgeBandWidthIsRespected() {
    var s = GestureSettings()
    #expect(s.edge(forX: 0.08) == nil)
    #expect(s.edge(forX: 0.92) == nil)
    s.edgeBandWidth = 0.10
    #expect(s.edge(forX: 0.08) == .left)
    #expect(s.edge(forX: 0.92) == .right)
}

@Test("a zero-width band classifies nothing, not even the outermost x")
func zeroWidthBandDisablesClassification() {
    var s = GestureSettings()
    s.edgeBandWidth = 0
    #expect(s.edge(forX: 0) == nil)
    #expect(s.edge(forX: 1) == nil)
    #expect(s.edge(forX: 0.5) == nil)
}

@Test("bands wider than half resolve to the nearer edge instead of overlapping")
func overlappingBandsResolveToNearerEdge() {
    var s = GestureSettings()
    s.edgeBandWidth = 0.6
    // 0.45 lies in both bands; it is nearer the left, so left wins.
    #expect(s.edge(forX: 0.45) == .left)
    #expect(s.edge(forX: 0.55) == .right)
    // The midpoint is equidistant; the tie is resolved deterministically to the left.
    #expect(s.edge(forX: 0.5) == .left)
}

@Test("left edge is brightness and right edge is volume by default")
func defaultControlMapping() {
    let s = GestureSettings()
    #expect(s.control(for: .left) == .brightness)
    #expect(s.control(for: .right) == .volume)
}

@Test("swapSides inverts the control mapping")
func swappedControlMapping() {
    var s = GestureSettings()
    s.swapSides = true
    #expect(s.control(for: .left) == .volume)
    #expect(s.control(for: .right) == .brightness)
}

@Test("fine control steps at exactly the configured step distance")
func fineStepDistance() {
    var s = GestureSettings()
    #expect(s.effectiveStepDistance == s.stepDistance)
    // Not a constant in disguise: retuning stepDistance retunes the effective distance.
    s.stepDistance = 0.05
    #expect(s.effectiveStepDistance == 0.05)
}

@Test("one full-height slide spans the control's whole range, fine or coarse")
func fullHeightSlideSpansTheRange() {
    var s = GestureSettings()
    // The reason stepDistance is 0.016 rather than any other number: a slide from the bottom
    // of the trackpad to the top should cover the 64 sub-steps fine mode offers, and the 16
    // whole steps coarse mode offers — once, not four times and not a quarter of the way.
    // Ranges rather than equalities, because the tuning is an approximation of 1/64.
    let fineSteps = 1.0 / s.effectiveStepDistance
    #expect(fineSteps > 56 && fineSteps < 72)
    s.fineControl = false
    let coarseSteps = 1.0 / s.effectiveStepDistance
    #expect(coarseSteps > 14 && coarseSteps < 18)
}

@Test("disabling fine control makes each step four times longer")
func coarseStepDistance() {
    var s = GestureSettings()
    let fine = s.effectiveStepDistance
    s.fineControl = false
    #expect(s.effectiveStepDistance == fine * 4)
}


@Test("out-of-range x classifies as the edge it is beyond")
func outOfRangeXClassifiesAsTheNearerEdge() {
    let s = GestureSettings()
    // `NormalizedPoint` deliberately does not clamp, so an adapter bug can deliver x outside
    // 0...1. The documented contract is that such a value still resolves to the edge it has
    // overshot rather than to `nil`: a gesture already in progress must not evaporate because
    // one frame reported 1.02. Pinned here because a `>= 0 && < width` style rewrite of
    // `edge(forX:)` would silently break it while every in-range test stayed green.
    #expect(s.edge(forX: -0.5) == .left)
    #expect(s.edge(forX: 1.5) == .right)
}

@Test("drift tolerance stays narrower than the band it is a tolerance for")
func driftToleranceIsNarrowerThanTheBand() {
    let s = GestureSettings()
    // `maxDriftOutsideBand` only has meaning as a margin *around* the band. If it were the
    // wider of the two, the reachable area outside the band would exceed the band itself and
    // "started at the edge" would stop being the thing that defines the gesture — a finger
    // could spend most of a stroke in the middle of the trackpad and still be driving a
    // control. The band must remain the dominant term.
    #expect(s.maxDriftOutsideBand < s.edgeBandWidth)
    #expect(s.maxDriftOutsideBand > 0)
}

@Test("a stale gesture expires sooner than the typing lockout releases")
func gestureTimeoutExpiresBeforeTypingLockout() {
    let s = GestureSettings()
    // These two windows both end a gesture, and their order decides which one is ever the
    // cause. If a gesture could outlive the typing lockout, then a gesture interrupted by a
    // keystroke would already have timed out by the time the lockout expired, and the lockout
    // could never be the thing that released — it would be dead configuration. Keeping the
    // timeout the shorter of the two makes the lockout a real, observable window.
    #expect(s.gestureTimeout < s.typingLockout)
    #expect(s.gestureTimeout > 0)
}

@Test("the dead zone costs at least one step and at most a couple")
func deadZoneIsMeasuredInSteps() {
    let s = GestureSettings()
    // The dead zone is travel the user spends with no feedback, so its only meaningful unit is
    // steps, not trackpad fractions. At least one step must be due the moment the gesture
    // engages, or recognition is followed by another stretch of nothing (see the
    // `activationDistance` doc comment). Fewer than a few steps, or the gesture stops feeling
    // immediate — a dead zone of half the trackpad would satisfy the lower bound and be
    // unusable.
    let stepsSpentArming = s.activationDistance / s.effectiveStepDistance
    #expect(stepsSpentArming >= 1)
    #expect(stepsSpentArming < 3)
}

@Test("the bottom-quarter restriction ships off")
func bottomQuarterRestrictionShipsOff() {
    let s = GestureSettings()
    // Asserted as policy, not as a literal: DESIGN.md commits to shipping the strongest and
    // most restrictive false-positive defence *disabled*, so that it is switched on in
    // response to evidence rather than imposed before any exists. Flipping the default is a
    // product decision, and this test is the thing that makes it a deliberate one.
    #expect(s.bottomQuarterOnly == false)
}
