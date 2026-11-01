import Foundation

/// What each app normally uses, as an exponentially decayed mean and variance per resource.
public struct UsualUsage: Codable, Equatable, Sendable {
    public static let halfLife: TimeInterval = 3 * 86_400
    public static let learnedAfter: TimeInterval = 2 * 3_600

    private struct Slot: Hashable, Codable, Sendable {
        let key: EntityKey
        let resource: Resource
    }

    private struct Stat: Codable, Equatable, Sendable {
        var mean: Double
        var variance: Double
        var observed: TimeInterval
        var lastSeen: Date
    }

    private var stats: [Slot: Stat] = [:]

    public init() {}

    /// Gaps longer than `maxElapsed` (sleep, a stalled tick) are skipped rather than weighted.
    public mutating func record(_ entities: [Entity], elapsed: TimeInterval, maxElapsed: TimeInterval, at date: Date) {
        guard elapsed > 0, elapsed <= maxElapsed else { return }
        let alpha = 1 - exp(-log(2) * elapsed / Self.halfLife)
        for entity in entities {
            for resource in Resource.allCases {
                let x = entity.value(for: resource)
                let slot = Slot(key: entity.key, resource: resource)
                guard var stat = stats[slot] else {
                    stats[slot] = Stat(mean: x, variance: 0, observed: elapsed, lastSeen: date)
                    continue
                }
                let d = x - stat.mean
                stat.mean += alpha * d
                stat.variance = (1 - alpha) * (stat.variance + alpha * d * d)
                stat.observed += elapsed
                stat.lastSeen = date
                stats[slot] = stat
            }
        }
    }

    /// Nil until the app has been watched for `learnedAfter`.
    public func usualHigh(_ key: EntityKey, _ resource: Resource) -> Double? {
        guard let stat = stats[Slot(key: key, resource: resource)], stat.observed >= Self.learnedAfter else { return nil }
        return max(stat.mean + 2 * stat.variance.squareRoot(), stat.mean * 1.25)
    }

    func mean(_ key: EntityKey, _ resource: Resource) -> Double? {
        stats[Slot(key: key, resource: resource)]?.mean
    }

    public mutating func prune(notSeenSince cutoff: Date) {
        stats = stats.filter { $0.value.lastSeen >= cutoff }
    }

    public mutating func forgetAll() {
        stats = [:]
    }
}
