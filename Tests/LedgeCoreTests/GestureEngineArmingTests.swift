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
    _ = engine.process(frame: frame(0.0, 0.5, 0.2))
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

@Test("clearing the dead zone engages the control for that edge")
func clearingDeadZoneEngages() {
    var engine = GestureEngine()
    _ = engine.process(frame: frame(0.0, 0.02, 0.40))
    let events = engine.process(frame: frame(0.05, 0.02, 0.45))
    #expect(events.first == .engaged(.brightness))
}

@Test("a gesture that starts out sideways never engages")
func horizontalGestureRejected() {
    var engine = GestureEngine()
    _ = engine.process(frame: frame(0.0, 0.02, 0.40))
    let events = engine.process(frame: frame(0.05, 0.12, 0.43))
    #expect(events.isEmpty)
}

@Test("the engine obeys the settings it was constructed with, not the defaults")
func injectedSettingsAreHonoured() {
    var settings = GestureSettings()
    settings.edgeBandWidth = 0.3
    var engine = GestureEngine(settings: settings)
    // x = 0.20 is outside the default 0.10 band and inside this 0.30 one, so an engine that
    // quietly used `GestureSettings()` instead of the value it was handed cannot pass.
    _ = engine.process(frame: frame(0.0, 0.20, 0.40))
    let events = engine.process(frame: frame(0.05, 0.20, 0.45))
    #expect(events.first == .engaged(.brightness))
}

@Test("a finger that has disqualified itself stays disqualified while it is down")
func rejectedTouchIsNotReEvaluated() {
    var engine = GestureEngine()
    // Starts in the middle, so it can never be a gesture. Later frames put it deep in the
    // left band moving cleanly upward — every arming condition a fresh touch would have to
    // meet. Without a rejected state the engine re-decides each frame and engages here, which
    // is precisely the mid-scroll false positive the "must start in the band" rule exists to
    // stop.
    _ = engine.process(frame: frame(0.0, 0.5, 0.40))
    _ = engine.process(frame: frame(0.05, 0.2, 0.50))
    _ = engine.process(frame: frame(0.10, 0.02, 0.60))
    let events = engine.process(frame: frame(0.15, 0.02, 0.70))
    #expect(events.isEmpty)
}


@Test("equal vertical and horizontal travel is not enough to engage")
func diagonalTieRejected() {
    var engine = GestureEngine()
    _ = engine.process(frame: frame(0.0, 0.0625, 0.5))
    // dx and dy are both exactly +0.03125: past the dead zone, but exactly as horizontal as it
    // is vertical. The tie is resolved against engaging, because an ambiguous stroke wrongly
    // taken for a gesture costs the user a volume change they did not ask for, while an
    // ambiguous stroke wrongly ignored costs them a second attempt.
    //
    // The coordinates are powers of two on purpose. Round-looking decimals do not tie: with
    // 0.40→0.43 and 0.02→0.05 the two deltas differ in the last bit, so the test would pass
    // against an implementation that accepts ties and prove nothing.
    let events = engine.process(frame: frame(0.05, 0.09375, 0.53125))
    #expect(events.isEmpty)
}

@Test("a slow stroke engages once its travel adds up, however small each frame is")
func slowStrokeStillEngages() {
    var engine = GestureEngine()
    _ = engine.process(frame: frame(0.0, 0.02, 0.40))
    var events: [GestureEvent] = []
    // Five frames of 0.01 — every single one of them smaller than the dead zone. The dead zone
    // is measured from where the finger started, not from the previous frame, so a deliberate
    // slow slide engages; measured per frame it never would, and slow gestures would silently
    // stop working.
    for i in 1...5 {
        events += engine.process(frame: frame(Double(i) * 0.02, 0.02, 0.40 + Double(i) * 0.01))
    }
    #expect(events.first == .engaged(.brightness))
    // Once, not once per frame: engaging is a transition, and an adapter that opened a control
    // twice would owe two closes.
    #expect(events.filter { $0 == .engaged(.brightness) }.count == 1)
}
