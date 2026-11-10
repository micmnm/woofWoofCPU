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
    /// Hard-edged art that must be scaled without interpolation.
    var isPixelArt: Bool { get }
    /// Bundled sound resource name (without extension); falls back to a system sound if missing.
    var barkSoundName: String { get }
    /// Breed-specific lines added to the CPU and memory bark banks.
    var extraBarkLines: [String] { get }
}

extension Skin {
    /// Fits `image` in `box`; pixel art snaps down to a whole-number multiple so no cell is dropped.
    func displaySize(of image: NSImage, fitting box: CGSize) -> CGSize {
        let fit = min(box.width / image.size.width, box.height / image.size.height)
        let scale = isPixelArt && fit >= 1 ? fit.rounded(.down) : fit
        return CGSize(width: image.size.width * scale, height: image.size.height * scale)
    }

    var iconArt: NSImage { portrait(for: .napping) }
    var extraBarkLines: [String] { [] }
}

@MainActor
enum SkinRegistry {
    // PixelSymbolSkin and ShibaSkin are kept but hidden; a saved hidden id falls back to Classic.
    static let all: [any Skin] = [SymbolSkin(), PixelSkin()]

    static func skin(id: String) -> any Skin {
        all.first { $0.id == id } ?? all[0]
    }
}
