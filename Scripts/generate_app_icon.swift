#!/usr/bin/env swift
// Generates the macOS app icon set (PNGs + Contents.json) and Assets/X11Logo.icns
// from Assets/X11Logo.svg.
//
// The icon is FULL-BLEED: an opaque square with no rounded corners and no transparent margin.
// macOS 26 applies its own rounded mask to the icon (like Claude / System Settings). If the corners
// are baked into the PNG, the system shrinks the artwork onto a plate and a border shows in the Dock.
//
// Usage (from the repository root):
//   swift Scripts/generate_app_icon.swift

import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let svgURL = root.appendingPathComponent("Assets/X11Logo.svg")
let iconSetURL = root.appendingPathComponent("Assets.xcassets/AppIcon.appiconset")
let icnsURL = root.appendingPathComponent("Assets/X11Logo.icns")

// MARK: - Parse the polygon out of the SVG (M x y L x y ... Z)

let svg = try String(contentsOf: svgURL, encoding: .utf8)
guard let dRange = svg.range(of: #"d="([^"]+)""#, options: .regularExpression) else {
    fatalError("No path data found in \(svgURL.path)")
}
let d = String(svg[dRange]).dropFirst(3).dropLast(1)
let numbers = d.split(whereSeparator: { !"0123456789.-".contains($0) }).compactMap { Double($0) }
var points: [CGPoint] = []
var i = 0
while i + 1 < numbers.count {
    points.append(CGPoint(x: numbers[i], y: numbers[i + 1]))
    i += 2
}
guard points.count > 3 else { fatalError("Could not parse SVG path") }

// MARK: - Rendering

func renderIcon(pixels: Int) -> Data {
    let size = CGFloat(pixels)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.clear(CGRect(x: 0, y: 0, width: size, height: size))

    // Full-bleed square: the background covers the ENTIRE canvas (no rounded corners, no transparent margin).
    let body = CGRect(x: 0, y: 0, width: size, height: size)

    // Background gradient (light)
    ctx.saveGState()
    ctx.clip(to: body)
    let colors = [
        NSColor(calibratedWhite: 1.0, alpha: 1).cgColor,
        NSColor(calibratedWhite: 0.86, alpha: 1).cgColor,
    ] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: body.midX, y: body.maxY),
                           end: CGPoint(x: body.midX, y: body.minY),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()

    // Logo: viewBox is 320x320 with y pointing down, so flip.
    // Fit the glyph's real bounding box (not the whole viewBox) into the icon.
    let minX = points.map(\.x).min()!, maxX = points.map(\.x).max()!
    let minY = points.map(\.y).min()!, maxY = points.map(\.y).max()!
    let glyphW = maxX - minX, glyphH = maxY - minY
    let target = body.width * 0.56
    let scale = target / max(glyphW, glyphH)
    let offsetX = body.midX - (minX + glyphW / 2) * scale
    let offsetY = body.midY + (minY + glyphH / 2) * scale
    let logoPath = CGMutablePath()
    for (index, p) in points.enumerated() {
        let pt = CGPoint(x: offsetX + p.x * scale, y: offsetY - p.y * scale)
        if index == 0 { logoPath.move(to: pt) } else { logoPath.addLine(to: pt) }
    }
    logoPath.closeSubpath()
    ctx.addPath(logoPath)
    ctx.setFillColor(NSColor(calibratedWhite: 0.05, alpha: 1).cgColor)
    ctx.fillPath()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// MARK: - Write icon set

try FileManager.default.createDirectory(at: iconSetURL, withIntermediateDirectories: true)

struct Entry { let points: Int; let scale: Int }
let entries: [Entry] = [16, 32, 128, 256, 512].flatMap { [Entry(points: $0, scale: 1), Entry(points: $0, scale: 2)] }

var images: [[String: String]] = []
for e in entries {
    let name = e.scale == 1 ? "AppIcon-\(e.points).png" : "AppIcon-\(e.points)@2x.png"
    try renderIcon(pixels: e.points * e.scale).write(to: iconSetURL.appendingPathComponent(name))
    images.append([
        "filename": name,
        "idiom": "mac",
        "scale": "\(e.scale)x",
        "size": "\(e.points)x\(e.points)",
    ])
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: iconSetURL.appendingPathComponent("Contents.json"))
print("Wrote \(entries.count) PNGs + Contents.json to \(iconSetURL.path)")

// MARK: - Build .icns via iconutil

let tmpSet = FileManager.default.temporaryDirectory.appendingPathComponent("X11Logo.iconset")
try? FileManager.default.removeItem(at: tmpSet)
try FileManager.default.createDirectory(at: tmpSet, withIntermediateDirectories: true)
for e in entries {
    let name = e.scale == 1 ? "icon_\(e.points)x\(e.points).png" : "icon_\(e.points)x\(e.points)@2x.png"
    try renderIcon(pixels: e.points * e.scale).write(to: tmpSet.appendingPathComponent(name))
}
let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", tmpSet.path, "-o", icnsURL.path]
try proc.run()
proc.waitUntilExit()
print(proc.terminationStatus == 0 ? "Wrote \(icnsURL.path)" : "iconutil failed (\(proc.terminationStatus))")
