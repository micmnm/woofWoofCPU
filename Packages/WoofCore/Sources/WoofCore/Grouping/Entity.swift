import Foundation

/// Stable identity of what the dog judges; also the key for ignore lists and snoozes.
public enum EntityKey: Hashable, Codable, Sendable {
    case app(bundleID: String)
    case process(path: String)
}

/// Either an app (its main process plus helpers, values summed) or a standalone process.
public struct Entity: Identifiable, Equatable, Sendable {
    public let key: EntityKey
    public let displayName: String
    /// `/Applications/Foo.app` for app entities; nil for standalone processes.
    public let bundlePath: String?
    /// The app's own process (not a helper), when it is running.
    public let mainPID: Int32?
    /// Sorted by CPU, highest first.
    public let members: [ProcessSample]
    public let cpuPercent: Double
    public let memoryBytes: UInt64
    /// False when any member belongs to another user or root.
    public let ownedByCurrentUser: Bool

    public var id: EntityKey { key }
    public var isApp: Bool { bundlePath != nil }

    public init(
        key: EntityKey,
        displayName: String,
        bundlePath: String?,
        mainPID: Int32?,
        members: [ProcessSample],
        ownedByCurrentUser: Bool
    ) {
        self.key = key
        self.displayName = displayName
        self.bundlePath = bundlePath
        self.mainPID = mainPID
        self.members = members.sorted { $0.cpuPercent > $1.cpuPercent }
        self.cpuPercent = members.reduce(0) { $0 + $1.cpuPercent }
        self.memoryBytes = members.reduce(0) { $0 + $1.memoryBytes }
        self.ownedByCurrentUser = ownedByCurrentUser
    }

    /// CPU in percent, memory in bytes.
    public func value(for resource: Resource) -> Double {
        switch resource {
        case .cpu: cpuPercent
        case .memory: Double(memoryBytes)
        }
    }
}
