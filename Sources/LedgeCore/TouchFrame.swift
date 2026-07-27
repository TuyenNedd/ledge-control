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
    /// When the frame was observed, in seconds.
    public let timestamp: Double
    /// The touches present, in no guaranteed order.
    public let touches: [TouchPoint]

    public init(timestamp: Double, touches: [TouchPoint]) {
        self.timestamp = timestamp
        self.touches = touches
    }
}
