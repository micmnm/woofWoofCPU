import AppKit
import SwiftUI

/// Non-activating panel so the popover never steals keyboard focus, and can float over full-screen apps.
final class PopoverPanel: NSPanel {
    var onCancel: (() -> Void)?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 300),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isMovable = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

@MainActor
final class PopoverController {
    private let panel = PopoverPanel()
    private let status: StatusItemController
    private let optionKey: OptionKeyMonitor
    private var clickMonitor: Any?

    /// Called when the user dismisses the popover (Esc or click outside), not when we close it.
    var onUserDismiss: (() -> Void)?

    var isShown: Bool { panel.isVisible }

    init<Content: View>(status: StatusItemController, optionKey: OptionKeyMonitor, content: Content) {
        self.status = status
        self.optionKey = optionKey
        let host = NSHostingController(
            rootView: content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        )
        host.sizingOptions = [.preferredContentSize]
        panel.contentViewController = host
        panel.onCancel = { [weak self] in self?.dismissByUser() }
    }

    func toggle() {
        isShown ? dismissByUser() : show()
    }

    func show() {
        panel.contentViewController?.view.layoutSubtreeIfNeeded()
        position()
        panel.orderFrontRegardless()
        panel.makeKey()
        optionKey.start()
        if clickMonitor == nil {
            clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                MainActor.assumeIsolated { self?.dismissByUser() }
            }
        }
    }

    func close() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
        optionKey.stop()
        panel.orderOut(nil)
    }

    private func dismissByUser() {
        guard isShown else { return }
        close()
        onUserDismiss?()
    }

    /// Under the dog when the menu bar is visible; top-right of the active screen in full-screen.
    private func position() {
        let size = panel.contentViewController?.view.fittingSize ?? panel.frame.size
        let screen = NSScreen.main ?? NSScreen.screens[0]
        var origin: NSPoint
        if let anchor = status.anchorRect {
            origin = NSPoint(x: anchor.midX - size.width + 40, y: anchor.minY - size.height - 6)
        } else {
            origin = NSPoint(x: screen.frame.maxX - size.width - 12, y: screen.frame.maxY - size.height - 8)
        }
        let bounds = screen.visibleFrame
        origin.x = min(max(origin.x, bounds.minX + 8), bounds.maxX - size.width - 8)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }
}
