import Foundation
import Testing
@testable import WoofCore

@Suite struct MachineStateTests {
    @Test func firstReadingIsZero() {
        var calc = HostCPUCalculator()
        #expect(calc.busy(busyTicks: 500, totalTicks: 1000) == 0)
    }

    @Test func deltaGivesBusyFraction() {
        var calc = HostCPUCalculator()
        _ = calc.busy(busyTicks: 500, totalTicks: 1000)
        #expect(calc.busy(busyTicks: 800, totalTicks: 1400) == 0.75)
    }

    @Test func countersGoingBackwardsGiveZero() {
        var calc = HostCPUCalculator()
        _ = calc.busy(busyTicks: 500, totalTicks: 1000)
        #expect(calc.busy(busyTicks: 100, totalTicks: 1100) == 0)
        #expect(calc.busy(busyTicks: 150, totalTicks: 1200) == 0.5)
    }

    @Test func zeroTotalDeltaGivesZero() {
        var calc = HostCPUCalculator()
        _ = calc.busy(busyTicks: 500, totalTicks: 1000)
        #expect(calc.busy(busyTicks: 500, totalTicks: 1000) == 0)
    }

    @Test func resetForgetsBaseline() {
        var calc = HostCPUCalculator()
        _ = calc.busy(busyTicks: 500, totalTicks: 1000)
        calc.reset()
        #expect(calc.busy(busyTicks: 800, totalTicks: 1400) == 0)
    }

    @Test func pressureLevelMapping() {
        #expect(MemoryPressure(sysctlLevel: 1) == .normal)
        #expect(MemoryPressure(sysctlLevel: 2) == .warning)
        #expect(MemoryPressure(sysctlLevel: 4) == .critical)
        #expect(MemoryPressure(sysctlLevel: 0) == .normal)
        #expect(MemoryPressure(sysctlLevel: 3) == .normal)
    }

    @Test func thermalMapping() {
        #expect(ThermalLevel(ProcessInfo.ThermalState.nominal) == .nominal)
        #expect(ThermalLevel(ProcessInfo.ThermalState.fair) == .fair)
        #expect(ThermalLevel(ProcessInfo.ThermalState.serious) == .serious)
        #expect(ThermalLevel(ProcessInfo.ThermalState.critical) == .critical)
    }

    @Test func calmIsCalm() {
        let m = MachineState.calm()
        #expect(m.memoryPressure == .normal && m.thermal == .nominal)
        #expect(!m.onBattery && !m.lowPowerMode && m.cpuBusy == 0)
        #expect(m.logicalCores == 8 && m.physicalMemory == 8 << 30)
    }

    @Test func liveSourceReadsSaneValues() {
        let source = LiveMachineStateSource()
        _ = source.read()
        let m = source.read()
        #expect(m.logicalCores > 0)
        #expect(m.physicalMemory > 0)
        #expect((0...1).contains(m.cpuBusy))
    }

    @Test func samplerReturnsMachineState() async {
        var hurting = MachineState.calm()
        hurting.memoryPressure = .critical
        let sampler = Sampler(
            source: FakeSource([[]]),
            grouper: AppGrouper(selfPID: 1, currentUID: 501, appInfo: StubAppInfo()),
            machine: FakeMachineSource([hurting])
        )
        let snapshot = await sampler.sample(now: 0)
        #expect(snapshot.machine == hurting)
        #expect(snapshot.entities.isEmpty)
    }
}
