import Testing
import LedgeCore

private func frame(_ t: Double, _ x: Double, _ y: Double, id: Int = 1) -> TouchFrame {
    TouchFrame(timestamp: t, touches: [TouchPoint(id: id, position: NormalizedPoint(x: x, y: y))])
}

@Test("modifier not held prevents engagement when modifier is required")
func modifierNotHeldPreventsEngagement() {
    var settings = GestureSettings()
    settings.modifierKeyRequired = .holdOption
    var engine = GestureEngine(settings: settings)
    _ = engine.process(frame: frame(0.0, 0.98, 0.40))
    let events = engine.process(frame: frame(0.05, 0.98, 0.45))
    #expect(events.isEmpty)
}

@Test("modifier held allows normal gesture when modifier is required")
func modifierHeldAllowsGesture() {
    var settings = GestureSettings()
    settings.modifierKeyRequired = .holdOption
    var engine = GestureEngine(settings: settings)
    _ = engine.setModifierHeld(true)
    _ = engine.process(frame: frame(0.0, 0.98, 0.40))
    let events = engine.process(frame: frame(0.05, 0.98, 0.45))
    #expect(events.first == .engaged(.right, .volume))
}

@Test("releasing modifier mid-gesture disengages")
func releasingModifierMidGestureDisengages() {
    var settings = GestureSettings()
    settings.modifierKeyRequired = .holdControl
    var engine = GestureEngine(settings: settings)
    _ = engine.setModifierHeld(true)
    _ = engine.process(frame: frame(0.0, 0.98, 0.40))
    let engaged = engine.process(frame: frame(0.05, 0.98, 0.45))
    #expect(engaged.first == .engaged(.right, .volume))
    let events = engine.setModifierHeld(false)
    #expect(events == [.disengaged(.right)])
}

@Test("mode .none ignores modifier state entirely")
func modeNoneIgnoresModifierState() {
    var settings = GestureSettings()
    settings.modifierKeyRequired = .none
    var engine = GestureEngine(settings: settings)
    _ = engine.process(frame: frame(0.0, 0.98, 0.40))
    let events = engine.process(frame: frame(0.05, 0.98, 0.45))
    #expect(events.first == .engaged(.right, .volume))
}

@Test("mode .none ignores setModifierHeld(false) during a gesture")
func modeNoneDoesNotDisengageOnModifierRelease() {
    var settings = GestureSettings()
    settings.modifierKeyRequired = .none
    var engine = GestureEngine(settings: settings)
    _ = engine.process(frame: frame(0.0, 0.98, 0.40))
    let engaged = engine.process(frame: frame(0.05, 0.98, 0.45))
    #expect(engaged.first == .engaged(.right, .volume))
    let events = engine.setModifierHeld(false)
    #expect(events.isEmpty)
}

@Test("ModifierKeyMode displayName returns human-readable labels")
func displayNames() {
    #expect(ModifierKeyMode.none.displayName == "None")
    #expect(ModifierKeyMode.holdOption.displayName == "Hold Option")
    #expect(ModifierKeyMode.holdFn.displayName == "Hold Fn")
    #expect(ModifierKeyMode.holdControl.displayName == "Hold Control")
}

@Test("ModifierKeyMode conforms to CaseIterable")
func caseIterable() {
    #expect(ModifierKeyMode.allCases.count == 4)
}

@Test("ModifierKeyMode rawValue is the case name")
func rawValues() {
    #expect(ModifierKeyMode.none.rawValue == "none")
    #expect(ModifierKeyMode.holdOption.rawValue == "holdOption")
    #expect(ModifierKeyMode.holdFn.rawValue == "holdFn")
    #expect(ModifierKeyMode.holdControl.rawValue == "holdControl")
}
