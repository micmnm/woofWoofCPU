import Foundation

public enum MemoryPressure: Int, Codable, Comparable, Sendable {
    case normal, warning, critical

    /// `kern.memorystatus_vm_pressure_level`: 1 normal, 2 warning, 4 critical.
    public init(sysctlLevel: Int32) {
        switch sysctlLevel {
        case 2: self = .warning
        case 4: self = .critical
        default: self = .normal
        }
    }

    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

public enum ThermalLevel: Int, Codable, Comparable, Sendable {
    case nominal, fair, serious, critical

    public init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        @unknown default: self = .nominal
        }
    }

    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

public struct MachineState: Equatable, Sendable {
    public var memoryPressure: MemoryPressure
    public var thermal: ThermalLevel
    public var onBattery: Bool
    public var lowPowerMode: Bool
    /// 0...1 of all cores.
    public var cpuBusy: Double
    public var logicalCores: Int
    public var physicalMemory: UInt64

    public init(
        memoryPressure: MemoryPressure, thermal: ThermalLevel, onBattery: Bool, lowPowerMode: Bool,
        cpuBusy: Double, logicalCores: Int, physicalMemory: UInt64
    ) {
        self.memoryPressure = memoryPressure
        self.thermal = thermal
        self.onBattery = onBattery
        self.lowPowerMode = lowPowerMode
        self.cpuBusy = cpuBusy
        self.logicalCores = logicalCores
        self.physicalMemory = physicalMemory
    }

    public static func calm(cores: Int = 8, memory: UInt64 = 8 << 30) -> MachineState {
        MachineState(
            memoryPressure: .normal, thermal: .nominal, onBattery: false, lowPowerMode: false,
            cpuBusy: 0, logicalCores: cores, physicalMemory: memory)
    }
}

public protocol MachineStateSource: Sendable {
    func read() -> MachineState
    /// Call after sleep/wake so time asleep never shows up as CPU.
    func reset()
}

/// Turns cumulative host CPU ticks into the busy fraction since the previous reading.
public struct HostCPUCalculator: Sendable {
    private var previous: (busy: UInt64, total: UInt64)?

    public init() {}

    public mutating func busy(busyTicks: UInt64, totalTicks: UInt64) -> Double {
        defer { previous = (busyTicks, totalTicks) }
        guard let p = previous, totalTicks > p.total, busyTicks >= p.busy else { return 0 }
        return min(1, Double(busyTicks - p.busy) / Double(totalTicks - p.total))
    }

    public mutating func reset() { previous = nil }
}
