import Testing
import LedgeCore

private func frame(_ t: Double, _ x: Double, _ y: Double, id: Int = 1) -> TouchFrame {
    TouchFrame(timestamp: t, touches: [TouchPoint(id: id, position: NormalizedPoint(x: x, y: y))])
}

/// Engages a gesture on the right edge and returns the engine with the anchor at `y`.
///
/// Engagement itself emits steps, because the dead zone is wider than one step (see
/// `GestureSettings.activationDistance`), so tests that care only about later steps start from
/// here rather than re-deriving it.
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
    #expect(events.allSatisfy { $0 == .step(.volume, .up) })
}

@Test("sliding down the right edge steps volume down")
func slidingDownStepsDown() {
    var engine = GestureEngine()
    _ = engine.process(frame: frame(0.0, 0.98, 0.60))
    _ = engine.process(frame: frame(0.05, 0.98, 0.55))
    let events = engine.process(frame: frame(0.10, 0.98, 0.45))
    #expect(!events.isEmpty)
    #expect(events.allSatisfy { $0 == .step(.volume, .down) })
}

@Test("a gesture engages with its first step already due")
func engagementEmitsItsFirstStepImmediately() {
    let (_, events, _) = engagedOnTheRight()
    // The dead zone (0.02) is wider than a step (0.016) and the anchor is the touch's *start*,
    // so travel spent arming counts. Recognition therefore produces feedback in the same frame
    // instead of leaving the gesture silent for another step's worth of travel.
    #expect(events.first == .engaged(.volume))
    #expect(events.dropFirst().allSatisfy { $0 == .step(.volume, .up) })
    #expect(events.count > 1)
}

@Test("step count over a slide is total travel from the start divided by step distance")
func stepCountMatchesTravel() {
    var engine = GestureEngine()
    let settings = GestureSettings()
    _ = engine.process(frame: frame(0.0, 0.98, 0.10))
    let events = engine.process(frame: frame(0.05, 0.98, 0.90))
    let steps = events.filter { $0 == .step(.volume, .up) }.count
    // Measured from where the finger started, not from where it engaged: the dead zone is not
    // travel the user loses, so `activationDistance` does not appear in this expression and
    // retuning it cannot change the total.
    #expect(steps == Int((0.80 / settings.effectiveStepDistance).rounded(.down)))
}

@Test("the same travel in many small frames yields the same steps as one big frame")
func anchoringDoesNotDrift() {
    let settings = GestureSettings()
    let startY = 0.10
    // 80 frames of 0.01 each — deliberately not a whole number of steps per frame, so every
    // frame leaves a remainder that a per-frame implementation would throw away, and each
    // endpoint is computed from an integer so both engines are fed the *identical* final y.
    let ys = (1...80).map { startY + Double($0) * 0.01 }

    var fineGrained = GestureEngine(settings: settings)
    _ = fineGrained.process(frame: frame(0.0, 0.98, startY))
    var manyFrameSteps = 0
    for (i, y) in ys.enumerated() {
        manyFrameSteps += fineGrained.process(frame: frame(Double(i + 1) * 0.02, 0.98, y))
            .filter { $0 == .step(.volume, .up) }.count
    }

    var oneShot = GestureEngine(settings: settings)
    _ = oneShot.process(frame: frame(0.0, 0.98, startY))
    let oneFrameSteps = oneShot.process(frame: frame(0.02, 0.98, ys.last!))
        .filter { $0 == .step(.volume, .up) }.count

    // The property the anchor exists for. Accumulating per-frame deltas, or advancing the
    // anchor by repeated addition of a fractional step, both lose or gain steps here: 80
    // truncations of 0.01/0.016 emit nothing at all, and 50 additions of 0.016 to 0.10 land
    // above 0.90 and lose the last step.
    #expect(manyFrameSteps == oneFrameSteps)
    #expect(manyFrameSteps == Int(((ys.last! - startY) / settings.effectiveStepDistance).rounded(.down)))
}

@Test("reversing direction costs a full step of travel before it emits")
func reversalHasOneStepOfHysteresis() {
    let settings = GestureSettings()
    let step = settings.effectiveStepDistance
    var (engine, _, top) = engagedOnTheRight()
    // The anchor sits at or just below `top`, so coming back down less than one step must emit
    // nothing: without hysteresis a finger held almost still at a step boundary alternates up
    // and down forever, which is a stream of haptic pulses for no movement.
    let jitter = engine.process(frame: frame(0.10, 0.98, top - step * 0.9))
    #expect(jitter.isEmpty)
    // A full step below the anchor does emit. Two steps' worth of travel back is the worst
    // case, since the anchor may be a whole step below where the finger actually is.
    let reversal = engine.process(frame: frame(0.15, 0.98, top - step * 2))
    #expect(reversal.contains(.step(.volume, .down)))
    #expect(reversal.allSatisfy { $0 == .step(.volume, .down) })
}

@Test("lifting the finger disengages exactly once")
func liftingDisengagesOnce() {
    var engine = GestureEngine()
    _ = engine.process(frame: frame(0.0, 0.98, 0.40))
    _ = engine.process(frame: frame(0.05, 0.98, 0.50))
    let lift = engine.process(frame: TouchFrame(timestamp: 0.10, touches: []))
    #expect(lift == [.disengaged(.volume)])
    // A repeat must be silent, or the adapter sees two disengages for one engage and any state
    // it keeps per control goes wrong.
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

@Test("a gesture in flight keeps the control it engaged with when settings change")
func midGestureSettingsChangeDoesNotSplitTheGesture() {
    var engine = GestureEngine()
    _ = engine.process(frame: frame(0.0, 0.98, 0.40))
    #expect(engine.process(frame: frame(0.05, 0.98, 0.45)).first == .engaged(.volume))
    // Settings are snapshotted when a gesture begins. If they were read live, this flip would
    // send the rest of the slide to brightness and leave the adapter with `.engaged(.volume)`
    // never closed and a `.disengaged(.brightness)` it never opened.
    engine.settings.swapSides = true
    let steps = engine.process(frame: frame(0.10, 0.98, 0.55))
    #expect(steps.allSatisfy { $0 == .step(.volume, .up) })
    #expect(engine.process(frame: TouchFrame(timestamp: 0.15, touches: [])) == [.disengaged(.volume)])
    // The next gesture does pick the new mapping up.
    _ = engine.process(frame: frame(0.20, 0.98, 0.40))
    #expect(engine.process(frame: frame(0.25, 0.98, 0.45)).first == .engaged(.brightness))
}

@Test("a zero step distance engages without emitting steps instead of hanging")
func zeroStepDistanceEmitsNoSteps() {
    var settings = GestureSettings()
    // Not a hypothetical: `UserDefaults.double(forKey:)` returns 0 for a key that was never
    // written, so the preferences layer can hand the engine a zero. Zero would make "how many
    // steps fit in this travel" unanswerable, so the answer is none — the gesture still opens
    // and closes cleanly, which keeps the adapter's pairing intact while the control does
    // nothing visible.
    settings.stepDistance = 0
    var engine = GestureEngine(settings: settings)
    _ = engine.process(frame: frame(0.0, 0.98, 0.10))
    let events = engine.process(frame: frame(0.05, 0.98, 0.90))
    #expect(events == [.engaged(.volume)])
    #expect(engine.process(frame: TouchFrame(timestamp: 0.10, touches: [])) == [.disengaged(.volume)])
}


@Test("an absurd position emits no steps rather than trapping")
func absurdPositionEmitsNoSteps() {
    var engine = GestureEngine()
    _ = engine.process(frame: frame(0.0, 0.98, 0.40))
    _ = engine.process(frame: frame(0.05, 0.98, 0.45))
    // `NormalizedPoint` deliberately does not clamp, so a broken adapter can deliver this. The
    // step count it implies fits in no `Int` and would allocate an unbounded array, so the
    // frame is ignored: a menu bar app that crashes is worse than one that visibly does
    // nothing, and the gesture still closes cleanly afterwards.
    let events = engine.process(frame: frame(0.10, 0.98, 1e30))
    #expect(events.isEmpty)
    #expect(engine.process(frame: TouchFrame(timestamp: 0.15, touches: [])) == [.disengaged(.volume)])
}


@Test("settings that change while a finger is armed do not apply to that finger")
func settingsAreSnapshottedWhenTheGestureBegins() {
    var engine = GestureEngine()
    // Armed on the right edge, not yet engaged.
    _ = engine.process(frame: frame(0.0, 0.98, 0.40))
    engine.settings.swapSides = true
    // The snapshot is taken when the gesture *begins*, not when it engages, so the edge that
    // admitted this finger and the control it drives are decided by the same set of rules. Read
    // live at engagement instead, and a menu flip in the gap between a finger touching down and
    // moving would send the stroke to a control the user was not aiming at.
    #expect(engine.process(frame: frame(0.05, 0.98, 0.45)).first == .engaged(.volume))

    // The same applies to the size of a step, not just the choice of control. Armed under the
    // default 0.016, this stroke of 0.05 is worth three steps; re-read live it would be worth
    // none, and the user's slide would silently do nothing.
    var retuned = GestureEngine()
    _ = retuned.process(frame: frame(0.0, 0.98, 0.40))
    retuned.settings.stepDistance = 0.2
    let events = retuned.process(frame: frame(0.05, 0.98, 0.45))
    #expect(events == [.engaged(.volume), .step(.volume, .up), .step(.volume, .up), .step(.volume, .up)])
}
