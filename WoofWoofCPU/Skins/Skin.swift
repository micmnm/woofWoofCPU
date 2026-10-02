import AppKit
import WoofCore

/// A dog look: menu bar frames per mood, a large portrait for the popover, and a bark sound.
@MainActor
protocol Skin: AnyObject {
    var id: String { get }
    var displayName: String { get }
    /// Menu bar frames, cycled by `DogAnimator`.
    func frames(for mood: DogMood) -> [NSImage]
    func frameDuration(for mood: DogMood) -> TimeInterval
    /// Large art for the popover header and the Settings preview.
    func portrait(for mood: DogMood) -> NSImage
    /// Art composed onto the app icon background.
    var iconArt: NSImage { get }
    /// Bundled sound resource name (without extension); falls back to a system sound if missing.
    var barkSoundName: String { get }
}

extension Skin {
    var iconArt: NSImage { portrait(for: .napping) }
}

@MainActor
enum SkinRegistry {
    static let all: [any Skin] = [SymbolSkin(), PixelSymbolSkin(), PixelSkin(), ShibaSkin()]

    static func skin(id: String) -> any Skin {
        all.first { $0.id == id } ?? all[0]
    }
}
