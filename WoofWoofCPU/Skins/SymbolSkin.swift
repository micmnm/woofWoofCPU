import AppKit
import WoofCore

/// Smooth SF Symbols dog with a mood badge; template frames unless a mood has a coloured part.
@MainActor
final class SymbolSkin: Skin {
    let id = "symbol"
    let displayName = "Symbol dog"
    let barkSoundName = "bark-pixel"
    let isPixelArt = false

    private var frameCache: [DogMood: [NSImage]] = [:]
    private var portraitCache: [DogMood: NSImage] = [:]

    func frames(for mood: DogMood) -> [NSImage] {
        if let cached = frameCache[mood] { return cached }
        let images = SymbolDog.poses(for: mood).map { Self.render($0, zoom: 1, template: !$0.isColored) }
        frameCache[mood] = images
        return images
    }

    func frameDuration(for mood: DogMood) -> TimeInterval {
        SymbolDog.frameDuration(for: mood)
    }

    func portrait(for mood: DogMood) -> NSImage {
        if let cached = portraitCache[mood] { return cached }
        let image = Self.render(SymbolDog.poses(for: mood)[0], zoom: 3, template: false)
        portraitCache[mood] = image
        return image
    }

    /// Drawn on demand so `labelColor` resolves against the menu bar's appearance.
    static func render(_ pose: SymbolDog.Pose, zoom: CGFloat, template: Bool) -> NSImage {
        let size = NSSize(width: SymbolDog.slot.width * zoom, height: SymbolDog.slot.height * zoom)
        let resolved = SymbolDog.resolve(pose, zoom: zoom)
        let image = NSImage(size: size, flipped: true) { _ in
            resolved.draw(at: .zero, ink: template ? .black : .labelColor)
            return true
        }
        image.isTemplate = template
        return image
    }
}
