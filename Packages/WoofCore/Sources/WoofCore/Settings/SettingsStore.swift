import Foundation
import Observation

public enum SnoozeDuration: String, CaseIterable, Sendable {
    case fifteenMinutes, oneHour, untilTomorrow

    public var displayName: String {
        switch self {
        case .fifteenMinutes: "for 15 minutes"
        case .oneHour: "for 1 hour"
        case .untilTomorrow: "until tomorrow"
        }
    }

    /// "Until tomorrow" means the next 06:00 local time.
    public func until(from now: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .fifteenMinutes: return now.addingTimeInterval(15 * 60)
        case .oneHour: return now.addingTimeInterval(60 * 60)
        case .untilTomorrow:
            return calendar.nextDate(
                after: now,
                matching: DateComponents(hour: 6, minute: 0, second: 0),
                matchingPolicy: .nextTime
            ) ?? now.addingTimeInterval(24 * 60 * 60)
        }
    }
}

@MainActor
@Observable
public final class SettingsStore {
    public static let defaultRowsShown = 5
    public static let rowsShownRange = 3...10
    public static let defaultPollInterval: TimeInterval = 5
    public static let pollIntervalChoices: [TimeInterval] = [2, 5, 10, 30]

    @ObservationIgnored private let defaults: UserDefaults

    public var limitsSetting: LimitsSetting { didSet { save(limitsSetting, Keys.limits) } }
    public var rowsShown: Int {
        didSet {
            // Re-assigning re-enters this didSet once, with an in-range value.
            guard Self.rowsShownRange.contains(rowsShown) else { rowsShown = Self.clampedRows(rowsShown); return }
            defaults.set(rowsShown, forKey: Keys.rows)
        }
    }
    public var skinID: String { didSet { defaults.set(skinID, forKey: Keys.skin) } }
    public var soundMuted: Bool { didSet { defaults.set(soundMuted, forKey: Keys.muted) } }
    public var pollInterval: TimeInterval { didSet { defaults.set(pollInterval, forKey: Keys.pollInterval) } }
    public private(set) var ignoreList: Set<EntityKey> { didSet { save(ignoreList, Keys.ignore) } }
    public private(set) var snoozes: [EntityKey: Date] { didSet { save(snoozes, Keys.snoozes) } }
    /// Only non-regular bowls are stored.
    public private(set) var bowls: [EntityKey: Bowl] { didSet { save(bowls, Keys.bowls) } }
    public var pausedUntil: Date? { didSet { save(pausedUntil, Keys.paused) } }

    public init(defaults: UserDefaults = .standard, now: Date = Date()) {
        self.defaults = defaults
        limitsSetting = Self.load(LimitsSetting.self, Keys.limits, defaults) ?? .preset(.balanced)
        let rows = defaults.object(forKey: Keys.rows) as? Int ?? Self.defaultRowsShown
        rowsShown = Self.clampedRows(rows)
        skinID = defaults.string(forKey: Keys.skin) ?? "symbol"
        soundMuted = defaults.bool(forKey: Keys.muted)
        pollInterval = Self.nearestPollInterval(defaults.object(forKey: Keys.pollInterval) as? Double)
        ignoreList = Self.load(Set<EntityKey>.self, Keys.ignore, defaults) ?? []
        snoozes = (Self.load([EntityKey: Date].self, Keys.snoozes, defaults) ?? [:]).filter { $0.value > now }
        bowls = Self.load([EntityKey: Bowl].self, Keys.bowls, defaults) ?? [:]
        pausedUntil = Self.load(Date?.self, Keys.paused, defaults) ?? nil
    }

    public var limits: Limits { limitsSetting.limits }

    public func limits(for key: EntityKey) -> Limits {
        limits.fed(bowl(for: key))
    }

    public func bowl(for key: EntityKey) -> Bowl {
        bowls[key] ?? .regular
    }

    public func setBowl(_ bowl: Bowl, for key: EntityKey) {
        bowls[key] = bowl == .regular ? nil : bowl
    }

    public func isMuted(_ key: EntityKey, now: Date) -> Bool {
        if ignoreList.contains(key) { return true }
        if let until = snoozes[key], until > now { return true }
        return false
    }

    public func isPaused(now: Date) -> Bool {
        guard let pausedUntil else { return false }
        return pausedUntil > now
    }

    public func alwaysIgnore(_ key: EntityKey) {
        ignoreList.insert(key)
    }

    public func removeFromIgnoreList(_ key: EntityKey) {
        ignoreList.remove(key)
    }

    public func snooze(_ key: EntityKey, until: Date) {
        snoozes[key] = until
    }

    public func cancelSnooze(_ key: EntityKey) {
        snoozes[key] = nil
    }

    public func pruneExpired(now: Date) {
        let live = snoozes.filter { $0.value > now }
        if live.count != snoozes.count { snoozes = live }
        if let pausedUntil, pausedUntil <= now { self.pausedUntil = nil }
    }

    private static func clampedRows(_ rows: Int) -> Int {
        min(max(rows, rowsShownRange.lowerBound), rowsShownRange.upperBound)
    }

    /// Missing or non-positive values get the default; anything else snaps to the nearest choice.
    private static func nearestPollInterval(_ stored: Double?) -> TimeInterval {
        guard let stored, stored > 0 else { return defaultPollInterval }
        return pollIntervalChoices.min { abs($0 - stored) < abs($1 - stored) } ?? defaultPollInterval
    }

    private enum Keys {
        static let limits = "limitsSetting"
        static let rows = "rowsShown"
        static let skin = "skinID"
        static let muted = "soundMuted"
        static let pollInterval = "pollInterval"
        static let ignore = "ignoreList"
        static let snoozes = "snoozes"
        static let bowls = "bowls"
        static let paused = "pausedUntil"
    }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }

    private static func load<T: Decodable>(_ type: T.Type, _ key: String, _ defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
