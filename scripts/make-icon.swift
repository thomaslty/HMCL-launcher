#!/usr/bin/env swift
// Draws Resources/AppIcon.icns — an original isometric block, not a Mojang asset.
// Run: swift scripts/make-icon.swift

import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appending(path: "build/AppIcon.iconset")
let output = root.appending(path: "Resources/AppIcon.icns")

func srgb(_ r: Int, _ g: Int, _ b: Int) -> NSColor {
    NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
}

// Same moss family as the Start button, three faces so the block reads as solid.
let backdropTop = srgb(28, 38, 48)
let backdropBottom = srgb(14, 20, 26)
let faceTop = srgb(74, 176, 120)
let faceLeft = srgb(31, 111, 74)
let faceRight = srgb(45, 138, 92)

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let pixels = Int(size)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // macOS icon grid: the artwork sits inset with a continuous-corner square.
    let inset = size * 0.086
    let plate = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = plate.width * 0.2237
    let backdrop = NSBezierPath(roundedRect: plate, xRadius: radius, yRadius: radius)
    NSGradient(starting: backdropTop, ending: backdropBottom)?.draw(in: backdrop, angle: -90)

    let cx = size / 2
    let cy = size * 0.52
    let w = size * 0.27       // half width of the block
    let top = size * 0.27     // height of the top diamond
    let side = size * 0.23    // depth of the vertical faces

    func polygon(_ points: [CGPoint], _ color: NSColor) {
        let path = NSBezierPath()
        path.move(to: points[0])
        for point in points.dropFirst() { path.line(to: point) }
        path.close()
        color.setFill()
        path.fill()
    }

    let apex = CGPoint(x: cx, y: cy + top)
    let right = CGPoint(x: cx + w, y: cy + top / 2)
    let middle = CGPoint(x: cx, y: cy)
    let left = CGPoint(x: cx - w, y: cy + top / 2)

    polygon([apex, right, middle, left], faceTop)
    polygon([
        left, middle,
        CGPoint(x: cx, y: cy - side),
        CGPoint(x: cx - w, y: cy + top / 2 - side),
    ], faceLeft)
    polygon([
        right, middle,
        CGPoint(x: cx, y: cy - side),
        CGPoint(x: cx + w, y: cy + top / 2 - side),
    ], faceRight)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

// The sizes iconutil expects.
let variants: [(name: String, pixels: CGFloat)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

for variant in variants {
    let rep = drawIcon(size: variant.pixels)
    guard let png = rep.representation(using: .png, properties: [:]) else { continue }
    try png.write(to: iconset.appending(path: variant.name))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()

guard iconutil.terminationStatus == 0 else {
    FileHandle.standardError.write(Data("iconutil failed\n".utf8))
    exit(1)
}
print("wrote \(output.path)")
