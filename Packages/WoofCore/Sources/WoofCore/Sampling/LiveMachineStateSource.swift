import Darwin
import Foundation
import IOKit.ps
import os

public final class LiveMachineStateSource: MachineStateSource, @unchecked Sendable {
    private let cpu = OSAllocatedUnfairLock(initialState: HostCPUCalculator())
    /// Each `mach_host_self()` call adds a port reference, so take one for the source's lifetime.
    private let host = mach_host_self()

    public init() {}

    public func read() -> MachineState {
        let info = ProcessInfo.processInfo
        return MachineState(
            memoryPressure: MemoryPressure(sysctlLevel: Self.pressureLevel()),
            thermal: ThermalLevel(info.thermalState),
            onBattery: Self.onBattery(),
            lowPowerMode: info.isLowPowerModeEnabled,
            cpuBusy: busyFraction(),
            logicalCores: info.processorCount,
            physicalMemory: info.physicalMemory)
    }

    public func reset() { cpu.withLock { $0.reset() } }

    private func busyFraction() -> Double {
        var load = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &load) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return 0 }
        let t = load.cpu_ticks
        let busy = UInt64(t.0) + UInt64(t.1) + UInt64(t.3)  // user + system + nice
        return cpu.withLock { $0.busy(busyTicks: busy, totalTicks: busy + UInt64(t.2)) }
    }

    private static func pressureLevel() -> Int32 {
        var level: Int32 = 1
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return 1 }
        return level
    }

    private static func onBattery() -> Bool {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(blob)?.takeUnretainedValue() as String?
        else { return false }
        return type == kIOPMBatteryPowerKey
    }
}
