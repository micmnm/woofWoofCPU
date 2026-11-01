import Foundation

/// Everything that happens per tick after sampling: breaches → mood → alerts, plus history.
public struct WatchPipeline: Sendable {
    public struct Step: Equatable, Sendable {
        public let mood: DogMood
        public let breaches: [Breach]
        public let newAlerts: [Breach]
        public let strain: Strain
    }

    public private(set) var tracker = BreachTracker()
    public var engine = MoodEngine()
    public private(set) var history = UsageHistory()
    private var lastBreaches: [Breach] = []
    private var mutedLastTick: Set<EntityKey> = []
    private var lastStrain = Strain(memory: false, cpu: false)

    public init() {}

    public mutating func step(
        entities: [Entity],
        machine: MachineState,
        limits: Limits,
        bowls: [EntityKey: Bowl] = [:],
        usual: UsualUsage,
        isMuted: (EntityKey) -> Bool,
        paused: Bool,
        now: TimeInterval
    ) -> Step {
        history.record(entities, now: now)
        let muted = Set(entities.map(\.key).filter(isMuted))
        for key in mutedLastTick.subtracting(muted) { tracker.restart(entity: key, now: now) }
        mutedLastTick = muted
        // Pausing drops running timers so resuming never barks instantly.
        if paused { tracker.reset() }
        let strain = Judge.strain(machine, limits)
        let breaches = paused
            ? []
            : tracker.update(entities: entities, now: now) { entity, resource, continuing in
                Judge.verdicts(
                    entity, resource, machine: machine, strain: strain, limits: limits,
                    bowl: bowls[entity.key] ?? .regular, usual: usual, continuing: continuing)
            }
        lastBreaches = breaches
        lastStrain = strain
        let alerts = engine.evaluate(breaches: breaches, isMuted: isMuted, paused: paused, now: now)
        return Step(mood: engine.mood, breaches: breaches, newAlerts: alerts, strain: strain)
    }

    /// Re-runs only the mood engine on the last tick's breaches, so a snooze/ignore/pause shows up
    /// at once without adding a history point or a (calm) tick to the tracker.
    public mutating func reevaluate(isMuted: (EntityKey) -> Bool, paused: Bool, now: TimeInterval) -> Step {
        if paused { // as in `step`: resuming must start every timer from scratch
            tracker.reset()
            lastBreaches = []
        }
        let keys = Set(lastBreaches.map(\.key.entity))
        let muted = keys.filter(isMuted)
        let unmuted = mutedLastTick.intersection(keys).subtracting(muted)
        for key in unmuted { tracker.restart(entity: key, now: now) }
        if !unmuted.isEmpty {
            lastBreaches = lastBreaches.map { unmuted.contains($0.key.entity) ? $0.restarted() : $0 }
        }
        mutedLastTick = mutedLastTick.subtracting(keys).union(muted)
        let alerts = engine.evaluate(breaches: lastBreaches, isMuted: isMuted, paused: paused, now: now)
        return Step(mood: engine.mood, breaches: lastBreaches, newAlerts: alerts, strain: lastStrain)
    }

    /// Ends this breach now; if the pair is still over on the next tick, a new one starts from zero.
    public mutating func endBreach(_ key: BreachKey) {
        tracker.end(key)
        lastBreaches.removeAll { $0.key == key }
    }

    /// After sleep/wake or a clock jump: no time spent asleep counts toward a bark.
    public mutating func resetTimers() {
        tracker.reset()
        engine.reset()
        lastBreaches = []
    }
}
