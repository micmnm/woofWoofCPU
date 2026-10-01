import AppKit
import SwiftUI
import WoofCore

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let settings: SettingsStore

    init(settings: SettingsStore) {
        self.settings = settings
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(settings: settings)))
            window.title = "woofWoofCPU Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        // Agent apps aren't active by default; activate so the window comes to the front.
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
