import Foundation
import Testing
@testable import WoofCore

@Suite struct JudgeTests {
    let balanced = Sensitivity.balanced.limits
    let calm = MachineState.calm(cores: 8, memory: 8 * gb)

    func machine(
        pressure: MemoryPressure = .normal, thermal: ThermalLevel = .nominal, busy: Double = 0,
        battery: Bool = false, lowPower: Bool = false
    ) -> MachineState {
        var m = calm
        m.memoryPressure = pressure
        m.thermal = thermal
        m.cpuBusy = busy
        m.onBattery = battery
        m.lowPowerMode = lowPower
        return m
    }

    func bytes(_ gigabytes: Double) -> UInt64 { UInt64(gigabytes * Double(gb)) }

    /// One app whose members run at the given CPU percents.
    func app(cpu members: [Double] = [0], memory: UInt64 = 0) -> Entity {
        Entity(
            key: .process(path: "/usr/bin/app"), displayName: "app", bundlePath: nil, mainPID: nil,
            members: members.enumerated().map { i, cpu in
                sample(Int32(100 + i), cpu: cpu, memory: i == 0 ? memory : 0)
            },
            ownedByCurrentUser: true)
    }

    /// Usual usage learned from `entity` held constant for 2.5 h of 5 s ticks.
    func learned(_ entity: Entity) -> UsualUsage {
        var usual = UsualUsage()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        for i in 0..<1_800 {
            usual.record([entity], elapsed: 5, maxElapsed: 15, at: t0.addingTimeInterval(Double(i) * 5))
        }
        return usual
    }

    func judge(
        _ entity: Entity, _ resource: Resource, _ machine: MachineState, bowl: Bowl = .regular,
        usual: UsualUsage = UsualUsage(), continuing: Bool = false
    ) -> [Verdict] {
        Judge.verdicts(
            entity, resource, machine: machine, strain: Judge.strain(machine, balanced), limits: balanced,
            bowl: bowl, usual: usual, continuing: continuing)
    }

    // MARK: Strain

    @Test func memoryStrainAtWarning() {
        #expect(Judge.strain(machine(pressure: .warning), balanced) == Strain(memory: true, cpu: false))
        #expect(Judge.strain(machine(pressure: .critical), balanced).memory)
    }

    @Test func noMemoryStrainWhenNormal() {
        #expect(Judge.strain(calm, balanced) == Strain(memory: false, cpu: false))
    }

    @Test func cpuStrainWhenThermalSerious() {
        #expect(Judge.strain(machine(thermal: .serious), balanced) == Strain(memory: false, cpu: true))
        #expect(!Judge.strain(machine(thermal: .fair), balanced).cpu)
    }

    @Test func cpuStrainWhenBusyAtLeast75() {
        #expect(Judge.strain(machine(busy: 0.75), balanced).cpu)
        #expect(!Judge.strain(machine(busy: 0.74), balanced).cpu)
    }

    @Test func batteryLowersBusyTriggerTo50() {
        #expect(Judge.strain(machine(busy: 0.55, battery: true), balanced).cpu)
        #expect(!Judge.strain(machine(busy: 0.55), balanced).cpu)
        #expect(!Judge.strain(machine(busy: 0.45, battery: true), balanced).cpu)
    }

    @Test func lowPowerModeLowersBusyTrigger() {
        #expect(Judge.strain(machine(busy: 0.55, lowPower: true), balanced).cpu)
    }

    // MARK: Memory

    @Test func memoryCulpritNeedsStrain() {
        #expect(judge(app(memory: bytes(2.4)), .memory, calm) == [])
    }

    @Test func workedExampleBarksAtBrowser() {
        #expect(judge(app(memory: bytes(2.4)), .memory, machine(pressure: .warning)) == [Verdict(reason: .strain, window: 300)])
    }

    @Test func smallAppIsNoMemoryCulprit() {
        #expect(judge(app(memory: bytes(1.0)), .memory, machine(pressure: .warning)) == [])
    }

    @Test func bowlRaisesFloor() {
        let tight = machine(pressure: .warning)
        #expect(judge(app(memory: bytes(1.5)), .memory, tight, bowl: .big) == [])
        #expect(judge(app(memory: bytes(1.9)), .memory, tight, bowl: .big) == [Verdict(reason: .strain, window: 300)])
    }

    @Test func bottomlessNeverMemoryCulprit() {
        #expect(judge(app(memory: 8 * gb), .memory, machine(pressure: .critical), bowl: .bottomless) == [])
    }

    @Test func usualSuppresses() {
        let usual = learned(app(memory: bytes(2.4)))
        let tight = machine(pressure: .warning)
        #expect(judge(app(memory: bytes(2.4)), .memory, tight, usual: usual) == [])
        #expect(judge(app(memory: bytes(3.5)), .memory, tight, usual: usual) == [Verdict(reason: .strain, window: 300)])
    }

    @Test func continuingLowersFloorTenPercent() {
        let tight = machine(pressure: .warning)
        #expect(judge(app(memory: bytes(1.1)), .memory, tight, continuing: true) == [Verdict(reason: .strain, window: 300)])
        #expect(judge(app(memory: bytes(1.1)), .memory, tight) == [])
    }

    // MARK: CPU

    @Test func cpuCulpritNeedsMinimumAndShare() {
        let busy = machine(busy: 0.8)
        #expect(judge(app(cpu: [50, 50, 50, 50, 50]), .cpu, busy) == [Verdict(reason: .strain, window: 180)])
        #expect(judge(app(cpu: [50, 50, 50]), .cpu, busy) == [])
    }

    @Test func cpuShareSkippedWhenLoadZero() {
        #expect(judge(app(cpu: [60, 60]), .cpu, machine(thermal: .serious)) == [Verdict(reason: .strain, window: 180)])
    }

    @Test func noVisibleCulprit() {
        let hot = machine(thermal: .serious, busy: 0.9)
        #expect(judge(app(cpu: [80]), .cpu, hot) == [])
        #expect(judge(app(cpu: [30, 30]), .cpu, hot) == [])
    }

    // MARK: Runaway

    @Test func runawayOnCalmMac() {
        #expect(judge(app(cpu: [95]), .cpu, calm) == [Verdict(reason: .runaway, window: 600)])
    }

    @Test func runawayCountsMultiCoreJobs() {
        #expect(judge(app(cpu: [400]), .cpu, calm) == [Verdict(reason: .runaway, window: 600)])
    }

    @Test func runawayIgnoresUsual() throws {
        let usual = learned(app(cpu: [400]))
        let high = try #require(usual.usualHigh(app().key, .cpu))
        #expect(abs(high - 500) < 0.1)
        #expect(judge(app(cpu: [400]), .cpu, calm, usual: usual) == [Verdict(reason: .runaway, window: 600)])
    }

    @Test func runawayWindowHalvesOnBattery() {
        #expect(judge(app(cpu: [95]), .cpu, machine(battery: true)) == [Verdict(reason: .runaway, window: 300)])
        #expect(judge(app(cpu: [95]), .cpu, machine(lowPower: true)) == [Verdict(reason: .runaway, window: 300)])
    }

    @Test func runawayIsPerProcessNotSum() {
        #expect(judge(app(cpu: [40, 40, 40]), .cpu, calm) == [])
    }

    @Test func continuingLowersRunawayToEightyOne() {
        #expect(judge(app(cpu: [85]), .cpu, calm, continuing: true) == [Verdict(reason: .runaway, window: 600)])
        #expect(judge(app(cpu: [85]), .cpu, calm) == [])
    }

    @Test func runawayIsCPUOnly() {
        #expect(judge(app(cpu: [95]), .memory, calm) == [])
    }

    @Test func bothReasons() {
        #expect(judge(app(cpu: [95, 70, 70, 65]), .cpu, machine(busy: 0.8)) == [
            Verdict(reason: .strain, window: 180), Verdict(reason: .runaway, window: 600),
        ])
    }
}
