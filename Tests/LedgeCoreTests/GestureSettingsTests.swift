import Testing

// Plain import, not `@testable`, per the convention set in GeometryTests: this target is the
// only place a missing `public` can be caught.
import LedgeCore

// MARK: - EdgeAction enum

@Test("EdgeAction conforms to CaseIterable with all expected cases")
func edgeActionCaseIterable() {
    let cases = EdgeAction.allCases
    #expect(cases.count == 6)
    #expect(cases.contains(.volume))
    #expect(cases.contains(.brightness))
    #expect(cases.contains(.zoom))
    #expect(cases.contains(.nextPreviousTrack))
    #expect(cases.contains(.scroll))
    #expect(cases.contains(.none))
}

@Test("EdgeAction displayName returns human-readable labels")
func edgeActionDisplayNames() {
    #expect(EdgeAction.volume.displayName == "Volume")
    #expect(EdgeAction.brightness.displayName == "Brightness")
    #expect(EdgeAction.zoom.displayName == "Zoom")
    #expect(EdgeAction.nextPreviousTrack.displayName == "Next/Previous Track")
    #expect(EdgeAction.scroll.displayName == "Scroll")
    #expect(EdgeAction.none.displayName == "None")
}

// MARK: - EdgeConfig defaults

@Test("EdgeConfig defaults to none action, 0.025 band, disabled")
func edgeConfigDefaults() {
    let config = EdgeConfig()
    #expect(config.action == .none)
    #expect(config.bandWidth == 0.025)
    #expect(config.isEnabled == false)
}

@Test("EdgeConfig can be constructed with custom values")
func edgeConfigCustom() {
    let config = EdgeConfig(action: .volume, bandWidth: 0.05, isEnabled: true)
    #expect(config.action == .volume)
    #expect(config.bandWidth == 0.05)
    #expect(config.isEnabled == true)
}

// MARK: - GestureSettings per-edge defaults

@Test("left edge defaults to brightness, 0.025 band, enabled")
func leftEdgeDefaults() {
    let s = GestureSettings()
    #expect(s.leftEdge.action == .brightness)
    #expect(s.leftEdge.bandWidth == 0.025)
    #expect(s.leftEdge.isEnabled == true)
}

@Test("right edge defaults to volume, 0.025 band, enabled")
func rightEdgeDefaults() {
    let s = GestureSettings()
    #expect(s.rightEdge.action == .volume)
    #expect(s.rightEdge.bandWidth == 0.025)
    #expect(s.rightEdge.isEnabled == true)
}

@Test("top edge defaults to none, 0.025 band, disabled")
func topEdgeDefaults() {
    let s = GestureSettings()
    #expect(s.topEdge.action == .none)
    #expect(s.topEdge.bandWidth == 0.025)
    #expect(s.topEdge.isEnabled == false)
}

@Test("bottom edge defaults to none, 0.025 band, disabled")
func bottomEdgeDefaults() {
    let s = GestureSettings()
    #expect(s.bottomEdge.action == .none)
    #expect(s.bottomEdge.bandWidth == 0.025)
    #expect(s.bottomEdge.isEnabled == false)
}

// MARK: - edge(forPosition:) basic classification

@Test("x within the left band classifies as left edge")
func leftEdgeClassification() {
    let s = GestureSettings()
    let edge = s.edge(forPosition: NormalizedPoint(x: 0.02, y: 0.5))
    #expect(edge == .left)
}

@Test("x within the right band classifies as right edge")
func rightEdgeClassification() {
    let s = GestureSettings()
    let edge = s.edge(forPosition: NormalizedPoint(x: 0.98, y: 0.5))
    #expect(edge == .right)
}

@Test("position in the middle classifies as nil")
func middleClassification() {
    let s = GestureSettings()
    let edge = s.edge(forPosition: NormalizedPoint(x: 0.5, y: 0.5))
    #expect(edge == nil)
}

@Test("y near the top classifies as top edge when enabled")
func topEdgeClassification() {
    var s = GestureSettings()
    s.topEdge.isEnabled = true
    let edge = s.edge(forPosition: NormalizedPoint(x: 0.5, y: 0.98))
    #expect(edge == .top)
}

@Test("y near the bottom classifies as bottom edge when enabled")
func bottomEdgeClassification() {
    var s = GestureSettings()
    s.bottomEdge.isEnabled = true
    let edge = s.edge(forPosition: NormalizedPoint(x: 0.5, y: 0.02))
    #expect(edge == .bottom)
}

// MARK: - Band boundaries

@Test("the left band is exactly bandWidth wide, open at its inner boundary")
func leftBandBoundary() {
    let s = GestureSettings()
    #expect(s.edge(forPosition: NormalizedPoint(x: 0.02, y: 0.5)) == .left)
    #expect(s.edge(forPosition: NormalizedPoint(x: 0.03, y: 0.5)) == nil)
    // The inner boundary itself is outside the band.
    #expect(s.edge(forPosition: NormalizedPoint(x: s.leftEdge.bandWidth, y: 0.5)) == nil)
    // The outer limit is inside it.
    #expect(s.edge(forPosition: NormalizedPoint(x: 0, y: 0.5)) == .left)
}

@Test("the right band is exactly bandWidth wide, open at its inner boundary")
func rightBandBoundary() {
    let s = GestureSettings()
    #expect(s.edge(forPosition: NormalizedPoint(x: 0.98, y: 0.5)) == .right)
    #expect(s.edge(forPosition: NormalizedPoint(x: 0.97, y: 0.5)) == nil)
    #expect(s.edge(forPosition: NormalizedPoint(x: 1 - s.rightEdge.bandWidth, y: 0.5)) == nil)
    #expect(s.edge(forPosition: NormalizedPoint(x: 1, y: 0.5)) == .right)
}

// MARK: - Per-edge bandWidth

@Test("widening a single edge's band classifies x that a narrower band rejected")
func perEdgeBandWidthIsRespected() {
    var s = GestureSettings()
    #expect(s.edge(forPosition: NormalizedPoint(x: 0.04, y: 0.5)) == nil)
    s.leftEdge.bandWidth = 0.05
    #expect(s.edge(forPosition: NormalizedPoint(x: 0.04, y: 0.5)) == .left)
    // Right edge still has the original width
    #expect(s.edge(forPosition: NormalizedPoint(x: 0.96, y: 0.5)) == nil)
}

@Test("a zero-width band classifies nothing")
func zeroWidthBandDisablesClassification() {
    var s = GestureSettings()
    s.leftEdge.bandWidth = 0
    s.rightEdge.bandWidth = 0
    #expect(s.edge(forPosition: NormalizedPoint(x: 0, y: 0.5)) == nil)
    #expect(s.edge(forPosition: NormalizedPoint(x: 1, y: 0.5)) == nil)
}

// MARK: - Disabled edges

@Test("a disabled edge never classifies")
func disabledEdgeNeverClassifies() {
    var s = GestureSettings()
    s.leftEdge.isEnabled = false
    #expect(s.edge(forPosition: NormalizedPoint(x: 0.02, y: 0.5)) == nil)
    // Right is still enabled
    #expect(s.edge(forPosition: NormalizedPoint(x: 0.98, y: 0.5)) == .right)
}

@Test("disabled top edge does not classify even when position is in band")
func disabledTopEdge() {
    let s = GestureSettings()
    // top is disabled by default
    #expect(s.edge(forPosition: NormalizedPoint(x: 0.5, y: 0.99)) == nil)
}

// MARK: - Priority: vertical edges win over horizontal in corners

@Test("vertical edge wins over horizontal in a corner")
func verticalEdgePriorityInCorner() {
    var s = GestureSettings()
    s.topEdge.isEnabled = true
    s.bottomEdge.isEnabled = true
    // Position in both left band AND top band: left (vertical) wins
    let edge = s.edge(forPosition: NormalizedPoint(x: 0.02, y: 0.98))
    #expect(edge == .left)
    // Position in both right band AND bottom band: right (vertical) wins
    let edge2 = s.edge(forPosition: NormalizedPoint(x: 0.98, y: 0.02))
    #expect(edge2 == .right)
}

// MARK: - Overlapping bands

@Test("overlapping vertical bands resolve to the nearer edge")
func overlappingVerticalBandsResolveToNearerEdge() {
    var s = GestureSettings()
    s.leftEdge.bandWidth = 0.6
    s.rightEdge.bandWidth = 0.6
    #expect(s.edge(forPosition: NormalizedPoint(x: 0.45, y: 0.5)) == .left)
    #expect(s.edge(forPosition: NormalizedPoint(x: 0.55, y: 0.5)) == .right)
    // Tie goes to left
    #expect(s.edge(forPosition: NormalizedPoint(x: 0.5, y: 0.5)) == .left)
}

// MARK: - edgeConfig(for:) helper

@Test("edgeConfig returns the correct config for each edge")
func edgeConfigForEdge() {
    var s = GestureSettings()
    s.leftEdge.action = .zoom
    s.rightEdge.action = .scroll
    s.topEdge.action = .nextPreviousTrack
    s.bottomEdge.action = .brightness
    #expect(s.edgeConfig(for: .left).action == .zoom)
    #expect(s.edgeConfig(for: .right).action == .scroll)
    #expect(s.edgeConfig(for: .top).action == .nextPreviousTrack)
    #expect(s.edgeConfig(for: .bottom).action == .brightness)
}

// MARK: - effectiveStepDistance

@Test("fine control steps at exactly the configured step distance")
func fineStepDistance() {
    var s = GestureSettings()
    #expect(s.effectiveStepDistance == s.stepDistance)
    s.stepDistance = 0.05
    #expect(s.effectiveStepDistance == 0.05)
}

@Test("one full-height slide spans the control's whole range, fine or coarse")
func fullHeightSlideSpansTheRange() {
    var s = GestureSettings()
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

// MARK: - Relationship invariants

@Test("drift tolerance stays narrower than the band it is a tolerance for")
func driftToleranceIsNarrowerThanTheBand() {
    let s = GestureSettings()
    #expect(s.maxDriftOutsideBand < s.leftEdge.bandWidth)
    #expect(s.maxDriftOutsideBand < s.rightEdge.bandWidth)
    #expect(s.maxDriftOutsideBand > 0)
}

@Test("a stale gesture expires sooner than the typing lockout releases")
func gestureTimeoutExpiresBeforeTypingLockout() {
    let s = GestureSettings()
    #expect(s.gestureTimeout < s.typingLockout)
    #expect(s.gestureTimeout > 0)
}

@Test("the dead zone costs at least one step and at most a couple")
func deadZoneIsMeasuredInSteps() {
    let s = GestureSettings()
    let stepsSpentArming = s.activationDistance / s.effectiveStepDistance
    #expect(stepsSpentArming >= 1)
    #expect(stepsSpentArming < 3)
}

@Test("the bottom-quarter restriction ships off")
func bottomQuarterRestrictionShipsOff() {
    let s = GestureSettings()
    #expect(s.bottomQuarterOnly == false)
}

@Test("out-of-range x classifies as the edge it is beyond")
func outOfRangeXClassifiesAsTheNearerEdge() {
    let s = GestureSettings()
    #expect(s.edge(forPosition: NormalizedPoint(x: -0.5, y: 0.5)) == .left)
    #expect(s.edge(forPosition: NormalizedPoint(x: 1.5, y: 0.5)) == .right)
}
