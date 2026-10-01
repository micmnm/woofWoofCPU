import Foundation
import Testing
@testable import WoofCore

@MainActor
@Suite struct SettingsStoreTests {
    let defaults: UserDefaults
    let key = EntityKey.app(bundleID: "com.google.Chrome")
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    init() {
        let suite = "woof.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    @Test func defaultsMatchSpec() {
        let store = SettingsStore(defaults: defaults, now: now)
        #expect(store.limitsSetting == .preset(.balanced))
        #expect(store.rowsShown == 5)
        #expect(store.skinID == "pixel")
        #expect(store.soundMuted == false)
        #expect(store.ignoreList.isEmpty)
    }

    @Test func valuesPersistAcrossInstances() {
        let store = SettingsStore(defaults: defaults, now: now)
        store.limitsSetting = .preset(.paranoid)
        store.rowsShown = 7
        store.skinID = "shiba"
        store.soundMuted = true
        store.alwaysIgnore(key)
        store.snooze(.process(path: "/usr/bin/yes"), until: now.addingTimeInterval(60))

        let reloaded = SettingsStore(defaults: defaults, now: now)
        #expect(reloaded.limitsSetting == .preset(.paranoid))
        #expect(reloaded.rowsShown == 7)
        #expect(reloaded.skinID == "shiba")
        #expect(reloaded.soundMuted)
        #expect(reloaded.ignoreList == [key])
        #expect(reloaded.snoozes.count == 1)
    }

    @Test func rowsShownIsClampedOnLoad() {
        defaults.set(99, forKey: "rowsShown")
        #expect(SettingsStore(defaults: defaults, now: now).rowsShown == 10)
    }

    @Test func ignoredOrSnoozedEntitiesAreMuted() {
        let store = SettingsStore(defaults: defaults, now: now)
        #expect(!store.isMuted(key, now: now))
        store.snooze(key, until: now.addingTimeInterval(60))
        #expect(store.isMuted(key, now: now))
        #expect(!store.isMuted(key, now: now.addingTimeInterval(61)))
        store.alwaysIgnore(key)
        #expect(store.isMuted(key, now: now.addingTimeInterval(61)))
        store.removeFromIgnoreList(key)
        #expect(!store.isMuted(key, now: now.addingTimeInterval(61)))
    }

    @Test func expiredSnoozesArePrunedOnLoadAndOnDemand() {
        let store = SettingsStore(defaults: defaults, now: now)
        store.snooze(key, until: now.addingTimeInterval(60))
        #expect(SettingsStore(defaults: defaults, now: now.addingTimeInterval(120)).snoozes.isEmpty)
        store.pruneExpired(now: now.addingTimeInterval(120))
        #expect(store.snoozes.isEmpty)
    }

    @Test func pauseExpires() {
        let store = SettingsStore(defaults: defaults, now: now)
        store.pausedUntil = now.addingTimeInterval(3600)
        #expect(store.isPaused(now: now))
        #expect(!store.isPaused(now: now.addingTimeInterval(3601)))
        store.pruneExpired(now: now.addingTimeInterval(3601))
        #expect(store.pausedUntil == nil)
    }

    @Test func snoozeUntilTomorrowIsNextSixAM() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let evening = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 22))!
        let until = SnoozeDuration.untilTomorrow.until(from: evening, calendar: calendar)
        #expect(until == calendar.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 6)))
        let earlyMorning = calendar.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 3))!
        #expect(SnoozeDuration.untilTomorrow.until(from: earlyMorning, calendar: calendar)
                == calendar.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 6)))
        #expect(SnoozeDuration.fifteenMinutes.until(from: evening) == evening.addingTimeInterval(900))
    }
}
