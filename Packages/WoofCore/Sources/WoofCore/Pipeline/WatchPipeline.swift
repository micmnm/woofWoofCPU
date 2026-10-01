import Foundation

/// Everything that happens per tick after sampling: breaches → mood → alerts, plus history.
public struct WatchPipeline: Sendable {
    public struct Step: Equatable, Sendable {
        public let mood: DogMood
        public let breaches: [Breach]
        public let newAlerts: [Breach]
    }

    public private(set) var tracker = BreachTracker()
    public var engine = MoodEngine()
    public private(set) var history = UsageHistory()
    private var lastBreaches: [Breach] = []

    public init() {}

    public mutating func step(
        entities: [Entity],
        limits: Limits,
        physicalMemory: UInt64,
        isMuted: (EntityKey) -> Bool,
        paused: Bool,
        now: TimeInterval
    ) -> Step {
        history.record(entities, now: now)
        // Pausing drops running timers so resuming never barks instantly.
        if paused { tracker.reset() }
        let breaches = paused
            ? []
            : tracker.update(entities: entities, limits: limits, physicalMemory: physicalMemory, now: now)
        lastBreaches = breaches
        let alerts = engine.evaluate(breaches: breaches, isMuted: isMuted, paused: paused, now: now)
        return Step(mood: engine.mood, breaches: breaches, newAlerts: alerts)
    }

    /// Re-runs only the mood engine on the last tick's breaches, so a snooze/ignore/pause shows up
    /// at once without adding a history point or a (calm) tick to the tracker.
    public mutating func reevaluate(isMuted: (EntityKey) -> Bool, paused: Bool, now: TimeInterval) -> Step {
        if paused { // as in `step`: resuming must start every timer from scratch
            tracker.reset()
            lastBreaches = []
        }
        let alerts = engine.evaluate(breaches: lastBreaches, isMuted: isMuted, paused: paused, now: now)
        return Step(mood: engine.mood, breaches: lastBreaches, newAlerts: alerts)
    }

    /// After sleep/wake or a clock jump: no time spent asleep counts toward a bark.
    public mutating func resetTimers() {
        tracker.reset()
        engine.reset()
        lastBreaches = []
    }
}
