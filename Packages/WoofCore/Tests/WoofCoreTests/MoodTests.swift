import Testing
@testable import WoofCore

@Suite struct MoodEngineTests {
    let key = BreachKey(entity: .process(path: "/usr/bin/yes"), resource: .cpu)

    func breach(id: Int = 1, progress: Double, entity: EntityKey? = nil, isOver: Bool = true) -> Breach {
        Breach(
            id: id,
            key: entity.map { BreachKey(entity: $0, resource: .cpu) } ?? key,
            since: 0,
            overTime: progress * 60,
            isOver: isOver,
            progress: progress,
            lastValue: 150
        )
    }

    func eval(_ engine: inout MoodEngine, _ breaches: [Breach], at now: Double = 0,
              muted: Set<EntityKey> = [], paused: Bool = false) -> [Breach] {
        engine.evaluate(breaches: breaches, isMuted: { muted.contains($0) }, paused: paused, now: now)
    }

    @Test func noBreachesMeansNapping() {
        var engine = MoodEngine()
        _ = eval(&engine, [])
        #expect(engine.mood == .napping)
    }

    @Test func progressDrivesSniffThenGrowl() {
        var engine = MoodEngine()
        _ = eval(&engine, [breach(progress: 0)])
        #expect(engine.mood == .sniffing)
        _ = eval(&engine, [breach(progress: 0.49)])
        #expect(engine.mood == .sniffing)
        _ = eval(&engine, [breach(progress: 0.5)])
        #expect(engine.mood == .growling)
    }

    @Test func fullProgressBarksOnceAndAlertsOnce() {
        var engine = MoodEngine()
        let first = eval(&engine, [breach(progress: 1)])
        #expect(first.map(\.id) == [1])
        #expect(engine.mood == .barking)
        let second = eval(&engine, [breach(progress: 1)], at: 2)
        #expect(second.isEmpty)
        #expect(engine.mood == .barking)
    }

    @Test func dismissingTheAlertSulksWhileBreachContinues() {
        var engine = MoodEngine()
        _ = eval(&engine, [breach(progress: 1)])
        engine.alertDismissed()
        #expect(engine.mood == .sulking)
        _ = eval(&engine, [breach(progress: 1)], at: 2)
        #expect(engine.mood == .sulking)
    }

    @Test func endedAlertMakesTheDogProudThenNap() {
        var engine = MoodEngine()
        _ = eval(&engine, [breach(progress: 1)])
        _ = eval(&engine, [], at: 2)
        #expect(engine.mood == .proud)
        _ = eval(&engine, [], at: 11)
        #expect(engine.mood == .proud)
        _ = eval(&engine, [], at: 12)
        #expect(engine.mood == .napping)
    }

    @Test func sulkingThatEndsIsAlsoProud() {
        var engine = MoodEngine()
        _ = eval(&engine, [breach(progress: 1)])
        engine.alertDismissed()
        _ = eval(&engine, [], at: 2)
        #expect(engine.mood == .proud)
    }

    @Test func ignoreMutesTheKeyAcrossEpisodes() {
        var engine = MoodEngine()
        _ = eval(&engine, [breach(id: 1, progress: 1)])
        engine.ignore(key, now: 0)
        _ = eval(&engine, [breach(id: 1, progress: 1)], at: 2)
        #expect(engine.mood == .napping)
        #expect(eval(&engine, [breach(id: 2, progress: 1)], at: 4).isEmpty)
        #expect(engine.mood == .napping)
    }

    @Test func ignoreSurvivesANewEpisode() {
        var engine = MoodEngine()
        engine.ignore(key, now: 0)
        _ = eval(&engine, [breach(id: 1, progress: 1)])
        _ = eval(&engine, [], at: 2)
        #expect(eval(&engine, [breach(id: 2, progress: 1)], at: 100).isEmpty)
        #expect(engine.isIgnored(key))
    }

    @Test func ignoreExpiresAfterTenCalmMinutes() {
        var engine = MoodEngine()
        engine.ignore(key, now: 0)
        _ = eval(&engine, [], at: 300)
        #expect(engine.isIgnored(key))
        #expect(eval(&engine, [breach(id: 2, progress: 1)], at: 601).map(\.id) == [2])
        #expect(!engine.isIgnored(key))
    }

    @Test func ignoreIsRefreshedWhileTheKeyKeepsBreaching() {
        var engine = MoodEngine()
        engine.ignore(key, now: 0)
        for t in stride(from: 2.0, through: 1200, by: 2) { _ = eval(&engine, [breach(progress: 1)], at: t) }
        #expect(engine.isIgnored(key))
    }

    @Test func ignoreSurvivesReset() {
        var engine = MoodEngine()
        engine.ignore(key, now: 0)
        engine.reset()
        #expect(engine.isIgnored(key))
    }

    @Test func ignoreSurvivesPause() {
        var engine = MoodEngine()
        engine.ignore(key, now: 0)
        for t in stride(from: 2.0, through: 3602, by: 300) { _ = eval(&engine, [], at: t, paused: true) }
        _ = eval(&engine, [], at: 3604)
        #expect(engine.isIgnored(key))
    }

    @Test func isIgnoredIsPerKey() {
        var engine = MoodEngine()
        engine.ignore(key, now: 0)
        #expect(!engine.isIgnored(BreachKey(entity: .process(path: "/bin/cat"), resource: .cpu)))
        #expect(!engine.isIgnored(BreachKey(entity: key.entity, resource: .memory)))
    }

    @Test func alertNeedsIsOver() {
        var engine = MoodEngine()
        #expect(eval(&engine, [breach(progress: 1, isOver: false)]).isEmpty)
        #expect(eval(&engine, [breach(progress: 1)], at: 2).map(\.id) == [1])
    }

    @Test func snoozedOrIgnoredEntitiesNeverBarkAndAreNotProud() {
        var engine = MoodEngine()
        let entityKey = key.entity
        _ = eval(&engine, [breach(progress: 1)])
        let alerts = eval(&engine, [breach(progress: 1)], at: 2, muted: [entityKey])
        #expect(alerts.isEmpty)
        #expect(engine.mood == .napping)
        #expect(eval(&engine, [breach(id: 9, progress: 1)], at: 4, muted: [entityKey]).isEmpty)
    }

    @Test func snoozedBreachAlertsAgainOnceTheSnoozeEnds() {
        var engine = MoodEngine()
        #expect(eval(&engine, [breach(progress: 1)]).map(\.id) == [1])
        #expect(eval(&engine, [breach(progress: 1)], at: 2, muted: [key.entity]).isEmpty)
        #expect(engine.mood == .napping)
        let again = eval(&engine, [breach(progress: 1)], at: 4)
        #expect(again.map(\.id) == [1])
        #expect(engine.mood == .barking)
    }

    @Test func ignoredBreachNeverAlertsAgain() {
        var engine = MoodEngine()
        _ = eval(&engine, [breach(progress: 1)])
        engine.ignore(key, now: 0)
        #expect(eval(&engine, [breach(progress: 1)], at: 2).isEmpty)
        #expect(eval(&engine, [breach(progress: 1)], at: 4, muted: [key.entity]).isEmpty)
        #expect(eval(&engine, [breach(progress: 1)], at: 6).isEmpty)
        #expect(engine.mood == .napping)
    }

    @Test func pausedIsAlwaysNapping() {
        var engine = MoodEngine()
        let alerts = eval(&engine, [breach(progress: 1)], paused: true)
        #expect(alerts.isEmpty)
        #expect(engine.mood == .napping)
    }

    @Test func twoEntitiesBarkingTogetherBothAlert() {
        var engine = MoodEngine()
        let other = EntityKey.process(path: "/usr/bin/other")
        let alerts = eval(&engine, [breach(id: 1, progress: 1), breach(id: 2, progress: 1, entity: other)])
        #expect(Set(alerts.map(\.id)) == [1, 2])
        #expect(engine.openAlertIDs == [1, 2])
    }

    @Test func barkWinsOverSulk() {
        var engine = MoodEngine()
        let other = EntityKey.process(path: "/usr/bin/other")
        _ = eval(&engine, [breach(id: 1, progress: 1)])
        engine.alertDismissed()
        _ = eval(&engine, [breach(id: 1, progress: 1), breach(id: 2, progress: 1, entity: other)], at: 2)
        #expect(engine.mood == .barking)
    }
}
