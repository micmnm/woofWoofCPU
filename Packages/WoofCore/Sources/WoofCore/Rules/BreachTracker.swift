import Foundation

public struct BreachKey: Hashable, Sendable {
    public let entity: EntityKey
    public let resource: Resource

    public init(entity: EntityKey, resource: Resource) {
        self.entity = entity
        self.resource = resource
    }
}

public struct Breach: Equatable, Sendable {
    /// Unique per breach episode; a new episode for the same key gets a new id.
    public let id: Int
    public let key: BreachKey
    /// Start of the episode.
    public let since: TimeInterval
    /// Seconds `reason` has spent over; frozen while calm.
    public let overTime: TimeInterval
    /// False on the calm ticks that keep an episode alive until `calmPeriod` has passed.
    public let isOver: Bool
    /// 0...1 — the highest of the reasons' over-time against their own windows.
    public let progress: Double
    /// The reason with that highest progress.
    public let reason: BreachReason
    public let lastValue: Double

    func restarted() -> Breach {
        Breach(id: id, key: key, since: since, overTime: 0, isOver: isOver, progress: 0, reason: reason, lastValue: lastValue)
    }
}

/// Tracks, per (entity, resource), how long each verdict's reason has applied.
public struct BreachTracker: Equatable, Sendable {
    /// Seconds without any verdict that end a breach, independent of the tick interval.
    public static let calmPeriod: TimeInterval = 60

    private struct Clock: Equatable, Sendable {
        var overTime: TimeInterval
        var window: TimeInterval

        var progress: Double { window > 0 ? min(1, max(0, overTime / window)) : 1 }
    }

    private struct State: Equatable, Sendable {
        let id: Int
        let since: TimeInterval
        var lastTick: TimeInterval
        var clocks: [BreachReason: Clock] = [:]
        var calmSince: TimeInterval?
        var isOver = true
        var lastValue: Double

        /// A reason's clock runs only on ticks where it applies; its first tick adds nothing.
        mutating func advance(_ verdicts: [Verdict], elapsed: TimeInterval) {
            for verdict in verdicts {
                clocks[verdict.reason] = Clock(
                    overTime: clocks[verdict.reason].map { $0.overTime + elapsed } ?? 0, window: verdict.window)
            }
        }
    }

    private var states: [BreachKey: State] = [:]
    private var nextID = 1

    public init() {}

    /// `verdicts(entity, resource, continuing)`: why the pair is over this tick (empty when calm);
    /// `continuing` is true while a breach for the pair is already running.
    public mutating func update(
        entities: [Entity],
        now: TimeInterval,
        verdicts: (Entity, Resource, Bool) -> [Verdict]
    ) -> [Breach] {
        var present = Set<BreachKey>()
        for entity in entities {
            for resource in Resource.allCases {
                let key = BreachKey(entity: entity.key, resource: resource)
                present.insert(key)
                let value = entity.value(for: resource)
                let over = verdicts(entity, resource, states[key] != nil)
                if var state = states[key] {
                    state.isOver = !over.isEmpty
                    if state.isOver {
                        state.advance(over, elapsed: now - state.lastTick)
                        state.calmSince = nil
                    } else if state.calmSince == nil {
                        state.calmSince = now
                    }
                    state.lastTick = now
                    state.lastValue = value
                    states[key] = state.calmSince.map { now - $0 >= Self.calmPeriod } == true ? nil : state
                } else if !over.isEmpty {
                    var state = State(id: nextID, since: now, lastTick: now, lastValue: value)
                    state.advance(over, elapsed: 0)
                    states[key] = state
                    nextID += 1
                }
            }
        }
        // An entity that disappeared (quit, killed, exited) ends its breaches at once.
        states = states.filter { present.contains($0.key) }

        return states.map { key, state in
            // Every state starts with a verdict, so there is at least one clock; ties go to strain.
            let clocks = BreachReason.allCases.compactMap { r in state.clocks[r].map { (reason: r, clock: $0) } }
            let top = clocks.dropFirst().reduce(clocks[0]) { $1.clock.progress > $0.clock.progress ? $1 : $0 }
            return Breach(
                id: state.id, key: key, since: state.since, overTime: top.clock.overTime, isOver: state.isOver,
                progress: top.clock.progress, reason: top.reason, lastValue: state.lastValue
            )
        }
        .sorted { $0.id < $1.id }
    }

    /// Zeroes every reason's time spent over for this entity, as when its snooze ends.
    public mutating func restart(entity: EntityKey, now: TimeInterval) {
        for (key, var state) in states where key.entity == entity {
            state.clocks = state.clocks.mapValues { Clock(overTime: 0, window: $0.window) }
            state.lastTick = now
            states[key] = state
        }
    }

    public mutating func reset() {
        states = [:]
    }
}
