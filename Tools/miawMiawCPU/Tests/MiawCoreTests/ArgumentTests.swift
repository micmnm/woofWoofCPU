import Testing
@testable import MiawCore

@Suite struct ArgumentParsingTests {
    func parse(_ line: String, activeCores: Int = 8) throws(UsageError) -> Command {
        try ArgumentParser.parse(line.split(separator: " ").map(String.init), activeCores: activeCores)
    }

    func failure(_ line: String) -> String? {
        do {
            _ = try parse(line)
            return nil
        } catch {
            return error.message
        }
    }

    @Test func cpuAppliesDefaults() throws {
        let expected = CPUJob(cores: 1, load: 100, pattern: .steady, schedule: Schedule(delay: 0, duration: 120))
        #expect(try parse("cpu") == .cpu(expected))
    }

    @Test func cpuReadsEveryFlag() throws {
        let command = try parse("cpu --cores 4 --load 80 --for 1m30s --in 25 --every 10m --times 3 --pattern ramp --ramp-from 30")
        let schedule = Schedule(delay: 25, duration: 90, every: 600, times: 3)
        #expect(command == .cpu(CPUJob(cores: 4, load: 80, pattern: .ramp(from: 30), schedule: schedule)))
    }

    @Test func coresAllUsesActiveProcessorCount() throws {
        guard case .cpu(let job) = try parse("cpu --cores all", activeCores: 12) else {
            Issue.record("expected cpu")
            return
        }
        #expect(job.cores == 12)
    }

    @Test func coresAllowUpToFourTimesTheActiveCount() throws {
        guard case .cpu(let job) = try parse("cpu --cores 32", activeCores: 8) else {
            Issue.record("expected cpu")
            return
        }
        #expect(job.cores == 32)
        do {
            _ = try parse("cpu --cores 33", activeCores: 8)
            Issue.record("expected --cores 33 to be rejected on 8 cores")
        } catch {
            #expect(error.message.contains("--cores"))
            #expect(error.message.contains("32"))
        }
    }

    @Test func everyWithoutTimesRepeatsForever() throws {
        guard case .cpu(let job) = try parse("cpu --for 1m --every 5m") else {
            Issue.record("expected cpu")
            return
        }
        #expect(job.schedule == Schedule(delay: 0, duration: 60, every: 300, times: nil))
    }

    @Test func rampStartsAtTwentyByDefault() throws {
        guard case .cpu(let job) = try parse("cpu --pattern ramp") else {
            Issue.record("expected cpu")
            return
        }
        #expect(job.pattern == .ramp(from: 20))
    }

    @Test func spikesDefaultToTwentyOnFortyOff() throws {
        guard case .cpu(let job) = try parse("cpu --pattern spikes") else {
            Issue.record("expected cpu")
            return
        }
        #expect(job.pattern == .spikes(on: 20, off: 40))
    }

    @Test func spikeTimingIsConfigurable() throws {
        guard case .cpu(let job) = try parse("cpu --pattern spikes --spike-on 30s --spike-off 1m --load 70") else {
            Issue.record("expected cpu")
            return
        }
        #expect(job.pattern == .spikes(on: 30, off: 60))
        #expect(job.load == 70)
    }

    @Test func memAppliesDefaults() throws {
        #expect(try parse("mem --gb 0.5") == .mem(MemJob(gigabytes: 0.5, schedule: Schedule(delay: 0, duration: 120))))
    }

    @Test func memReadsSchedule() throws {
        let schedule = Schedule(delay: 10, duration: 300, every: 1200, times: 2)
        #expect(try parse("mem --gb 6 --for 5m --in 10s --every 20m --times 2") == .mem(MemJob(gigabytes: 6, schedule: schedule)))
    }

    @Test func memByteCountUsesBinaryGigabytes() {
        #expect(MemJob(gigabytes: 0.5, schedule: Schedule(delay: 0, duration: 1)).byteCount == 1 << 29)
        #expect(MemJob(gigabytes: 6, schedule: Schedule(delay: 0, duration: 1)).byteCount == 6 << 30)
    }

    @Test(arguments: ["help", "--help", "-h", "", "cpu --help", "mem -h", "help cpu", "cpu --for 1m --help", "demo -h"])
    func helpForms(line: String) throws {
        #expect(try parse(line) == .help)
    }

    @Test func demoBarkIsTwoFullCoresForFourMinutes() throws {
        let expected = CPUJob(cores: 2, load: 100, pattern: .steady, schedule: Schedule(delay: 0, duration: 240))
        #expect(try parse("demo bark") == .cpu(expected))
    }

    @Test func demoSpikeIsShortBurstsForSixMinutes() throws {
        let expected = CPUJob(cores: 2, load: 100, pattern: .spikes(on: 30, off: 30), schedule: Schedule(delay: 0, duration: 360))
        #expect(try parse("demo spike") == .cpu(expected))
    }

    /// Two cores pass a 90% runaway at 45% load (≈ 2m20s in), leaving Paranoid's 3 min window time to bark.
    @Test func demoRampClimbsFromTenToHundredOverSixMinutes() throws {
        let expected = CPUJob(cores: 2, load: 100, pattern: .ramp(from: 10), schedule: Schedule(delay: 0, duration: 360))
        #expect(try parse("demo ramp") == .cpu(expected))
    }

    @Test(arguments: [
        "bogus", "cpu stray", "cpu --bogus", "cpu --load", "cpu --load abc", "cpu --load 0", "cpu --load 101",
        "cpu --for 5x", "cpu --for 0", "cpu --in -5s", "cpu --cores 0", "cpu --cores many",
        "cpu --for 2m --every 2m", "cpu --for 2m --every 1m", "cpu --times 3", "cpu --every 5m --times 0",
        "cpu --every 5m --times x", "cpu --pattern wobble", "cpu --ramp-from 101", "cpu --ramp-from -1",
        "cpu --pattern spikes --spike-on 0", "cpu --pattern spikes --spike-off 0",
        "mem", "mem --gb", "mem --gb 0", "mem --gb abc", "mem --gb -1", "mem --gb nan", "mem --gb inf",
        "mem --gb 1 --pattern ramp", "mem --gb 1 --cores 2", "mem --gb 1 --load 50",
        "demo", "demo meow", "demo bark extra", "demo bark --cores 4",
        "cpu --for 9223372036854775807", "cpu --in 169h", "mem --gb 1 --for 2m --every 169h",
        "cpu --pattern help", "mem --gb help", "cpu help", "demo help",
        "cpu --cores 1000000", "cpu --cores 9223372036854775807",
    ])
    func rejectsBadArguments(line: String) {
        #expect(failure(line) != nil)
    }

    @Test func errorsNameTheProblem() {
        #expect(failure("frobnicate")?.contains("frobnicate") == true)
        #expect(failure("cpu --wiggle")?.contains("--wiggle") == true)
        #expect(failure("cpu --for 2m --every 1m")?.contains("--every") == true)
        #expect(failure("cpu --times 3")?.contains("--times") == true)
        #expect(failure("mem")?.contains("--gb") == true)
        #expect(failure("cpu --load 150")?.contains("--load") == true)
        #expect(failure("cpu --for soon")?.contains("soon") == true)
        #expect(failure("cpu --for 9223372036854775807")?.contains("7 days") == true)
        #expect(failure("cpu --pattern help")?.contains("--pattern") == true)
    }

    @Test func usageListsEveryCommand() {
        for word in ["cpu", "mem", "demo", "bark", "spike", "ramp", "--every", "--times", "--pattern", "--gb"] {
            #expect(Usage.text.contains(word))
        }
    }
}
