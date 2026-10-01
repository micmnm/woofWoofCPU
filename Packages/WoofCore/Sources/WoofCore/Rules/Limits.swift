import Foundation

public struct Limit: Codable, Equatable, Sendable {
    /// CPU: percent (100 = one core). Memory: fraction of physical RAM (0...1).
    public var threshold: Double
    /// Seconds a value must stay over `threshold` before the dog barks.
    public var window: TimeInterval

    public init(threshold: Double, window: TimeInterval) {
        self.threshold = threshold
        self.window = window
    }
}

public struct Limits: Codable, Equatable, Sendable {
    public var cpu: Limit
    public var memory: Limit

    public init(cpu: Limit, memory: Limit) {
        self.cpu = cpu
        self.memory = memory
    }

    public subscript(resource: Resource) -> Limit {
        switch resource {
        case .cpu: cpu
        case .memory: memory
        }
    }

    /// Threshold in the same unit as `Entity.value(for:)` (percent or bytes).
    public func thresholdValue(for resource: Resource, physicalMemory: UInt64) -> Double {
        switch resource {
        case .cpu: cpu.threshold
        case .memory: memory.threshold * Double(physicalMemory)
        }
    }
}

public enum Sensitivity: Int, Codable, CaseIterable, Sendable {
    case chill, relaxed, balanced, alert, paranoid

    public var displayName: String {
        switch self {
        case .chill: "Chill"
        case .relaxed: "Relaxed"
        case .balanced: "Balanced"
        case .alert: "Alert"
        case .paranoid: "Paranoid"
        }
    }

    public var limits: Limits {
        switch self {
        case .chill:    Limits(cpu: Limit(threshold: 200, window: 600), memory: Limit(threshold: 0.40, window: 900))
        case .relaxed:  Limits(cpu: Limit(threshold: 150, window: 300), memory: Limit(threshold: 0.30, window: 600))
        case .balanced: Limits(cpu: Limit(threshold: 100, window: 180), memory: Limit(threshold: 0.20, window: 300))
        case .alert:    Limits(cpu: Limit(threshold: 70, window: 120), memory: Limit(threshold: 0.15, window: 180))
        case .paranoid: Limits(cpu: Limit(threshold: 50, window: 60), memory: Limit(threshold: 0.10, window: 120))
        }
    }
}

public enum LimitsSetting: Codable, Equatable, Sendable {
    case preset(Sensitivity)
    case custom(Limits)

    public var limits: Limits {
        switch self {
        case .preset(let sensitivity): sensitivity.limits
        case .custom(let limits): limits
        }
    }
}
