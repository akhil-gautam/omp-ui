import SwiftUI

/// One colour of a theme.
public struct RGB: Sendable, Hashable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(_ hex: UInt32) {
        red = Double((hex >> 16) & 0xFF) / 255
        green = Double((hex >> 8) & 0xFF) / 255
        blue = Double(hex & 0xFF) / 255
    }

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// The colour a share of the way towards `other`.
    public func mixed(with other: RGB, _ amount: Double) -> RGB {
        RGB(
            red: red + (other.red - red) * amount,
            green: green + (other.green - green) * amount,
            blue: blue + (other.blue - blue) * amount
        )
    }

    public var hex: UInt32 {
        let r = UInt32((red * 255).rounded())
        let g = UInt32((green * 255).rounded())
        let b = UInt32((blue * 255).rounded())
        return (r << 16) | (g << 8) | b
    }

    public var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: 1) }
}

/// The colours of one theme.
public struct Palette: Sendable, Hashable {
    public var name: String
    public var isLight: Bool
    public var ground: Color
    public var panel: Color
    public var raised: Color
    public var hairline: Color
    /// A fainter rule, for the quietest of edges.
    public var hairlineSoft: Color
    /// The ground a block of code sits on.
    public var codeBackground: Color
    public var ink: Color
    public var inkDim: Color
    public var inkFaint: Color
    public var accent: Color
    /// The accent, thinned: the edge of something that is in focus.
    public var accentLine: Color
    public var danger: Color
    public var success: Color

    /// A theme is two choices: the ground it stands on and the colour it
    /// speaks in. Everything else is derived.
    static func make(_ name: String, light: Bool = false, ground: UInt32, accent: UInt32) -> Palette {
        let base = RGB(ground)
        let white = RGB(0xFFFFFF)
        let black = RGB(0x000000)
        let accentColour = RGB(accent)

        if light {
            return Palette(
                name: name,
                isLight: true,
                ground: base.color,
                panel: base.mixed(with: white, 0.85).color,
                raised: base.mixed(with: black, 0.045).color,
                hairline: base.mixed(with: black, 0.11).color,
                hairlineSoft: base.mixed(with: black, 0.07).color,
                codeBackground: base.mixed(with: black, 0.035).color,
                ink: base.mixed(with: black, 0.88).color,
                inkDim: base.mixed(with: black, 0.46).color,
                inkFaint: base.mixed(with: black, 0.28).color,
                accent: accentColour.color,
                accentLine: accentColour.mixed(with: base, 0.55).color,
                danger: RGB(0xB3261E).color,
                success: RGB(0x1E7A46).color
            )
        }
        return Palette(
            name: name,
            isLight: false,
            ground: base.color,
            panel: base.mixed(with: white, 0.045).color,
            raised: base.mixed(with: white, 0.10).color,
            hairline: base.mixed(with: white, 0.15).color,
            hairlineSoft: base.mixed(with: white, 0.09).color,
            codeBackground: base.mixed(with: white, 0.025).color,
            ink: white.mixed(with: accentColour, 0.05).color,
            inkDim: base.mixed(with: white, 0.58).color,
            inkFaint: base.mixed(with: white, 0.34).color,
            accent: accentColour.color,
            accentLine: accentColour.mixed(with: base, 0.62).color,
            danger: RGB(0xE5696E).color,
            success: RGB(0x55B98A).color
        )
    }
}

/// The themes the app ships with.
public enum Theme {
    public static let palettes: [Palette] = [
        // Dark grounds.
        .make("Void", ground: 0x0A0A0B, accent: 0xED4FA6),
        .make("Carbon", ground: 0x0C0C0D, accent: 0xE8B45C),
        .make("Ink", ground: 0x090C11, accent: 0x5AB6E8),
        .make("Moss", ground: 0x090F0B, accent: 0x6FCF7F),
        .make("Plum", ground: 0x0C0A11, accent: 0xA98CF0),
        .make("Rust", ground: 0x100C0A, accent: 0xE08A55),
        .make("Slate", ground: 0x0B0C0E, accent: 0x8FA6C4),
        .make("Ember", ground: 0x0B0808, accent: 0xF2664F),
        .make("Terminal", ground: 0x070907, accent: 0x57D98A),
        .make("Dusk", ground: 0x0A0912, accent: 0xE77BC4),
        .make("Indigo", ground: 0x0A0A14, accent: 0x7C8CF8),
        // Light grounds.
        .make("Paper", light: true, ground: 0xF7F6F3, accent: 0xB4731A),
        .make("Arctic", light: true, ground: 0xF3F6F9, accent: 0x2E6FB8),
        .make("Sand", light: true, ground: 0xF8F4EA, accent: 0x9A6B2F),
        .make("Mint", light: true, ground: 0xF2F7F4, accent: 0x1F7A5C),
        .make("Lavender", light: true, ground: 0xF6F4F9, accent: 0x6B4FBB),
        .make("Fog", light: true, ground: 0xF4F5F6, accent: 0x45596F),
        .make("Rose", light: true, ground: 0xFAF4F5, accent: 0xB03A56),
        .make("Fern", light: true, ground: 0xF2F6F2, accent: 0x3D7A43),
        .make("Snow", light: true, ground: 0xFAFAFA, accent: 0x2A2A2E),
    ]

    public static func palette(named name: String) -> Palette {
        palettes.first { $0.name == name } ?? palettes[0]
    }

    // MARK: - Type

    /// The small uppercase labels the chrome is built from.
    public static func label(_ size: CGFloat = 10.5) -> Font {
        .system(size: size, weight: .semibold, design: .monospaced)
    }

    /// A heading, set tight.
    public static func heading(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .default)
    }

    public static func body(_ size: CGFloat = 13) -> Font {
        .system(size: size, weight: .regular, design: .default)
    }

    public static func code(_ size: CGFloat = 12) -> Font {
        .system(size: size, weight: .regular, design: .monospaced)
    }

    // MARK: - Metrics

    public static let railWidth: CGFloat = 52
    public static let sidebarWidth: CGFloat = 268
    public static let contentWidth: CGFloat = 780
}

// MARK: - The environment

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Theme.palettes[0]
}

extension EnvironmentValues {
    /// The colours the interface is drawn with.
    public var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}
