import Foundation

/// Recent per-entity values for the popover sparklines.
public struct UsageHistory: Sendable {
    public struct Point: Equatable, Sendable {
        public let time: TimeInterval
        public let cpuPercent: Double
        public let memoryBytes: UInt64
    }

    /// Ticks between sweeps that drop series of entities no longer recorded.
    static let pruneEveryTicks = 30

    /// Longest window any preset uses (Chill memory, 15 min).
    public var retention: TimeInterval
    /// Each series is oldest first; expired heads are trimmed lazily and hidden by `series`.
    private var points: [EntityKey: [Point]] = [:]
    private var latest: TimeInterval = -.infinity
    private var ticksSincePrune = 0

    public init(retention: TimeInterval = 900) {
        self.retention = retention
    }

    public mutating func record(_ entities: [Entity], now: TimeInterval) {
        latest = now
        let cutoff = now - retention
        // Trimming in batches keeps the per-tick cost to one append per entity.
        let trimBefore = cutoff - max(retention / 10, 1)
        for entity in entities {
            Self.append(
                Point(time: now, cpuPercent: entity.cpuPercent, memoryBytes: entity.memoryBytes),
                to: &points[entity.key, default: []],
                trimmingBefore: trimBefore,
                cutoff: cutoff
            )
        }
        ticksSincePrune += 1
        if ticksSincePrune >= Self.pruneEveryTicks {
            ticksSincePrune = 0
            points = points.compactMapValues { series in
                let kept = series[Self.firstIndex(in: series, atOrAfter: cutoff)...]
                return kept.isEmpty ? nil : Array(kept)
            }
        }
    }

    /// Values since `since`, oldest first; CPU in percent, memory in bytes.
    public func series(for key: EntityKey, resource: Resource, since: TimeInterval) -> [Double] {
        guard let series = points[key] else { return [] }
        let start = Self.firstIndex(in: series, atOrAfter: max(since, latest - retention))
        return series[start...].map { point in
            switch resource {
            case .cpu: point.cpuPercent
            case .memory: Double(point.memoryBytes)
            }
        }
    }

    var storedPointCount: Int { points.values.reduce(0) { $0 + $1.count } }

    public mutating func reset() {
        points = [:]
        latest = -.infinity
        ticksSincePrune = 0
    }

    private static func append(_ point: Point, to series: inout [Point], trimmingBefore: TimeInterval, cutoff: TimeInterval) {
        series.append(point)
        if let first = series.first, first.time < trimmingBefore {
            series.removeFirst(firstIndex(in: series, atOrAfter: cutoff))
        }
    }

    private static func firstIndex(in series: [Point], atOrAfter time: TimeInterval) -> Int {
        var low = 0, high = series.count
        while low < high {
            let mid = (low + high) / 2
            if series[mid].time < time { low = mid + 1 } else { high = mid }
        }
        return low
    }
}
