// Regenerates AppIcon.appiconset: xcrun swift scripts/make-icon.swift
import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

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

    // The Symbol dog skin's plain pose (WoofWoofCPU/Skins/SymbolDog.swift), centred.
    let config = NSImage.SymbolConfiguration(pointSize: body.width * 0.5, weight: .semibold)
    let dog = NSImage(systemSymbolName: "dog.fill", accessibilityDescription: nil)!.withSymbolConfiguration(config)!
    let rect = CGRect(x: body.midX - dog.size.width / 2, y: body.midY - dog.size.height / 2,
                      width: dog.size.width, height: dog.size.height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    ctx.beginTransparencyLayer(in: rect, auxiliaryInfo: nil)
    dog.draw(in: rect)
    NSColor(red: 0.165, green: 0.102, blue: 0.063, alpha: 1).set()
    rect.fill(using: .sourceAtop)
    ctx.endTransparencyLayer()
    NSGraphicsContext.restoreGraphicsState()
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
