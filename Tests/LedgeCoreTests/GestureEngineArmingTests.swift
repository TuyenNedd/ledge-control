import Testing

// Plain import, not `@testable`: the engine is what the macOS layer consumes, so its surface
// has to be exercised exactly as that layer will see it.
import LedgeCore

private func frame(_ t: Double, _ x: Double, _ y: Double, id: Int = 1) -> TouchFrame {
    TouchFrame(timestamp: t, touches: [TouchPoint(id: id, position: NormalizedPoint(x: x, y: y))])
}

@Test("a touch starting in the middle never engages")
func centreTouchNeverEngages() {
    var engine = GestureEngine()
    _ = engine.process(frame: frame(0.0, 0.5, 0.5))
    let events = engine.process(frame: frame(0.05, 0.5, 0.8))
    #expect(events.isEmpty)
}

@Test("a touch starting in the band does not engage before the dead zone is cleared")
func deadZoneSuppressesEngagement() {
    var engine = GestureEngine()
    _ = engine.process(frame: frame(0.0, 0.02, 0.40))
    let events = engine.process(frame: frame(0.05, 0.02, 0.41))
    #expect(events.isEmpty)
}

@Test("clearing the dead zone engages the action for that edge")
func clearingDeadZoneEngages() {
    var engine = GestureEngine()
    _ = engine.process(frame: frame(0.0, 0.02, 0.40))
    let events = engine.process(frame: frame(0.05, 0.02, 0.45))
    #expect(events.first == .engaged(.left, .brightness))
}

@Test("a gesture that starts out sideways never engages on a vertical edge")
func horizontalGestureRejectedOnVerticalEdge() {
    var engine = GestureEngine()
    _ = engine.process(frame: frame(0.0, 0.02, 0.40))
    let events = engine.process(frame: frame(0.05, 0.12, 0.43))
    #expect(events.isEmpty)
}

@Test("the engine obeys the settings it was constructed with, not the defaults")
func injectedSettingsAreHonoured() {
    var settings = GestureSettings()
    settings.leftEdge.bandWidth = 0.3
    var engine = GestureEngine(settings: settings)
    _ = engine.process(frame: frame(0.0, 0.20, 0.40))
    let events = engine.process(frame: frame(0.05, 0.20, 0.45))
    #expect(events.first == .engaged(.left, .brightness))
}

@Test("a finger that has disqualified itself stays disqualified while it is down")
func rejectedTouchIsNotReEvaluated() {
    var engine = GestureEngine()
    _ = engine.process(frame: frame(0.0, 0.5, 0.40))
    _ = engine.process(frame: frame(0.05, 0.2, 0.50))
    _ = engine.process(frame: frame(0.10, 0.02, 0.60))
    let events = engine.process(frame: frame(0.15, 0.02, 0.70))
    #expect(events.isEmpty)
}

@Test("equal vertical and horizontal travel is not enough to engage on vertical edge")
func diagonalTieRejected() {
    var engine = GestureEngine()
    _ = engine.process(frame: frame(0.0, 0.0625, 0.5))
    let events = engine.process(frame: frame(0.05, 0.09375, 0.53125))
    #expect(events.isEmpty)
}

@Test("a slow stroke engages once its travel adds up, however small each frame is")
func slowStrokeStillEngages() {
    var engine = GestureEngine()
    _ = engine.process(frame: frame(0.0, 0.02, 0.40))
    var events: [GestureEvent] = []
    for i in 1...5 {
        events += engine.process(frame: frame(Double(i) * 0.02, 0.02, 0.40 + Double(i) * 0.01))
    }
    #expect(events.first == .engaged(.left, .brightness))
    #expect(events.filter { $0 == .engaged(.left, .brightness) }.count == 1)
}
