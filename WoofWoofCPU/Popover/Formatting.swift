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
        return "Barks at \(value(threshold, for: resource)) after \(duration(limits[resource].window))"
    }

    /// Dog words normally; the memory limit it allows while ⌥ is held.
    static func bowl(_ bowl: Bowl, shared limits: Limits, technical: Bool) -> String {
        let detail: String
        if technical {
            let bytes = limits.fed(bowl).thresholdValue(for: .memory, physicalMemory: SystemInfo.physicalMemory)
            detail = bytes.isFinite ? "up to \(value(bytes, for: .memory))" : "no memory limit"
        } else {
            switch bowl {
            case .regular: return bowl.displayName
            case .big: detail = "a bit more"
            case .huge: detail = "lots more"
            case .bottomless: detail = "never bark about memory"
            }
        }
        return "\(bowl.displayName) — \(detail)"
    }

    private static func durationFormatter(_ units: NSCalendar.Unit) -> DateComponentsFormatter {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = units
        formatter.unitsStyle = .abbreviated
        return formatter
    }
}
