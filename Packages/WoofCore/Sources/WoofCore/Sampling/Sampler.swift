import Foundation

public struct Snapshot: Sendable {
    public let entities: [Entity]
    public let machine: MachineState

    public init(entities: [Entity], machine: MachineState) {
        self.entities = entities
        self.machine = machine
    }
}

/// Owns the process source and CPU deltas; runs off the main actor.
public actor Sampler {
    private let source: any ProcessSource
    private let grouper: AppGrouper
    private let machine: any MachineStateSource
    private var calculator = CPUCalculator()

    public init(source: any ProcessSource, grouper: AppGrouper, machine: any MachineStateSource) {
        self.source = source
        self.grouper = grouper
        self.machine = machine
    }

    public func sample(now: TimeInterval) -> Snapshot {
        Snapshot(
            entities: grouper.group(calculator.samples(from: source.snapshot(), at: now)),
            machine: machine.read())
    }

    /// Call after sleep/wake so time asleep never shows up as CPU.
    public func reset() {
        calculator.reset()
        machine.reset()
    }
}
