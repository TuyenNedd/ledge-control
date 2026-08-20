/// Something the gesture engine has decided, for the macOS layer to carry out.
///
/// Each event carries enough context for the adapter to act without tracking engine state:
/// `.engaged` names the edge and action, `.step` names the edge, action, and direction, and
/// `.disengaged` names the edge. Every `.engaged` is followed by exactly one `.disengaged`
/// for the same edge.
public enum GestureEvent: Sendable, Equatable {
    /// A gesture has been recognised on `edge` driving `action`, and now owns it until
    /// `.disengaged`.
    case engaged(TrackpadEdge, EdgeAction)
    /// Move the action one step in this direction, and pulse once.
    case step(TrackpadEdge, EdgeAction, StepDirection)
    /// The gesture on `edge` is over, for any reason: lift, drift, typing, or being switched off.
    case disengaged(TrackpadEdge)
}
