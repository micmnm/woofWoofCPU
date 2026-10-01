@testable import WoofCore

final class FakeSignaller: ProcessSignaller, @unchecked Sendable {
    var sent: [(signal: Int32, pid: Int32)] = []
    var appQuits: [Int32] = []
    var results: [Int32: SignalResult] = [:]
    var runningApps: Set<Int32> = []

    func send(_ signal: Int32, to pid: Int32) -> SignalResult {
        sent.append((signal, pid))
        return results[pid] ?? .sent
    }
    func isAlive(_ pid: Int32) -> Bool { results[pid] != .alreadyGone }
    func quitApp(pid: Int32) -> Bool {
        appQuits.append(pid)
        return runningApps.contains(pid)
    }
}
