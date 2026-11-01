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
    /// `threshold` is the CPU minimum, in percent of one core.
    public var cpu: Limit
    /// `threshold` is the memory floor, as a fraction of RAM.
    public var memory: Limit
    /// The Mac counts as short on memory from this pressure level up.
    public var memoryStrainAt: MemoryPressure
    /// The Mac counts as running hot from this thermal level up.
    public var cpuStrainThermal: ThermalLevel
    /// Whole-machine CPU busy fraction (0...1) that counts as strained when plugged in.
    public var cpuStrainBusy: Double
    /// Minimum share (0...1) of the machine's load for an app to be the CPU culprit.
    public var cpuShare: Double
    /// Seconds one process must stay at a full core before the dog barks regardless of strain.
    public var runawayWindow: TimeInterval

    public init(
        cpu: Limit, memory: Limit, memoryStrainAt: MemoryPressure, cpuStrainThermal: ThermalLevel,
        cpuStrainBusy: Double, cpuShare: Double, runawayWindow: TimeInterval
    ) {
        self.cpu = cpu
        self.memory = memory
        self.memoryStrainAt = memoryStrainAt
        self.cpuStrainThermal = cpuStrainThermal
        self.cpuStrainBusy = cpuStrainBusy
        self.cpuShare = cpuShare
        self.runawayWindow = runawayWindow
    }

    /// The other fields take Balanced's values (literals, since `Sensitivity.balanced` is built from this type).
    public init(cpu: Limit, memory: Limit) {
        self.init(
            cpu: cpu, memory: memory, memoryStrainAt: .critical, cpuStrainThermal: .serious,
            cpuStrainBusy: 0.75, cpuShare: 0.33, runawayWindow: 600
        )
    }

    /// Stored custom limits from before the strain fields existed lack them; Balanced fills in.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            cpu: try c.decode(Limit.self, forKey: .cpu),
            memory: try c.decode(Limit.self, forKey: .memory),
            memoryStrainAt: try c.decodeIfPresent(MemoryPressure.self, forKey: .memoryStrainAt) ?? .critical,
            cpuStrainThermal: try c.decodeIfPresent(ThermalLevel.self, forKey: .cpuStrainThermal) ?? .serious,
            cpuStrainBusy: try c.decodeIfPresent(Double.self, forKey: .cpuStrainBusy) ?? 0.75,
            cpuShare: try c.decodeIfPresent(Double.self, forKey: .cpuShare) ?? 0.33,
            runawayWindow: try c.decodeIfPresent(TimeInterval.self, forKey: .runawayWindow) ?? 600
        )
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

    /// These limits for an app given a bigger bowl; only memory changes.
    public func fed(_ bowl: Bowl) -> Limits {
        var limits = self
        limits.memory.threshold *= bowl.factor
        return limits
    }
}

/// How much more memory than the shared limit one app may use before the dog minds.
public enum Bowl: String, Codable, CaseIterable, Sendable {
    case regular, big, huge, bottomless

    /// Relative to the shared limit, so bowls follow the sensitivity slider.
    public var factor: Double {
        switch self {
        case .regular: 1
        case .big: 1.5
        case .huge: 2
        case .bottomless: .infinity
        }
    }

    public var displayName: String { rawValue.capitalized }
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
        case .chill:
            Limits(cpu: Limit(threshold: 200, window: 600), memory: Limit(threshold: 0.25, window: 900),
                   memoryStrainAt: .critical, cpuStrainThermal: .critical, cpuStrainBusy: 0.90, cpuShare: 0.50, runawayWindow: 1800)
        case .relaxed:
            Limits(cpu: Limit(threshold: 150, window: 300), memory: Limit(threshold: 0.20, window: 600),
                   memoryStrainAt: .critical, cpuStrainThermal: .serious, cpuStrainBusy: 0.85, cpuShare: 0.40, runawayWindow: 1200)
        case .balanced:
            Limits(cpu: Limit(threshold: 100, window: 180), memory: Limit(threshold: 0.15, window: 300),
                   memoryStrainAt: .critical, cpuStrainThermal: .serious, cpuStrainBusy: 0.75, cpuShare: 0.33, runawayWindow: 600)
        case .alert:
            Limits(cpu: Limit(threshold: 70, window: 120), memory: Limit(threshold: 0.10, window: 180),
                   memoryStrainAt: .warning, cpuStrainThermal: .serious, cpuStrainBusy: 0.60, cpuShare: 0.25, runawayWindow: 300)
        case .paranoid:
            Limits(cpu: Limit(threshold: 50, window: 60), memory: Limit(threshold: 0.05, window: 120),
                   memoryStrainAt: .warning, cpuStrainThermal: .fair, cpuStrainBusy: 0.50, cpuShare: 0.20, runawayWindow: 180)
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
