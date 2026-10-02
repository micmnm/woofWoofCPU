import Testing
@testable import MiawCore

@Suite struct LoadPatternTests {
    func job(_ pattern: LoadPattern, load: Int = 100, duration: Int = 100) -> CPUJob {
        CPUJob(cores: 1, load: load, pattern: pattern, schedule: Schedule(delay: 0, duration: duration))
    }

    @Test func steadyHoldsTheLoad() {
        let steady = job(.steady, load: 80)
        #expect(steady.load(at: 0) == 80)
        #expect(steady.load(at: 50) == 80)
        #expect(steady.load(at: 99.9) == 80)
    }

    @Test func rampClimbsLinearlyOverTheRun() {
        let ramp = job(.ramp(from: 20), load: 100, duration: 100)
        #expect(ramp.load(at: 0) == 20)
        #expect(ramp.load(at: 50) == 60)
        #expect(ramp.load(at: 100) == 100)
    }

    @Test func rampClampsOutsideTheRun() {
        let ramp = job(.ramp(from: 20), load: 100, duration: 100)
        #expect(ramp.load(at: -5) == 20)
        #expect(ramp.load(at: 150) == 100)
    }

    @Test func rampCanClimbDown() {
        let ramp = job(.ramp(from: 100), load: 40, duration: 60)
        #expect(ramp.load(at: 30) == 70)
    }

    @Test func spikesAlternateOnAndOff() {
        let spikes = job(.spikes(on: 20, off: 40), duration: 300)
        #expect(spikes.load(at: 0) == 100)
        #expect(spikes.load(at: 19.9) == 100)
        #expect(spikes.load(at: 20) == 0)
        #expect(spikes.load(at: 59.9) == 0)
        #expect(spikes.load(at: 60) == 100)
        #expect(spikes.load(at: 80) == 0)
    }

    @Test func spikesUseTheLoadAsTheOnLevel() {
        let spikes = job(.spikes(on: 20, off: 40), load: 70, duration: 300)
        #expect(spikes.load(at: 5) == 70)
        #expect(spikes.load(at: 25) == 0)
    }
}
