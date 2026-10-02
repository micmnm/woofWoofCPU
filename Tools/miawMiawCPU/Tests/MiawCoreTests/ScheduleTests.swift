import Testing
@testable import MiawCore

@Suite struct ScheduleTests {
    let single = Schedule(delay: 5, duration: 60)
    let cycle = Schedule(delay: 10, duration: 60, every: 600, times: 3)
    let forever = Schedule(delay: 0, duration: 30, every: 300)

    @Test func singleRunStartsAfterDelay() {
        #expect(single.totalRuns == 1)
        #expect(single.start(ofRun: 0) == 5)
        #expect(single.end(ofRun: 0) == 65)
    }

    @Test func cycleRunsAreSpacedByEvery() {
        #expect(cycle.totalRuns == 3)
        #expect(cycle.start(ofRun: 0) == 10)
        #expect(cycle.start(ofRun: 2) == 1210)
        #expect(cycle.end(ofRun: 2) == 1270)
    }

    @Test func everyWithoutTimesIsInfinite() {
        #expect(forever.totalRuns == nil)
        #expect(forever.start(ofRun: 1000) == 300_000)
    }

    @Test func waitsUntilTheDelayPasses() {
        #expect(single.phase(at: 0) == .waiting(remaining: 5))
        #expect(single.phase(at: 2) == .waiting(remaining: 3))
    }

    @Test func singleRunRunsThenFinishes() {
        #expect(single.phase(at: 5) == .running(run: 0, elapsed: 0, remaining: 60))
        #expect(single.phase(at: 64.5) == .running(run: 0, elapsed: 59.5, remaining: 0.5))
        #expect(single.phase(at: 65) == .finished)
        #expect(single.phase(at: 1000) == .finished)
    }

    @Test func cycleNapsBetweenRuns() {
        #expect(cycle.phase(at: 69) == .running(run: 0, elapsed: 59, remaining: 1))
        #expect(cycle.phase(at: 70) == .napping(remaining: 540))
        #expect(cycle.phase(at: 609) == .napping(remaining: 1))
        #expect(cycle.phase(at: 610) == .running(run: 1, elapsed: 0, remaining: 60))
        #expect(cycle.phase(at: 1269) == .running(run: 2, elapsed: 59, remaining: 1))
        #expect(cycle.phase(at: 1270) == .finished)
        #expect(cycle.phase(at: 1810) == .finished)
    }

    @Test func infiniteCycleNeverFinishes() {
        #expect(forever.phase(at: 300_010) == .running(run: 1000, elapsed: 10, remaining: 20))
        #expect(forever.phase(at: 300_100) == .napping(remaining: 200))
    }
}
