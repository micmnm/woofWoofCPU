import Darwin

public enum SignalResult: Equatable, Sendable {
    case sent
    case notAllowed
    case alreadyGone
    case failed(Int32)
}

/// Seam over `kill(2)` and NSRunningApplication so actions are testable.
public protocol ProcessSignaller: Sendable {
    func send(_ signal: Int32, to pid: Int32) -> SignalResult
    func isAlive(_ pid: Int32) -> Bool
    /// Polite app quit (Apple Event, lets the app ask to save). False when no such app is running.
    func quitApp(pid: Int32) -> Bool
}

public struct PosixSignaller: ProcessSignaller {
    private let quitAppHandler: @Sendable (Int32) -> Bool

    /// `quitApp` is injected by the app target (NSRunningApplication.terminate) to keep this module AppKit-free.
    public init(quitApp: @escaping @Sendable (Int32) -> Bool) {
        quitAppHandler = quitApp
    }

    /// pid ≤ 0 is refused: kill(0, …) signals our own process group, kill(-1, …) every process we own.
    public func send(_ signal: Int32, to pid: Int32) -> SignalResult {
        guard pid > 0 else { return .failed(EINVAL) }
        if kill(pid, signal) == 0 { return .sent }
        switch errno {
        case EPERM: return .notAllowed
        case ESRCH: return .alreadyGone
        case let code: return .failed(code)
        }
    }

    public func isAlive(_ pid: Int32) -> Bool {
        pid > 0 && (kill(pid, 0) == 0 || errno == EPERM)
    }

    public func quitApp(pid: Int32) -> Bool {
        quitAppHandler(pid)
    }
}

/// Quit = polite (app quit / SIGTERM). Kill = SIGKILL, used while ⌥ is held.
public struct ProcessActions: Sendable {
    private let signaller: any ProcessSignaller

    public init(signaller: any ProcessSignaller) {
        self.signaller = signaller
    }

    public func canAct(on entity: Entity) -> Bool {
        entity.ownedByCurrentUser
    }

    public func canAct(on sample: ProcessSample, currentUID: UInt32) -> Bool {
        sample.process.uid == currentUID
    }

    public func quit(_ entity: Entity) -> SignalResult {
        if let main = entity.mainPID, signaller.quitApp(pid: main) { return .sent }
        return Self.combine(entity.members.map { signaller.send(SIGTERM, to: $0.process.pid) })
    }

    public func kill(_ entity: Entity) -> SignalResult {
        var pids = entity.members.map(\.process.pid)
        if let main = entity.mainPID, let index = pids.firstIndex(of: main) {
            pids.swapAt(0, index)
        }
        return Self.combine(pids.map { signaller.send(SIGKILL, to: $0) })
    }

    public func quit(_ sample: ProcessSample) -> SignalResult {
        signaller.send(SIGTERM, to: sample.process.pid)
    }

    public func kill(_ sample: ProcessSample) -> SignalResult {
        signaller.send(SIGKILL, to: sample.process.pid)
    }

    public func isAlive(_ pid: Int32) -> Bool {
        signaller.isAlive(pid)
    }

    static func combine(_ results: [SignalResult]) -> SignalResult {
        if results.contains(.notAllowed) { return .notAllowed }
        if let failure = results.first(where: { if case .failed = $0 { true } else { false } }) { return failure }
        if !results.isEmpty, results.allSatisfy({ $0 == .alreadyGone }) { return .alreadyGone }
        return .sent
    }
}
