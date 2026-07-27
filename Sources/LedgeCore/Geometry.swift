/// A position on the trackpad in the coordinate space of `NSTouch.normalizedPosition`:
/// both axes run 0...1 with the origin at the **lower left**, so `y` increases upward and
/// sliding a finger up the trackpad increases `y`.
///
/// The convention is stated once, here, so no other type has to re-derive it.
///
/// The 0...1 domain is documented but deliberately **not** validated or clamped. Values
/// arrive already normalized from the OS, so an out-of-range value means the adapter is
/// wrong; clamping would quietly absorb that bug instead of letting it show up as visibly
/// wrong behaviour. Please do not add clamping here.
public struct NormalizedPoint: Sendable, Equatable {
    /// Distance from the left edge, 0 at the left, 1 at the right.
    public let x: Double
    /// Distance from the bottom edge, 0 at the bottom, 1 at the top.
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    /// Whether this point sits higher up the trackpad than `other`.
    public func isAbove(_ other: NormalizedPoint) -> Bool {
        y > other.y
    }
}
