import AppKit

/// Keeps `NSApp.applicationIconImage` in step with the selected skin (in-process only; the bundle icon stays signed).
@MainActor
final class AppIconUpdater {
    private var appliedSkinID: String?

    func apply(_ skin: any Skin) {
        guard skin.id != appliedSkinID else { return }
        appliedSkinID = skin.id
        NSApp.applicationIconImage = skin.id == "pixel" ? Self.bundledIcon() : Self.compose(skin)
    }

    private static func bundledIcon() -> NSImage? { NSImage(named: "AppIcon") }

    /// Same rounded-square macOS grid as scripts/make-icon.swift, with the skin's napping portrait on top.
    private static func compose(_ skin: any Skin) -> NSImage {
        let portrait = skin.portrait(for: .napping)
        return NSImage(size: NSSize(width: 1024, height: 1024), flipped: false) { rect in
            let body = rect.insetBy(dx: rect.width * 0.0977, dy: rect.height * 0.0977)
            let shape = NSBezierPath(roundedRect: body, xRadius: body.width * 0.225, yRadius: body.width * 0.225)
            NSGradient(
                starting: NSColor(red: 1.0, green: 0.93, blue: 0.80, alpha: 1),
                ending: NSColor(red: 0.98, green: 0.62, blue: 0.28, alpha: 1)
            )?.draw(in: shape, angle: -90)
            let box = body.insetBy(dx: body.width * 0.11, dy: body.width * 0.11)
            let scale = min(box.width / portrait.size.width, box.height / portrait.size.height)
            let size = NSSize(width: portrait.size.width * scale, height: portrait.size.height * scale)
            NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
                NSGraphicsContext.current?.imageInterpolation = .none
                portrait.draw(in: NSRect(x: body.midX - size.width / 2, y: body.midY - size.height / 2, width: size.width, height: size.height))
            }
            return true
        }
    }
}
