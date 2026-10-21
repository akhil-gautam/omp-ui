import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// The mark's geometry comes from BrandGeometry.swift, which is compiled in
// alongside this file so the icon and the title bar can never drift apart.

/// The canvas the icon is drawn on, in points.
let tile = 128.0

/// Where the mark sits on the tile, in points.
let markX = 35.25
let markY = 45.25
let markWidth = 57.5

/// The macOS app icon: a dark tile with the mark in omp's accent.
func drawIcon(pixels: Int) -> CGImage? {
    let scale = Double(pixels) / tile
    let space = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    context.setAllowsAntialiasing(true)
    context.interpolationQuality = .high
    // CoreGraphics counts from the bottom; the art is drawn from the top.
    context.translateBy(x: 0, y: CGFloat(pixels))
    context.scaleBy(x: 1, y: -1)

    let frame = CGRect(x: 4 * scale, y: 4 * scale, width: 120 * scale, height: 120 * scale)
    let corner = 27 * scale
    let path = CGPath(roundedRect: frame, cornerWidth: corner, cornerHeight: corner, transform: nil)

    // The tile: darker at the bottom, the way a raised surface catches light.
    let top = CGColor(red: 0x22 / 255, green: 0x22 / 255, blue: 0x27 / 255, alpha: 1)
    let bottom = CGColor(red: 0x0a / 255, green: 0x0a / 255, blue: 0x0b / 255, alpha: 1)
    if let gradient = CGGradient(colorsSpace: space, colors: [top, bottom] as CFArray, locations: [0, 1]) {
        context.saveGState()
        context.addPath(path)
        context.clip()
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: frame.midX, y: frame.minY),
            end: CGPoint(x: frame.midX, y: frame.maxY),
            options: []
        )
        context.restoreGState()
    }
    context.addPath(path)
    context.setStrokeColor(CGColor(red: 0x33 / 255, green: 0x33 / 255, blue: 0x3a / 255, alpha: 1))
    context.setLineWidth(1.5 * scale)
    context.strokePath()

    // The mark.
    context.setFillColor(CGColor(red: 0xed / 255, green: 0x4f / 255, blue: 0xa6 / 255, alpha: 1))
    let unit = markWidth / BrandGeometry.width
    for bar in BrandGeometry.bars {
        let rect = CGRect(
            x: (markX + bar.x * unit) * scale,
            y: (markY + bar.y * unit) * scale,
            width: bar.width * unit * scale,
            height: bar.height * unit * scale
        )
        context.addPath(
            CGPath(
                roundedRect: rect,
                cornerWidth: bar.radius * unit * scale,
                cornerHeight: bar.radius * unit * scale,
                transform: nil
            )
        )
        context.fillPath()
    }
    return context.makeImage()
}

@main
struct IconRenderer {
    /// The icon set macOS expects, and the pixels each entry holds.
    static let entries: [(name: String, pixels: Int)] = [
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512@2x.png", 1024),
    ]

    static func main() {
        let directory = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
        for entry in entries {
            guard let image = drawIcon(pixels: entry.pixels) else {
                fail("could not draw \(entry.name)")
            }
            let url = URL(fileURLWithPath: directory).appendingPathComponent(entry.name) as CFURL
            guard let destination = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil) else {
                fail("could not open \(entry.name)")
            }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else {
                fail("could not write \(entry.name)")
            }
        }
    }

    static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
        exit(1)
    }
}
