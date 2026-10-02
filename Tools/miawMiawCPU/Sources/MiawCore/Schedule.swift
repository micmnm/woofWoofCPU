/// When runs happen, in seconds from launch. Run k (0-based) starts at `delay + k * every` and lasts `duration`.
public struct Schedule: Equatable, Sendable {
    public var delay: Int
    public var duration: Int
    /// Cycle length; nil means a single run.
    public var every: Int?
    /// Number of runs in a cycle; nil with `every` set means repeat until stopped.
    public var times: Int?

    public init(delay: Int, duration: Int, every: Int? = nil, times: Int? = nil) {
        self.delay = delay
        self.duration = duration
        self.every = every
        self.times = times
    }

    /// nil when the cycle repeats forever.
    public var totalRuns: Int? {
        every == nil ? 1 : times
    }

    public func start(ofRun run: Int) -> Int {
        delay + run * (every ?? 0)
    }

    public func end(ofRun run: Int) -> Int {
        start(ofRun: run) + duration
    }

    public func phase(at time: Double) -> Phase {
        if time < Double(delay) { return .waiting(remaining: Double(delay) - time) }
        let sinceFirst = time - Double(delay)
        let run = every.map { Int(sinceFirst / Double($0)) } ?? 0
        if let totalRuns, run >= totalRuns { return .finished }
        let elapsed = sinceFirst - Double(run * (every ?? 0))
        if elapsed < Double(duration) {
            return .running(run: run, elapsed: elapsed, remaining: Double(duration) - elapsed)
        }
        guard let every else { return .finished }
        if let totalRuns, run + 1 >= totalRuns { return .finished }
        return .napping(remaining: Double(every) - elapsed)
    }
}

public enum Phase: Equatable, Sendable {
    case waiting(remaining: Double)
    /// `run` is 0-based; `elapsed` is seconds since this run started.
    case running(run: Int, elapsed: Double, remaining: Double)
    case napping(remaining: Double)
    case finished
}
