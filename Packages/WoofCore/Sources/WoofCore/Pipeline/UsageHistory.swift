import Foundation

/// Recent per-entity values for the popover sparklines.
public struct UsageHistory: Sendable {
    public struct Point: Equatable, Sendable {
        public let time: TimeInterval
        public let cpuPercent: Double
        public let memoryBytes: UInt64
    }

    /// Longest window any preset uses (Chill memory, 15 min).
    public var retention: TimeInterval
    private var points: [EntityKey: [Point]] = [:]

    public init(retention: TimeInterval = 900) {
        self.retention = retention
    }

    public mutating func record(_ entities: [Entity], now: TimeInterval) {
        let cutoff = now - retention
        for entity in entities {
            points[entity.key, default: []].append(
                Point(time: now, cpuPercent: entity.cpuPercent, memoryBytes: entity.memoryBytes)
            )
        }
        points = points.compactMapValues { series in
            let kept = series.filter { $0.time >= cutoff }
            return kept.isEmpty ? nil : kept
        }
    }

    /// Values since `since`, oldest first; CPU in percent, memory in bytes.
    public func series(for key: EntityKey, resource: Resource, since: TimeInterval) -> [Double] {
        (points[key] ?? []).filter { $0.time >= since }.map { point in
            switch resource {
            case .cpu: point.cpuPercent
            case .memory: Double(point.memoryBytes)
            }
        }
    }

    public mutating func reset() {
        points = [:]
    }
}
