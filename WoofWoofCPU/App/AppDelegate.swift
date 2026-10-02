import AppKit
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
        coordinator.onMoodChange = { [weak self] _ in self?.refreshDog() }
        coordinator.onTick = { [weak self] in self?.refreshDog() }
        // The bark doesn't open the popover; a click on the barking dog opens it in alert mode.
        coordinator.onAlert = { [weak self] in
            guard let self, !self.coordinator.settings.soundMuted else { return }
            self.bark.play(self.coordinator.skin.barkSoundName)
        }

        coordinator.start()
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
            menu.addItem(ClosureMenuItem("Pause for 30 minutes") { [weak self] in self?.coordinator.pause(for: 30 * 60) })
            menu.addItem(ClosureMenuItem("Pause for 1 hour") { [weak self] in self?.coordinator.pause(for: 60 * 60) })
            menu.addItem(ClosureMenuItem("Pause until I resume") { [weak self] in self?.coordinator.pause(for: nil) })
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
