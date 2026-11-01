import SwiftUI
import WoofCore

struct PopoverView: View {
    let coordinator: AppCoordinator
    let optionKey: OptionKeyMonitor
    var openSettings: () -> Void

    @State private var expanded: Set<EntityKey> = []
    /// Runaway rows open by default; these are the ones the user closed.
    @State private var collapsed: Set<EntityKey> = []
    @State private var showAll = false
    /// While the pointer is over the list, rows keep their order so clicks land on the intended row.
    @State private var frozenOrder: [EntityKey]?
    /// Natural height of the rows; the scroll view shows them all until `maxListHeight`.
    @State private var rowsHeight: CGFloat = 0
    @Environment(\.popoverMaxListHeight) private var maxListHeight

    private static let maxExpandedRows = 30

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
        .frame(width: PopoverController.width)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            let portrait = coordinator.skin.portrait(for: coordinator.mood)
            let size = coordinator.skin.displaySize(of: portrait, fitting: CGSize(width: 64, height: 48))
            Image(nsImage: portrait)
                .interpolation(coordinator.skin.isPixelArt ? .none : .high)
                .resizable()
                .frame(width: size.width, height: size.height)
                .frame(width: 64, height: 48)
                .accessibilityLabel("Dog is \(coordinator.mood.rawValue)")
            VStack(alignment: .leading, spacing: 2) {
                Text(headline).font(.system(size: 13, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                if let line = Lines.strainLine(strain, machine: coordinator.machine) {
                    Text(line).font(.system(size: 11))
                } else if let subline {
                    Text(subline).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Ticks stop while paused, so the last strain would be stale.
    private var strain: Strain {
        coordinator.settings.isPaused(now: Date()) ? Strain(memory: false, cpu: false) : coordinator.strain
    }

    private var headline: String {
        if coordinator.popoverMode == .list, coordinator.activeBreaches.isEmpty {
            let resource: Resource = strain.memory ? .memory : .cpu
            let busiest = coordinator.entities.max { $0.value(for: resource) < $1.value(for: resource) }
            if let line = Lines.noCulpritLine(strain: strain, topApp: busiest?.displayName) { return line }
        }
        if coordinator.settings.isPaused(now: Date()) { return Lines.paused }
        let top = coordinator.headlineEntity()
        let resource = top?.breach.key.resource
        let value = top.map { top in
            // Runaway copy names the stuck process, not the app's total.
            let shown = top.breach.reason == .runaway
                ? top.entity.members.map(\.cpuPercent).max() ?? top.breach.lastValue
                : top.breach.lastValue
            return Formatting.value(shown, for: top.breach.key.resource)
        } ?? ""
        let duration = top.map { Formatting.duration($0.breach.overTime) } ?? ""
        let now = Date()
        return Lines.line(
            mood: coordinator.mood,
            resource: resource,
            reason: top?.breach.reason,
            app: top?.entity.displayName,
            value: value,
            duration: duration,
            // No breach: change the napping line hourly.
            seed: top?.breach.id ?? Int(now.timeIntervalSinceReferenceDate / 3600),
            skinID: coordinator.skin.id,
            date: now
        )
    }

    private var subline: String? {
        if coordinator.settings.isPaused(now: Date()), let until = coordinator.settings.pausedUntil {
            return until == .distantFuture ? "Off duty until you resume" : "Off duty until \(until.formatted(date: .omitted, time: .shortened))"
        }
        guard let top = coordinator.headlineEntity() else { return nil }
        if top.breach.reason == .runaway {
            let saving = coordinator.machine.onBattery || coordinator.machine.lowPowerMode
            return Formatting.runawayLimit(coordinator.settings.limits(for: top.entity.key), saving: saving)
        }
        return Formatting.limit(coordinator.settings.limits(for: top.entity.key), top.breach.key.resource)
    }

    // MARK: List

    private var orderedEntities: [Entity] {
        let sorted = coordinator.sortedEntities
        guard let frozenOrder else { return sorted }
        let rank = Dictionary(uniqueKeysWithValues: frozenOrder.enumerated().map { ($1, $0) })
        return sorted.sorted { (rank[$0.key] ?? Int.max) < (rank[$1.key] ?? Int.max) }
    }

    private var list: some View {
        // Every sampled process is an entity; past the top few dozen the rows are idle noise.
        let all = Array(orderedEntities.prefix(Self.maxExpandedRows))
        let limit = showAll ? all.count : coordinator.settings.rowsShown
        let visible = Array(all.prefix(limit))
        return VStack(alignment: .leading, spacing: 2) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(visible) { entity in
                        EntityRow(
                            coordinator: coordinator,
                            entity: entity,
                            optionDown: optionKey.isOptionDown,
                            expanded: isExpanded(entity)
                        )
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { rowsHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(rowsHeight, maxListHeight))
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

    private func isExpanded(_ entity: Entity) -> Binding<Bool> {
        let runaway = entity.isApp && entity.members.count > 1 && coordinator.breach(for: entity.key)?.reason == .runaway
        return Binding(
            get: { runaway ? !collapsed.contains(entity.key) : expanded.contains(entity.key) },
            set: { open in
                if runaway {
                    if open { collapsed.remove(entity.key) } else { collapsed.insert(entity.key) }
                } else {
                    if open { expanded.insert(entity.key) } else { expanded.remove(entity.key) }
                }
            }
        )
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

extension EnvironmentValues {
    /// Set by `PopoverController` from the screen height, so the panel never runs off-screen.
    @Entry var popoverMaxListHeight: CGFloat = 420
}
