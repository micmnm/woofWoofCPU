import Foundation

public enum Resource: String, Codable, CaseIterable, Sendable {
    case cpu
    case memory
}

/// PIDs are reused by the kernel; the start time disambiguates.
public struct ProcessIdentity: Hashable, Codable, Sendable {
    public let pid: Int32
    public let startMicros: UInt64

    public init(pid: Int32, startMicros: UInt64) {
        self.pid = pid
        self.startMicros = startMicros
    }
}

/// One process as read from the kernel in a single snapshot.
public struct RawProcess: Equatable, Sendable {
    public var identity: ProcessIdentity
    public var ppid: Int32
    public var uid: UInt32
    public var name: String
    public var path: String?
    public var responsiblePID: Int32?
    /// Cumulative user + system CPU time, already converted to nanoseconds.
    public var cpuTimeNanos: UInt64
    /// `ri_phys_footprint` — matches Activity Monitor's "Memory" column.
    public var memoryBytes: UInt64

    public init(
        identity: ProcessIdentity,
        ppid: Int32 = 1,
        uid: UInt32 = 501,
        name: String,
        path: String? = nil,
        responsiblePID: Int32? = nil,
        cpuTimeNanos: UInt64 = 0,
        memoryBytes: UInt64 = 0
    ) {
        self.identity = identity
        self.ppid = ppid
        self.uid = uid
        self.name = name
        self.path = path
        self.responsiblePID = responsiblePID
        self.cpuTimeNanos = cpuTimeNanos
        self.memoryBytes = memoryBytes
    }

    public var pid: Int32 { identity.pid }
}

/// A process plus the CPU % computed from the previous snapshot.
public struct ProcessSample: Equatable, Sendable {
    public var process: RawProcess
    /// 100 = one full core (Activity Monitor convention).
    public var cpuPercent: Double

    public init(process: RawProcess, cpuPercent: Double) {
        self.process = process
        self.cpuPercent = cpuPercent
    }

    public var memoryBytes: UInt64 { process.memoryBytes }
}

public protocol ProcessSource: Sendable {
    func snapshot() -> [RawProcess]
}
