import Foundation
import Testing
@testable import WoofCore

/// Each test gets a throwaway domain. An absolute-path suite keeps its plist out of
/// ~/Library/Preferences, where cfprefsd leaves an empty file behind even after removal.
@MainActor
@Suite final class SettingsStoreTests {
    let suite = FileManager.default.temporaryDirectory.appending(path: "woof.tests.\(UUID().uuidString)").path
    let defaults: UserDefaults
    let key = EntityKey.app(bundleID: "com.google.Chrome")
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    init() {
        defaults = UserDefaults(suiteName: suite)!
    }

    deinit {
        UserDefaults.standard.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(atPath: suite + ".plist")
    }

    @Test func defaultsMatchSpec() {
        let store = SettingsStore(defaults: defaults, now: now)
        #expect(store.limitsSetting == .preset(.balanced))
        #expect(store.rowsShown == 5)
        #expect(store.skinID == "symbol")
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
        store.setBowl(.huge, for: key)

        let reloaded = SettingsStore(defaults: defaults, now: now)
        #expect(reloaded.bowls == [key: .huge])
        #expect(reloaded.limitsSetting == .preset(.paranoid))
        #expect(reloaded.rowsShown == 7)
        #expect(reloaded.skinID == "shiba")
        #expect(reloaded.soundMuted)
        #expect(reloaded.ignoreList == [key])
        #expect(reloaded.snoozes.count == 1)
    }

    @Test func oldCustomLimitsStillDecode() throws {
        struct OldLimits: Codable { var cpu: Limit; var memory: Limit }
        let old = OldLimits(cpu: Limit(threshold: 42, window: 7), memory: Limit(threshold: 0.5, window: 9))
        let json = try "{\"custom\":{\"_0\":" + String(decoding: JSONEncoder().encode(old), as: UTF8.self) + "}}"
        let decoded = try JSONDecoder().decode(LimitsSetting.self, from: Data(json.utf8))
        var expected = Sensitivity.balanced.limits
        expected.cpu = old.cpu
        expected.memory = old.memory
        #expect(decoded == .custom(expected))
    }

    @Test func regularBowlIsNotStored() {
        let store = SettingsStore(defaults: defaults, now: now)
        store.setBowl(.big, for: key)
        #expect(store.bowl(for: key) == .big)
        #expect(store.limits(for: key) == store.limits.fed(.big))
        store.setBowl(.regular, for: key)
        #expect(store.bowls.isEmpty)
        #expect(store.bowl(for: key) == .regular)
    }

    @Test func rowsShownIsClampedOnLoad() {
        defaults.set(99, forKey: "rowsShown")
        #expect(SettingsStore(defaults: defaults, now: now).rowsShown == 10)
    }

    @Test func rowsShownIsClampedOnSet() {
        let store = SettingsStore(defaults: defaults, now: now)
        store.rowsShown = 2
        #expect(store.rowsShown == 3)
        #expect(defaults.integer(forKey: "rowsShown") == 3)
        store.rowsShown = 99
        #expect(store.rowsShown == 10)
        #expect(defaults.integer(forKey: "rowsShown") == 10)
        #expect(SettingsStore(defaults: defaults, now: now).rowsShown == 10)
    }

    @Test func pausedUntilPersistsAcrossInstances() {
        let store = SettingsStore(defaults: defaults, now: now)
        let until = now.addingTimeInterval(3600)
        store.pausedUntil = until
        #expect(SettingsStore(defaults: defaults, now: now).pausedUntil == until)
        store.pausedUntil = nil
        #expect(SettingsStore(defaults: defaults, now: now).pausedUntil == nil)
    }

    @Test func pollIntervalDefaultsToFiveSeconds() {
        let store = SettingsStore(defaults: defaults, now: now)
        #expect(store.pollInterval == 5)
        #expect(SettingsStore.pollIntervalChoices == [2, 5, 10, 30])
    }

    @Test func pollIntervalPersistsAcrossInstances() {
        let store = SettingsStore(defaults: defaults, now: now)
        store.pollInterval = 30
        #expect(defaults.double(forKey: "pollInterval") == 30)
        #expect(SettingsStore(defaults: defaults, now: now).pollInterval == 30)
    }

    @Test func invalidPollIntervalFallsBackOnLoad() {
        defaults.set(7, forKey: "pollInterval")
        #expect(SettingsStore(defaults: defaults, now: now).pollInterval == 5)
        defaults.set(25, forKey: "pollInterval")
        #expect(SettingsStore(defaults: defaults, now: now).pollInterval == 30)
        defaults.set(0, forKey: "pollInterval")
        #expect(SettingsStore(defaults: defaults, now: now).pollInterval == 5)
        defaults.set(-3, forKey: "pollInterval")
        #expect(SettingsStore(defaults: defaults, now: now).pollInterval == 5)
        defaults.set("fast", forKey: "pollInterval")
        #expect(SettingsStore(defaults: defaults, now: now).pollInterval == 5)
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
