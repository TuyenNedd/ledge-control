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

    /// Whether the engine is listening at all.
    ///
    /// Read-only because switching it off can end a gesture, and that has to be reported;
    /// `setEnabled(_:)` is the only way to change it so the events cannot be dropped.
    public private(set) var isEnabled: Bool = true

    private var phase: Phase = .idle
    /// When the last keystroke was seen, on the `TouchFrame.timestamp` clock.
    private var lastTypingTime: Double?
    /// When the last frame arrived, for spotting a gap the gesture should not survive.
    private var lastFrameTime: Double?

    /// The top of the "bottom quarter", in trackpad heights.
    ///
    /// A constant rather than a setting: `bottomQuarterOnly` is a switch the user can understand
    /// ("only near me"), and turning it into an adjustable number would add a knob whose right
    /// value nobody could guess. If it ever needs tuning it becomes a setting then.
    private static let bottomQuarterTop = 0.25

    public init(settings: GestureSettings = GestureSettings()) {
        self.settings = settings
    }

    /// Report a keystroke, suppressing gestures for `typingLockout` seconds.
    ///
    /// `timestamp` must come from the same clock as `TouchFrame.timestamp`.
    ///
    /// Ends any gesture in flight as well as blocking new ones: a finger resting at the edge
    /// while the user types is the commonest false positive there is, and if typing only blocked
    /// *new* gestures then a gesture already running would keep responding to the palm.
    public mutating func noteTyping(at timestamp: Double) -> [GestureEvent] {
        lastTypingTime = timestamp
        return end()
    }

    /// Switch the engine on or off, ending anything in flight when switching off.
    ///
    /// Switching off twice reports the ending once, because there is nothing left in flight to
    /// report the second time — a menu that re-asserts its state cannot manufacture a second
    /// `.disengaged`.
    public mutating func setEnabled(_ enabled: Bool) -> [GestureEvent] {
        isEnabled = enabled
        return enabled ? [] : end()
    }

    /// Abandon any gesture in flight, for reasons the engine cannot see.
    ///
    /// The adapter calls this when the world changes underneath it — the event tap is disabled,
    /// the screen locks, the app loses trust. Distinct from `setEnabled(false)` because it does
    /// not change whether the engine is listening; the next gesture is allowed.
    public mutating func cancel() -> [GestureEvent] {
        end()
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
        guard isEnabled else { return end() }

        // A gap in the frames means the finger stopped moving, and travel measured across it
        // would be credited to an intention the user has had time to abandon.
        var events: [GestureEvent] = []
        if let lastFrameTime, frame.timestamp - lastFrameTime > activeSettings.gestureTimeout {
            events += abandonStaleGesture()
        }
        lastFrameTime = frame.timestamp

        // An empty frame is the finger leaving the trackpad, which is how gestures normally
        // end. Any other count is not a single-finger gesture: two-finger scrolling crosses the
        // edge constantly, so a second finger arriving ends the gesture rather than being
        // ignored, and no gesture arms while more than one finger is down.
        guard frame.touches.count == 1 else { return events + end() }
        let touch = frame.touches[0]

        switch phase {
        case .rejected(let touchID) where touchID == touch.id:
            // Already disqualified. Not re-examined, because a finger that entered the band
            // mid-stroke would otherwise satisfy every arming test on some later frame.
            return events
        case .armed(let arming) where arming.touchID == touch.id:
            return events + activate(arming, at: touch)
        case .engaged(let engagement) where engagement.touchID == touch.id:
            return events + continueGesture(engagement, to: touch.position)
        case .engaged:
            // A different finger, and the one that owned the gesture is not in this frame: it
            // has gone, whether or not an empty frame ever said so. Ending here rather than
            // waiting keeps the engine from sitting open and unresponsive on a finger that no
            // longer exists.
            return events + end()
        case .idle, .armed, .rejected:
            return events + arm(touch, at: frame.timestamp)
        }
    }

    /// The rules currently in force: a gesture in flight is judged by its own snapshot, and
    /// anything else by whatever is set now.
    private var activeSettings: GestureSettings {
        switch phase {
        case .armed(let arming): return arming.settings
        case .engaged(let engagement): return engagement.settings
        case .idle, .rejected: return settings
        }
    }

    /// Drop a gesture whose frames stopped arriving, so the next frame starts one afresh.
    private mutating func abandonStaleGesture() -> [GestureEvent] {
        switch phase {
        case .engaged:
            return end()
        case .armed:
            phase = .idle
            return []
        case .idle, .rejected:
            // A disqualified finger stays disqualified. Holding still is not evidence that a
            // finger which entered the band mid-scroll has become deliberate, and clearing the
            // rejection here would hand it a second chance every time it paused.
            return []
        }
    }

    /// End whatever is in flight, reporting it only if it had been announced.
    ///
    /// Every exit from `engaged` routes through here, so there is one place responsible for the
    /// `.engaged`/`.disengaged` pairing the adapter relies on, and calling it twice is harmless.
    private mutating func end() -> [GestureEvent] {
        defer { phase = .idle }
        if case .engaged(let engagement) = phase {
            return [.disengaged(engagement.control)]
        }
        return []
    }

    /// Decide whether a newly seen finger could become a gesture at all.
    private mutating func arm(_ touch: TouchPoint, at timestamp: Double) -> [GestureEvent] {
        // Left undecided rather than rejected, so a finger already resting at the edge when the
        // user stops typing can still become a gesture once the window passes, without lifting.
        if let lastTypingTime, timestamp - lastTypingTime < settings.typingLockout { return [] }

        guard let edge = settings.edge(forX: touch.position.x),
              !settings.bottomQuarterOnly || touch.position.y <= Self.bottomQuarterTop
        else {
            phase = .rejected(touchID: touch.id)
            return []
        }
        phase = .armed(Arming(touchID: touch.id, start: touch.position, edge: edge, settings: settings))
        return []
    }

    /// Step an engaged gesture along, unless the finger has wandered off the edge.
    ///
    /// Named apart from `Engagement.advance(to:)` because it decides *whether* the gesture
    /// survives this frame, where that one only counts steps.
    private mutating func continueGesture(_ engagement: Engagement, to position: NormalizedPoint) -> [GestureEvent] {
        let settings = engagement.settings
        // Measured from the band's inner boundary rather than from the trackpad edge, so the
        // tolerance means the same thing whatever `edgeBandWidth` is set to. Generous on purpose:
        // a long vertical slide pivots from the wrist and wanders inward, and cutting the gesture
        // off mid-stroke feels like a bug, while a finger this far in has genuinely moved on.
        let innerLimit = settings.edgeBandWidth + settings.maxDriftOutsideBand
        let hasDriftedOut: Bool
        switch engagement.edge {
        case .left: hasDriftedOut = position.x > innerLimit
        case .right: hasDriftedOut = position.x < 1 - innerLimit
        }
        guard !hasDriftedOut else { return end() }

        var engagement = engagement
        let events = engagement.advance(to: position.y)
        phase = .engaged(engagement)
        return events
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
        // Steps are counted from where the finger *started*, not from here, so the travel spent
        // clearing the dead zone is not thrown away. Since the dead zone is wider than a step
        // by default, that means at least one step is already due and goes out in this same
        // frame — recognition and first feedback arrive together.
        var engagement = Engagement(
            touchID: touch.id,
            control: control,
            edge: arming.edge,
            settings: settings,
            baseY: arming.start.y
        )
        let steps = engagement.advance(to: touch.position.y)
        phase = .engaged(engagement)
        return [.engaged(control)] + steps
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
        /// Which edge this gesture belongs to, kept so the drift check knows which side to
        /// measure from once the finger is no longer necessarily in the band.
        let edge: TrackpadEdge
        /// The rules this gesture was recognised under, kept so a menu change mid-slide cannot
        /// change the size of a step or which control the closing `.disengaged` names.
        let settings: GestureSettings
        /// Where the finger started, in trackpad heights — the origin the step count is
        /// measured from.
        let baseY: Double
        /// Steps emitted so far, signed, up positive.
        ///
        /// The anchor is stored as this integer over a fixed origin rather than as a running
        /// `Double`, because advancing a `Double` by `+= 0.016` fifty times accumulates enough
        /// error to lose a step over one full-height slide — which is precisely the drift the
        /// anchor exists to prevent. An integer count cannot drift at all.
        var stepIndex: Int = 0

        /// Emit one step per whole step of travel between the anchor and `y`.
        ///
        /// The anchor — the position that produced the last step — is `baseY + stepIndex *
        /// stepDistance`. It is never materialised as a stored value; the comparison is done in
        /// step units instead, which is the same thing without the accumulated error.
        ///
        /// Reversing direction costs a full step from the anchor before anything is emitted, so
        /// a finger resting on a boundary cannot rattle between up and down. Since the anchor
        /// may already sit a step away from the finger, a deliberate reversal can cost up to two
        /// steps of travel — the price of never pulsing for movement the user did not make.
        mutating func advance(to y: Double) -> [GestureEvent] {
            let travelInSteps = (y - baseY) / settings.effectiveStepDistance
            // One guard covers both ways this can be unanswerable: a step distance of zero
            // makes it infinite, and an unclamped position makes it astronomical. Neither is a
            // gesture, so the frame is ignored while the gesture stays open — that keeps the
            // `.engaged`/`.disengaged` pairing intact, where trapping or allocating a
            // billion-element array in the middle of the user's slide would not.
            guard let stepsBelow = Int(exactly: travelInSteps.rounded(.down)),
                  let stepsAbove = Int(exactly: travelInSteps.rounded(.up))
            else { return [] }

            if stepsBelow > stepIndex {
                let count = stepsBelow - stepIndex
                stepIndex = stepsBelow
                return Array(repeating: .step(control, .up), count: count)
            }
            if stepsAbove < stepIndex {
                let count = stepIndex - stepsAbove
                stepIndex = stepsAbove
                return Array(repeating: .step(control, .down), count: count)
            }
            return []
        }
    }
}
