import Foundation

public enum DogMood: String, CaseIterable, Codable, Sendable {
    case napping, sniffing, growling, barking, sulking, proud
}

/// Turns breaches into the dog's mood and emits each breach's alert at most once.
public struct MoodEngine: Sendable {
    public static let proudDuration: TimeInterval = 10

    public private(set) var mood: DogMood = .napping
    /// Breaches whose alert popover is currently open.
    public private(set) var openAlertIDs: Set<Int> = []
    private var sulkingIDs: Set<Int> = []
    private var alertedIDs: Set<Int> = []
    private var ignoredIDs: Set<Int> = []
    private var proudUntil: TimeInterval?

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
            openAlertIDs = []
            sulkingIDs = []
            proudUntil = nil
            mood = .napping
            return []
        }

        let allIDs = Set(breaches.map(\.id))
        let active = breaches.filter { !isMuted($0.key.entity) && !ignoredIDs.contains($0.id) }
        let activeIDs = Set(active.map(\.id))

        // An alerted breach that ended (not merely muted) was dealt with — be proud.
        if !openAlertIDs.union(sulkingIDs).subtracting(allIDs).isEmpty {
            proudUntil = now + Self.proudDuration
        }
        openAlertIDs.formIntersection(activeIDs)
        sulkingIDs.formIntersection(activeIDs)
        alertedIDs.formIntersection(allIDs)
        ignoredIDs.formIntersection(allIDs)

        let newAlerts = active.filter { $0.progress >= 1 && !alertedIDs.contains($0.id) }
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

    /// "Ignore": mute this breach episode only. A later episode can bark again.
    public mutating func ignore(breachID: Int) {
        ignoredIDs.insert(breachID)
        openAlertIDs.remove(breachID)
        sulkingIDs.remove(breachID)
    }

    public mutating func reset() {
        self = MoodEngine()
    }
}
