import Testing
import LedgeCore

private func frame(_ t: Double, _ x: Double, _ y: Double, id: Int = 1) -> TouchFrame {
    TouchFrame(timestamp: t, touches: [TouchPoint(id: id, position: NormalizedPoint(x: x, y: y))])
}

private func touch(_ id: Int, _ x: Double, _ y: Double) -> TouchPoint {
    TouchPoint(id: id, position: NormalizedPoint(x: x, y: y))
}

/// Engages a gesture on the right edge, ending at t = 0.05 with the finger at y = 0.45.
private func engagedOnTheRight(_ settings: GestureSettings = GestureSettings()) -> GestureEngine {
    var engine = GestureEngine(settings: settings)
    _ = engine.process(frame: frame(0.0, 0.98, 0.40))
    #expect(engine.process(frame: frame(0.05, 0.98, 0.45)).first == .engaged(.right, .volume))
    return engine
}

@Test("a second finger arriving ends the gesture")
func secondTouchDisengages() {
    var engine = engagedOnTheRight()
    let events = engine.process(frame: TouchFrame(
        timestamp: 0.10,
        touches: [touch(1, 0.98, 0.50), touch(2, 0.60, 0.50)]
    ))
    #expect(events == [.disengaged(.right)])
}

@Test("more than one finger never arms a gesture")
func multipleTouchesNeverArm() {
    var engine = GestureEngine()
    var events: [GestureEvent] = []
    events += engine.process(frame: TouchFrame(timestamp: 0.0, touches: [touch(1, 0.98, 0.40), touch(2, 0.90, 0.40)]))
    events += engine.process(frame: TouchFrame(timestamp: 0.05, touches: [touch(1, 0.98, 0.50), touch(2, 0.90, 0.50)]))
    events += engine.process(frame: TouchFrame(timestamp: 0.10, touches: [touch(1, 0.98, 0.60), touch(2, 0.90, 0.60)]))
    #expect(events.isEmpty)
}

@Test("drifting past the band plus its tolerance ends the gesture")
func driftBeyondToleranceDisengages() {
    let settings = GestureSettings()
    var engine = engagedOnTheRight(settings)
    let limit = 1 - (settings.rightEdge.bandWidth + settings.maxDriftOutsideBand)
    let events = engine.process(frame: frame(0.10, limit - 0.01, 0.50))
    #expect(events == [.disengaged(.right)])
}

@Test("drifting within the tolerance keeps the gesture alive")
func driftWithinToleranceKeepsStepping() {
    let settings = GestureSettings()
    var engine = engagedOnTheRight(settings)
    let limit = 1 - (settings.rightEdge.bandWidth + settings.maxDriftOutsideBand)
    let events = engine.process(frame: frame(0.10, limit + 0.01, 0.55))
    #expect(!events.isEmpty)
    #expect(events.allSatisfy { $0 == .step(.right, .volume, .up) })
}

@Test("a keystroke suppresses gestures for the lockout window")
func typingSuppressesEngagement() {
    var engine = GestureEngine()
    #expect(engine.noteTyping(at: 1.0).isEmpty)
    _ = engine.process(frame: frame(1.1, 0.98, 0.40))
    let events = engine.process(frame: frame(1.15, 0.98, 0.50))
    #expect(events.isEmpty)
}

@Test("a keystroke during a gesture ends it")
func typingWhileEngagedDisengages() {
    var engine = engagedOnTheRight()
    #expect(engine.noteTyping(at: 0.10) == [.disengaged(.right)])
    #expect(engine.noteTyping(at: 0.11).isEmpty)
}

@Test("gestures work again once the lockout has elapsed")
func gesturesResumeAfterLockout() {
    let settings = GestureSettings()
    var engine = GestureEngine(settings: settings)
    _ = engine.noteTyping(at: 1.0)
    let after = 1.0 + settings.typingLockout + 0.01
    _ = engine.process(frame: frame(after, 0.98, 0.40))
    #expect(engine.process(frame: frame(after + 0.05, 0.98, 0.45)).first == .engaged(.right, .volume))
}

@Test("a gap longer than the timeout restarts the gesture instead of resuming it")
func staleGestureRestarts() {
    let settings = GestureSettings()
    var engine = engagedOnTheRight(settings)
    let afterTheGap = 0.05 + settings.gestureTimeout + 0.01
    let events = engine.process(frame: frame(afterTheGap, 0.98, 0.80))
    #expect(events == [.disengaged(.right)])
    #expect(!events.contains { if case .step = $0 { return true }; return false })
    let resumed = engine.process(frame: frame(afterTheGap + 0.05, 0.98, 0.85))
    #expect(resumed.first == .engaged(.right, .volume))
}

@Test("bottomQuarterOnly refuses a touch that starts above the bottom quarter")
func bottomQuarterRejectsHighStart() {
    var settings = GestureSettings()
    settings.bottomQuarterOnly = true
    var engine = GestureEngine(settings: settings)
    _ = engine.process(frame: frame(0.0, 0.98, 0.30))
    #expect(engine.process(frame: frame(0.05, 0.98, 0.40)).isEmpty)
}

@Test("bottomQuarterOnly accepts a touch that starts in the bottom quarter")
func bottomQuarterAcceptsLowStart() {
    var settings = GestureSettings()
    settings.bottomQuarterOnly = true
    var engine = GestureEngine(settings: settings)
    _ = engine.process(frame: frame(0.0, 0.98, 0.20))
    #expect(engine.process(frame: frame(0.05, 0.98, 0.60)).first == .engaged(.right, .volume))
}

@Test("being switched off ends the gesture and suppresses everything after")
func disablingSuppressesEverything() {
    var engine = engagedOnTheRight()
    #expect(engine.isEnabled)
    #expect(engine.setEnabled(false) == [.disengaged(.right)])
    #expect(!engine.isEnabled)
    _ = engine.process(frame: frame(0.20, 0.98, 0.40))
    #expect(engine.process(frame: frame(0.25, 0.98, 0.50)).isEmpty)
    #expect(engine.noteTyping(at: 0.30).isEmpty)
}

@Test("switching off twice reports the gesture ending only once")
func disablingIsIdempotent() {
    var engine = engagedOnTheRight()
    #expect(engine.setEnabled(false) == [.disengaged(.right)])
    #expect(engine.setEnabled(false).isEmpty)
}

@Test("re-enabling allows a fresh gesture")
func reEnablingRestoresGestures() {
    var engine = engagedOnTheRight()
    _ = engine.setEnabled(false)
    #expect(engine.setEnabled(true).isEmpty)
    #expect(engine.isEnabled)
    _ = engine.process(frame: frame(0.30, 0.98, 0.40))
    #expect(engine.process(frame: frame(0.35, 0.98, 0.45)).first == .engaged(.right, .volume))
}

@Test("cancel ends a gesture in flight and is silent when there is none")
func cancelEndsTheGesture() {
    var engine = engagedOnTheRight()
    #expect(engine.cancel() == [.disengaged(.right)])
    #expect(engine.cancel().isEmpty)
    _ = engine.process(frame: frame(0.20, 0.98, 0.40))
    #expect(engine.process(frame: frame(0.25, 0.98, 0.45)).first == .engaged(.right, .volume))
}

@Test("a gap while armed discards the stale start position")
func staleArmingIsDiscarded() {
    let settings = GestureSettings()
    var engine = GestureEngine()
    _ = engine.process(frame: frame(0.0, 0.98, 0.40))
    let afterTheGap = settings.gestureTimeout + 0.01
    #expect(engine.process(frame: frame(afterTheGap, 0.98, 0.45)).isEmpty)
    #expect(engine.process(frame: frame(afterTheGap + 0.05, 0.98, 0.50)).first == .engaged(.right, .volume))
}

@Test("a gap does not give a disqualified finger a second chance")
func staleRejectionIsNotForgiven() {
    let settings = GestureSettings()
    var engine = GestureEngine()
    _ = engine.process(frame: frame(0.0, 0.5, 0.40))
    _ = engine.process(frame: frame(0.05, 0.5, 0.50))
    let afterTheGap = 0.05 + settings.gestureTimeout + 0.01
    _ = engine.process(frame: frame(afterTheGap, 0.98, 0.40))
    #expect(engine.process(frame: frame(afterTheGap + 0.05, 0.98, 0.50)).isEmpty)
}

@Test("a different finger replacing the engaged one ends the gesture")
func replacedTouchDisengages() {
    var engine = engagedOnTheRight()
    let events = engine.process(frame: TouchFrame(timestamp: 0.10, touches: [touch(2, 0.98, 0.50)]))
    #expect(events == [.disengaged(.right)])
    #expect(engine.process(frame: TouchFrame(timestamp: 0.15, touches: [touch(2, 0.98, 0.55)])).isEmpty)
    #expect(engine.process(frame: TouchFrame(timestamp: 0.20, touches: [touch(2, 0.98, 0.60)])).first
        == .engaged(.right, .volume))
}
