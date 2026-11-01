import AppKit
import WoofCore

/// The symbol dog snapped to a 54×36 grid (one cell per Retina pixel in a 27×18-pt slot), plus a 27×18 grid for 1× screens.
@MainActor
final class PixelSymbolSkin: Skin {
    let id = "symbolPixel"
    let displayName = "8-bit classic"
    let barkSoundName = "bark-pixel"
    let isPixelArt = true
    let extraBarkLines = ["{app} TOOK {value}. GAME OVER?", "WARNING: {app} AT {value}."]

    /// Grid widths; heights are two thirds of these.
    static let fineGrid = 54
    static let coarseGrid = 27

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
        let images = SymbolDog.poses(for: mood).map(Self.frame)
        frameCache[mood] = images
        return images
    }

    func frameDuration(for mood: DogMood) -> TimeInterval {
        SymbolDog.frameDuration(for: mood)
    }

    func portrait(for mood: DogMood) -> NSImage {
        if let cached = portraitCache[mood] { return cached }
        let image = Self.portrait(Self.cells(for: SymbolDog.poses(for: mood)[0], grid: Self.fineGrid))
        portraitCache[mood] = image
        return image
    }

    var iconArt: NSImage {
        Self.portrait(Self.cells(for: SymbolDog.Pose(), grid: Self.fineGrid))
    }

    /// Rasterizes the composition (inset 1.5 pt in the 27-pt slot, sRGB bitmap) and keeps cells at least 42% opaque.
    static func cells(for pose: SymbolDog.Pose, grid width: Int) -> Cells {
        let height = width * 2 / 3
        let zoom = CGFloat(width) / 27
        guard let blank = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32
        ), let rep = blank.retagging(with: .sRGB),
            let context = NSGraphicsContext(bitmapImageRep: rep), let data = rep.bitmapData else { return [] }
        let resolved = SymbolDog.resolve(pose, zoom: zoom)
        let composed = NSImage(size: NSSize(width: width, height: height), flipped: true) { _ in
            resolved.draw(at: NSPoint(x: 1.5 * zoom, y: 0), ink: .black)
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

    /// AppKit picks the rep whose pixel size matches the screen, so each grid lands on whole device pixels.
    static func frame(_ pose: SymbolDog.Pose) -> NSImage {
        let coarse = cells(for: pose, grid: coarseGrid)
        let fine = cells(for: pose, grid: fineGrid)
        let template = isInkOnly(coarse) && isInkOnly(fine)
        let image = NSImage(size: NSSize(width: 27, height: 18))
        for (cells, grid) in [(coarse, coarseGrid), (fine, fineGrid)] {
            let representation = rep(cells, grid: grid, cell: 27 / CGFloat(grid), template: template)
            representation.pixelsWide = grid
            representation.pixelsHigh = grid * 2 / 3
            image.addRepresentation(representation)
        }
        image.isTemplate = template
        return image
    }

    /// 1-pt cells from the fine grid (54×36 pt): whole device pixels at 1× and 2× with full badge detail; never a template.
    static func portrait(_ cells: Cells) -> NSImage {
        let representation = rep(cells, grid: fineGrid, cell: 1, template: false)
        let image = NSImage(size: representation.size)
        image.addRepresentation(representation)
        return image
    }

    private static func isInkOnly(_ cells: Cells) -> Bool {
        cells.allSatisfy { $0 == nil || $0 == .ink }
    }

    /// Drawn on demand so non-template ink follows `labelColor`.
    private static func rep(_ cells: Cells, grid: Int, cell: CGFloat, template: Bool) -> NSImageRep {
        let ink: NSColor = template ? .black : .labelColor
        let rows = grid * 2 / 3
        return NSCustomImageRep(size: NSSize(width: CGFloat(grid) * cell, height: CGFloat(rows) * cell), flipped: true) { _ in
            for (index, paint) in cells.enumerated() {
                guard let paint else { continue }
                paint.color(ink: ink).setFill()
                NSRect(x: CGFloat(index % grid) * cell, y: CGFloat(index / grid) * cell, width: cell, height: cell).fill()
            }
            return true
        }
    }
}
