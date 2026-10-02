import Foundation

enum SystemInfo {
    static let physicalMemory = ProcessInfo.processInfo.physicalMemory

    /// Monotonic seconds; doesn't advance during sleep (timers are reset on wake anyway).
    static var uptime: TimeInterval { ProcessInfo.processInfo.systemUptime }
}
