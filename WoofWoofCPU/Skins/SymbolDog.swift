import AppKit
import WoofCore

/// The SF Symbols dog plus a mood badge, composed in the 24×18-pt menu bar slot. Shared by both symbol skins.
enum SymbolDog {
    static let slot = NSSize(width: 24, height: 18)
    private static let dogPointSize: CGFloat = 11.5
    private static let badgePointSize: CGFloat = 6.5

    struct Pose {
        var dog = "dog.fill"
        /// Faces left and sits at the right edge, badge top-left.
        var flip = false
        var badge: String?
        var badgePointSize = SymbolDog.badgePointSize
        /// nil draws in the ink color.
        var dogColor: NSColor?
        var badgeColor: NSColor?

        var isColored: Bool { dogColor != nil || (badge != nil && badgeColor != nil) }
    }

    static func poses(for mood: DogMood) -> [Pose] {
        switch mood {
        case .napping:
            [Pose(dog: "dog", badge: "zzz"), Pose(dog: "dog")]
        case .sniffing:
            [Pose(badge: "questionmark")]
        case .growling:
            [Pose(badge: "exclamationmark.2", badgeColor: .systemOrange)]
        case .barking:
            [Pose(badge: "speaker.wave.3.fill", dogColor: .systemRed, badgeColor: .systemRed), Pose(dogColor: .systemRed)]
        case .sulking:
            [Pose(flip: true, badge: "cloud.rain.fill")]
        case .proud:
            [Pose(badge: "heart.fill", badgeColor: .systemPink),
             Pose(badge: "heart.fill", badgePointSize: 5.5, badgeColor: .systemPink)]
        }
    }

    static func frameDuration(for mood: DogMood) -> TimeInterval {
        switch mood {
        case .barking: 0.25
        case .proud: 0.3
        case .napping: 1.2
        default: 0.6
        }
    }

    /// Draws into a flipped context: dog on the slot's bottom edge, badge in the opposite top corner.
    static func draw(_ pose: Pose, at origin: NSPoint, zoom: CGFloat, ink: NSColor) {
        let slotWidth = slot.width * zoom
        let slotHeight = slot.height * zoom
        if let dog = symbol(pose.dog, pointSize: dogPointSize * zoom, weight: .semibold) {
            let rect = NSRect(
                x: pose.flip ? origin.x + slotWidth - dog.size.width : origin.x,
                y: origin.y + slotHeight - dog.size.height,
                width: dog.size.width, height: dog.size.height
            )
            NSGraphicsContext.saveGraphicsState()
            if pose.flip {
                let mirror = NSAffineTransform()
                mirror.translateX(by: rect.midX, yBy: 0)
                mirror.scaleX(by: -1, yBy: 1)
                mirror.translateX(by: -rect.midX, yBy: 0)
                mirror.concat()
            }
            drawTinted(dog, in: rect, color: pose.dogColor ?? ink)
            NSGraphicsContext.restoreGraphicsState()
        }
        guard let name = pose.badge,
              let badge = symbol(name, pointSize: pose.badgePointSize * zoom, weight: .heavy),
              let full = symbol(name, pointSize: badgePointSize * zoom, weight: .heavy) else { return }
        // A smaller badge (the proud pulse) stays centred where the full-size one sits.
        let x = pose.flip ? origin.x : origin.x + slotWidth - full.size.width
        let rect = NSRect(
            x: x + (full.size.width - badge.size.width) / 2,
            y: origin.y + (full.size.height - badge.size.height) / 2,
            width: badge.size.width, height: badge.size.height
        )
        drawTinted(badge, in: rect, color: pose.badgeColor ?? ink)
    }

    private static func symbol(_ name: String, pointSize: CGFloat, weight: NSFont.Weight) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: pointSize, weight: weight))
    }

    /// The transparency layer keeps the source-atop tint off whatever is already drawn underneath.
    private static func drawTinted(_ image: NSImage, in rect: NSRect, color: NSColor) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.beginTransparencyLayer(in: rect, auxiliaryInfo: nil)
        image.draw(in: rect)
        color.set()
        rect.fill(using: .sourceAtop)
        context.endTransparencyLayer()
    }
}
