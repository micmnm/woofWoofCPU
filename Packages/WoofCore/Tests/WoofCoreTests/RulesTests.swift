import Testing
@testable import WoofCore

@Suite struct LimitsTests {
    @Test func balancedIsTheSpecDefault() {
        let limits = Sensitivity.balanced.limits
        #expect(limits.cpu == Limit(threshold: 100, window: 180))
        #expect(limits.memory == Limit(threshold: 0.20, window: 300))
    }

    @Test func presetsGetStricterFromChillToParanoid() {
        let cpuThresholds = Sensitivity.allCases.map(\.limits.cpu.threshold)
        #expect(cpuThresholds == cpuThresholds.sorted(by: >))
        let windows = Sensitivity.allCases.map(\.limits.cpu.window)
        #expect(windows == windows.sorted(by: >))
    }

    @Test func memoryThresholdScalesWithRAM() {
        let limits = Sensitivity.balanced.limits
        #expect(limits.thresholdValue(for: .memory, physicalMemory: 16 * gb) == 0.2 * Double(16 * gb))
        #expect(limits.thresholdValue(for: .cpu, physicalMemory: 16 * gb) == 100)
    }

    @Test func bowlsScaleOnlyTheMemoryThreshold() {
        let limits = Sensitivity.balanced.limits
        #expect(limits.fed(.regular) == limits)
        #expect(abs(limits.fed(.big).memory.threshold - 0.30) < 1e-9)
        #expect(limits.fed(.big).memory.window == 300)
        #expect(limits.fed(.huge).memory.threshold == 0.40)
        #expect(limits.fed(.huge).cpu == limits.cpu)
        #expect(limits.fed(.bottomless).thresholdValue(for: .memory, physicalMemory: 16 * gb) == .infinity)
    }

    @Test func customLimitsOverridePreset() {
        let custom = Limits(cpu: Limit(threshold: 42, window: 7), memory: Limit(threshold: 0.5, window: 9))
        #expect(LimitsSetting.custom(custom).limits == custom)
        #expect(LimitsSetting.preset(.chill).limits == Sensitivity.chill.limits)
    }
}

@Suite struct BreachTrackerTests {
    let limits = Limits(cpu: Limit(threshold: 100, window: 60), memory: Limit(threshold: 0.5, window: 60))
    let ram = 16 * gb

    func tick(_ tracker: inout BreachTracker, cpu: Double, at now: Double) -> [Breach] {
        tracker.update(entities: [entity("yes", cpu: cpu)], limits: limits, physicalMemory: ram, now: now)
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

    @Test func valueInsideHysteresisBandKeepsBreachAlive() {
        var tracker = BreachTracker()
        _ = tick(&tracker, cpu: 150, at: 0)
        for t in stride(from: 2.0, through: 20, by: 2) {
            #expect(tick(&tracker, cpu: 95, at: t).count == 1)
        }
    }

    @Test func breachEndsAfterThreeCalmTicks() {
        var tracker = BreachTracker()
        _ = tick(&tracker, cpu: 150, at: 0)
        #expect(tick(&tracker, cpu: 10, at: 2).count == 1)
        #expect(tick(&tracker, cpu: 10, at: 4).count == 1)
        #expect(tick(&tracker, cpu: 10, at: 6).isEmpty)
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
        for t in [2.0, 4, 6] { _ = tick(&tracker, cpu: 0, at: t) }
        let second = tick(&tracker, cpu: 150, at: 8)[0].id
        #expect(first != second)
    }

    @Test func vanishedEntityEndsBreachImmediately() {
        var tracker = BreachTracker()
        _ = tick(&tracker, cpu: 150, at: 0)
        #expect(tracker.update(entities: [], limits: limits, physicalMemory: ram, now: 2).isEmpty)
    }

    @Test func memoryBreachUsesFractionOfRAM() {
        var tracker = BreachTracker()
        let hog = entity("hog", memory: 9 * gb) // > 50% of 16 GB
        let breaches = tracker.update(entities: [hog], limits: limits, physicalMemory: ram, now: 0)
        #expect(breaches.map(\.key.resource) == [.memory])
    }

    @Test func bowlRaisesOnlyThatEntitysMemoryLimit() {
        var tracker = BreachTracker()
        let fed = entity("fed", memory: 9 * gb) // over 8 GB, under the Big bowl's 12 GB
        let hungry = entity("hungry", memory: 9 * gb)
        let breaches = tracker.update(
            entities: [fed, hungry], limits: limits, bowls: [fed.key: .big], physicalMemory: ram, now: 0
        )
        #expect(breaches.map(\.key.entity) == [hungry.key])
    }

    @Test func bottomlessBowlStillWatchesCPU() {
        var tracker = BreachTracker()
        let hog = entity("hog", cpu: 150, memory: 15 * gb)
        let breaches = tracker.update(
            entities: [hog], limits: limits, bowls: [hog.key: .bottomless], physicalMemory: ram, now: 0
        )
        #expect(breaches.map(\.key.resource) == [.cpu])
    }

    @Test func resetForgetsRunningBreaches() {
        var tracker = BreachTracker()
        _ = tick(&tracker, cpu: 150, at: 0)
        tracker.reset()
        #expect(tick(&tracker, cpu: 150, at: 100)[0].progress == 0)
    }
}
