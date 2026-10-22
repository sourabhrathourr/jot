#!/usr/bin/env swift
// Renders the DMG window background (660×400 points) at 1× or 2×, after Hun's "Quiet
// Utility": a warm off-white field, two plates on one axis (Jot.app, then Applications), one
// fine arrow between them in Jot's red, and a few words. Finder's icon labels are dark, so the
// field stays light in both appearances.
// Usage: render-dmg-background.swift OUTPUT.png SCALE(1|2)

import AppKit

let canvasSize = NSSize(width: 660, height: 400)

guard CommandLine.arguments.count == 3,
      let scale = Int(CommandLine.arguments[2]),
      [1, 2].contains(scale)
else {
    fputs("Usage: render-dmg-background.swift OUTPUT.png SCALE(1|2)\n", stderr)
    exit(1)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvasSize.width) * scale,
    pixelsHigh: Int(canvasSize.height) * scale,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!
bitmap.size = canvasSize

guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fputs("Could not create the DMG background graphics context.\n", stderr)
    exit(1)
}

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        calibratedRed: CGFloat((hex >> 16) & 0xff) / 255,
        green: CGFloat((hex >> 8) & 0xff) / 255,
        blue: CGFloat(hex & 0xff) / 255,
        alpha: alpha
    )
}

func drawCentered(_ text: String, y: CGFloat, font: NSFont, foreground: NSColor, tracking: CGFloat = 0) {
    let attributed = NSAttributedString(string: text, attributes: [
        .font: font,
        .foregroundColor: foreground,
        .kern: tracking,
    ])
    let size = attributed.size()
    attributed.draw(at: NSPoint(x: (canvasSize.width - size.width) / 2, y: y))
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphicsContext

let fullRect = NSRect(origin: .zero, size: canvasSize)
color(0xf4f3f1).setFill()
NSBezierPath(rect: fullRect).fill()

// The plates under Jot.app and Applications (icon centres at x 170 and 490, y 170 from the bottom).
for centerX in [CGFloat(170), CGFloat(490)] {
    let plate = NSRect(x: centerX - 82, y: 88, width: 164, height: 164)
    color(0xffffff, alpha: 0.75).setFill()
    NSBezierPath(ovalIn: plate).fill()
    color(0xdcdad6).setStroke()
    let ring = NSBezierPath(ovalIn: plate)
    ring.lineWidth = 1
    ring.stroke()
}

// One fine arrow, in Jot's red.
let red = color(0xe5484d)
let line = NSBezierPath()
line.move(to: NSPoint(x: 272, y: 170))
line.line(to: NSPoint(x: 380, y: 170))
line.lineWidth = 1.25
red.withAlphaComponent(0.55).setStroke()
line.stroke()

let head = NSBezierPath()
head.move(to: NSPoint(x: 380, y: 170))
head.line(to: NSPoint(x: 369, y: 176.5))
head.move(to: NSPoint(x: 380, y: 170))
head.line(to: NSPoint(x: 369, y: 163.5))
head.lineWidth = 1.25
head.lineCapStyle = .round
head.lineJoinStyle = .round
red.setStroke()
head.stroke()

drawCentered("Jot", y: 322, font: NSFont.systemFont(ofSize: 28, weight: .semibold), foreground: color(0x1c1c1e))
drawCentered("DRAG TO INSTALL", y: 298, font: NSFont.systemFont(ofSize: 9, weight: .medium), foreground: color(0x77756f), tracking: 1.6)
drawCentered("Drag Jot into Applications", y: 42, font: NSFont.systemFont(ofSize: 11, weight: .regular), foreground: color(0x7a7872))

color(0xd8d6d1).setStroke()
let border = NSBezierPath(roundedRect: fullRect.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10)
border.lineWidth = 1
border.stroke()

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Could not encode the DMG background PNG.\n", stderr)
    exit(1)
}
try png.write(to: outputURL, options: .atomic)
