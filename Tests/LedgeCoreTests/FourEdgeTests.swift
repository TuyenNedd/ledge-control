import Testing
import LedgeCore

private func frame(_ t: Double, _ x: Double, _ y: Double, id: Int = 1) -> TouchFrame {
    TouchFrame(timestamp: t, touches: [TouchPoint(id: id, position: NormalizedPoint(x: x, y: y))])
}

// MARK: - Top edge detection

@Test("touch near the top edge arms on the top edge when enabled")
func topEdgeDetection() {
    var settings = GestureSettings()
    settings.topEdge = EdgeConfig(action: .scroll, bandWidth: 0.025, isEnabled: true)
    var engine = GestureEngine(settings: settings)
    // y > 1 - 0.025 = 0.975, and x is in the middle (not in any vertical band)
    _ = engine.process(frame: frame(0.0, 0.5, 0.98))
    // Move horizontally to engage (primary axis for top/bottom is x)
    let events = engine.process(frame: frame(0.05, 0.55, 0.98))
    #expect(events.first == .engaged(.top, .scroll))
}

// MARK: - Bottom edge detection

@Test("touch near the bottom edge arms on the bottom edge when enabled")
func bottomEdgeDetection() {
    var settings = GestureSettings()
    settings.bottomEdge = EdgeConfig(action: .zoom, bandWidth: 0.025, isEnabled: true)
    var engine = GestureEngine(settings: settings)
    // y < 0.025, x in the middle
    _ = engine.process(frame: frame(0.0, 0.5, 0.02))
    // Move horizontally to engage
    let events = engine.process(frame: frame(0.05, 0.55, 0.02))
    #expect(events.first == .engaged(.bottom, .zoom))
}

// MARK: - Horizontal gesture activation

@Test("horizontal gesture on top edge: dx is primary axis, engage when abs(dx) > activationDistance")
func horizontalGestureActivation() {
    var settings = GestureSettings()
    settings.topEdge = EdgeConfig(action: .volume, bandWidth: 0.025, isEnabled: true)
    var engine = GestureEngine(settings: settings)
    _ = engine.process(frame: frame(0.0, 0.5, 0.98))
    // Small movement that does not clear the dead zone
    let small = engine.process(frame: frame(0.05, 0.51, 0.98))
    #expect(small.isEmpty)
    // Now clear the activation distance (0.02) with mostly horizontal travel
    let events = engine.process(frame: frame(0.10, 0.525, 0.98))
    #expect(events.first == .engaged(.top, .volume))
}

@Test("vertical movement on a horizontal edge does not engage")
func verticalMovementOnHorizontalEdgeRejected() {
    var settings = GestureSettings()
    settings.topEdge = EdgeConfig(action: .volume, bandWidth: 0.025, isEnabled: true)
    var engine = GestureEngine(settings: settings)
    _ = engine.process(frame: frame(0.0, 0.5, 0.98))
    // Move vertically (dy > dx) - should reject
    let events = engine.process(frame: frame(0.05, 0.51, 0.95))
    #expect(events.isEmpty)
}

// MARK: - Horizontal stepping

@Test("sliding right on top edge steps up")
func slidingRightOnTopEdgeStepsUp() {
    var settings = GestureSettings()
    settings.topEdge = EdgeConfig(action: .brightness, bandWidth: 0.025, isEnabled: true)
    var engine = GestureEngine(settings: settings)
    _ = engine.process(frame: frame(0.0, 0.3, 0.98))
    _ = engine.process(frame: frame(0.05, 0.35, 0.98))  // engage
    let events = engine.process(frame: frame(0.10, 0.45, 0.98))  // more steps
    #expect(!events.isEmpty)
    #expect(events.allSatisfy { $0 == .step(.top, .brightness, .up) })
}

@Test("sliding left on top edge steps down")
func slidingLeftOnTopEdgeStepsDown() {
    var settings = GestureSettings()
    settings.topEdge = EdgeConfig(action: .brightness, bandWidth: 0.025, isEnabled: true)
    var engine = GestureEngine(settings: settings)
    _ = engine.process(frame: frame(0.0, 0.7, 0.98))
    _ = engine.process(frame: frame(0.05, 0.65, 0.98))  // engage going left
    let events = engine.process(frame: frame(0.10, 0.55, 0.98))  // more steps
    #expect(!events.isEmpty)
    #expect(events.allSatisfy { $0 == .step(.top, .brightness, .down) })
}

@Test("sliding right on bottom edge steps up")
func slidingRightOnBottomEdgeStepsUp() {
    var settings = GestureSettings()
    settings.bottomEdge = EdgeConfig(action: .zoom, bandWidth: 0.025, isEnabled: true)
    var engine = GestureEngine(settings: settings)
    _ = engine.process(frame: frame(0.0, 0.3, 0.02))
    _ = engine.process(frame: frame(0.05, 0.35, 0.02))  // engage
    let events = engine.process(frame: frame(0.10, 0.45, 0.02))
    #expect(!events.isEmpty)
    #expect(events.allSatisfy { $0 == .step(.bottom, .zoom, .up) })
}

// MARK: - Corner priority: vertical edges win

@Test("position in both left band and top band resolves to left (vertical wins)")
func cornerPriorityLeftWinsOverTop() {
    var settings = GestureSettings()
    settings.topEdge = EdgeConfig(action: .scroll, bandWidth: 0.025, isEnabled: true)
    var engine = GestureEngine(settings: settings)
    // x = 0.02 is in left band, y = 0.98 is in top band
    _ = engine.process(frame: frame(0.0, 0.02, 0.98))
    // Move vertically (appropriate for left edge)
    let events = engine.process(frame: frame(0.05, 0.02, 0.93))
    // Should engage on left edge with brightness (not top edge with scroll)
    #expect(events.first == .engaged(.left, .brightness))
}

@Test("position in both right band and bottom band resolves to right (vertical wins)")
func cornerPriorityRightWinsOverBottom() {
    var settings = GestureSettings()
    settings.bottomEdge = EdgeConfig(action: .zoom, bandWidth: 0.025, isEnabled: true)
    var engine = GestureEngine(settings: settings)
    // x = 0.98 is in right band, y = 0.02 is in bottom band
    _ = engine.process(frame: frame(0.0, 0.98, 0.02))
    // Move vertically
    let events = engine.process(frame: frame(0.05, 0.98, 0.07))
    #expect(events.first == .engaged(.right, .volume))
}

// MARK: - Disabled edge

@Test("a disabled edge does not arm")
func disabledEdgeDoesNotArm() {
    var settings = GestureSettings()
    settings.rightEdge.isEnabled = false
    var engine = GestureEngine(settings: settings)
    _ = engine.process(frame: frame(0.0, 0.98, 0.40))
    let events = engine.process(frame: frame(0.05, 0.98, 0.45))
    #expect(events.isEmpty)
}

@Test("a disabled top edge does not arm even with position in band")
func disabledTopEdgeDoesNotArm() {
    let settings = GestureSettings()
    // top edge disabled by default
    var engine = GestureEngine(settings: settings)
    _ = engine.process(frame: frame(0.0, 0.5, 0.98))
    let events = engine.process(frame: frame(0.05, 0.55, 0.98))
    #expect(events.isEmpty)
}

// MARK: - Per-edge bandWidth

@Test("different band widths per edge work correctly")
func perEdgeBandWidth() {
    var settings = GestureSettings()
    settings.leftEdge.bandWidth = 0.05  // wider left band
    settings.rightEdge.bandWidth = 0.01  // narrower right band
    var engine = GestureEngine(settings: settings)

    // x = 0.04 is inside the wider left band (0.05) but would be outside default (0.025)
    _ = engine.process(frame: frame(0.0, 0.04, 0.40))
    let leftEvents = engine.process(frame: frame(0.05, 0.04, 0.45))
    #expect(leftEvents.first == .engaged(.left, .brightness))

    // x = 0.98 is outside the narrower right band (needs x > 0.99)
    var engine2 = GestureEngine(settings: settings)
    _ = engine2.process(frame: frame(0.0, 0.98, 0.40))
    let rightEvents = engine2.process(frame: frame(0.05, 0.98, 0.45))
    #expect(rightEvents.isEmpty)  // rejected because 0.98 is not > 0.99
}

// MARK: - Drift check for horizontal edges

@Test("y-drift beyond tolerance ends gesture on top edge")
func yDriftEndsTopEdgeGesture() {
    var settings = GestureSettings()
    settings.topEdge = EdgeConfig(action: .volume, bandWidth: 0.025, isEnabled: true)
    var engine = GestureEngine(settings: settings)
    _ = engine.process(frame: frame(0.0, 0.5, 0.98))
    _ = engine.process(frame: frame(0.05, 0.55, 0.98))  // engage

    // Drift away from top edge: y drops below 1 - bandWidth - maxDrift
    // 1 - 0.025 - 0.02 = 0.955, so going below that ends it
    let events = engine.process(frame: frame(0.10, 0.60, 0.93))
    #expect(events == [.disengaged(.top)])
}

@Test("y-drift within tolerance keeps gesture on top edge alive")
func yDriftWithinToleranceOnTopEdge() {
    var settings = GestureSettings()
    settings.topEdge = EdgeConfig(action: .volume, bandWidth: 0.025, isEnabled: true)
    var engine = GestureEngine(settings: settings)
    _ = engine.process(frame: frame(0.0, 0.5, 0.98))
    _ = engine.process(frame: frame(0.05, 0.55, 0.98))  // engage

    // Stay within tolerance: y = 0.96 is above 1 - 0.025 - 0.02 = 0.955
    let events = engine.process(frame: frame(0.10, 0.60, 0.96))
    #expect(!events.isEmpty)
    #expect(events.allSatisfy { $0 == .step(.top, .volume, .up) })
}

@Test("y-drift beyond tolerance ends gesture on bottom edge")
func yDriftEndsBottomEdgeGesture() {
    var settings = GestureSettings()
    settings.bottomEdge = EdgeConfig(action: .zoom, bandWidth: 0.025, isEnabled: true)
    var engine = GestureEngine(settings: settings)
    _ = engine.process(frame: frame(0.0, 0.5, 0.02))
    _ = engine.process(frame: frame(0.05, 0.55, 0.02))  // engage

    // Drift away from bottom edge: y rises above bandWidth + maxDrift
    // 0.025 + 0.02 = 0.045, so going above that ends it
    let events = engine.process(frame: frame(0.10, 0.60, 0.05))
    #expect(events == [.disengaged(.bottom)])
}

// MARK: - Mid-gesture settings snapshot for horizontal edges

@Test("settings snapshot works for horizontal edges too")
func settingsSnapshotForHorizontalEdges() {
    var settings = GestureSettings()
    settings.topEdge = EdgeConfig(action: .scroll, bandWidth: 0.025, isEnabled: true)
    var engine = GestureEngine(settings: settings)
    _ = engine.process(frame: frame(0.0, 0.5, 0.98))
    let engaged = engine.process(frame: frame(0.05, 0.55, 0.98))
    #expect(engaged.first == .engaged(.top, .scroll))

    // Change action mid-gesture - should not affect current gesture
    engine.settings.topEdge.action = .brightness
    let steps = engine.process(frame: frame(0.10, 0.65, 0.98))
    #expect(steps.allSatisfy { $0 == .step(.top, .scroll, .up) })

    // Disengage
    let lift = engine.process(frame: TouchFrame(timestamp: 0.15, touches: []))
    #expect(lift == [.disengaged(.top)])
}

// MARK: - Step count for horizontal gestures

@Test("step count on horizontal edge matches travel from start divided by step distance")
func horizontalStepCountMatchesTravel() {
    var settings = GestureSettings()
    settings.topEdge = EdgeConfig(action: .volume, bandWidth: 0.025, isEnabled: true)
    var engine = GestureEngine(settings: settings)
    _ = engine.process(frame: frame(0.0, 0.1, 0.98))
    let events = engine.process(frame: frame(0.05, 0.9, 0.98))
    let steps = events.filter { $0 == .step(.top, .volume, .up) }.count
    #expect(steps == Int((0.80 / settings.effectiveStepDistance).rounded(.down)))
}

// MARK: - Engagement on left edge (brightness by default)

@Test("left edge engages with brightness action by default")
func leftEdgeEngagesBrightness() {
    var engine = GestureEngine()
    _ = engine.process(frame: frame(0.0, 0.02, 0.40))
    let events = engine.process(frame: frame(0.05, 0.02, 0.45))
    #expect(events.first == .engaged(.left, .brightness))
}

@Test("left edge disengages with just the edge")
func leftEdgeDisengages() {
    var engine = GestureEngine()
    _ = engine.process(frame: frame(0.0, 0.02, 0.40))
    _ = engine.process(frame: frame(0.05, 0.02, 0.45))
    let lift = engine.process(frame: TouchFrame(timestamp: 0.10, touches: []))
    #expect(lift == [.disengaged(.left)])
}

// MARK: - Custom action assignment

@Test("custom action assignment works per edge")
func customActionAssignment() {
    var settings = GestureSettings()
    settings.rightEdge.action = .nextPreviousTrack
    var engine = GestureEngine(settings: settings)
    _ = engine.process(frame: frame(0.0, 0.98, 0.40))
    let events = engine.process(frame: frame(0.05, 0.98, 0.45))
    #expect(events.first == .engaged(.right, .nextPreviousTrack))
}
