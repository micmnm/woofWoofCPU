// Regenerates AppIcon.appiconset: xcrun swift scripts/make-icon.swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Mirrors PixelArt.nap (WoofWoofCPU/Skins/PixelArt.swift).
let nap = [
    "..............#.#.",
    "...............#..",
    "..................",
    "..................",
    "..................",
    "............##....",
    "...........####...",
    "..#........#####..",
    ".##.....########..",
    ".##############...",
    "..#############...",
    "..................",
]

let outDir = "WoofWoofCPU/Resources/Assets.xcassets/AppIcon.appiconset"
let rgb = CGColorSpaceCreateDeviceRGB()

func render(_ px: Int) -> CGImage {
    let s = CGFloat(px)
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: rgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // macOS icon grid: 824/1024 body with ~22.4% corner radius.
    let body = CGRect(x: s * 0.0977, y: s * 0.0977, width: s * 0.8047, height: s * 0.8047)
    let path = CGPath(roundedRect: body, cornerWidth: body.width * 0.225, cornerHeight: body.width * 0.225, transform: nil)
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let colors = [CGColor(red: 1.0, green: 0.93, blue: 0.80, alpha: 1), CGColor(red: 0.98, green: 0.62, blue: 0.28, alpha: 1)]
    let gradient = CGGradient(colorsSpace: rgb, colors: colors as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: s / 2, y: body.maxY), end: CGPoint(x: s / 2, y: body.minY), options: [])
    ctx.restoreGState()

    // Sprite: 18x12 cells, crisp, centred.
    let cell = body.width * 0.78 / 18
    let origin = CGPoint(x: body.midX - cell * 9, y: body.midY - cell * 6)
    ctx.setShouldAntialias(false)
    ctx.setFillColor(CGColor(red: 0.20, green: 0.12, blue: 0.08, alpha: 1))
    for (row, line) in nap.enumerated() {
        for (col, ch) in line.enumerated() where ch == "#" {
            let x0 = (origin.x + cell * CGFloat(col)).rounded()
            let x1 = (origin.x + cell * CGFloat(col + 1)).rounded()
            let y0 = (origin.y + cell * CGFloat(11 - row)).rounded()
            let y1 = (origin.y + cell * CGFloat(12 - row)).rounded()
            ctx.fill(CGRect(x: x0, y: y0, width: max(1, x1 - x0), height: max(1, y1 - y0)))
        }
    }
    return ctx.makeImage()!
}

func write(_ image: CGImage, to name: String) {
    let url = URL(fileURLWithPath: "\(outDir)/\(name)") as CFURL
    let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    precondition(CGImageDestinationFinalize(dest))
}

try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
var entries: [String] = []
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"
        write(render(base * scale), to: name)
        entries.append(#"    {"idiom":"mac","size":"\#(base)x\#(base)","scale":"\#(scale)x","filename":"\#(name)"}"#)
    }
}
let contents = "{\n  \"images\":[\n\(entries.joined(separator: ",\n"))\n  ],\n  \"info\":{\"version\":1,\"author\":\"xcode\"}\n}\n"
try contents.write(toFile: "\(outDir)/Contents.json", atomically: true, encoding: .utf8)
