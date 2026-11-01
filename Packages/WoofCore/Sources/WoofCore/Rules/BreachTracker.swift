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
    /// Seconds actually spent over the limit; frozen while calm.
    public let overTime: TimeInterval
    /// False on the calm ticks that keep an episode alive until `calmPeriod` has passed.
    public let isOver: Bool
    /// 0...1 — fraction of the window spent over the limit.
    public let progress: Double
    public let lastValue: Double

    func restarted() -> Breach {
        Breach(id: id, key: key, since: since, overTime: 0, isOver: isOver, progress: 0, lastValue: lastValue)
    }
}

/// Tracks, per (entity, resource), how long a value has stayed over its limit.
public struct BreachTracker: Equatable, Sendable {
    /// A breach continues while the value stays above this fraction of the limit.
    public static let hysteresis = 0.9
    /// Seconds below the hysteresis band that end a breach, independent of the tick interval.
    public static let calmPeriod: TimeInterval = 60

    private struct State: Equatable, Sendable {
        let id: Int
        let since: TimeInterval
        var lastTick: TimeInterval
        var overTime: TimeInterval
        var calmSince: TimeInterval?
        var isOver: Bool
        var lastValue: Double
    }

    private var states: [BreachKey: State] = [:]
    private var nextID = 1

    public init() {}

    public mutating func update(
        entities: [Entity],
        limits: Limits,
        bowls: [EntityKey: Bowl] = [:],
        physicalMemory: UInt64,
        now: TimeInterval
    ) -> [Breach] {
        var present = Set<BreachKey>()
        for entity in entities {
            let entityLimits = limits.fed(bowls[entity.key] ?? .regular)
            for resource in Resource.allCases {
                let key = BreachKey(entity: entity.key, resource: resource)
                present.insert(key)
                let value = entity.value(for: resource)
                let threshold = entityLimits.thresholdValue(for: resource, physicalMemory: physicalMemory)
                if var state = states[key] {
                    state.isOver = value > threshold * Self.hysteresis
                    if state.isOver {
                        state.overTime += now - state.lastTick
                        state.calmSince = nil
                    } else if state.calmSince == nil {
                        state.calmSince = now
                    }
                    state.lastTick = now
                    state.lastValue = value
                    states[key] = state.calmSince.map { now - $0 >= Self.calmPeriod } == true ? nil : state
                } else if value > threshold {
                    states[key] = State(
                        id: nextID, since: now, lastTick: now, overTime: 0, calmSince: nil, isOver: true, lastValue: value
                    )
                    nextID += 1
                }
            }
        }
        // An entity that disappeared (quit, killed, exited) ends its breaches at once.
        states = states.filter { present.contains($0.key) }

        return states.map { key, state in
            let window = limits[key.resource].window
            let progress = window > 0 ? min(1, max(0, state.overTime / window)) : 1
            return Breach(
                id: state.id, key: key, since: state.since, overTime: state.overTime, isOver: state.isOver,
                progress: progress, lastValue: state.lastValue
            )
        }
        .sorted { $0.id < $1.id }
    }

    /// Zeroes the time spent over for this entity, as when its snooze ends.
    public mutating func restart(entity: EntityKey, now: TimeInterval) {
        for key in states.keys where key.entity == entity {
            states[key]?.overTime = 0
            states[key]?.lastTick = now
        }
    }

    public mutating func reset() {
        states = [:]
    }
}
