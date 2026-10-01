import Foundation
import WoofCore

enum Formatting {
    static func value(_ value: Double, for resource: Resource) -> String {
        switch resource {
        case .cpu: "\(Int(value.rounded()))%"
        case .memory: ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .memory)
        }
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: max(0, seconds)) ?? ""
    }

    static func limit(_ limits: Limits, _ resource: Resource) -> String {
        let threshold = limits.thresholdValue(for: resource, physicalMemory: SystemInfo.physicalMemory)
        return "limit \(value(threshold, for: resource)) for \(duration(limits[resource].window))"
    }
}
