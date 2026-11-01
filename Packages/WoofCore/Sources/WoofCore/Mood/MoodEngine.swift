import Foundation

public enum DogMood: String, CaseIterable, Codable, Sendable {
    case napping, sniffing, growling, barking, sulking, proud
}

/// Turns breaches into the dog's mood and emits each breach's alert at most once.
public struct MoodEngine: Sendable {
    public static let proudDuration: TimeInterval = 10
    /// An Ignore lasts until its key has had no breach for this long.
    public static let ignoreCooldown: TimeInterval = 600

    public private(set) var mood: DogMood = .napping
    /// Breaches whose alert popover is currently open.
    public private(set) var openAlertIDs: Set<Int> = []
    private var sulkingIDs: Set<Int> = []
    private var alertedIDs: Set<Int> = []
    /// Ignored key → last uptime it had a breach (or the app was paused).
    private var ignored: [BreachKey: TimeInterval] = [:]
    private var proudUntil: TimeInterval?
    private var wasPaused = false

    public init() {}

    /// Returns the breaches that reached their window on this tick (the caller barks + opens the popover).
    @discardableResult
    public mutating func evaluate(
        breaches: [Breach],
        isMuted: (EntityKey) -> Bool,
        paused: Bool,
        now: TimeInterval
    ) -> [Breach] {
        if paused {
            wasPaused = true
            openAlertIDs = []
            sulkingIDs = []
            proudUntil = nil
            mood = .napping
            return []
        }
        // The pause stops ticks, so its length counts as calm only from resume.
        if wasPaused {
            wasPaused = false
            ignored = ignored.mapValues { _ in now }
        }

        ignored = ignored.filter { now - $0.value < Self.ignoreCooldown }
        for breach in breaches where ignored[breach.key] != nil { ignored[breach.key] = now }

        let allIDs = Set(breaches.map(\.id))
        let active = breaches.filter { !isMuted($0.key.entity) && ignored[$0.key] == nil }
        let activeIDs = Set(active.map(\.id))

        // An alerted breach that ended (not merely muted) was dealt with — be proud.
        if !openAlertIDs.union(sulkingIDs).subtracting(allIDs).isEmpty {
            proudUntil = now + Self.proudDuration
        }
        openAlertIDs.formIntersection(activeIDs)
        sulkingIDs.formIntersection(activeIDs)
        // Pruned against active (not all) breaches, so one re-alerts when its snooze or always-ignore ends.
        alertedIDs.formIntersection(activeIDs)

        let newAlerts = active.filter { $0.isOver && $0.progress >= 1 && !alertedIDs.contains($0.id) }
        for breach in newAlerts {
            alertedIDs.insert(breach.id)
            openAlertIDs.insert(breach.id)
            sulkingIDs.remove(breach.id)
        }

        if let until = proudUntil, now >= until { proudUntil = nil }

        let maxProgress = active.map(\.progress).max()
        if !openAlertIDs.isEmpty {
            mood = .barking
        } else if !sulkingIDs.isEmpty {
            mood = .sulking
        } else if proudUntil != nil {
            mood = .proud
        } else if let maxProgress {
            mood = maxProgress >= 0.5 ? .growling : .sniffing
        } else {
            mood = .napping
        }
        return newAlerts
    }

    /// The alert popover was closed without acting (Esc / click outside).
    public mutating func alertDismissed() {
        sulkingIDs.formUnion(openAlertIDs)
        openAlertIDs = []
        if !sulkingIDs.isEmpty { mood = .sulking }
    }

    /// "Ignore": mute this app and resource until it has been calm for `ignoreCooldown`.
    public mutating func ignore(_ key: BreachKey, now: TimeInterval) {
        ignored[key] = now
    }

    public func isIgnored(_ key: BreachKey) -> Bool {
        ignored[key] != nil
    }

    /// Forgets the running state but keeps Ignores.
    public mutating func reset() {
        var fresh = MoodEngine()
        fresh.ignored = ignored
        self = fresh
    }
}
