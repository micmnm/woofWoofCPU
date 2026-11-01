import Testing
@testable import WoofCore

@Suite struct LimitsTests {
    @Test func balancedIsTheSpecDefault() {
        let limits = Sensitivity.balanced.limits
        #expect(limits.cpu == Limit(threshold: 100, window: 180))
        #expect(limits.memory == Limit(threshold: 0.15, window: 300))
    }

    @Test func presetsGetStricterFromChillToParanoid() {
        let cpuThresholds = Sensitivity.allCases.map(\.limits.cpu.threshold)
        #expect(cpuThresholds == cpuThresholds.sorted(by: >))
        let windows = Sensitivity.allCases.map(\.limits.cpu.window)
        #expect(windows == windows.sorted(by: >))
    }

    @Test func memoryThresholdScalesWithRAM() {
        let limits = Sensitivity.balanced.limits
        #expect(limits.thresholdValue(for: .memory, physicalMemory: 16 * gb) == 0.15 * Double(16 * gb))
        #expect(limits.thresholdValue(for: .cpu, physicalMemory: 16 * gb) == 100)
    }

    @Test func bowlsScaleOnlyTheMemoryThreshold() {
        let limits = Sensitivity.balanced.limits
        #expect(limits.fed(.regular) == limits)
        #expect(abs(limits.fed(.big).memory.threshold - 0.225) < 1e-9)
        #expect(limits.fed(.big).memory.window == 300)
        #expect(abs(limits.fed(.huge).memory.threshold - 0.30) < 1e-9)
        #expect(limits.fed(.huge).cpu == limits.cpu)
        #expect(limits.fed(.bottomless).thresholdValue(for: .memory, physicalMemory: 16 * gb) == .infinity)
    }

    @Test func stopsMatchTheSpecTable() {
        // cpu, cpu window, mem floor, mem window, memoryStrainAt, cpuStrainThermal, cpuStrainBusy, cpuShare, runaway
        let rows: [(Sensitivity, Double, Double, Double, Double, MemoryPressure, ThermalLevel, Double, Double, Double)] = [
            (.chill, 200, 600, 0.25, 900, .critical, .critical, 0.90, 0.50, 1800),
            (.relaxed, 150, 300, 0.20, 600, .critical, .serious, 0.85, 0.40, 1200),
            (.balanced, 100, 180, 0.15, 300, .warning, .serious, 0.75, 0.33, 600),
            (.alert, 70, 120, 0.10, 180, .warning, .serious, 0.60, 0.25, 300),
            (.paranoid, 50, 60, 0.05, 120, .warning, .fair, 0.50, 0.20, 180),
        ]
        for (stop, cpu, cpuWindow, floor, memWindow, memAt, thermal, busy, share, runaway) in rows {
            let expected = Limits(
                cpu: Limit(threshold: cpu, window: cpuWindow), memory: Limit(threshold: floor, window: memWindow),
                memoryStrainAt: memAt, cpuStrainThermal: thermal, cpuStrainBusy: busy, cpuShare: share, runawayWindow: runaway
            )
            #expect(stop.limits == expected, "\(stop.displayName)")
        }
    }

    @Test func conveniencePairInitUsesBalancedExtras() {
        let limits = Limits(cpu: Limit(threshold: 42, window: 7), memory: Limit(threshold: 0.5, window: 9))
        var expected = Sensitivity.balanced.limits
        expected.cpu = limits.cpu
        expected.memory = limits.memory
        #expect(limits == expected)
    }

    @Test func customLimitsOverridePreset() {
        let custom = Limits(cpu: Limit(threshold: 42, window: 7), memory: Limit(threshold: 0.5, window: 9))
        #expect(LimitsSetting.custom(custom).limits == custom)
        #expect(LimitsSetting.preset(.chill).limits == Sensitivity.chill.limits)
    }
}

@Suite struct BreachTrackerTests {
    let yes = entity("yes")

    /// Judges only (yes, CPU), with the given verdicts.
    func tick(_ tracker: inout BreachTracker, _ verdicts: [Verdict], at now: Double) -> [Breach] {
        tracker.update(entities: [yes], now: now) { _, resource, _ in resource == .cpu ? verdicts : [] }
    }

    /// Over (strain, 60 s window) while CPU is above 100%.
    func tick(_ tracker: inout BreachTracker, cpu: Double, at now: Double) -> [Breach] {
        tick(&tracker, cpu > 100 ? [Verdict(reason: .strain, window: 60)] : [], at: now)
    }

    @Test func breachStartsAboveLimitAndProgressGrows() {
        var tracker = BreachTracker()
        #expect(tick(&tracker, cpu: 50, at: 0).isEmpty)
        let started = tick(&tracker, cpu: 150, at: 2)
        #expect(started.count == 1)
        #expect(started[0].progress == 0)
        #expect(started[0].key.resource == .cpu)
        let half = tick(&tracker, cpu: 150, at: 32)
        #expect(half[0].progress == 0.5)
        let full = tick(&tracker, cpu: 150, at: 100)
        #expect(full[0].progress == 1)
    }

    @Test func continuingIsTrueOnceABreachExists() {
        var tracker = BreachTracker()
        var seen: [Bool] = []
        let judge: (Entity, Resource, Bool) -> [Verdict] = { _, resource, continuing in
            if resource == .cpu { seen.append(continuing) }
            return resource == .cpu ? [Verdict(reason: .strain, window: 60)] : []
        }
        _ = tracker.update(entities: [yes], now: 0, verdicts: judge)
        _ = tracker.update(entities: [yes], now: 2, verdicts: judge)
        #expect(seen == [false, true])
    }

    @Test func breachEndsAfterSixtySecondsCalmAtTwoSecondTicks() {
        var tracker = BreachTracker()
        _ = tick(&tracker, cpu: 150, at: 0)
        for t in stride(from: 2.0, through: 60, by: 2) { #expect(tick(&tracker, cpu: 10, at: t).count == 1) }
        #expect(tick(&tracker, cpu: 10, at: 62).isEmpty)
    }

    @Test func breachEndsAfterSixtySecondsCalmAtThirtySecondTicks() {
        var tracker = BreachTracker()
        _ = tick(&tracker, cpu: 150, at: 0)
        #expect(tick(&tracker, cpu: 10, at: 30).count == 1)
        #expect(tick(&tracker, cpu: 10, at: 60).count == 1)
        #expect(tick(&tracker, cpu: 10, at: 90).isEmpty)
    }

    @Test func progressCountsOnlyTimeOver() {
        var tracker = BreachTracker()
        for t in stride(from: 0.0, through: 30, by: 2) { _ = tick(&tracker, cpu: 150, at: t) }
        for t in stride(from: 32.0, through: 50, by: 2) {
            let calm = tick(&tracker, cpu: 10, at: t)[0]
            #expect(!calm.isOver)
            #expect(calm.progress == 0.5)
        }
        let again = tick(&tracker, cpu: 150, at: 52)[0]
        #expect(again.isOver)
        #expect(again.progress == 32.0 / 60)
        #expect(again.overTime == 32)
    }

    @Test func restartZeroesOverTime() {
        var tracker = BreachTracker()
        for t in stride(from: 0.0, through: 30, by: 2) { _ = tick(&tracker, cpu: 150, at: t) }
        tracker.restart(entity: .process(path: "/usr/bin/yes"), now: 30)
        let next = tick(&tracker, cpu: 150, at: 32)[0]
        #expect(next.overTime == 2)
        #expect(next.since == 0)
    }

    @Test func spikeShorterThanWindowNeverReachesFullProgress() {
        var tracker = BreachTracker()
        var maxProgress = 0.0
        for t in stride(from: 0.0, through: 50, by: 2) {
            maxProgress = max(maxProgress, tick(&tracker, cpu: 300, at: t).first?.progress ?? 0)
        }
        for t in stride(from: 52.0, through: 60, by: 2) {
            maxProgress = max(maxProgress, tick(&tracker, cpu: 0, at: t).first?.progress ?? 0)
        }
        #expect(maxProgress < 1)
    }

    @Test func newEpisodeGetsNewID() {
        var tracker = BreachTracker()
        let first = tick(&tracker, cpu: 150, at: 0)[0].id
        for t in stride(from: 2.0, through: 62, by: 2) { _ = tick(&tracker, cpu: 0, at: t) }
        let second = tick(&tracker, cpu: 150, at: 64)[0].id
        #expect(first != second)
    }

    @Test func vanishedEntityEndsBreachImmediately() {
        var tracker = BreachTracker()
        _ = tick(&tracker, cpu: 150, at: 0)
        #expect(tracker.update(entities: [], now: 2) { _, _, _ in [Verdict(reason: .strain, window: 60)] }.isEmpty)
    }

    @Test func breachesAreKeptPerResource() {
        var tracker = BreachTracker()
        let breaches = tracker.update(entities: [yes], now: 0) { _, resource, _ in
            resource == .memory ? [Verdict(reason: .strain, window: 60)] : []
        }
        #expect(breaches.map(\.key.resource) == [.memory])
    }

    @Test func resetForgetsRunningBreaches() {
        var tracker = BreachTracker()
        _ = tick(&tracker, cpu: 150, at: 0)
        tracker.reset()
        #expect(tick(&tracker, cpu: 150, at: 100)[0].progress == 0)
    }

    @Test func reasonsKeepTheirOwnClocks() {
        var tracker = BreachTracker()
        let runaway = Verdict(reason: .runaway, window: 600)
        let strain = Verdict(reason: .strain, window: 180)
        for t in stride(from: 0.0, to: 480, by: 10) { _ = tick(&tracker, [runaway], at: t) }
        #expect(tick(&tracker, [runaway], at: 480)[0].progress == 0.8)
        for t in stride(from: 490.0, to: 540, by: 10) {
            #expect(tick(&tracker, [strain, runaway], at: t)[0].progress < 0.9)
        }
        let both = tick(&tracker, [strain, runaway], at: 540)[0]
        #expect(both.progress == 0.9)
        #expect(both.reason == .runaway)
        #expect(both.overTime == 540)
    }

    @Test func reasonDroppingOutKeepsProgress() {
        var tracker = BreachTracker()
        let strain = Verdict(reason: .strain, window: 100)
        let runaway = Verdict(reason: .runaway, window: 600)
        for t in stride(from: 0.0, through: 70, by: 10) { _ = tick(&tracker, [strain], at: t) }
        for t in stride(from: 80.0, through: 300, by: 10) {
            let breach = tick(&tracker, [runaway], at: t)[0]
            #expect(breach.progress == 0.7) // strain frozen at 70/100, runaway still below it
            #expect(breach.reason == .strain)
        }
        let back = tick(&tracker, [strain], at: 310)[0]
        #expect(back.overTime == 80) // only the 10 s since the last tick counts
    }
}
