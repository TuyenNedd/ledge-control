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
    #expect(engine.process(frame: frame(0.05, 0.98, 0.45)).first == .engaged(.volume))
    return engine
}

@Test("a second finger arriving ends the gesture")
func secondTouchDisengages() {
    var engine = engagedOnTheRight()
    // Not "ignore the extra finger and carry on": a second finger down means the user has
    // almost certainly started a two-finger scroll or a click-drag, and continuing to drive the
    // volume through that is the loudest possible false positive.
    let events = engine.process(frame: TouchFrame(
        timestamp: 0.10,
        touches: [touch(1, 0.98, 0.50), touch(2, 0.60, 0.50)]
    ))
    #expect(events == [.disengaged(.volume)])
}

@Test("more than one finger never arms a gesture")
func multipleTouchesNeverArm() {
    var engine = GestureEngine()
    // Two-finger scrolling runs along the edge constantly, and the leading finger of a scroll
    // looks exactly like a deliberate edge slide if you only look at one of them.
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
    // The finger has left the edge entirely; whatever it is doing now, it is not the gesture
    // that was started. Measured from the inner boundary of the band, not from the trackpad
    // edge, so the tolerance means the same thing however wide the band is.
    let limit = 1 - (settings.edgeBandWidth + settings.maxDriftOutsideBand)
    let events = engine.process(frame: frame(0.10, limit - 0.01, 0.50))
    #expect(events == [.disengaged(.volume)])
}

@Test("drifting within the tolerance keeps the gesture alive")
func driftWithinToleranceKeepsStepping() {
    let settings = GestureSettings()
    var engine = engagedOnTheRight(settings)
    // A long vertical slide wanders sideways — fingers pivot from the wrist. Cutting the
    // gesture off for that would make the app feel broken halfway through every stroke, which
    // is why the tolerance exists at all.
    let limit = 1 - (settings.edgeBandWidth + settings.maxDriftOutsideBand)
    let events = engine.process(frame: frame(0.10, limit + 0.01, 0.55))
    #expect(!events.isEmpty)
    #expect(events.allSatisfy { $0 == .step(.volume, .up) })
}

@Test("a keystroke suppresses gestures for the lockout window")
func typingSuppressesEngagement() {
    var engine = GestureEngine()
    #expect(engine.noteTyping(at: 1.0).isEmpty)
    // A palm or a thumb resting at the edge while the hands are on the keyboard is the most
    // common false positive there is, and it does not look any different from a slow gesture.
    _ = engine.process(frame: frame(1.1, 0.98, 0.40))
    let events = engine.process(frame: frame(1.15, 0.98, 0.50))
    #expect(events.isEmpty)
}

@Test("a keystroke during a gesture ends it")
func typingWhileEngagedDisengages() {
    var engine = engagedOnTheRight()
    // The user's attention has moved to the keyboard. Ending the gesture also stops a resting
    // finger from picking the stroke back up when the lockout expires.
    #expect(engine.noteTyping(at: 0.10) == [.disengaged(.volume)])
    #expect(engine.noteTyping(at: 0.11).isEmpty)
}

@Test("gestures work again once the lockout has elapsed")
func gesturesResumeAfterLockout() {
    let settings = GestureSettings()
    var engine = GestureEngine(settings: settings)
    _ = engine.noteTyping(at: 1.0)
    // The lockout is a window, not a mode: if it failed to expire the app would be dead after
    // the first keystroke, which no test of the suppressing case would notice.
    let after = 1.0 + settings.typingLockout + 0.01
    _ = engine.process(frame: frame(after, 0.98, 0.40))
    #expect(engine.process(frame: frame(after + 0.05, 0.98, 0.45)).first == .engaged(.volume))
}

@Test("a gap longer than the timeout restarts the gesture instead of resuming it")
func staleGestureRestarts() {
    let settings = GestureSettings()
    var engine = engagedOnTheRight(settings)
    let afterTheGap = 0.05 + settings.gestureTimeout + 0.01
    // The finger stopped moving, so frames stopped arriving. Travel measured across that gap
    // would be attributed to an intention the user has had time to abandon — so the gesture
    // closes, and the finger has to earn a new one from where it now is.
    let events = engine.process(frame: frame(afterTheGap, 0.98, 0.80))
    #expect(events == [.disengaged(.volume)])
    // Restarting, not resuming: this finger is treated as a fresh start at y = 0.80, so the
    // 0.35 of travel it made during the gap produces no steps at all.
    #expect(!events.contains { $0 == .step(.volume, .up) })
    let resumed = engine.process(frame: frame(afterTheGap + 0.05, 0.98, 0.85))
    #expect(resumed.first == .engaged(.volume))
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
    // Starting low is the restriction; the stroke itself may run the whole height, or the mode
    // would also be a limit on how far the control can move.
    _ = engine.process(frame: frame(0.0, 0.98, 0.20))
    #expect(engine.process(frame: frame(0.05, 0.98, 0.60)).first == .engaged(.volume))
}

@Test("being switched off ends the gesture and suppresses everything after")
func disablingSuppressesEverything() {
    var engine = engagedOnTheRight()
    #expect(engine.isEnabled)
    // The off switch has to be immediate and unconditional — it is what a user reaches for when
    // the app is misbehaving, so it cannot be the one thing that waits for the current gesture.
    #expect(engine.setEnabled(false) == [.disengaged(.volume)])
    #expect(!engine.isEnabled)
    _ = engine.process(frame: frame(0.20, 0.98, 0.40))
    #expect(engine.process(frame: frame(0.25, 0.98, 0.50)).isEmpty)
    #expect(engine.noteTyping(at: 0.30).isEmpty)
}

@Test("switching off twice reports the gesture ending only once")
func disablingIsIdempotent() {
    var engine = engagedOnTheRight()
    #expect(engine.setEnabled(false) == [.disengaged(.volume)])
    #expect(engine.setEnabled(false).isEmpty)
}

@Test("re-enabling allows a fresh gesture")
func reEnablingRestoresGestures() {
    var engine = engagedOnTheRight()
    _ = engine.setEnabled(false)
    #expect(engine.setEnabled(true).isEmpty)
    #expect(engine.isEnabled)
    _ = engine.process(frame: frame(0.30, 0.98, 0.40))
    #expect(engine.process(frame: frame(0.35, 0.98, 0.45)).first == .engaged(.volume))
}

@Test("cancel ends a gesture in flight and is silent when there is none")
func cancelEndsTheGesture() {
    var engine = engagedOnTheRight()
    // For the adapter to call when the world changes underneath it — losing the event tap,
    // going to sleep, the screen locking. It must report the ending so the pairing survives
    // whatever the adapter does next.
    #expect(engine.cancel() == [.disengaged(.volume)])
    #expect(engine.cancel().isEmpty)
    // Cancelling is not disabling: the next gesture is allowed.
    _ = engine.process(frame: frame(0.20, 0.98, 0.40))
    #expect(engine.process(frame: frame(0.25, 0.98, 0.45)).first == .engaged(.volume))
}


@Test("a gap while armed discards the stale start position")
func staleArmingIsDiscarded() {
    let settings = GestureSettings()
    var engine = GestureEngine()
    _ = engine.process(frame: frame(0.0, 0.98, 0.40))
    // Travel of 0.05 would clear the dead zone measured from y = 0.40, but that start is stale:
    // the finger sat still through the gap, so it has to earn activation from where it now is.
    // Without this an idle finger accumulates travel across arbitrary pauses.
    let afterTheGap = settings.gestureTimeout + 0.01
    #expect(engine.process(frame: frame(afterTheGap, 0.98, 0.45)).isEmpty)
    #expect(engine.process(frame: frame(afterTheGap + 0.05, 0.98, 0.50)).first == .engaged(.volume))
}

@Test("a gap does not give a disqualified finger a second chance")
func staleRejectionIsNotForgiven() {
    let settings = GestureSettings()
    var engine = GestureEngine()
    // Disqualified by starting in the middle of the trackpad.
    _ = engine.process(frame: frame(0.0, 0.5, 0.40))
    _ = engine.process(frame: frame(0.05, 0.5, 0.50))
    // Pausing is not evidence of intent. If the timeout cleared the rejection, a finger that
    // drifted into the band mid-scroll could earn a gesture just by holding still for a moment.
    let afterTheGap = 0.05 + settings.gestureTimeout + 0.01
    _ = engine.process(frame: frame(afterTheGap, 0.98, 0.40))
    #expect(engine.process(frame: frame(afterTheGap + 0.05, 0.98, 0.50)).isEmpty)
}


@Test("a different finger replacing the engaged one ends the gesture")
func replacedTouchDisengages() {
    var engine = engagedOnTheRight()
    // The tap can deliver a frame where the finger that owned the gesture is gone and another
    // is present, with no empty frame in between — touch identity comes from the hardware, not
    // from us. Left unhandled the gesture would sit open, emitting nothing, until something
    // else happened to end it, and the adapter would believe a control was still being driven.
    let events = engine.process(frame: TouchFrame(timestamp: 0.10, touches: [touch(2, 0.98, 0.50)]))
    #expect(events == [.disengaged(.volume)])
    // The frame that ends a gesture does not also start one — the same rule as a second finger
    // arriving, and it keeps one frame from being both the end of one intention and the start of
    // another. The new finger arms on the next frame and can engage on the one after that.
    #expect(engine.process(frame: TouchFrame(timestamp: 0.15, touches: [touch(2, 0.98, 0.55)])).isEmpty)
    #expect(engine.process(frame: TouchFrame(timestamp: 0.20, touches: [touch(2, 0.98, 0.60)])).first
        == .engaged(.volume))
}
