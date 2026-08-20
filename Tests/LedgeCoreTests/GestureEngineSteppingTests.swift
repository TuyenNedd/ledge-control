import Testing
import LedgeCore

private func frame(_ t: Double, _ x: Double, _ y: Double, id: Int = 1) -> TouchFrame {
    TouchFrame(timestamp: t, touches: [TouchPoint(id: id, position: NormalizedPoint(x: x, y: y))])
}

/// Engages a gesture on the right edge and returns the engine with the anchor at `y`.
private func engagedOnTheRight(from y: Double = 0.40, settings: GestureSettings = GestureSettings())
    -> (engine: GestureEngine, engagementEvents: [GestureEvent], engagedAt: Double)
{
    var engine = GestureEngine(settings: settings)
    _ = engine.process(frame: frame(0.0, 0.98, y))
    let events = engine.process(frame: frame(0.05, 0.98, y + 0.05))
    return (engine, events, y + 0.05)
}

@Test("sliding up the right edge steps volume up")
func slidingUpStepsUp() {
    var engine = GestureEngine()
    _ = engine.process(frame: frame(0.0, 0.98, 0.40))
    _ = engine.process(frame: frame(0.05, 0.98, 0.45))
    let events = engine.process(frame: frame(0.10, 0.98, 0.55))
    #expect(!events.isEmpty)
    #expect(events.allSatisfy { $0 == .step(.right, .volume, .up) })
}

@Test("sliding down the right edge steps volume down")
func slidingDownStepsDown() {
    var engine = GestureEngine()
    _ = engine.process(frame: frame(0.0, 0.98, 0.60))
    _ = engine.process(frame: frame(0.05, 0.98, 0.55))
    let events = engine.process(frame: frame(0.10, 0.98, 0.45))
    #expect(!events.isEmpty)
    #expect(events.allSatisfy { $0 == .step(.right, .volume, .down) })
}

@Test("a gesture engages with its first step already due")
func engagementEmitsItsFirstStepImmediately() {
    let (_, events, _) = engagedOnTheRight()
    #expect(events.first == .engaged(.right, .volume))
    #expect(events.dropFirst().allSatisfy { $0 == .step(.right, .volume, .up) })
    #expect(events.count > 1)
}

@Test("step count over a slide is total travel from the start divided by step distance")
func stepCountMatchesTravel() {
    var engine = GestureEngine()
    let settings = GestureSettings()
    _ = engine.process(frame: frame(0.0, 0.98, 0.10))
    let events = engine.process(frame: frame(0.05, 0.98, 0.90))
    let steps = events.filter { $0 == .step(.right, .volume, .up) }.count
    #expect(steps == Int((0.80 / settings.effectiveStepDistance).rounded(.down)))
}

@Test("the same travel in many small frames yields the same steps as one big frame")
func anchoringDoesNotDrift() {
    let settings = GestureSettings()
    let startY = 0.10
    let ys = (1...80).map { startY + Double($0) * 0.01 }

    var fineGrained = GestureEngine(settings: settings)
    _ = fineGrained.process(frame: frame(0.0, 0.98, startY))
    var manyFrameSteps = 0
    for (i, y) in ys.enumerated() {
        manyFrameSteps += fineGrained.process(frame: frame(Double(i + 1) * 0.02, 0.98, y))
            .filter { $0 == .step(.right, .volume, .up) }.count
    }

    var oneShot = GestureEngine(settings: settings)
    _ = oneShot.process(frame: frame(0.0, 0.98, startY))
    let oneFrameSteps = oneShot.process(frame: frame(0.02, 0.98, ys.last!))
        .filter { $0 == .step(.right, .volume, .up) }.count

    #expect(manyFrameSteps == oneFrameSteps)
    #expect(manyFrameSteps == Int(((ys.last! - startY) / settings.effectiveStepDistance).rounded(.down)))
}

@Test("reversing direction costs a full step of travel before it emits")
func reversalHasOneStepOfHysteresis() {
    let settings = GestureSettings()
    let step = settings.effectiveStepDistance
    var (engine, _, top) = engagedOnTheRight()
    let jitter = engine.process(frame: frame(0.10, 0.98, top - step * 0.9))
    #expect(jitter.isEmpty)
    let reversal = engine.process(frame: frame(0.15, 0.98, top - step * 2))
    #expect(reversal.contains(.step(.right, .volume, .down)))
    #expect(reversal.allSatisfy { $0 == .step(.right, .volume, .down) })
}

@Test("lifting the finger disengages exactly once")
func liftingDisengagesOnce() {
    var engine = GestureEngine()
    _ = engine.process(frame: frame(0.0, 0.98, 0.40))
    _ = engine.process(frame: frame(0.05, 0.98, 0.50))
    let lift = engine.process(frame: TouchFrame(timestamp: 0.10, touches: []))
    #expect(lift == [.disengaged(.right)])
    let after = engine.process(frame: TouchFrame(timestamp: 0.15, touches: []))
    #expect(after.isEmpty)
}

@Test("lifting a finger that never engaged emits nothing")
func liftingAnArmedFingerIsSilent() {
    var engine = GestureEngine()
    _ = engine.process(frame: frame(0.0, 0.98, 0.40))
    let lift = engine.process(frame: TouchFrame(timestamp: 0.05, touches: []))
    #expect(lift.isEmpty)
}

@Test("a gesture in flight keeps the action it engaged with when settings change")
func midGestureSettingsChangeDoesNotSplitTheGesture() {
    var engine = GestureEngine()
    _ = engine.process(frame: frame(0.0, 0.98, 0.40))
    #expect(engine.process(frame: frame(0.05, 0.98, 0.45)).first == .engaged(.right, .volume))
    // Change the right edge's action mid-gesture
    engine.settings.rightEdge.action = .brightness
    let steps = engine.process(frame: frame(0.10, 0.98, 0.55))
    #expect(steps.allSatisfy { $0 == .step(.right, .volume, .up) })
    #expect(engine.process(frame: TouchFrame(timestamp: 0.15, touches: [])) == [.disengaged(.right)])
    // The next gesture does pick up the new action.
    _ = engine.process(frame: frame(0.20, 0.98, 0.40))
    #expect(engine.process(frame: frame(0.25, 0.98, 0.45)).first == .engaged(.right, .brightness))
}

@Test("a zero step distance engages without emitting steps instead of hanging")
func zeroStepDistanceEmitsNoSteps() {
    var settings = GestureSettings()
    settings.stepDistance = 0
    var engine = GestureEngine(settings: settings)
    _ = engine.process(frame: frame(0.0, 0.98, 0.10))
    let events = engine.process(frame: frame(0.05, 0.98, 0.90))
    #expect(events == [.engaged(.right, .volume)])
    #expect(engine.process(frame: TouchFrame(timestamp: 0.10, touches: [])) == [.disengaged(.right)])
}

@Test("an absurd position emits no steps rather than trapping")
func absurdPositionEmitsNoSteps() {
    var engine = GestureEngine()
    _ = engine.process(frame: frame(0.0, 0.98, 0.40))
    _ = engine.process(frame: frame(0.05, 0.98, 0.45))
    let events = engine.process(frame: frame(0.10, 0.98, 1e30))
    #expect(events.isEmpty)
    #expect(engine.process(frame: TouchFrame(timestamp: 0.15, touches: [])) == [.disengaged(.right)])
}

@Test("settings that change while a finger is armed do not apply to that finger")
func settingsAreSnapshottedWhenTheGestureBegins() {
    var engine = GestureEngine()
    _ = engine.process(frame: frame(0.0, 0.98, 0.40))
    engine.settings.rightEdge.action = .brightness
    // Snapshot was taken when gesture began (armed), so it still uses volume
    #expect(engine.process(frame: frame(0.05, 0.98, 0.45)).first == .engaged(.right, .volume))

    // Same applies to step distance
    var retuned = GestureEngine()
    _ = retuned.process(frame: frame(0.0, 0.98, 0.40))
    retuned.settings.stepDistance = 0.2
    let events = retuned.process(frame: frame(0.05, 0.98, 0.45))
    #expect(events == [.engaged(.right, .volume), .step(.right, .volume, .up), .step(.right, .volume, .up), .step(.right, .volume, .up)])
}
