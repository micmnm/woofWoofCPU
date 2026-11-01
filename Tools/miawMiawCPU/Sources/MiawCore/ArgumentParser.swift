public struct UsageError: Error, Equatable, Sendable {
    public var message: String

    public init(_ message: String) {
        self.message = message
    }
}

public enum ArgumentParser {
    static let helpFlags: Set = ["--help", "-h"]
    static let helpWords = helpFlags.union(["help"])
    static let scheduleFlags: Set = ["--for", "--in", "--every", "--times"]
    static let cpuFlags = scheduleFlags.union(["--cores", "--load", "--pattern", "--ramp-from", "--spike-on", "--spike-off"])
    static let memFlags = scheduleFlags.union(["--gb"])
    static let maxGigabytes = 1024.0

    /// `activeCores` resolves `--cores all` and bounds `--cores N`.
    public static func parse(_ arguments: [String], activeCores: Int) throws(UsageError) -> Command {
        // A bare `help` only counts as the command, so `--pattern help` stays a bad value.
        guard let command = arguments.first, !helpWords.contains(command),
              !arguments.contains(where: helpFlags.contains) else { return .help }
        let rest = Array(arguments.dropFirst())
        switch command {
        case "cpu": return .cpu(try cpu(flags(rest, allowed: cpuFlags), activeCores: activeCores))
        case "mem": return .mem(try mem(flags(rest, allowed: memFlags)))
        case "demo": return .cpu(try demo(rest))
        default: throw UsageError("unknown command '\(command)'")
        }
    }

    static func demo(_ rest: [String]) throws(UsageError) -> CPUJob {
        guard rest.count == 1 else { throw UsageError("demo needs exactly one of: bark, spike, ramp") }
        switch rest[0] {
        case "bark":
            return CPUJob(cores: 2, load: 100, pattern: .steady, schedule: Schedule(delay: 0, duration: 240))
        case "spike":
            return CPUJob(cores: 2, load: 100, pattern: .spikes(on: 30, off: 30), schedule: Schedule(delay: 0, duration: 360))
        case "ramp":
            return CPUJob(cores: 2, load: 100, pattern: .ramp(from: 10), schedule: Schedule(delay: 0, duration: 360))
        default:
            throw UsageError("unknown demo '\(rest[0])' (try bark, spike or ramp)")
        }
    }

    static func cpu(_ flags: [String: String], activeCores: Int) throws(UsageError) -> CPUJob {
        var cores = 1
        if let text = flags["--cores"] {
            if text == "all" {
                cores = activeCores
            } else {
                // One thread per core: a typo like 1000 would spawn a thousand spinning threads.
                let maxCores = 4 * max(activeCores, 1)
                guard let value = Int(text), (1...maxCores).contains(value) else {
                    throw UsageError("--cores must be a number from 1 to \(maxCores) (4 × this Mac's cores) or 'all', not '\(text)'")
                }
                cores = value
            }
        }
        let load = try integer(flags, "--load", default: 100, in: 1...100)
        let rampFrom = try integer(flags, "--ramp-from", default: 20, in: 0...100)
        let spikeOn = try duration(flags, "--spike-on", default: 20)
        let spikeOff = try duration(flags, "--spike-off", default: 40)
        guard spikeOn > 0, spikeOff > 0 else { throw UsageError("--spike-on and --spike-off must be longer than 0s") }

        let pattern: LoadPattern
        switch flags["--pattern"] ?? "steady" {
        case "steady":
            pattern = .steady
        case "ramp":
            pattern = .ramp(from: rampFrom)
        case "spikes":
            pattern = .spikes(on: spikeOn, off: spikeOff)
        case let other:
            throw UsageError("--pattern must be steady, ramp or spikes, not '\(other)'")
        }
        return CPUJob(cores: cores, load: load, pattern: pattern, schedule: try schedule(flags))
    }

    static func mem(_ flags: [String: String]) throws(UsageError) -> MemJob {
        guard let text = flags["--gb"] else { throw UsageError("mem needs --gb (gigabytes to hold, e.g. --gb 2)") }
        guard let gigabytes = Double(text), gigabytes.isFinite, gigabytes > 0, gigabytes <= maxGigabytes else {
            throw UsageError("--gb must be a number above 0 and at most \(Int(maxGigabytes)), not '\(text)'")
        }
        return MemJob(gigabytes: gigabytes, schedule: try schedule(flags))
    }

    static func schedule(_ flags: [String: String]) throws(UsageError) -> Schedule {
        let length = try duration(flags, "--for", default: 120)
        guard length > 0 else { throw UsageError("--for must be longer than 0s") }
        let delay = try duration(flags, "--in", default: 0)

        guard flags["--every"] != nil else {
            if flags["--times"] != nil { throw UsageError("--times only works together with --every") }
            return Schedule(delay: delay, duration: length)
        }
        let every = try duration(flags, "--every", default: 0)
        guard every > length else {
            throw UsageError("--every (\(flags["--every"] ?? "")) must be longer than --for (\(flags["--for"] ?? "2m"))")
        }
        var times: Int?
        if flags["--times"] != nil {
            times = try integer(flags, "--times", default: 1, in: 1...Int.max)
        }
        return Schedule(delay: delay, duration: length, every: every, times: times)
    }

    /// Pairs each `--flag` with the value after it; later duplicates win.
    static func flags(_ arguments: [String], allowed: Set<String>) throws(UsageError) -> [String: String] {
        var result: [String: String] = [:]
        var index = 0
        while index < arguments.count {
            let flag = arguments[index]
            guard flag.hasPrefix("-") else { throw UsageError("unexpected argument '\(flag)'") }
            guard allowed.contains(flag) else { throw UsageError("unknown option '\(flag)' for this command") }
            guard index + 1 < arguments.count else { throw UsageError("\(flag) needs a value") }
            result[flag] = arguments[index + 1]
            index += 2
        }
        return result
    }

    static func duration(_ flags: [String: String], _ flag: String, default fallback: Int) throws(UsageError) -> Int {
        guard let text = flags[flag] else { return fallback }
        guard let seconds = DurationParser.seconds(from: text) else {
            throw UsageError("\(flag) needs a duration like 90, 90s, 5m, 1h or 1m30s, at most 7 days (168h), not '\(text)'")
        }
        return seconds
    }

    static func integer(_ flags: [String: String], _ flag: String, default fallback: Int,
                        in range: ClosedRange<Int>) throws(UsageError) -> Int {
        guard let text = flags[flag] else { return fallback }
        guard let value = Int(text), range.contains(value) else {
            let bounds = range.upperBound == Int.max ? "a whole number ≥ \(range.lowerBound)"
                : "a whole number from \(range.lowerBound) to \(range.upperBound)"
            throw UsageError("\(flag) must be \(bounds), not '\(text)'")
        }
        return value
    }
}

public enum Usage {
    public static let text = """
        usage: miawMiawCPU <command> [options]

        Loads this Mac on purpose so you can watch woofWoofCPU sniff, growl and bark.

          cpu   [--cores N|all] [--load P] [--for DUR]   burn CPU (default: 1 core, 100%, 2m)
                [--pattern steady|ramp|spikes]           steady (default), ramp or on/off bursts
                [--ramp-from P]                          ramp starts at P% (default 20) and climbs to --load
                [--spike-on DUR --spike-off DUR]         burst timing (default 20s on, 40s off)
          mem   --gb G [--for DUR]                       hold G gigabytes of touched memory (default 2m)
          demo  bark | spike | ramp                      presets on 2 cores:
                                                           bark   100% for 4m — barks on Paranoid (runaway after 3 min)
                                                           spike  30s bursts for 6m — too short to bark
                                                           ramp   10% to 100% over 6m — sniff, growl, bark on Paranoid
                                                         On Balanced the dog waits 10 min, so bark and ramp only sniff.
          help                                           show this text

        When (cpu and mem):
          --in DUR                  start after a delay (default 0)
          --every DUR [--times K]   repeat on a cycle; --every must be longer than --for;
                                    without --times it repeats until stopped

        DUR is 90, 90s, 5m, 1h or 1m30s (a bare number means seconds), at most 168h. --load is percent of each core.
        Ctrl-C, or Quit / ⌥Kill from the dog, stops everything.
        """
}
