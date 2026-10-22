#!/usr/bin/env swift
// Renders Jot's app icon (the mark from the website: a dark tile with two lines) into an
// .iconset, full-bleed so macOS 26 applies its own squircle mask instead of placing the
// artwork on a grey plate. Usage: render-app-icon.swift OUTPUT.iconset

import AppKit

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: render-app-icon.swift OUTPUT.iconset\n", stderr)
    exit(1)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.removeItem(at: output)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

/// Draws the icon at `pixels` square. The mark's 24-unit grid maps onto the whole canvas.
func render(pixels: Int) -> Data {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    let size = CGFloat(pixels)
    bitmap.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let unit = size / 24

    // The tile: #2c2c2e at the top to #141415 at the bottom, like the website's mark.
    NSGradient(starting: color(0x2c2c2e), ending: color(0x141415))!
        .draw(in: NSRect(x: 0, y: 0, width: size, height: size), angle: -90)
    // A faint top light, so it sits well next to Apple's glassy icons.
    NSGradient(colors: [color(0xffffff, 0.07), color(0xffffff, 0)])!
        .draw(in: NSRect(x: 0, y: size * 0.55, width: size, height: size * 0.45), angle: -90)

    // Two lines of a note: a full one and a shorter, softer one (y is from the top in the mark).
    func line(from x0: CGFloat, to x1: CGFloat, y: CGFloat, alpha: CGFloat) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: x0 * unit, y: size - y * unit))
        path.line(to: NSPoint(x: x1 * unit, y: size - y * unit))
        path.lineWidth = 1.7 * unit
        path.lineCapStyle = .round
        color(0xffffff, alpha).setStroke()
        path.stroke()
    }
    line(from: 6.75, to: 17.25, y: 9.6, alpha: 0.94)
    line(from: 6.75, to: 12, y: 14.4, alpha: 0.5)

    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        try render(pixels: points * scale).write(to: output.appendingPathComponent(name))
    }
}
