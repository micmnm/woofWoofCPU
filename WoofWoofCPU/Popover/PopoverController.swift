import AppKit
import Observation
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

/// Per-open state the hosted view reads. Bumping `openCount` re-identifies the content, so its
/// `@State` (expanded rows, "+N more", hover freeze) starts fresh on every open.
@MainActor
@Observable
final class PopoverSession {
    var openCount = 0
    var maxListHeight: CGFloat = 420
}

/// Lays the content out at its ideal size and reports it, so the panel is resized with its top edge pinned.
private struct PopoverRoot<Content: View>: View {
    let content: Content
    let session: PopoverSession
    let onSize: @MainActor (CGSize) -> Void

    var body: some View {
        content
            .id(session.openCount)
            .environment(\.popoverMaxListHeight, session.maxListHeight)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .fixedSize()
            .onGeometryChange(for: CGSize.self) { $0.size } action: { onSize($0) }
    }
}

@MainActor
final class PopoverController {
    private let panel = PopoverPanel()
    private let session = PopoverSession()
    private var host: NSHostingController<PopoverRoot<AnyView>>!
    private let status: StatusItemController
    private let optionKey: OptionKeyMonitor
    private var clickMonitor: Any?

    /// Called when the user dismisses the popover (Esc or click outside), not when we close it.
    var onUserDismiss: (() -> Void)?

    var isShown: Bool { panel.isVisible }

    init<Content: View>(status: StatusItemController, optionKey: OptionKeyMonitor, content: Content) {
        self.status = status
        self.optionKey = optionKey
        host = NSHostingController(
            rootView: PopoverRoot(content: AnyView(content), session: session) { [weak self] size in
                self?.contentSizeChanged(size)
            }
        )
        // The panel is sized by `place(size:)`; AppKit's own resizing keeps the bottom edge fixed.
        host.sizingOptions = []
        panel.contentViewController = host
        panel.onCancel = { [weak self] in self?.dismissByUser() }
    }

    /// The user's dog click: the panel takes key so Esc works straight away.
    func toggle() {
        isShown ? dismissByUser() : show(activate: true)
    }

    /// `activate: false` (alert opens) only orders the panel front, so typing elsewhere is not captured;
    /// the first click into it makes it key.
    func show(activate: Bool = false) {
        let screen = targetScreen()
        session.maxListHeight = min(520, max(120, screen.visibleFrame.height - 260))
        place(size: host.sizeThatFits(in: screen.visibleFrame.size), on: screen)
        panel.orderFrontRegardless()
        if activate { panel.makeKey() }
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
        // An Esc while hovering never delivers onHover(false), so the freeze would outlive the open.
        session.openCount += 1
    }

    private func dismissByUser() {
        guard isShown else { return }
        close()
        onUserDismiss?()
    }

    private func contentSizeChanged(_ size: CGSize) {
        guard isShown, size != panel.frame.size else { return }
        place(size: size, on: targetScreen())
    }

    private func targetScreen() -> NSScreen {
        if let anchor = status.anchorRect, let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens[0]
    }

    /// Under the dog when the menu bar is visible; top-right of the active screen in full-screen.
    private func place(size: CGSize, on screen: NSScreen) {
        var origin: NSPoint
        if let anchor = status.anchorRect {
            origin = NSPoint(x: anchor.midX - size.width + 40, y: anchor.minY - size.height - 6)
        } else {
            origin = NSPoint(x: screen.frame.maxX - size.width - 12, y: screen.frame.maxY - size.height - 8)
        }
        let bounds = screen.visibleFrame
        origin.x = min(max(origin.x, bounds.minX + 8), bounds.maxX - size.width - 8)
        origin.y = max(origin.y, bounds.minY + 8)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }
}
