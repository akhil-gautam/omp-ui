import AppKit
import SwiftUI
import Testing
@testable import OMPApp

/// The colour as numbers, so a test can compare it.
private func rgb(_ color: Color) throws -> RGB {
    let colour = try #require(NSColor(color).usingColorSpace(.sRGB))
    return RGB(red: colour.redComponent, green: colour.greenComponent, blue: colour.blueComponent)
}

/// How different two colours look: CIE76 ΔE in CIELAB, where about 2 is
/// just noticeable and 50 is a different colour altogether.
private func difference(_ a: RGB, _ b: RGB) -> Double {
    func lab(_ colour: RGB) -> (Double, Double, Double) {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let (r, g, b) = (linear(colour.red), linear(colour.green), linear(colour.blue))
        let x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
        let y = 0.2126 * r + 0.7152 * g + 0.0722 * b
        let z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
        func f(_ t: Double) -> Double { t > 0.008856 ? cbrt(t) : 7.787 * t + 16 / 116 }
        return (116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z)))
    }
    let (p, q) = (lab(a), lab(b))
    return ((p.0 - q.0) * (p.0 - q.0) + (p.1 - q.1) * (p.1 - q.1) + (p.2 - q.2) * (p.2 - q.2)).squareRoot()
}

@Suite("The themes")
struct ThemeTests {
    @Test("there are twenty themes, ten light and ten dark, and no two share a name")
    func twentyThemes() {
        #expect(Theme.palettes.count == 20)
        #expect(Set(Theme.palettes.map(\.name)).count == 20)
        #expect(Theme.palettes.filter(\.isLight).count == 10)
        #expect(Theme.palettes.first?.name == "Paper")
    }

    @Test("a theme is found by its name")
    func findsATheme() {
        #expect(Theme.palette(named: "Sky").isLight)
        #expect(Theme.palette(named: "Void").isLight == false)
        #expect(Theme.palette(named: "Nothing").name == Theme.palettes[0].name)
    }

    @Test("every kind of text reads on every surface it sits on", arguments: Theme.palettes)
    func everyTextReads(palette: Palette) throws {
        let ground = try rgb(palette.ground)
        let surfaces: [(String, RGB)] = [
            ("ground", ground),
            ("panel", try rgb(palette.panel)),
            ("raised", try rgb(palette.raised)),
            ("code", try rgb(palette.codeBackground)),
            // The banner a failed turn is shown in.
            ("failure banner", ground.mixed(with: try rgb(palette.danger), 0.07)),
        ]
        let code = palette.code
        let texts: [(String, Color, Double)] = [
            ("ink", palette.ink, 7),
            ("inkDim", palette.inkDim, 5.5),
            ("inkFaint", palette.inkFaint, 4.5),
            ("accent", palette.accent, 4.5),
            ("link", palette.link, 4.5),
            ("danger", palette.danger, 4.5),
            ("success", palette.success, 4.5),
            ("code", code.plain, 7),
            ("keyword", code.keyword, 4.5),
            ("string", code.string, 4.5),
            ("number", code.number, 4.5),
            ("comment", code.comment, 4.5),
            ("type", code.type, 4.5),
            ("function", code.function, 4.5),
        ]
        for (role, colour, least) in texts {
            let text = try rgb(colour)
            for (surface, behind) in surfaces {
                let ratio = text.contrast(with: behind)
                #expect(ratio >= least, "\(palette.name): \(role) on \(surface) is \(String(format: "%.2f", ratio)):1, under \(least):1")
            }
        }
        // A button's label is set in the ground on a pill of ink.
        #expect(ground.contrast(with: try rgb(palette.ink)) >= 7, "\(palette.name): a button's label does not read")
    }

    @Test("the ink of a dark theme is light, and the ink of a light theme is dark", arguments: Theme.palettes)
    func theInkIsTheRightWay(palette: Palette) throws {
        let ink = try rgb(palette.ink).luminance
        let ground = try rgb(palette.ground).luminance
        #expect(palette.isLight ? ink < ground : ink > ground, "\(palette.name) has its ink the wrong way round")
    }

    @Test("no two themes look alike: ground, ink and accent together differ by a whole colour")
    func noTwoAlike() throws {
        let looks = try Theme.palettes.map { palette in
            (palette.name, try [palette.ground, palette.ink, palette.accent].map(rgb))
        }
        for (index, first) in looks.enumerated() {
            for second in looks[(index + 1)...] {
                let apart = zip(first.1, second.1).map { difference($0, $1) }.reduce(0, +)
                #expect(apart >= 50, "\(first.0) and \(second.0) are too alike: ΔE \(Int(apart))")
            }
        }
    }

    @Test("the contrast ratio is WCAG's")
    func contrastRatio() {
        #expect(abs(RGB(0x000000).contrast(with: RGB(0xFFFFFF)) - 21) < 0.01)
        #expect(abs(RGB(0x777777).contrast(with: RGB(0xFFFFFF)) - 4.48) < 0.01)
        #expect(RGB(0x123456).contrast(with: RGB(0x123456)) == 1)
    }
}
