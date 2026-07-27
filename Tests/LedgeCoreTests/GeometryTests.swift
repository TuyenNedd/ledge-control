import Testing

@testable import LedgeCore

@Test("y increases upward, matching NSTouch.normalizedPosition")
func normalizedPointOriginIsLowerLeft() {
    let lower = NormalizedPoint(x: 0.5, y: 0.1)
    let upper = NormalizedPoint(x: 0.5, y: 0.9)
    #expect(upper.isAbove(lower))
}

@Test("a frame reports the single touch it carries")
func frameCarriesTouches() {
    let frame = TouchFrame(
        timestamp: 1.0,
        touches: [TouchPoint(id: 7, position: NormalizedPoint(x: 0.02, y: 0.4))]
    )
    #expect(frame.touches.count == 1)
    #expect(frame.touches[0].id == 7)
}
