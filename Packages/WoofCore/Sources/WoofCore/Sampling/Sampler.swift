import Foundation

/// Owns the process source and CPU deltas; runs off the main actor.
public actor Sampler {
    private let source: any ProcessSource
    private let grouper: AppGrouper
    private var calculator = CPUCalculator()

    public init(source: any ProcessSource, grouper: AppGrouper) {
        self.source = source
        self.grouper = grouper
    }

    public func sample(now: TimeInterval) -> [Entity] {
        grouper.group(calculator.samples(from: source.snapshot(), at: now))
    }

    /// Call after sleep/wake so time asleep never shows up as CPU.
    public func reset() {
        calculator.reset()
    }
}
