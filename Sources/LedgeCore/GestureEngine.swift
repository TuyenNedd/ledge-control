/// Turns a stream of `TouchFrame`s into `GestureEvent`s: the whole of the app's judgement about
/// what the user meant, in the one place that can be tested.
///
/// A value type with `mutating` methods rather than a class, to match the rest of `LedgeCore`
/// and so a test can hold two independent engines without either reaching the other. The macOS
/// layer owns exactly one, on the main thread, since touch frames arrive from the event tap
/// callback in order.
///
/// Every entry point returns `[GestureEvent]`. Guards can end a gesture, and a gesture that
/// ends must say so, so there is no path — not typing, not being disabled — that can drop a
/// `.disengaged` the adapter is waiting for.
public struct GestureEngine: Sendable {
    /// The thresholds every decision is measured against.
    ///
    /// Free to replace at any time — the menu bar does — but a change only affects gestures
    /// that start afterwards: a gesture snapshots these when it begins and runs to completion
    /// on that snapshot. See the note on `process(frame:)` for why.
    public var settings: GestureSettings

    private var phase: Phase = .idle

    public init(settings: GestureSettings = GestureSettings()) {
        self.settings = settings
    }

    /// Feed one frame of touch data and act on whatever it implies.
    ///
    /// Settings are snapshotted when a gesture begins, so mid-gesture edits do not apply until
    /// the next one. This keeps a single stroke governed by one consistent set of rules —
    /// travel already made cannot be reinterpreted, and the `.engaged`/`.disengaged` pair
    /// cannot name two different controls because `swapSides` changed halfway. The cost is
    /// theoretical only: changing a setting means using the menu, which means using the
    /// trackpad, which means the gesture has already ended.
    public mutating func process(frame: TouchFrame) -> [GestureEvent] {
        // Exactly one finger, or there is nothing to interpret. Two-finger scrolling crosses
        // the edge constantly.
        guard frame.touches.count == 1 else { return [] }
        let touch = frame.touches[0]

        switch phase {
        case .rejected(let touchID) where touchID == touch.id:
            // Already disqualified. Not re-examined, because a finger that entered the band
            // mid-stroke would otherwise satisfy every arming test on some later frame.
            return []
        case .armed(let arming) where arming.touchID == touch.id:
            return activate(arming, at: touch)
        case .engaged:
            return []
        case .idle, .armed, .rejected:
            return arm(touch)
        }
    }

    /// Decide whether a newly seen finger could become a gesture at all.
    private mutating func arm(_ touch: TouchPoint) -> [GestureEvent] {
        guard let edge = settings.edge(forX: touch.position.x) else {
            phase = .rejected(touchID: touch.id)
            return []
        }
        phase = .armed(Arming(touchID: touch.id, start: touch.position, edge: edge, settings: settings))
        return []
    }

    /// Decide whether an armed finger has now moved like a gesture.
    private mutating func activate(_ arming: Arming, at touch: TouchPoint) -> [GestureEvent] {
        let settings = arming.settings
        let dy = touch.position.y - arming.start.y
        let dx = touch.position.x - arming.start.x

        // Still inside the dead zone: undecided, not rejected. A finger resting at the edge is
        // allowed to become a gesture later without lifting first.
        guard abs(dy) > settings.activationDistance else { return [] }

        // Rejected on ties as well as on genuinely horizontal motion: a stroke that has moved
        // no further vertically than horizontally is not evidence of intent, and treating the
        // ambiguous case as a gesture is the expensive mistake.
        guard abs(dy) > abs(dx) else {
            phase = .rejected(touchID: touch.id)
            return []
        }

        let control = settings.control(for: arming.edge)
        phase = .engaged(Engagement(touchID: touch.id, control: control))
        return [.engaged(control)]
    }

    private enum Phase: Sendable {
        case idle
        case armed(Arming)
        case engaged(Engagement)
        /// A finger that cannot become a gesture, remembered by id so it is judged once rather
        /// than on every frame it remains down for.
        case rejected(touchID: Int)
    }

    private struct Arming: Sendable {
        let touchID: Int
        /// Where the finger first appeared. Both the dead zone and the vertical-vs-horizontal
        /// test measure from here rather than from the previous frame, so a slow stroke
        /// accumulates toward activation instead of being judged one imperceptible delta at a
        /// time.
        let start: NormalizedPoint
        let edge: TrackpadEdge
        /// The rules this gesture will be judged by for its whole life.
        let settings: GestureSettings
    }

    private struct Engagement: Sendable {
        let touchID: Int
        let control: Control
    }
}
