public enum Command: Equatable, Sendable {
    case help
    case cpu(CPUJob)
    case mem(MemJob)
}

public enum LoadPattern: Equatable, Sendable {
    case steady
    /// Linear from `from` % to the job's load over each run.
    case ramp(from: Int)
    /// The job's load for `on` seconds, idle for `off` seconds, repeating from the run start.
    case spikes(on: Int, off: Int)
}

public struct CPUJob: Equatable, Sendable {
    public var cores: Int
    /// Percent of each core, 1–100.
    public var load: Int
    public var pattern: LoadPattern
    public var schedule: Schedule

    public init(cores: Int, load: Int, pattern: LoadPattern, schedule: Schedule) {
        self.cores = cores
        self.load = load
        self.pattern = pattern
        self.schedule = schedule
    }

    /// Percent of each core to burn `elapsed` seconds into a run.
    public func load(at elapsed: Double) -> Double {
        switch pattern {
        case .steady:
            return Double(load)
        case .ramp(let from):
            let progress = min(max(elapsed / Double(schedule.duration), 0), 1)
            return Double(from) + Double(load - from) * progress
        case .spikes(let on, let off):
            let position = elapsed.truncatingRemainder(dividingBy: Double(on + off))
            return position < Double(on) ? Double(load) : 0
        }
    }
}

public struct MemJob: Equatable, Sendable {
    public var gigabytes: Double
    public var schedule: Schedule

    public init(gigabytes: Double, schedule: Schedule) {
        self.gigabytes = gigabytes
        self.schedule = schedule
    }

    public var byteCount: Int {
        Int(gigabytes * Double(1 << 30))
    }
}
