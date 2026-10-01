import Testing
@testable import WoofCore

@Suite struct UsageHistoryTests {
    @Test func seriesKeepsOnlyRetentionWindow() {
        var history = UsageHistory(retention: 10)
        let e = entity("yes", cpu: 50, memory: gb)
        for t in stride(from: 0.0, through: 20, by: 2) { history.record([e], now: t) }
        #expect(history.series(for: e.key, resource: .cpu, since: 0).count == 6) // t = 10...20
        #expect(history.series(for: e.key, resource: .memory, since: 16) == [Double(gb), Double(gb), Double(gb)])
    }

    @Test func entitiesNotSeenAreEventuallyDropped() {
        var history = UsageHistory(retention: 10)
        let e = entity("yes", cpu: 50)
        history.record([e], now: 0)
        history.record([], now: 11)
        #expect(history.series(for: e.key, resource: .cpu, since: 0).isEmpty)
    }

    @Test func storageStaysBoundedAndVanishedEntitiesArePruned() {
        var history = UsageHistory(retention: 10)
        let e = entity("yes", cpu: 50)
        for t in stride(from: 0.0, through: 2000, by: 2) { history.record([e], now: t) }
        #expect(history.storedPointCount <= 100)
        for t in stride(from: 2002.0, through: 2200, by: 2) { history.record([], now: t) }
        #expect(history.storedPointCount == 0)
    }
}

@Suite struct WatchPipelineTests {
    let limits = Sensitivity.paranoid.limits // CPU > 50% for 60 s
    let ram = 16 * gb

    func run(_ pipeline: inout WatchPipeline, cpu: Double, at now: Double,
             muted: Set<EntityKey> = [], paused: Bool = false) -> WatchPipeline.Step {
        pipeline.step(entities: [entity("yes", cpu: cpu)], limits: limits, physicalMemory: ram,
                      isMuted: { muted.contains($0) }, paused: paused, now: now)
    }

    @Test func sustainedHogWalksThroughEveryMoodAndBarksOnce() {
        var pipeline = WatchPipeline()
        var moods: [DogMood] = []
        var alerts = 0
        for t in stride(from: 0.0, through: 80, by: 2) {
            let step = run(&pipeline, cpu: 120, at: t)
            alerts += step.newAlerts.count
            if moods.last != step.mood { moods.append(step.mood) }
        }
        #expect(moods == [.sniffing, .growling, .barking])
        #expect(alerts == 1)

        for t in stride(from: 82.0, through: 86, by: 2) { _ = run(&pipeline, cpu: 0, at: t) }
        #expect(pipeline.engine.mood == .proud)
    }

    @Test func pausingThenResumingStartsTimersFromScratch() {
        var pipeline = WatchPipeline()
        for t in stride(from: 0.0, through: 50, by: 2) { _ = run(&pipeline, cpu: 120, at: t) }
        _ = run(&pipeline, cpu: 120, at: 52, paused: true)
        let resumed = run(&pipeline, cpu: 120, at: 54)
        #expect(resumed.mood == .sniffing)
        #expect(resumed.breaches.first?.progress == 0)
    }

    @Test func resetTimersAfterWakeForgetsProgress() {
        var pipeline = WatchPipeline()
        for t in stride(from: 0.0, through: 50, by: 2) { _ = run(&pipeline, cpu: 120, at: t) }
        pipeline.resetTimers()
        #expect(run(&pipeline, cpu: 120, at: 4000).mood == .sniffing)
    }

    @Test func historyIsRecordedEvenWhenPaused() {
        var pipeline = WatchPipeline()
        _ = run(&pipeline, cpu: 120, at: 0, paused: true)
        #expect(pipeline.history.series(for: .process(path: "/usr/bin/yes"), resource: .cpu, since: 0) == [120])
    }
}
