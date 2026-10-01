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
        // Above the menu bar (status items sit at .statusBar), so no part can render behind it.
        level = .popUpMenu
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

/// State the hosted view reads.
@MainActor
@Observable
final class PopoverSession {
    var maxListHeight: CGFloat = 420
}

/// Lays the content out at its ideal size and reports it, so the panel is resized with its top edge pinned.
private struct PopoverRoot<Content: View>: View {
    let content: Content
    let session: PopoverSession
    let onSize: @MainActor (CGSize) -> Void

    var body: some View {
        content
            .environment(\.popoverMaxListHeight, session.maxListHeight)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .fixedSize()
            .onGeometryChange(for: CGSize.self) { $0.size } action: { onSize($0) }
    }
}

@MainActor
final class PopoverController {
    static let width: CGFloat = 380
    /// Header, picker, footer and padding around the scrolling list.
    static let chromeHeight: CGFloat = 240

    private let panel = PopoverPanel()
    private let session = PopoverSession()
    private let content: AnyView
    /// Exists only while shown: a fresh host per open resets the view's `@State` (expanded rows,
    /// "+N more", hover freeze), and a closed popover has no view left re-rendering on every tick.
    private var host: NSHostingController<PopoverRoot<AnyView>>?
    private let status: StatusItemController
    private let optionKey: OptionKeyMonitor
    private var clickMonitor: Any?
    /// Last size the content reported; it can arrive during the first layout, before the panel is visible.
    private var contentSize: CGSize?

    /// Called when the user dismisses the popover (Esc or click outside), not when we close it.
    var onUserDismiss: (() -> Void)?

    var isShown: Bool { panel.isVisible }

    init<Content: View>(status: StatusItemController, optionKey: OptionKeyMonitor, content: Content) {
        self.status = status
        self.optionKey = optionKey
        self.content = AnyView(content)
        panel.onCancel = { [weak self] in self?.dismissByUser() }
    }

    /// The user's dog click: the panel takes key so Esc works straight away.
    func toggle() {
        isShown ? dismissByUser() : show(activate: true)
    }

    /// `activate: false` (alert opens) only orders the panel front, so typing elsewhere is not captured;
    /// the first click into it makes it key. Does nothing when no screen is attached.
    func show(activate: Bool = false) {
        guard let screen = targetScreen() else { return }
        let available = availableHeight(on: screen)
        session.maxListHeight = min(520, max(120, available - Self.chromeHeight))
        let host = self.host ?? makeHost()
        let fitted = host.sizeThatFits(in: CGSize(width: Self.width, height: available))
        place(size: contentSize ?? fitted, on: screen)
        panel.orderFrontRegardless()
        // That first setFrame lays the content out and reports its real size while still hidden.
        if let contentSize, contentSize.height != panel.frame.height { place(size: contentSize, on: screen) }
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
        guard let retired = host else { return }
        host = nil
        contentSize = nil
        panel.contentViewController = nil
        panel.contentView = NSView()
        // close() can run inside one of the hosted view's own button actions; release it afterwards.
        Task { @MainActor in withExtendedLifetime(retired) {} }
    }

    private func makeHost() -> NSHostingController<PopoverRoot<AnyView>> {
        let host = NSHostingController(
            rootView: PopoverRoot(content: content, session: session) { [weak self] size in
                self?.contentSizeChanged(size)
            }
        )
        // The panel is sized by `place(size:)`; AppKit's own resizing keeps the bottom edge fixed.
        host.sizingOptions = []
        panel.contentViewController = host
        self.host = host
        return host
    }

    private func dismissByUser() {
        guard isShown else { return }
        close()
        onUserDismiss?()
    }

    private func contentSizeChanged(_ size: CGSize) {
        contentSize = size
        guard isShown, size != panel.frame.size, let screen = targetScreen() else { return }
        place(size: size, on: screen)
    }

    private func targetScreen() -> NSScreen? {
        if let anchor = status.anchorRect, let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    /// Under the dog, never above the visible frame: the dog sits inside the menu bar, so its
    /// own bottom edge can be higher than the menu bar's.
    private func topEdge(on screen: NSScreen) -> CGFloat {
        let limit = screen.visibleFrame.maxY - 4
        guard let anchor = status.anchorRect else { return min(screen.frame.maxY - 8, limit) }
        return min(anchor.minY - 6, limit)
    }

    private func availableHeight(on screen: NSScreen) -> CGFloat {
        topEdge(on: screen) - (screen.visibleFrame.minY + 8)
    }

    /// Under the dog when the menu bar is visible; top-right of the active screen in full-screen.
    /// Capped to the space under the dog (show() sizes the list to fit it) rather than pushed up.
    private func place(size: CGSize, on screen: NSScreen) {
        let bounds = screen.visibleFrame
        let top = topEdge(on: screen)
        let height = min(size.height, availableHeight(on: screen))
        var x = status.anchorRect.map { $0.midX - size.width + 40 } ?? (screen.frame.maxX - size.width - 12)
        x = min(max(x, bounds.minX + 8), bounds.maxX - size.width - 8)
        panel.setFrame(NSRect(x: x, y: top - height, width: size.width, height: height), display: true)
    }
}
