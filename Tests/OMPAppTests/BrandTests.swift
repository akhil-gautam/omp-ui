import AppKit
import SwiftUI
import Testing
@testable import OMPApp

/// The painted pixels of a rendered view.
private struct Ink {
    /// One run of painted pixels in a row.
    struct Run {
        let first: Int
        let last: Int
    }

    let width: Int
    let height: Int
    /// The painted pixels, row by row, top to bottom.
    let rows: [[Run]]
    /// The colour of the ink.
    let colour: NSColor

    /// The painted pixels in a row.
    func runs(in row: Int) -> [Run] { rows[row] }

    /// The bounds of the ink.
    var bounds: (minX: Int, maxX: Int, minY: Int, maxY: Int)? {
        var minX = width, maxX = -1, minY = height, maxY = -1
        for (y, runs) in rows.enumerated() {
            for run in runs {
                minX = min(minX, run.first)
                maxX = max(maxX, run.last)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        return (minX, maxX, minY, maxY)
    }
}

/// Renders a view and reads back what it painted.
@MainActor
private func ink(of view: some View, background: Color = .clear) throws -> Ink {
    let renderer = ImageRenderer(content: view.background(background))
    renderer.scale = 4
    let image = try #require(renderer.nsImage)
    let cg = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
    let rep = try #require(NSBitmapImageRep(cgImage: cg))
    let width = rep.pixelsWide
    let height = rep.pixelsHigh

    var rows: [[Ink.Run]] = []
    var colour = NSColor.white
    for y in 0..<height {
        var runs: [Ink.Run] = []
        var start: Int?
        for x in 0..<width {
            guard let raw = rep.colorAt(x: x, y: y), let pixel = raw.usingColorSpace(.sRGB) else { continue }
            let painted = pixel.alphaComponent > 0.9
            if painted, colour == .white { colour = pixel }
            if painted, start == nil {
                start = x
            } else if !painted, let first = start {
                runs.append(Ink.Run(first: first, last: x - 1))
                start = nil
            }
        }
        if let first = start { runs.append(Ink.Run(first: first, last: width - 1)) }
        rows.append(runs)
    }
    return Ink(width: width, height: height, rows: rows, colour: colour)
}

@Suite("The mark")
struct BrandTests {
    @Test("the mark is one bar over two stems")
    @MainActor
    func theMarkIsATwin() throws {
        let palette = Theme.palette(named: "Void")
        let drawn = try ink(of: BrandMark(width: 46).environment(\.palette, palette))
        let bounds = try #require(drawn.bounds)

        // The mark is 46 wide and 30 tall.
        let ratio = Double(bounds.maxX - bounds.minX + 1) / Double(bounds.maxY - bounds.minY + 1)
        #expect(abs(ratio - BrandGeometry.width / BrandGeometry.height) < 0.05)

        // The bar is a single run at the top, and the stems are two runs below.
        let top = bounds.minY
        #expect(drawn.runs(in: top).count == 1)
        let bottom = bounds.maxY
        #expect(drawn.runs(in: bottom).count == 2)
        // And the two stems are the same width.
        let stems = drawn.runs(in: bottom)
        #expect(stems[0].last - stems[0].first == stems[1].last - stems[1].first)
    }

    @Test("the mark is drawn in the theme's accent")
    @MainActor
    func theMarkTakesTheAccent() throws {
        let palette = Theme.palette(named: "Arctic")
        let drawn = try ink(of: BrandMark(width: 46).environment(\.palette, palette))
        let swatch = try ink(of: Rectangle().fill(palette.accent).frame(width: 8, height: 8))

        #expect(drawn.bounds != nil)
        #expect(abs(drawn.colour.redComponent - swatch.colour.redComponent) < 0.02)
        #expect(abs(drawn.colour.greenComponent - swatch.colour.greenComponent) < 0.02)
        #expect(abs(drawn.colour.blueComponent - swatch.colour.blueComponent) < 0.02)
    }
}
