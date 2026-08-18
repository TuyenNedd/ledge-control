/// Something the gesture engine has decided, for the macOS layer to carry out.
///
/// Deliberately not "here is the new volume": the engine reports *steps*, one event per step,
/// because the two outputs behave differently — volume goes through synthesised media keys that
/// only understand "one step up", while brightness is set as an absolute value. A step is the
/// coarsest thing both backends can honour, and it is also exactly one haptic pulse, so the
/// adapter can pulse per event without doing arithmetic of its own.
///
/// `.engaged` and `.disengaged` carry the `Control` rather than being bare markers so the
/// adapter can pair them without tracking engine state; every `.engaged(c)` is followed by
/// exactly one `.disengaged(c)` for the same `c`.
public enum GestureEvent: Sendable, Equatable {
    /// A gesture has been recognised and now owns this control until `.disengaged`.
    case engaged(Control)
    /// Move the control one step in this direction, and pulse once.
    case step(Control, StepDirection)
    /// The gesture is over, for any reason — lift, drift, typing, or being switched off.
    case disengaged(Control)
}
