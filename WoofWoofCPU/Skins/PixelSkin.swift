import AppKit
import WoofCore

/// Monochrome template sprites, red only while barking.
@MainActor
final class PixelSkin: Skin {
    let id = "pixel"
    let displayName = "Pixel pup"
    let barkSoundName = "bark-pixel"

    private var frameCache: [DogMood: [NSImage]] = [:]
    private var portraitCache: [DogMood: NSImage] = [:]

    func frames(for mood: DogMood) -> [NSImage] {
        if let cached = frameCache[mood] { return cached }
        let images = PixelArt.frames(for: mood).map {
            Self.render($0, pixel: 1.5, template: mood != .barking, ink: Self.ink(for: mood))
        }
        frameCache[mood] = images
        return images
    }

    func frameDuration(for mood: DogMood) -> TimeInterval {
        switch mood {
        case .barking: 0.25
        case .proud: 0.3
        case .napping: 1.2
        default: 0.6
        }
    }

    func portrait(for mood: DogMood) -> NSImage {
        if let cached = portraitCache[mood] { return cached }
        let image = Self.render(PixelArt.frames(for: mood)[0], pixel: 4, template: false, ink: Self.ink(for: mood))
        portraitCache[mood] = image
        return image
    }

    /// Black or white ink on a red tongue reads as growling in the menu bar, so barking is all red.
    static func ink(for mood: DogMood) -> NSColor {
        mood == .barking ? .systemRed : .labelColor
    }

    /// Template images ignore color: only alpha matters, so `r`/`p` read as ink there.
    static func render(_ rows: [String], pixel: CGFloat, template: Bool, ink: NSColor) -> NSImage {
        let size = NSSize(width: CGFloat(PixelArt.width) * pixel, height: CGFloat(PixelArt.height) * pixel)
        let image = NSImage(size: size, flipped: true) { _ in
            for (y, row) in rows.enumerated() {
                for (x, char) in row.enumerated() {
                    let color: NSColor
                    switch char {
                    case "#": color = template ? .black : ink
                    case "r": color = .systemRed
                    case "p": color = .systemPink
                    default: continue
                    }
                    color.setFill()
                    NSRect(x: CGFloat(x) * pixel, y: CGFloat(y) * pixel, width: pixel, height: pixel).fill()
                }
            }
            return true
        }
        image.isTemplate = template
        return image
    }
}
