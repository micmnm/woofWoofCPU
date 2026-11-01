import Foundation

public enum BreachReason: String, Codable, Sendable {
    case strain, runaway
}

public struct Verdict: Equatable, Sendable {
    public let reason: BreachReason
    public let window: TimeInterval

    public init(reason: BreachReason, window: TimeInterval) {
        self.reason = reason
        self.window = window
    }
}

/// Whether the Mac itself is hurting, per resource.
public struct Strain: Equatable, Sendable {
    public let memory: Bool
    public let cpu: Bool

    public init(memory: Bool, cpu: Bool) {
        self.memory = memory
        self.cpu = cpu
    }
}

/// Decides whether the Mac is strained and whether an entity is to blame or has a runaway process.
public enum Judge {
    /// One member process at this CPU percent (about a full core) is a runaway.
    public static let runawayCPU: Double = 90
    /// Lowers every bar while a breach is already running.
    public static let continuingFactor = 0.9
    /// How much lower the busy trigger sits on battery or in Low Power Mode.
    public static let batteryBusyDrop = 0.25

    public static func strain(_ machine: MachineState, _ limits: Limits) -> Strain {
        let busyTrigger = saving(machine) ? max(0, limits.cpuStrainBusy - batteryBusyDrop) : limits.cpuStrainBusy
        return Strain(
            memory: machine.memoryPressure >= limits.memoryStrainAt,
            cpu: machine.thermal >= limits.cpuStrainThermal || machine.cpuBusy >= busyTrigger)
    }

    /// Strain first, then runaway.
    public static func verdicts(
        _ entity: Entity, _ resource: Resource, machine: MachineState, strain: Strain, limits: Limits,
        bowl: Bowl, usual: UsualUsage, continuing: Bool
    ) -> [Verdict] {
        let k = continuing ? continuingFactor : 1
        var verdicts: [Verdict] = []
        if isCulprit(entity, resource, machine: machine, strain: strain, limits: limits, bowl: bowl, usual: usual, k: k) {
            verdicts.append(Verdict(reason: .strain, window: limits[resource].window))
        }
        if resource == .cpu, entity.members.contains(where: { $0.cpuPercent >= runawayCPU * k }) {
            let window = saving(machine) ? limits.runawayWindow / 2 : limits.runawayWindow
            verdicts.append(Verdict(reason: .runaway, window: window))
        }
        return verdicts
    }

    private static func isCulprit(
        _ entity: Entity, _ resource: Resource, machine: MachineState, strain: Strain, limits: Limits,
        bowl: Bowl, usual: UsualUsage, k: Double
    ) -> Bool {
        let value = entity.value(for: resource)
        switch resource {
        case .memory:
            guard strain.memory, bowl != .bottomless else { return false }
        case .cpu:
            guard strain.cpu else { return false }
            let load = machine.cpuBusy * Double(machine.logicalCores) * 100
            guard load <= 0 || value / load >= limits.cpuShare * k else { return false }
        }
        guard value >= limits.fed(bowl).thresholdValue(for: resource, physicalMemory: machine.physicalMemory) * k else {
            return false
        }
        return usual.usualHigh(entity.key, resource).map { value > $0 } ?? true
    }

    private static func saving(_ machine: MachineState) -> Bool {
        machine.onBattery || machine.lowPowerMode
    }
}
