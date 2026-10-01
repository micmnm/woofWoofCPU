import Foundation
import IOKit.ps

enum SystemInfo {
    static let physicalMemory = ProcessInfo.processInfo.physicalMemory
    static let batteryRecheckInterval: TimeInterval = 30

    /// Monotonic seconds; doesn't advance during sleep (timers are reset on wake anyway).
    static var uptime: TimeInterval { ProcessInfo.processInfo.systemUptime }

    @MainActor private static var battery: (onBattery: Bool, checkedAt: TimeInterval)?

    /// Re-read at most every `batteryRecheckInterval`; it only picks the tick interval.
    @MainActor static var isOnBattery: Bool {
        let now = uptime
        if let battery, now - battery.checkedAt < batteryRecheckInterval { return battery.onBattery }
        let onBattery = readIsOnBattery()
        battery = (onBattery, now)
        return onBattery
    }

    private static func readIsOnBattery() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else { return false }
        return (type as String) == kIOPMBatteryPowerKey
    }
}
