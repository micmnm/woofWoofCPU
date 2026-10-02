import AppKit
import SwiftUI
import WoofCore

/// Full-color cartoon head drawn with SwiftUI and rasterized once per mood/frame.
@MainActor
final class ShibaSkin: Skin {
    let id = "shiba"
    let displayName = "Shiba"
    let barkSoundName = "bark-shiba"
    let isPixelArt = false

    private var frameCache: [DogMood: [NSImage]] = [:]
    private var portraitCache: [DogMood: NSImage] = [:]

    func frames(for mood: DogMood) -> [NSImage] {
        if let cached = frameCache[mood] { return cached }
        let count = mood == .barking ? 2 : 1
        let images = (0..<count).map { Self.render(mood: mood, frame: $0, side: 18) }
        frameCache[mood] = images
        return images
    }

    func frameDuration(for mood: DogMood) -> TimeInterval {
        mood == .barking ? 0.25 : 0.6
    }

    func portrait(for mood: DogMood) -> NSImage {
        if let cached = portraitCache[mood] { return cached }
        let image = Self.render(mood: mood, frame: 0, side: 56)
        portraitCache[mood] = image
        return image
    }

    static func render(mood: DogMood, frame: Int, side: CGFloat) -> NSImage {
        let renderer = ImageRenderer(content: ShibaHead(mood: mood, frame: frame).frame(width: side, height: side))
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage(size: NSSize(width: side, height: side))
        image.isTemplate = false
        return image
    }
}

/// Geometry lives in a 24×24 box (same as the brainstorm mockup SVG).
struct ShibaHead: View {
    let mood: DogMood
    let frame: Int

    private static let fur = Color(red: 0.91, green: 0.59, blue: 0.23)
    private static let earFur = Color(red: 0.72, green: 0.39, blue: 0.12)
    private static let cream = Color(red: 1.0, green: 0.95, blue: 0.86)
    private static let ink = Color(red: 0.23, green: 0.14, blue: 0.08)
    private static let tongue = Color(red: 1.0, green: 0.48, blue: 0.56)

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 24
            context.scaleBy(x: scale, y: scale)
            if mood == .sniffing {
                context.translateBy(x: 12, y: 13)
                context.rotate(by: .degrees(-12))
                context.translateBy(x: -12, y: -13)
            }
            drawEars(&context)
            let head = Path(ellipseIn: CGRect(x: 5.5, y: 7.5, width: 13, height: 12))
            context.fill(head, with: .color(Self.fur))
            context.stroke(head, with: .color(Self.ink), lineWidth: 0.9)
            for rect in [CGRect(x: 8.3, y: 13.9, width: 7.4, height: 5.4),
                         CGRect(x: 6.4, y: 14.1, width: 3.2, height: 2.2),
                         CGRect(x: 14.4, y: 14.1, width: 3.2, height: 2.2)] {
                context.fill(Path(ellipseIn: rect), with: .color(Self.cream))
            }
            drawEyes(&context)
            context.fill(Path(ellipseIn: CGRect(x: 10.6, y: 14.4, width: 2.8, height: 2)), with: .color(Self.ink))
            drawMouth(&context)
            drawExtras(&context)
        }
    }

    private enum EarPose { case up, flop }

    private func ear(_ pose: EarPose, mirrored: Bool) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: mirrored ? 24 - x : x, y: y) }
        var path = Path()
        switch pose {
        case .up:
            path.move(to: p(6.4, 10.6))
            path.addCurve(to: p(5.8, 3), control1: p(4, 7.6), control2: p(4.2, 3.6))
            path.addCurve(to: p(10.8, 8.2), control1: p(7.8, 3.4), control2: p(10, 5.8))
        case .flop:
            path.move(to: p(7, 9.2))
            path.addCurve(to: p(2.8, 16.6), control1: p(4, 8.6), control2: p(1.8, 11.5))
            path.addCurve(to: p(6.4, 12), control1: p(4.8, 16.4), control2: p(6, 14))
        }
        path.closeSubpath()
        return path
    }

    private func drawEars(_ context: inout GraphicsContext) {
        let (left, right): (EarPose, EarPose) = switch mood {
        case .napping, .sulking: (.flop, .flop)
        case .sniffing: (.up, .flop)
        case .growling, .barking, .proud: (.up, .up)
        }
        for path in [ear(left, mirrored: false), ear(right, mirrored: true)] {
            context.fill(path, with: .color(Self.earFur))
            context.stroke(path, with: .color(Self.ink), lineWidth: 0.8)
        }
    }

    private func line(_ points: [CGPoint]) -> Path {
        var path = Path()
        path.addLines(points)
        return path
    }

    private func stroke(_ context: inout GraphicsContext, _ path: Path) {
        context.stroke(path, with: .color(Self.ink), style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
    }

    private func drawEyes(_ context: inout GraphicsContext) {
        switch mood {
        case .napping:
            for x in [9.4, 14.6] {
                var arc = Path()
                arc.move(to: CGPoint(x: x - 1.2, y: 12.6))
                arc.addQuadCurve(to: CGPoint(x: x + 1.2, y: 12.6), control: CGPoint(x: x, y: 13.7))
                stroke(&context, arc)
            }
        case .proud:
            for x in [9.4, 14.6] {
                stroke(&context, line([CGPoint(x: x - 1.2, y: 13), CGPoint(x: x, y: 11.8), CGPoint(x: x + 1.2, y: 13)]))
            }
        case .sulking:
            for x in [9.4, 14.6] {
                stroke(&context, line([CGPoint(x: x - 1.2, y: 12.2), CGPoint(x: x + 1.2, y: 12.2)]))
                context.fill(Path(ellipseIn: CGRect(x: x - 0.2, y: 12.1, width: 1.6, height: 1.6)), with: .color(Self.ink))
            }
        default:
            for x in [9.4, 14.6] {
                context.fill(Path(ellipseIn: CGRect(x: x - 1.1, y: 11.3, width: 2.2, height: 2.2)), with: .color(Self.ink))
            }
        }
        if mood == .growling || mood == .barking {
            stroke(&context, line([CGPoint(x: 7.8, y: 10.2), CGPoint(x: 10.6, y: 11.2)]))
            stroke(&context, line([CGPoint(x: 16.2, y: 10.2), CGPoint(x: 13.4, y: 11.2)]))
        }
    }

    private func drawMouth(_ context: inout GraphicsContext) {
        let teeth = line([9.6, 10.4, 11.2, 12, 12.8, 13.6, 14.4].enumerated().map { index, x in
            CGPoint(x: x, y: index.isMultiple(of: 2) ? 18 : 17.1)
        })
        var smile = Path()
        smile.move(to: CGPoint(x: 10.6, y: 17.3))
        smile.addQuadCurve(to: CGPoint(x: 13.4, y: 17.3), control: CGPoint(x: 12, y: 18.3))

        switch mood {
        case .napping, .sniffing:
            stroke(&context, smile)
        case .sulking:
            stroke(&context, line([CGPoint(x: 10.6, y: 17.9), CGPoint(x: 13.4, y: 17.4)]))
        case .growling:
            stroke(&context, teeth)
        case .proud:
            stroke(&context, smile)
            var tongue = Path()
            tongue.move(to: CGPoint(x: 11.2, y: 17.7))
            tongue.addQuadCurve(to: CGPoint(x: 12.8, y: 17.7), control: CGPoint(x: 12, y: 20.6))
            context.fill(tongue, with: .color(Self.tongue))
        case .barking:
            if frame == 0 {
                context.fill(Path(ellipseIn: CGRect(x: 10.1, y: 16.6, width: 3.8, height: 2.8)), with: .color(Self.ink))
                var waves = Path()
                waves.move(to: CGPoint(x: 19.6, y: 12.5))
                waves.addQuadCurve(to: CGPoint(x: 19.6, y: 17.5), control: CGPoint(x: 21, y: 15))
                waves.move(to: CGPoint(x: 21.4, y: 11))
                waves.addQuadCurve(to: CGPoint(x: 21.4, y: 19), control: CGPoint(x: 23.4, y: 15))
                context.stroke(waves, with: .color(.red), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
            } else {
                stroke(&context, teeth)
            }
        }
    }

    private func drawExtras(_ context: inout GraphicsContext) {
        switch mood {
        case .napping:
            context.draw(Text("z").font(.system(size: 5, weight: .bold)).foregroundStyle(Self.ink), at: CGPoint(x: 19.5, y: 4.5))
        case .sniffing:
            context.draw(Text("?").font(.system(size: 6, weight: .bold)).foregroundStyle(Self.ink), at: CGPoint(x: 20, y: 4.5))
        default:
            break
        }
    }
}
