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
    /// on that snapshot.
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
    /// Whether the required modifier key is currently held.
    private var modifierHeld: Bool = false

    /// The top of the "bottom quarter", in trackpad heights.
    private static let bottomQuarterTop = 0.25

    public init(settings: GestureSettings = GestureSettings()) {
        self.settings = settings
    }

    /// Report a keystroke, suppressing gestures for `typingLockout` seconds.
    public mutating func noteTyping(at timestamp: Double) -> [GestureEvent] {
        lastTypingTime = timestamp
        return end()
    }

    /// Switch the engine on or off, ending anything in flight when switching off.
    public mutating func setEnabled(_ enabled: Bool) -> [GestureEvent] {
        isEnabled = enabled
        return enabled ? [] : end()
    }

    /// Abandon any gesture in flight, for reasons the engine cannot see.
    public mutating func cancel() -> [GestureEvent] {
        end()
    }

    /// Report whether the required modifier key is currently held.
    public mutating func setModifierHeld(_ held: Bool) -> [GestureEvent] {
        modifierHeld = held
        guard settings.modifierKeyRequired != .none else { return [] }
        if !held {
            return end()
        }
        return []
    }

    /// Feed one frame of touch data and act on whatever it implies.
    ///
    /// Settings are snapshotted when a gesture begins, so mid-gesture edits do not apply until
    /// the next one.
    public mutating func process(frame: TouchFrame) -> [GestureEvent] {
        guard isEnabled else { return end() }

        var events: [GestureEvent] = []
        if let lastFrameTime, frame.timestamp - lastFrameTime > activeSettings.gestureTimeout {
            events += abandonStaleGesture()
        }
        lastFrameTime = frame.timestamp

        guard frame.touches.count == 1 else { return events + end() }
        let touch = frame.touches[0]

        switch phase {
        case .rejected(let touchID) where touchID == touch.id:
            return events
        case .armed(let arming) where arming.touchID == touch.id:
            return events + activate(arming, at: touch)
        case .engaged(let engagement) where engagement.touchID == touch.id:
            return events + continueGesture(engagement, to: touch.position)
        case .engaged:
            return events + end()
        case .idle, .armed, .rejected:
            return events + arm(touch, at: frame.timestamp)
        }
    }

    /// The rules currently in force.
    private var activeSettings: GestureSettings {
        switch phase {
        case .armed(let arming): return arming.settings
        case .engaged(let engagement): return engagement.settings
        case .idle, .rejected: return settings
        }
    }

    /// Drop a gesture whose frames stopped arriving.
    private mutating func abandonStaleGesture() -> [GestureEvent] {
        switch phase {
        case .engaged:
            return end()
        case .armed:
            phase = .idle
            return []
        case .idle, .rejected:
            return []
        }
    }

    /// End whatever is in flight, reporting it only if it had been announced.
    private mutating func end() -> [GestureEvent] {
        defer { phase = .idle }
        if case .engaged(let engagement) = phase {
            return [.disengaged(engagement.edge)]
        }
        return []
    }

    /// Decide whether a newly seen finger could become a gesture at all.
    private mutating func arm(_ touch: TouchPoint, at timestamp: Double) -> [GestureEvent] {
        if let lastTypingTime, timestamp - lastTypingTime < settings.typingLockout { return [] }
        if settings.modifierKeyRequired != .none && !modifierHeld { return [] }

        guard let edge = settings.edge(forPosition: touch.position) else {
            phase = .rejected(touchID: touch.id)
            return []
        }

        // bottomQuarterOnly applies only to vertical edges (left/right)
        if (edge == .left || edge == .right) && settings.bottomQuarterOnly && touch.position.y > Self.bottomQuarterTop {
            phase = .rejected(touchID: touch.id)
            return []
        }

        phase = .armed(Arming(touchID: touch.id, start: touch.position, edge: edge, settings: settings))
        return []
    }

    /// Step an engaged gesture along, unless the finger has wandered off the edge.
    private mutating func continueGesture(_ engagement: Engagement, to position: NormalizedPoint) -> [GestureEvent] {
        let settings = engagement.settings
        let config = settings.edgeConfig(for: engagement.edge)
        let innerLimit = config.bandWidth + settings.maxDriftOutsideBand

        let hasDriftedOut: Bool
        switch engagement.edge {
        case .left:
            hasDriftedOut = position.x > innerLimit
        case .right:
            hasDriftedOut = position.x < 1 - innerLimit
        case .top:
            hasDriftedOut = position.y < 1 - innerLimit
        case .bottom:
            hasDriftedOut = position.y > innerLimit
        }
        guard !hasDriftedOut else { return end() }

        var engagement = engagement
        let coordinate: Double
        switch engagement.edge {
        case .left, .right:
            coordinate = position.y
        case .top, .bottom:
            coordinate = position.x
        }
        let events = engagement.advance(to: coordinate)
        phase = .engaged(engagement)
        return events
    }

    /// Decide whether an armed finger has now moved like a gesture.
    private mutating func activate(_ arming: Arming, at touch: TouchPoint) -> [GestureEvent] {
        let settings = arming.settings
        let dy = touch.position.y - arming.start.y
        let dx = touch.position.x - arming.start.x

        switch arming.edge {
        case .left, .right:
            // Vertical edges: primary axis is y (vertical travel)
            guard abs(dy) > settings.activationDistance else { return [] }
            // Rejected if horizontal travel >= vertical travel
            guard abs(dy) > abs(dx) else {
                phase = .rejected(touchID: touch.id)
                return []
            }

            let config = settings.edgeConfig(for: arming.edge)
            var engagement = Engagement(
                touchID: touch.id,
                edge: arming.edge,
                action: config.action,
                settings: settings,
                baseCoordinate: arming.start.y
            )
            let steps = engagement.advance(to: touch.position.y)
            phase = .engaged(engagement)
            return [.engaged(arming.edge, config.action)] + steps

        case .top, .bottom:
            // Horizontal edges: primary axis is x (horizontal travel)
            guard abs(dx) > settings.activationDistance else { return [] }
            // Rejected if vertical travel >= horizontal travel
            guard abs(dx) > abs(dy) else {
                phase = .rejected(touchID: touch.id)
                return []
            }

            let config = settings.edgeConfig(for: arming.edge)
            var engagement = Engagement(
                touchID: touch.id,
                edge: arming.edge,
                action: config.action,
                settings: settings,
                baseCoordinate: arming.start.x
            )
            let steps = engagement.advance(to: touch.position.x)
            phase = .engaged(engagement)
            return [.engaged(arming.edge, config.action)] + steps
        }
    }

    private enum Phase: Sendable {
        case idle
        case armed(Arming)
        case engaged(Engagement)
        case rejected(touchID: Int)
    }

    private struct Arming: Sendable {
        let touchID: Int
        let start: NormalizedPoint
        let edge: TrackpadEdge
        let settings: GestureSettings
    }

    private struct Engagement: Sendable {
        let touchID: Int
        let edge: TrackpadEdge
        let action: EdgeAction
        let settings: GestureSettings
        /// The coordinate value where the finger started on the relevant axis.
        /// For left/right edges this is the y-coordinate; for top/bottom it is the x-coordinate.
        let baseCoordinate: Double
        /// Steps emitted so far, signed, up positive.
        var stepIndex: Int = 0

        /// Emit one step per whole step of travel between the anchor and the current coordinate.
        ///
        /// For horizontal edges (top/bottom), positive direction (rightward, increasing x)
        /// maps to `.up`, negative (leftward, decreasing x) maps to `.down`.
        /// For vertical edges (left/right), positive direction (upward, increasing y) maps
        /// to `.up`, negative (downward, decreasing y) maps to `.down`.
        mutating func advance(to coordinate: Double) -> [GestureEvent] {
            let travelInSteps = (coordinate - baseCoordinate) / settings.effectiveStepDistance
            guard let stepsBelow = Int(exactly: travelInSteps.rounded(.down)),
                  let stepsAbove = Int(exactly: travelInSteps.rounded(.up))
            else { return [] }

            if stepsBelow > stepIndex {
                let count = stepsBelow - stepIndex
                stepIndex = stepsBelow
                return Array(repeating: .step(edge, action, .up), count: count)
            }
            if stepsAbove < stepIndex {
                let count = stepIndex - stepsAbove
                stepIndex = stepsAbove
                return Array(repeating: .step(edge, action, .down), count: count)
            }
            return []
        }
    }
}
