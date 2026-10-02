import Testing
@testable import MiawCore

@Suite struct StatusLineTests {
    func cpu(cores: Int = 2, load: Int = 80, pattern: LoadPattern = .steady, schedule: Schedule) -> CPUJob {
        CPUJob(cores: cores, load: load, pattern: pattern, schedule: schedule)
    }

    @Test(arguments: [
        (0.0, "0:00"), (25.0, "0:25"), (102.0, "1:42"), (101.2, "1:42"), (478.0, "7:58"),
        (3599.0, "59:59"), (3600.0, "1:00:00"), (3725.0, "1:02:05"), (-3.0, "0:00"),
    ])
    func clockRoundsUpToWholeSeconds(seconds: Double, text: String) {
        #expect(Status.clock(seconds) == text)
    }

    @Test func waitingCountsDownToTheStart() {
        let job = cpu(schedule: Schedule(delay: 25, duration: 60))
        #expect(Status.line(for: .waiting(remaining: 25), cpu: job) == "🐱 miaw… starting in 0:25")
    }

    @Test func runningCPUShowsCoresLoadTimeLeftAndRun() {
        let job = cpu(schedule: Schedule(delay: 0, duration: 120, every: 600, times: 3))
        let line = Status.line(for: .running(run: 1, elapsed: 18, remaining: 102), cpu: job)
        #expect(line == "🐱 miaw… 2 cores @ 80% · 1:42 left · run 2/3")
    }

    @Test func singleRunOmitsTheRunCounter() {
        let job = cpu(cores: 1, load: 100, schedule: Schedule(delay: 0, duration: 120))
        let line = Status.line(for: .running(run: 0, elapsed: 0, remaining: 120), cpu: job)
        #expect(line == "🐱 miaw… 1 core @ 100% · 2:00 left")
    }

    @Test func endlessCycleShowsOnlyTheRunNumber() {
        let job = cpu(schedule: Schedule(delay: 0, duration: 60, every: 120))
        let line = Status.line(for: .running(run: 3, elapsed: 0, remaining: 60), cpu: job)
        #expect(line == "🐱 miaw… 2 cores @ 80% · 1:00 left · run 4")
    }

    @Test func patternsShowTheCurrentLoad() {
        let ramp = cpu(load: 100, pattern: .ramp(from: 20), schedule: Schedule(delay: 0, duration: 100))
        #expect(Status.line(for: .running(run: 0, elapsed: 50, remaining: 50), cpu: ramp)
            == "🐱 miaw… 2 cores @ 60% · 0:50 left")
        let spikes = cpu(load: 100, pattern: .spikes(on: 20, off: 40), schedule: Schedule(delay: 0, duration: 300))
        #expect(Status.line(for: .running(run: 0, elapsed: 30, remaining: 270), cpu: spikes)
            == "🐱 miaw… 2 cores @ 0% · 4:30 left")
    }

    @Test func memShowsGigabytesWithOneDecimal() {
        let job = MemJob(gigabytes: 6, schedule: Schedule(delay: 0, duration: 300))
        #expect(Status.line(for: .running(run: 0, elapsed: 198, remaining: 102), mem: job)
            == "🐱 miaw… holding 6.0 GB · 1:42 left")
        let half = MemJob(gigabytes: 0.3, schedule: Schedule(delay: 0, duration: 300, every: 600, times: 2))
        #expect(Status.line(for: .running(run: 0, elapsed: 0, remaining: 300), mem: half)
            == "🐱 miaw… holding 0.3 GB · 5:00 left · run 1/2")
    }

    @Test func memSaysAllocatingUntilEveryPageIsTouched() {
        let job = MemJob(gigabytes: 2, schedule: Schedule(delay: 0, duration: 20))
        #expect(Status.line(for: .running(run: 0, elapsed: 1, remaining: 19), mem: job, allocating: true)
            == "🐱 miaw… allocating 2.0 GB… · 0:19 left")
    }

    @Test func nappingCountsDownToTheNextRun() {
        let job = MemJob(gigabytes: 1, schedule: Schedule(delay: 0, duration: 60, every: 600))
        #expect(Status.line(for: .napping(remaining: 478), mem: job) == "🐱 napping… next run in 7:58")
    }

    @Test func finishedAndStoppedLines() {
        let job = cpu(schedule: Schedule(delay: 0, duration: 60))
        #expect(Status.line(for: .finished, cpu: job) == Status.done)
        #expect(Status.done == "🐱 miaw — done")
        #expect(Status.stopped == "🐱 miaw — stopped")
    }
}
