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
    // Pins the default width behaviourally: 0.09 is inside a 0.10 band, 0.11 is not. A
    // hardcoded or mistyped width fails one of these.
    #expect(s.edge(forX: 0.09) == .left)
    #expect(s.edge(forX: 0.11) == nil)
    // Mirrored on the right: 0.91 is inside the outer 0.10, 0.89 is not.
    #expect(s.edge(forX: 0.91) == .right)
    #expect(s.edge(forX: 0.89) == nil)
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
    #expect(s.edge(forX: 0.15) == nil)
    #expect(s.edge(forX: 0.85) == nil)
    s.edgeBandWidth = 0.2
    #expect(s.edge(forX: 0.15) == .left)
    #expect(s.edge(forX: 0.85) == .right)
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
