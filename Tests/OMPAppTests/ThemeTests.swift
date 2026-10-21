import AppKit
import SwiftUI
import Testing
@testable import OMPApp

/// The colour as numbers, so a test can compare it.
private func rgb(_ color: Color) throws -> RGB {
    let colour = try #require(NSColor(color).usingColorSpace(.sRGB))
    return RGB(red: colour.redComponent, green: colour.greenComponent, blue: colour.blueComponent)
}

@Suite("The themes")
struct ThemeTests {
    @Test("there are twenty themes, and no two share a name")
    func twentyThemes() {
        #expect(Theme.palettes.count == 20)
        #expect(Set(Theme.palettes.map(\.name)).count == 20)
    }

    @Test("a theme is found by its name")
    func findsATheme() {
        #expect(Theme.palette(named: "Arctic").isLight)
        #expect(Theme.palette(named: "Void").isLight == false)
        #expect(Theme.palette(named: "Nothing").name == Theme.palettes[0].name)
    }

    @Test("the ink of a dark theme is light, and the ink of a light theme is dark")
    func theInkIsReadable() throws {
        for palette in Theme.palettes {
            let ink = try rgb(palette.ink)
            let ground = try rgb(palette.ground)
            if palette.isLight {
                #expect(ink.red < ground.red, "\(palette.name) should have dark ink on a light ground")
            } else {
                #expect(ink.red > ground.red, "\(palette.name) should have light ink on a dark ground")
            }
        }
    }
}
