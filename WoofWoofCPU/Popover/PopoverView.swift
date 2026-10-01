import SwiftUI
import WoofCore

struct PopoverView: View {
    let coordinator: AppCoordinator
    let optionKey: OptionKeyMonitor
    var openSettings: () -> Void

    @State private var expanded: Set<EntityKey> = []
    @State private var showAll = false
    /// While the pointer is over the list, rows keep their order so clicks land on the intended row.
    @State private var frozenOrder: [EntityKey]?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider()
            if coordinator.popoverMode == .list {
                Picker("Sort", selection: Bindable(coordinator).sortResource) {
                    Text("CPU").tag(SortResource.cpu)
                    Text("Memory").tag(SortResource.memory)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            list
            Divider()
            footer
        }
        .padding(12)
        .frame(width: 380)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: coordinator.skin.portrait(for: coordinator.mood))
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(headline).font(.system(size: 13, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                if let subline { Text(subline).font(.system(size: 11)).foregroundStyle(.secondary) }
            }
        }
    }

    private var headline: String {
        let top = coordinator.headlineEntity()
        let resource = top?.breach.key.resource
        let value = top.map { Formatting.value($0.breach.lastValue, for: $0.breach.key.resource) } ?? ""
        let duration = top.map { Formatting.duration(SystemInfo.uptime - $0.breach.since) } ?? ""
        return Lines.line(
            mood: coordinator.mood,
            resource: resource,
            app: top?.entity.displayName,
            value: value,
            duration: duration,
            seed: top?.breach.id ?? 0
        )
    }

    private var subline: String? {
        if coordinator.settings.isPaused(now: Date()), let until = coordinator.settings.pausedUntil {
            return until == .distantFuture ? "Off duty until you resume" : "Off duty until \(until.formatted(date: .omitted, time: .shortened))"
        }
        guard let top = coordinator.headlineEntity() else { return nil }
        return Formatting.limit(coordinator.limits, top.breach.key.resource)
    }

    // MARK: List

    private var orderedEntities: [Entity] {
        let sorted = coordinator.sortedEntities
        guard let frozenOrder else { return sorted }
        let rank = Dictionary(uniqueKeysWithValues: frozenOrder.enumerated().map { ($1, $0) })
        return sorted.sorted { (rank[$0.key] ?? Int.max) < (rank[$1.key] ?? Int.max) }
    }

    private var list: some View {
        let all = orderedEntities
        let limit = showAll ? all.count : coordinator.settings.rowsShown
        let visible = Array(all.prefix(limit))
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(visible) { entity in
                EntityRow(
                    coordinator: coordinator,
                    entity: entity,
                    optionDown: optionKey.isOptionDown,
                    expanded: Binding(
                        get: { expanded.contains(entity.key) },
                        set: { if $0 { expanded.insert(entity.key) } else { expanded.remove(entity.key) } }
                    )
                )
            }
            if all.count > visible.count {
                Button("+\(all.count - visible.count) more…") { showAll = true }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
                    .padding(.leading, 6)
            } else if showAll, all.count > coordinator.settings.rowsShown {
                Button("Show fewer") { showAll = false }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
                    .padding(.leading, 6)
            }
        }
        .onHover { inside in
            frozenOrder = inside ? coordinator.sortedEntities.map(\.key) : nil
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Menu {
                if coordinator.settings.isPaused(now: Date()) {
                    Button("Resume watching") { coordinator.resume() }
                } else {
                    Button("Pause for 30 minutes") { coordinator.pause(for: 30 * 60) }
                    Button("Pause for 1 hour") { coordinator.pause(for: 60 * 60) }
                    Button("Pause until I resume") { coordinator.pause(for: nil) }
                }
            } label: {
                Label("Pause", systemImage: "pause.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Button {
                coordinator.settings.soundMuted.toggle()
            } label: {
                Image(systemName: coordinator.settings.soundMuted ? "speaker.slash" : "speaker.wave.2")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(coordinator.settings.soundMuted ? "Unmute bark" : "Mute bark")

            Spacer()
            Button("Settings…", action: openSettings).buttonStyle(.borderless)
        }
        .font(.system(size: 11))
    }
}
