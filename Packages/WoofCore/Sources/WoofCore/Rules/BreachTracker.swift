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
    public let since: TimeInterval
    /// 0...1 — fraction of the window spent over the limit.
    public let progress: Double
    public let lastValue: Double
}

/// Tracks, per (entity, resource), how long a value has stayed over its limit.
public struct BreachTracker: Equatable, Sendable {
    /// A breach continues while the value stays above this fraction of the limit.
    public static let hysteresis = 0.9
    /// Consecutive ticks below the hysteresis band that end a breach.
    public static let calmTicksToEnd = 3

    private struct State: Equatable, Sendable {
        let id: Int
        let since: TimeInterval
        var calmTicks: Int
        var lastValue: Double
    }

    private var states: [BreachKey: State] = [:]
    private var nextID = 1

    public init() {}

    public mutating func update(
        entities: [Entity],
        limits: Limits,
        physicalMemory: UInt64,
        now: TimeInterval
    ) -> [Breach] {
        var present = Set<BreachKey>()
        for entity in entities {
            for resource in Resource.allCases {
                let key = BreachKey(entity: entity.key, resource: resource)
                present.insert(key)
                let value = entity.value(for: resource)
                let threshold = limits.thresholdValue(for: resource, physicalMemory: physicalMemory)
                if var state = states[key] {
                    if value > threshold * Self.hysteresis {
                        state.calmTicks = 0
                    } else {
                        state.calmTicks += 1
                    }
                    state.lastValue = value
                    states[key] = state.calmTicks >= Self.calmTicksToEnd ? nil : state
                } else if value > threshold {
                    states[key] = State(id: nextID, since: now, calmTicks: 0, lastValue: value)
                    nextID += 1
                }
            }
        }
        // An entity that disappeared (quit, killed, exited) ends its breaches at once.
        states = states.filter { present.contains($0.key) }

        return states.map { key, state in
            let window = limits[key.resource].window
            let progress = window > 0 ? min(1, max(0, (now - state.since) / window)) : 1
            return Breach(id: state.id, key: key, since: state.since, progress: progress, lastValue: state.lastValue)
        }
        .sorted { $0.id < $1.id }
    }

    public mutating func reset() {
        states = [:]
    }
}
