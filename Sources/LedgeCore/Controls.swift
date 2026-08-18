/// Which vertical edge of the trackpad a touch belongs to.
///
/// Named for a physical side rather than for what it does, because which side drives which
/// control is a user setting (`GestureSettings.swapSides`) and must not be baked into the
/// vocabulary.
public enum TrackpadEdge: Sendable, Equatable {
    case left
    case right
}

/// A system property a gesture can drive.
public enum Control: Sendable, Equatable {
    case volume
    case brightness
}

/// Which way a single step moves the control.
///
/// Expressed as up/down rather than increase/decrease so it reads as the finger motion that
/// produced it; sliding up the trackpad always steps up.
public enum StepDirection: Sendable, Equatable {
    case up
    case down
}
