import Darwin
import Testing
@testable import WoofCore

@Suite struct SamplerTests {
    @Test func samplerGroupsAndComputesCPU() async {
        let source = FakeSource([
            [raw(10, name: "node", path: "/usr/local/bin/node", cpuNanos: 0)],
            [raw(10, name: "node", path: "/usr/local/bin/node", cpuNanos: 4_000_000_000)],
        ])
        let sampler = Sampler(source: source, grouper: AppGrouper(selfPID: 1, currentUID: 501, appInfo: StubAppInfo()), machine: FakeMachineSource())
        _ = await sampler.sample(now: 0)
        let entities = await sampler.sample(now: 2).entities
        #expect(entities.count == 1)
        #expect(entities.first?.cpuPercent == 200)
    }
}

@Suite struct LibprocSourceTests {
    @Test func liveSnapshotIncludesThisProcess() {
        let processes = LibprocProcessSource().snapshot()
        let me = processes.first { $0.pid == getpid() }
        #expect(me != nil)
        #expect((me?.memoryBytes ?? 0) > 0)
        #expect(me?.path?.isEmpty == false)
    }

    @Test func liveSnapshotReadsOnlyThisUsersProcesses() {
        #expect(LibprocProcessSource().snapshot().allSatisfy { $0.uid == getuid() })
    }

    /// The responsible PID only matters for bundled code; other processes skip the lookup.
    @Test func responsiblePIDIsOnlyLookedUpForBundledCode() {
        let unbundled = LibprocProcessSource().snapshot().filter { process in
            guard let path = process.path else { return true }
            return !path.contains(".app/") && !path.contains(".xpc/")
        }
        #expect(!unbundled.isEmpty)
        #expect(unbundled.allSatisfy { $0.responsiblePID == nil })
    }
}
