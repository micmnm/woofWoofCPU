import Testing
@testable import WoofCore

@Suite struct MachTimeTests {
    @Test func appleSiliconTimebaseConvertsTicksToNanoseconds() {
        // 24 MHz tick clock: 24_000_000 ticks = 1 s.
        #expect(MachTime.nanoseconds(24_000_000, numer: 125, denom: 3) == 1_000_000_000)
    }

    @Test func identityTimebaseIsUnchanged() {
        #expect(MachTime.nanoseconds(123_456, numer: 1, denom: 1) == 123_456)
    }

    @Test func largeValuesDoNotOverflow() {
        let tenYearsOfTicks: UInt64 = 24_000_000 * 60 * 60 * 24 * 365 * 10
        #expect(MachTime.nanoseconds(tenYearsOfTicks, numer: 125, denom: 3) == 315_360_000_000_000_000)
    }
}

@Suite struct CPUCalculatorTests {
    @Test func firstSightingReportsZero() {
        var calc = CPUCalculator()
        let result = calc.samples(from: [raw(10, cpuNanos: 5_000_000_000)], at: 100)
        #expect(result.first?.cpuPercent == 0)
    }

    @Test func oneFullCoreIsOneHundredPercent() {
        var calc = CPUCalculator()
        _ = calc.samples(from: [raw(10, cpuNanos: 0)], at: 100)
        let result = calc.samples(from: [raw(10, cpuNanos: 2_000_000_000)], at: 102)
        #expect(result.first?.cpuPercent == 100)
    }

    @Test func multipleCoresExceedOneHundred() {
        var calc = CPUCalculator()
        _ = calc.samples(from: [raw(10, cpuNanos: 0)], at: 0)
        let result = calc.samples(from: [raw(10, cpuNanos: 6_000_000_000)], at: 2)
        #expect(result.first?.cpuPercent == 300)
    }

    @Test func reusedPIDWithNewStartTimeDoesNotInheritHistory() {
        var calc = CPUCalculator()
        _ = calc.samples(from: [raw(10, start: 1, cpuNanos: 0)], at: 0)
        let result = calc.samples(from: [raw(10, start: 2, cpuNanos: 9_000_000_000)], at: 2)
        #expect(result.first?.cpuPercent == 0)
    }

    @Test func resetForgetsPreviousTick() {
        var calc = CPUCalculator()
        _ = calc.samples(from: [raw(10, cpuNanos: 0)], at: 0)
        calc.reset()
        let result = calc.samples(from: [raw(10, cpuNanos: 2_000_000_000)], at: 2)
        #expect(result.first?.cpuPercent == 0)
    }
}
