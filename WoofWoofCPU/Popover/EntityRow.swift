import AppKit
import SwiftUI
import WoofCore

/// One app or standalone process; apps can expand to their member processes.
struct EntityRow: View {
    let coordinator: AppCoordinator
    let entity: Entity
    let optionDown: Bool
    @Binding var expanded: Bool

    private var breach: Breach? { coordinator.breach(for: entity.key) }
    private var resource: Resource { breach?.key.resource ?? (coordinator.sortResource == .cpu ? .cpu : .memory) }
    private var alerting: Bool { coordinator.alertingKeys.contains(entity.key) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if entity.isApp && entity.members.count > 1 {
                    Button { expanded.toggle() } label: {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right").frame(width: 10)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(expanded ? "Hide processes" : "Show processes")
                } else {
                    Spacer().frame(width: 10)
                }
                icon.resizable().frame(width: 18, height: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(entity.displayName).font(.system(size: 12, weight: alerting ? .semibold : .regular)).lineLimit(1)
                    Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                Sparkline(
                    values: coordinator.series(for: entity.key, resource: resource),
                    limit: sparklineLimit,
                    color: alerting ? .red : .accentColor
                )
                .frame(width: 60, height: 18)
                QuitButton(optionDown: optionDown, enabled: coordinator.canAct(on: entity)) {
                    coordinator.quit(entity, force: optionDown)
                }
                Menu {
                    ForEach(SnoozeDuration.allCases, id: \.self) { duration in
                        Button("Snooze \(duration.displayName)") { coordinator.snooze(entity, for: duration) }
                    }
                    Divider()
                    Button("Ignore for now") { coordinator.ignore(entity) }
                    Button("Always ignore") { coordinator.alwaysIgnore(entity) }
                    Divider()
                    Menu("Bowl size") {
                        ForEach(Bowl.allCases, id: \.self) { bowlItem($0) }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel("More actions for \(entity.displayName)")
            }
            if let status = coordinator.rowStatus[RowID(entity: entity.key, pid: nil)] {
                StatusText(status: status).padding(.leading, 36)
            }
            if expanded {
                ForEach(entity.members.prefix(8), id: \.process.identity) { member in
                    ProcessRow(coordinator: coordinator, entity: entity, sample: member, optionDown: optionDown)
                        .padding(.leading, 36)
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(alerting ? Color.red.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 6))
    }

    /// The ⌥ poll timer doesn't run while a menu is tracking, so on macOS 15+ native alternate items
    /// swap the labels live; macOS 14 only sees an ⌥ held when the menu opened.
    @ViewBuilder private func bowlItem(_ bowl: Bowl) -> some View {
        if #available(macOS 15, *) {
            bowlToggle(bowl, technical: false).modifierKeyAlternate(.option) { bowlToggle(bowl, technical: true) }
        } else {
            bowlToggle(bowl, technical: optionDown)
        }
    }

    private func bowlToggle(_ bowl: Bowl, technical: Bool) -> some View {
        Toggle(
            Formatting.bowl(bowl, shared: coordinator.settings.limits, technical: technical),
            isOn: Binding(
                get: { coordinator.settings.bowl(for: entity.key) == bowl },
                set: { _ in coordinator.setBowl(bowl, for: entity.key) }
            )
        )
    }

    private var subtitle: String {
        var value = Formatting.value(entity.value(for: resource), for: resource)
        let bowl = coordinator.settings.bowl(for: entity.key)
        if resource == .memory, bowl != .regular { value += " · \(bowl.displayName) bowl" }
        guard let breach else { return value }
        return "\(value) · over for \(Formatting.duration(breach.overTime))"
    }

    /// The bar this row is judged against right now; none while the Mac isn't strained on it.
    private var sparklineLimit: Double? {
        // History holds the app's summed CPU, which a per-process runaway bar doesn't fit.
        if resource == .cpu, breach?.reason == .runaway { return nil }
        guard resource == .memory ? coordinator.strain.memory : coordinator.strain.cpu else { return nil }
        return coordinator.settings.limits(for: entity.key).thresholdValue(for: resource, physicalMemory: SystemInfo.physicalMemory)
    }

    private var icon: Image {
        if let path = entity.bundlePath {
            return Image(nsImage: AppIcons.icon(forBundle: path))
        }
        return Image(systemName: "terminal")
    }
}

/// `NSWorkspace.icon(forFile:)` hits the disk; rows re-render every tick while the popover is open.
@MainActor
enum AppIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(forBundle path: String) -> NSImage {
        if let cached = cache[path] { return cached }
        let icon = NSWorkspace.shared.icon(forFile: path)
        cache[path] = icon
        return icon
    }
}

struct ProcessRow: View {
    let coordinator: AppCoordinator
    let entity: Entity
    let sample: ProcessSample
    let optionDown: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(sample.process.name).font(.system(size: 11)).lineLimit(1)
                Spacer()
                Text("\(Formatting.value(sample.cpuPercent, for: .cpu)) · \(Formatting.value(Double(sample.memoryBytes), for: .memory))")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.secondary)
                QuitButton(optionDown: optionDown, enabled: coordinator.canAct(on: sample), compact: true) {
                    coordinator.quit(sample, in: entity, force: optionDown)
                }
            }
            if let status = coordinator.rowStatus[RowID(entity: entity.key, pid: sample.process.pid)] {
                StatusText(status: status)
            }
        }
    }
}

/// "Quit" normally; "Kill" (red) while ⌥ is held.
struct QuitButton: View {
    let optionDown: Bool
    let enabled: Bool
    var compact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(optionDown ? "Kill" : "Quit")
                .font(.system(size: compact ? 10 : 11, weight: .semibold))
                .frame(minWidth: compact ? 30 : 36)
        }
        .buttonStyle(.borderedProminent)
        .tint(optionDown ? .red : .accentColor)
        .controlSize(compact ? .mini : .small)
        .disabled(!enabled)
        .help(enabled ? (optionDown ? "Force quit now. Unsaved work is lost." : "Ask it to quit (hold ⌥ to Kill)") : "Belongs to the system or another user")
    }
}

struct StatusText: View {
    let status: RowStatus

    var body: some View {
        Text(text).font(.system(size: 10)).foregroundStyle(color)
    }

    private var text: String {
        switch status {
        case .askingPolitely: "Asking politely…"
        case .stillAlive: "Still here — hold ⌥ to Kill"
        case .notAllowed: "Not allowed: it belongs to another user"
        case .gone: "Already gone"
        case .failed(let code): "Couldn't quit it (error \(code))"
        }
    }

    private var color: Color {
        switch status {
        case .askingPolitely: .secondary
        case .stillAlive: .orange
        default: .red
        }
    }
}
