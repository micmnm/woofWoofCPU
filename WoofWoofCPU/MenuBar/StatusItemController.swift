import AppKit

/// Owns the NSStatusItem. Left click → `onLeftClick`; right click → menu from `menuProvider`.
/// AppKit rather than SwiftUI MenuBarExtra: the icon must animate and the popover must open on its own.
@MainActor
final class StatusItemController: NSObject {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var onLeftClick: (() -> Void)?
    var menuProvider: (() -> NSMenu)?

    var button: NSStatusBarButton? { statusItem.button }

    override init() {
        super.init()
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(clicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageOnly
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            guard let menu = menuProvider?() else { return }
            statusItem.menu = menu
            sender.performClick(nil)
            statusItem.menu = nil
        } else {
            onLeftClick?()
        }
    }

    /// Screen rect of the dog, used to anchor the popover. Nil if the menu bar isn't on screen.
    var anchorRect: NSRect? {
        guard let button, let window = button.window, window.isVisible else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }
}
