import AppKit
import Observation
import WoofCore

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator!
    private var status: StatusItemController!
    private var animator: DogAnimator!
    private var popover: PopoverController!
    private var settingsWindow: SettingsWindowController!
    private let bark = BarkPlayer()
    private var reminderTask: Task<Void, Never>?
    private let optionKey = OptionKeyMonitor()
    private let iconUpdater = AppIconUpdater()

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = SettingsStore()
        let sampler = Sampler(
            source: LibprocProcessSource(),
            grouper: AppGrouper(selfPID: getpid(), currentUID: getuid(), appInfo: BundleAppInfoProvider())
        )
        // ProcessActions is only driven from the popover, i.e. on the main thread.
        let signaller = PosixSignaller(quitApp: { pid in
            MainActor.assumeIsolated { NSRunningApplication(processIdentifier: pid)?.terminate() ?? false }
        })
        coordinator = AppCoordinator(settings: settings, sampler: sampler, actions: ProcessActions(signaller: signaller))
        settingsWindow = SettingsWindowController(settings: settings)

        status = StatusItemController()
        animator = DogAnimator(button: status.button, skin: coordinator.skin)
        iconUpdater.apply(coordinator.skin)
        popover = PopoverController(
            status: status,
            optionKey: optionKey,
            content: PopoverView(coordinator: coordinator, optionKey: optionKey) { [weak self] in
                // Leaving an alert for Settings counts as a dismissal (no-op unless popoverMode == .alert).
                self?.coordinator.popoverDismissedByUser()
                self?.popover.close()
                self?.settingsWindow.show()
            }
        )

        status.onLeftClick = { [weak self] in
            guard let self else { return }
            if !self.popover.isShown {
                self.coordinator.popoverMode = self.coordinator.alertingKeys.isEmpty ? .list : .alert
            }
            self.popover.toggle()
        }
        status.menuProvider = { [weak self] in self?.makeMenu() ?? NSMenu() }
        popover.onUserDismiss = { [weak self] in self?.coordinator.popoverDismissedByUser() }
        coordinator.onMoodChange = { [weak self] mood in
            if mood != .barking { self?.cancelReminders() }
            self?.refreshDog()
        }
        coordinator.onTick = { [weak self] in self?.refreshDog() }
        // The bark doesn't open the popover; a click on the barking dog opens it in alert mode.
        coordinator.onAlert = { [weak self] in
            guard let self else { return }
            self.playBark()
            self.scheduleReminders()
        }

        observeSkin()
        coordinator.start()
    }

    /// Ticks stop while paused, so a skin change reaches the dog and app icon on its own.
    /// onChange fires before the new value lands (willSet), hence the hop before refreshing.
    private func observeSkin() {
        withObservationTracking {
            _ = coordinator.settings.skinID
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.refreshDog()
                self?.observeSkin()
            }
        }
    }

    private func playBark() {
        guard !coordinator.settings.soundMuted else { return }
        bark.play(coordinator.skin.barkSoundName)
    }

    /// Re-barks at +10/+30/+90 s after the first bark while the dog is still in the red state.
    private func scheduleReminders() {
        reminderTask?.cancel()
        reminderTask = Task { [weak self] in
            var elapsed = 0
            for offset in [10, 30, 90] {
                try? await Task.sleep(for: .seconds(offset - elapsed))
                elapsed = offset
                guard !Task.isCancelled, let self, self.coordinator.mood == .barking else { return }
                self.playBark()
            }
        }
    }

    private func cancelReminders() {
        reminderTask?.cancel()
        reminderTask = nil
    }

    private func refreshDog() {
        animator.update(mood: coordinator.mood, skin: coordinator.skin)
        iconUpdater.apply(coordinator.skin)
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let paused = coordinator.settings.isPaused(now: Date())
        if paused {
            menu.addItem(ClosureMenuItem("Resume watching") { [weak self] in self?.coordinator.resume() })
        } else {
            let pause = NSMenu()
            pause.addItem(ClosureMenuItem("For 30 minutes") { [weak self] in self?.coordinator.pause(for: 30 * 60) })
            pause.addItem(ClosureMenuItem("For 1 hour") { [weak self] in self?.coordinator.pause(for: 60 * 60) })
            pause.addItem(ClosureMenuItem("Until I resume") { [weak self] in self?.coordinator.pause(for: nil) })
            let item = NSMenuItem(title: "Pause watching", action: nil, keyEquivalent: "")
            item.submenu = pause
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let mute = ClosureMenuItem("Mute bark") { [weak self] in self?.coordinator.settings.soundMuted.toggle() }
        mute.state = coordinator.settings.soundMuted ? .on : .off
        menu.addItem(mute)
        menu.addItem(ClosureMenuItem("Settings…") { [weak self] in self?.settingsWindow.show() })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Quit woofWoofCPU") { NSApp.terminate(nil) })
        return menu
    }
}

/// NSMenuItem that runs a closure, so menus don't need @objc selectors per item.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func run() { handler() }
}
