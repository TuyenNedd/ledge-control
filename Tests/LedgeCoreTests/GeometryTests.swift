import Testing

// A plain import, not `@testable`: this test target is the only place a missing `public` can
// be caught, because `Sources/Ledge/` is macOS-only and never compiles here. Testing through
// the public surface means the suite building is itself proof that surface is public.
import LedgeCore

@Test("y increases upward, matching NSTouch.normalizedPosition")
func normalizedPointOriginIsLowerLeft() {
    let lower = NormalizedPoint(x: 0.5, y: 0.1)
    let upper = NormalizedPoint(x: 0.5, y: 0.9)
    #expect(upper.isAbove(lower))
    // Asymmetry: rules out an implementation that always answers true.
    #expect(!lower.isAbove(upper))
    // Strictness: pins `>` rather than `>=`, so a point is never above itself.
    #expect(!lower.isAbove(lower))
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
