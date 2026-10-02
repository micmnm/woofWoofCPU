import AppKit
import WoofCore

/// The symbol dog snapped to a 54×36 grid: one cell per Retina pixel in a 27×18-pt slot.
@MainActor
final class PixelSymbolSkin: Skin {
    let id = "symbolPixel"
    let displayName = "Pixel symbol dog"
    let barkSoundName = "bark-pixel"

    static let gridWidth = 54
    static let gridHeight = 36

    enum Paint: CaseIterable {
        case ink, red, orange, pink

        /// sRGB reference used to snap anti-aliased colours.
        var reference: (r: Double, g: Double, b: Double) {
            switch self {
            case .ink: (0, 0, 0)
            case .red: (1, 0.231, 0.188)
            case .orange: (1, 0.584, 0)
            case .pink: (1, 0.176, 0.333)
            }
        }

        func color(ink: NSColor) -> NSColor {
            switch self {
            case .ink: ink
            case .red: .systemRed
            case .orange: .systemOrange
            case .pink: .systemPink
            }
        }
    }

    /// Row-major from the top-left; nil is an empty cell.
    typealias Cells = [Paint?]

    private var frameCache: [DogMood: [NSImage]] = [:]
    private var portraitCache: [DogMood: NSImage] = [:]

    func frames(for mood: DogMood) -> [NSImage] {
        if let cached = frameCache[mood] { return cached }
        let images = SymbolDog.poses(for: mood).map { Self.render(Self.cells(for: $0), cell: 0.5, allowTemplate: true) }
        frameCache[mood] = images
        return images
    }

    func frameDuration(for mood: DogMood) -> TimeInterval {
        SymbolDog.frameDuration(for: mood)
    }

    func portrait(for mood: DogMood) -> NSImage {
        if let cached = portraitCache[mood] { return cached }
        let image = Self.render(Self.cells(for: SymbolDog.poses(for: mood)[0]), cell: 2, allowTemplate: false)
        portraitCache[mood] = image
        return image
    }

    var iconArt: NSImage {
        Self.render(Self.cells(for: SymbolDog.Pose()), cell: 2, allowTemplate: false)
    }

    /// Rasterizes the composition (inset 1.5 pt in the 27-pt slot) and keeps cells at least 42% opaque.
    static func cells(for pose: SymbolDog.Pose) -> Cells {
        let width = gridWidth, height = gridHeight
        let zoom = CGFloat(width) / 27
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32
        ), let context = NSGraphicsContext(bitmapImageRep: rep), let data = rep.bitmapData else { return [] }
        let composed = NSImage(size: NSSize(width: width, height: height), flipped: true) { _ in
            SymbolDog.draw(pose, at: NSPoint(x: 1.5 * zoom, y: 0), zoom: zoom, ink: .black)
            return true
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        composed.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()

        // Premultiplied RGBA, top row first.
        return (0..<width * height).map { index in
            let alpha = Double(data[index * 4 + 3]) / 255
            guard alpha >= 0.42 else { return nil }
            let red = Double(data[index * 4]) / 255 / alpha
            let green = Double(data[index * 4 + 1]) / 255 / alpha
            let blue = Double(data[index * 4 + 2]) / 255 / alpha
            return Paint.allCases.min { lhs, rhs in
                distance(lhs.reference, red, green, blue) < distance(rhs.reference, red, green, blue)
            }
        }
    }

    private static func distance(_ reference: (r: Double, g: Double, b: Double), _ red: Double, _ green: Double, _ blue: Double) -> Double {
        let dr = reference.r - red, dg = reference.g - green, db = reference.b - blue
        return dr * dr + dg * dg + db * db
    }

    /// Template when every cell is ink (and `allowTemplate`); otherwise ink follows `labelColor`.
    static func render(_ cells: Cells, cell: CGFloat, allowTemplate: Bool) -> NSImage {
        let template = allowTemplate && cells.allSatisfy { $0 == nil || $0 == .ink }
        let ink: NSColor = template ? .black : .labelColor
        let size = NSSize(width: CGFloat(gridWidth) * cell, height: CGFloat(gridHeight) * cell)
        let image = NSImage(size: size, flipped: true) { _ in
            for (index, paint) in cells.enumerated() {
                guard let paint else { continue }
                paint.color(ink: ink).setFill()
                let x = CGFloat(index % gridWidth) * cell
                let y = CGFloat(index / gridWidth) * cell
                NSRect(x: x, y: y, width: cell, height: cell).fill()
            }
            return true
        }
        image.isTemplate = template
        return image
    }
}
