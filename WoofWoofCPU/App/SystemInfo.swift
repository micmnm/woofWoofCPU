import Foundation
import IOKit.ps

enum SystemInfo {
    static let physicalMemory = ProcessInfo.processInfo.physicalMemory

    /// Monotonic seconds; doesn't advance during sleep (timers are reset on wake anyway).
    static var uptime: TimeInterval { ProcessInfo.processInfo.systemUptime }

    static var isOnBattery: Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else { return false }
        return (type as String) == kIOPMBatteryPowerKey
    }
}
