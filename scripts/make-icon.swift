// Regenerates AppIcon.appiconset: xcrun swift scripts/make-icon.swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let outDir = "WoofWoofCPU/Resources/Assets.xcassets/AppIcon.appiconset"
let rgb = CGColorSpaceCreateDeviceRGB()

// Copy of PixelArt.proud (WoofWoofCPU/Skins/PixelArt.swift), not shared code: '#' body, 'o' eye, 'p' tongue.
let proud = [
    "#.................",
    ".#..........#.#...",
    "..#........#####..",
    "..#........#o####.",
    "...#.......####p..",
    "...#.......###.p..",
    "....#.....####....",
    ".....#...#####....",
    "......#.######....",
    ".......#######....",
    "....##########....",
    "........#..#.#....",
]

func hex(_ v: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: a)
}

func color(_ c: Character) -> CGColor? {
    switch c {
    case "#": return hex(0xffe9c4)
    case "o": return hex(0x0b3640)
    case "p": return hex(0xff2d55)
    default: return nil
    }
}

func render(_ px: Int) -> CGImage {
    let s = CGFloat(px)
    let small = px <= 64
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: rgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // macOS icon grid: 824/1024 body with ~22.4% corner radius.
    let body = CGRect(x: s * 0.0977, y: s * 0.0977, width: s * 0.8047, height: s * 0.8047)
    let path = CGPath(roundedRect: body, cornerWidth: body.width * 0.225, cornerHeight: body.width * 0.225, transform: nil)

    if !small {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.025, color: hex(0x000000, 0.35))
        ctx.addPath(path)
        ctx.setFillColor(hex(0x1a6f78))
        ctx.fillPath()
        ctx.restoreGState()
    }

    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let teal = CGGradient(colorsSpace: rgb, colors: [hex(0x2f8f95), hex(0x0f4f5c)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(teal, start: CGPoint(x: s / 2, y: body.maxY), end: CGPoint(x: s / 2, y: body.minY), options: [])
    let glow = CGGradient(colorsSpace: rgb, colors: [hex(0xffffff, 0.16), hex(0xffffff, 0)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(glow, start: CGPoint(x: s / 2, y: body.maxY), end: CGPoint(x: s / 2, y: body.midY + body.height * 0.1), options: [])
    ctx.restoreGState()

    // At 16 px the whole sprite doesn't fit the tile, so the tail and back-strip columns are dropped.
    let cropFrom = px <= 16 ? 7 : 0
    let rows = proud.count
    var minC = 99, maxC = 0, minR = 99, maxR = 0
    for (r, row) in proud.enumerated() { for (c, ch) in row.enumerated() where ch != "." && c >= cropFrom {
        minC = min(minC, c); maxC = max(maxC, c); minR = min(minR, r); maxR = max(maxR, r)
    } }
    let w = maxC - minC + 1, h = maxR - minR + 1
    let cell = max(1, Int((body.width * (small ? 0.80 : 0.74) / CGFloat(w)).rounded(.down)))
    // Whole-pixel cells and origin, antialiasing off, so every size stays crisp.
    let ox = Int((body.midX - CGFloat(w * cell) / 2).rounded()) - minC * cell
    let oy = Int((body.midY - CGFloat(h * cell) / 2).rounded()) - (rows - 1 - maxR) * cell
    ctx.setShouldAntialias(false)
    for (r, row) in proud.enumerated() { for (c, ch) in row.enumerated() where c >= cropFrom {
        guard let col = color(ch) else { continue }
        ctx.setFillColor(col)
        ctx.fill(CGRect(x: ox + c * cell, y: oy + (rows - 1 - r) * cell, width: cell, height: cell))
    } }
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
