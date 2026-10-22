#!/usr/bin/env swift
// Renders the link preview's backdrop (1200×630): a warm off-white with two balls in Jot's red
// (#ff6363), each shaded like a lit sphere, plus a blurred copy that shows through the window's
// frosted glass.
// Usage: swift scripts/render-og-backdrop.swift assets/og

import AppKit
import CoreImage

let size = CGSize(width: 1200, height: 630)
let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "assets/og")
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: 1)
}

let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
color(0xf3f2ef).setFill()
NSRect(origin: .zero, size: size).fill()
// A sphere: a soft highlight up and to the left, Jot's red through the middle, a deeper red
// at the rim. AppKit's y runs up: one top right, one bottom left, each half under the window.
let sphere = NSGradient(colors: [color(0xf27a72), color(0xe5484d), color(0xb3333a)], atLocations: [0, 0.55, 1], colorSpace: .sRGB)!
// Each ball is shifted (not enlarged) so it covers its corner of the canvas completely: no sliver
// of background between the ball and the corner, which platforms round and crop.
for rect in [NSRect(x: 830, y: 360, width: 400, height: 400), NSRect(x: -15, y: -185, width: 330, height: 330)] {
    sphere.draw(in: NSBezierPath(ovalIn: rect), relativeCenterPosition: NSPoint(x: -0.35, y: 0.38))
}
NSGraphicsContext.restoreGraphicsState()

let sharp = bitmap.representation(using: .png, properties: [:])!
try sharp.write(to: outputDirectory.appendingPathComponent("backdrop.png"))

// The frosted copy: a wide Gaussian blur, clamped so the edges don't darken.
let input = CIImage(data: sharp)!
let blurred = input.clampedToExtent()
    .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 48])
    .cropped(to: input.extent)
let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
let png = context.pngRepresentation(of: blurred, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)!
try png.write(to: outputDirectory.appendingPathComponent("backdrop-frosted.png"))
print("Wrote backdrop.png and backdrop-frosted.png to \(outputDirectory.path)")
