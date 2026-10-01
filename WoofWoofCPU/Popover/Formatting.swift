import Foundation
import WoofCore

@MainActor
enum Formatting {
    private static let minutesSeconds = durationFormatter([.minute, .second])
    private static let hoursMinutes = durationFormatter([.hour, .minute])

    static func value(_ value: Double, for resource: Resource) -> String {
        switch resource {
        case .cpu: "\(Int(value.rounded()))%"
        case .memory: ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .memory)
        }
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let formatter = seconds >= 3600 ? hoursMinutes : minutesSeconds
        return formatter.string(from: max(0, seconds)) ?? ""
    }

    static func limit(_ limits: Limits, _ resource: Resource) -> String {
        let threshold = limits.thresholdValue(for: resource, physicalMemory: SystemInfo.physicalMemory)
        return "limit \(value(threshold, for: resource)) for \(duration(limits[resource].window))"
    }

    private static func durationFormatter(_ units: NSCalendar.Unit) -> DateComponentsFormatter {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = units
        formatter.unitsStyle = .abbreviated
        return formatter
    }
}
