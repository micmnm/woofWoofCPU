import Foundation
@testable import WoofCore

func raw(
    _ pid: Int32,
    start: UInt64 = 1,
    name: String = "proc",
    path: String? = nil,
    uid: UInt32 = 501,
    responsible: Int32? = nil,
    cpuNanos: UInt64 = 0,
    memory: UInt64 = 0
) -> RawProcess {
    RawProcess(
        identity: ProcessIdentity(pid: pid, startMicros: start),
        uid: uid,
        name: name,
        path: path,
        responsiblePID: responsible,
        cpuTimeNanos: cpuNanos,
        memoryBytes: memory
    )
}

func sample(
    _ pid: Int32,
    name: String = "proc",
    path: String? = nil,
    uid: UInt32 = 501,
    responsible: Int32? = nil,
    cpu: Double = 0,
    memory: UInt64 = 0
) -> ProcessSample {
    ProcessSample(
        process: raw(pid, name: name, path: path, uid: uid, responsible: responsible, memory: memory),
        cpuPercent: cpu
    )
}

final class FakeSource: ProcessSource, @unchecked Sendable {
    var frames: [[RawProcess]]
    init(_ frames: [[RawProcess]]) { self.frames = frames }
    func snapshot() -> [RawProcess] { frames.isEmpty ? [] : frames.removeFirst() }
}

final class FakeMachineSource: MachineStateSource, @unchecked Sendable {
    var states: [MachineState]
    private(set) var resets = 0
    init(_ states: [MachineState] = [.calm()]) { self.states = states }
    func read() -> MachineState { states.count > 1 ? states.removeFirst() : states[0] }
    func reset() { resets += 1 }
}

let gb: UInt64 = 1 << 30
