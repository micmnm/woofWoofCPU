import Foundation

/// Turns cumulative CPU times into a per-tick CPU %.
public struct CPUCalculator: Sendable {
    private var lastCPU: [ProcessIdentity: UInt64] = [:]
    private var lastTime: TimeInterval?

    public init() {}

    /// `now` is monotonic seconds. Processes seen for the first time report 0%.
    public mutating func samples(from processes: [RawProcess], at now: TimeInterval) -> [ProcessSample] {
        let elapsed = lastTime.map { now - $0 } ?? 0
        var next: [ProcessIdentity: UInt64] = [:]
        next.reserveCapacity(processes.count)
        let result = processes.map { process -> ProcessSample in
            next[process.identity] = process.cpuTimeNanos
            var percent = 0.0
            if elapsed > 0, let previous = lastCPU[process.identity], process.cpuTimeNanos >= previous {
                percent = Double(process.cpuTimeNanos - previous) / (elapsed * 1e9) * 100
            }
            return ProcessSample(process: process, cpuPercent: percent)
        }
        lastCPU = next
        lastTime = now
        return result
    }

    public mutating func reset() {
        lastCPU = [:]
        lastTime = nil
    }
}
