/// A single finger on the trackpad, tracked across frames by its `id`.
public struct TouchPoint: Sendable, Equatable {
    /// Identifies the same finger from one frame to the next.
    public let id: Int
    /// Where the finger currently is.
    public let position: NormalizedPoint

    public init(id: Int, position: NormalizedPoint) {
        self.id = id
        self.position = position
    }
}

/// Every touch present on the trackpad at one instant — the unit of input the gesture logic
/// consumes.
public struct TouchFrame: Sendable, Equatable {
    /// When the frame was observed, in monotonically increasing seconds from an arbitrary
    /// origin.
    ///
    /// The absolute value is meaningless; it is only ever meaningful as a **difference**
    /// against another `LedgeCore` time value. The source is `NSEvent.timestamp`, which
    /// counts seconds since boot — not since 1970.
    ///
    /// Every time value entering `LedgeCore` must come from that same clock. Mixing clocks
    /// cannot be caught by the compiler or the tests, because both are plain `Double`: a
    /// `Date().timeIntervalSince1970` value differs from a since-boot value by decades, so a
    /// comparison against one would silently never fire, or never release.
    public let timestamp: Double
    /// The touches present. The hardware imposes no meaningful order, so no order should be
    /// read into this array — but note that the synthesized `Equatable` conformance is
    /// structural and compares `touches` element-wise, so element order *does* participate
    /// in equality. Two frames holding the same touches in different orders are unequal.
    public let touches: [TouchPoint]

    public init(timestamp: Double, touches: [TouchPoint]) {
        self.timestamp = timestamp
        self.touches = touches
    }
}
