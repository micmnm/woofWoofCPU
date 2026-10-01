import AppKit
import Observation
import WoofCore
import os

enum PopoverMode: Equatable {
    case list
    case alert
}

/// Identifies a popover row: a whole entity (pid nil) or one process inside it.
struct RowID: Hashable {
    let entity: EntityKey
    let pid: Int32?
}

enum RowStatus: Equatable {
    case askingPolitely
    case stillAlive
    case notAllowed
    case gone
    case failed(Int32)
}

enum SortResource: String, CaseIterable {
    case cpu, memory
}

/// Main-actor hub: runs the sampling loop, owns the pipeline, and exposes state to the UI.
@MainActor
@Observable
final class AppCoordinator {
    static let tickInterval: TimeInterval = 2
    static let calmBatteryTickInterval: TimeInterval = 5
    static let politeQuitGrace: Duration = .seconds(5)

    let settings: SettingsStore
    private(set) var entities: [Entity] = []
    private(set) var breaches: [Breach] = []
    /// `breaches` minus snoozed, always-ignored and Ignored ones; drives sorting and the headline.
    private(set) var activeBreaches: [Breach] = []
    private(set) var mood: DogMood = .napping
    private(set) var alertingKeys: Set<EntityKey> = []
    private(set) var rowStatus: [RowID: RowStatus] = [:]
    var popoverMode: PopoverMode = .list
    var sortResource: SortResource = .cpu

    @ObservationIgnored var onMoodChange: ((DogMood) -> Void)?
    @ObservationIgnored var onAlert: (() -> Void)?
    @ObservationIgnored var onTick: (() -> Void)?

    @ObservationIgnored private var pipeline = WatchPipeline()
    @ObservationIgnored private let sampler: Sampler
    @ObservationIgnored private let actions: ProcessActions
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private let log = Logger(subsystem: "com.woofwoofcpu", category: "coordinator")
    let currentUID = getuid()

    init(settings: SettingsStore, sampler: Sampler, actions: ProcessActions) {
        self.settings = settings
        self.sampler = sampler
        self.actions = actions
    }

    var skin: any Skin { SkinRegistry.skin(id: settings.skinID) }
    var limits: Limits { settings.limits }

    // MARK: Loop

    func start() {
        observeSleepWake()
        startLoop()
    }

    private func startLoop() {
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.tick()
                let calm = self.mood == .napping && SystemInfo.isOnBattery
                let interval = calm ? Self.calmBatteryTickInterval : Self.tickInterval
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func tick() async {
        let now = SystemInfo.uptime
        let sampled = await sampler.sample(now: now)
        apply(sampled, now: now)
    }

    func apply(_ sampled: [Entity], now: TimeInterval) {
        let date = Date()
        settings.pruneExpired(now: date)
        let step = pipeline.step(
            entities: sampled,
            limits: settings.limits,
            physicalMemory: SystemInfo.physicalMemory,
            isMuted: { [settings] key in settings.isMuted(key, now: date) },
            paused: settings.isPaused(now: date),
            now: now
        )
        entities = sampled
        breaches = step.breaches
        let engine = pipeline.engine
        activeBreaches = step.breaches.filter {
            !settings.isMuted($0.key.entity, now: date) && !engine.isIgnored(breachID: $0.id)
        }
        pruneRowStatus(for: sampled)
        let open = engine.openAlertIDs
        alertingKeys = Set(step.breaches.filter { open.contains($0.id) }.map(\.key.entity))
        updateMood(step.mood)
        if !step.newAlerts.isEmpty {
            popoverMode = .alert
            onAlert?()
        } else if popoverMode == .alert, alertingKeys.isEmpty {
            popoverMode = .list
        }
        onTick?()
    }

    /// Entity keys survive relaunches, so a status must not outlive the entity (or pid) it was set on.
    private func pruneRowStatus(for sampled: [Entity]) {
        guard !rowStatus.isEmpty else { return }
        let pids = Dictionary(sampled.map { ($0.key, Set($0.members.map(\.process.pid))) }, uniquingKeysWith: { $0.union($1) })
        let kept = rowStatus.filter { row, _ in
            guard let members = pids[row.entity] else { return false }
            return row.pid.map(members.contains) ?? true
        }
        if kept.count != rowStatus.count { rowStatus = kept }
    }

    private func updateMood(_ newMood: DogMood) {
        guard newMood != mood else { return }
        mood = newMood
        onMoodChange?(newMood)
    }

    private func observeSleepWake() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.loop?.cancel() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.pipeline.resetTimers()
                Task {
                    await self.sampler.reset()
                    self.startLoop()
                }
            }
        })
    }

    // MARK: Popover data

    func breach(for key: EntityKey) -> Breach? {
        activeBreaches.filter { $0.key.entity == key }.max { $0.progress < $1.progress }
    }

    /// Alerting entities first, then by severity, then by the chosen resource.
    var sortedEntities: [Entity] {
        let resource: Resource = sortResource == .cpu ? .cpu : .memory
        return entities.sorted { a, b in
            let aAlert = alertingKeys.contains(a.key), bAlert = alertingKeys.contains(b.key)
            if aAlert != bAlert { return aAlert }
            let aProgress = breach(for: a.key)?.progress ?? -1
            let bProgress = breach(for: b.key)?.progress ?? -1
            if aProgress != bProgress { return aProgress > bProgress }
            return a.value(for: resource) > b.value(for: resource)
        }
    }

    func series(for key: EntityKey, resource: Resource) -> [Double] {
        let window = settings.limits[resource].window
        return pipeline.history.series(for: key, resource: resource, since: SystemInfo.uptime - window)
    }

    func headlineEntity() -> (entity: Entity, breach: Breach)? {
        for entity in sortedEntities {
            if let breach = breach(for: entity.key), alertingKeys.contains(entity.key) || mood != .barking {
                return (entity, breach)
            }
        }
        return nil
    }

    // MARK: Actions

    func quit(_ entity: Entity, force: Bool) {
        let id = RowID(entity: entity.key, pid: nil)
        let result = force ? actions.kill(entity) : actions.quit(entity)
        handle(result, row: id, force: force, watchPID: entity.mainPID ?? entity.members.first?.process.pid)
    }

    func quit(_ sample: ProcessSample, in entity: Entity, force: Bool) {
        let id = RowID(entity: entity.key, pid: sample.process.pid)
        let result = force ? actions.kill(sample) : actions.quit(sample)
        handle(result, row: id, force: force, watchPID: sample.process.pid)
    }

    func canAct(on entity: Entity) -> Bool { actions.canAct(on: entity) }
    func canAct(on sample: ProcessSample) -> Bool { actions.canAct(on: sample, currentUID: currentUID) }

    private func handle(_ result: SignalResult, row: RowID, force: Bool, watchPID: Int32?) {
        log.info("action on \(String(describing: row.entity), privacy: .public) force=\(force) result=\(String(describing: result), privacy: .public)")
        switch result {
        case .sent where force:
            rowStatus[row] = nil
        case .sent:
            rowStatus[row] = .askingPolitely
            Task { [weak self] in
                try? await Task.sleep(for: Self.politeQuitGrace)
                guard let self, self.rowStatus[row] == .askingPolitely else { return }
                let alive = watchPID.map { self.actions.isAlive($0) } ?? false
                self.rowStatus[row] = alive ? .stillAlive : nil
            }
        case .notAllowed:
            rowStatus[row] = .notAllowed
        case .alreadyGone:
            rowStatus[row] = .gone
        case .failed(let code):
            rowStatus[row] = .failed(code)
        }
    }

    func snooze(_ entity: Entity, for duration: SnoozeDuration) {
        settings.snooze(entity.key, until: duration.until(from: Date()))
        reevaluate()
    }

    func ignore(_ entity: Entity) {
        for breach in breaches where breach.key.entity == entity.key {
            pipeline.engine.ignore(breachID: breach.id)
        }
        reevaluate()
    }

    func alwaysIgnore(_ entity: Entity) {
        settings.alwaysIgnore(entity.key)
        reevaluate()
    }

    /// Esc / click outside while barking → the dog sulks.
    func popoverDismissedByUser() {
        guard popoverMode == .alert else { return }
        pipeline.engine.alertDismissed()
        alertingKeys = []
        popoverMode = .list
        updateMood(pipeline.engine.mood)
    }

    func pause(for duration: TimeInterval?) {
        settings.pausedUntil = duration.map { Date().addingTimeInterval($0) } ?? .distantFuture
        reevaluate()
    }

    func resume() {
        settings.pausedUntil = nil
        reevaluate()
    }

    /// Re-run the pipeline on the last sample so actions show up immediately.
    private func reevaluate() {
        apply(entities, now: SystemInfo.uptime)
    }
}
