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

    /// How much light it gives, as WCAG measures it: 0 for black, 1 for white.
    public var luminance: Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// The WCAG contrast ratio between the two, from 1 (none) to 21.
    public func contrast(with other: RGB) -> Double {
        let (a, b) = (luminance, other.luminance)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// The colour, moved towards `end` only as far as it must go to stand out
    /// from every one of `surfaces` by `ratio`. A colour that already does is
    /// left as it was designed.
    func readable(on surfaces: [RGB], ratio: Double, towards end: RGB) -> RGB {
        var amount = 0.0
        var colour = self
        while surfaces.contains(where: { colour.contrast(with: $0) < ratio }), amount < 1 {
            amount = min(amount + 0.01, 1)
            colour = mixed(with: end, amount)
        }
        return colour
    }
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
    /// The colour of a command, and of a switch that is on.
    public var link: Color
    public var danger: Color
    public var success: Color
    /// The colour light is drawn in: the lamp over the page, the sky.
    public var glow: Color
    /// The colours of code.
    public var code: Highlighter.CodePalette

    /// How far each kind of text stands out from every surface it is set on,
    /// as a WCAG contrast ratio. 7 is AAA for body text and 4.5 is AA, so
    /// even the faintest caption is comfortably readable.
    public enum Contrast {
        public static let ink = 7.0
        public static let inkDim = 5.5
        /// The faintest text, and every coloured piece of text: the accent,
        /// links, errors, successes and code.
        public static let text = 4.5
    }

    /// A theme is designed as its ground, its rail, its ink and its colours.
    /// The surfaces and greys between are derived, and every colour text is
    /// set in is then moved, only as far as it must, until it reads on every
    /// surface it can sit on: the page, the rail, a raised card, a block of
    /// code and the page where the lamp lights it.
    static func make(
        _ name: String,
        light: Bool,
        ground groundHex: UInt32,
        panel panelHex: UInt32,
        ink inkHex: UInt32,
        accent accentHex: UInt32,
        link linkHex: UInt32,
        danger dangerHex: UInt32,
        success successHex: UInt32,
        code hues: (keyword: UInt32, string: UInt32, number: UInt32, type: UInt32, function: UInt32)
    ) -> Palette {
        let ground = RGB(groundHex)
        let panel = RGB(panelHex)
        let designedInk = RGB(inkHex)
        let accent = RGB(accentHex)
        // Text that must stand out moves away from the ground: lighter on a
        // dark theme, darker on a light one.
        let end = light ? RGB(0x000000) : RGB(0xFFFFFF)

        let raised = ground.mixed(with: designedInk, light ? 0.06 : 0.10)
        let codeBackground = ground.mixed(with: designedInk, light ? 0.04 : 0.05)
        let glow = light ? accent : accent.mixed(with: RGB(0xFFFFFF), 0.6)
        // The page under the lamp, at its brightest.
        let lit = ground.mixed(with: glow, light ? 0.09 : 0.15)
        let surfaces = [ground, panel, raised, codeBackground, lit]

        func text(_ colour: RGB, _ ratio: Double = Contrast.text) -> RGB {
            colour.readable(on: surfaces, ratio: ratio, towards: end)
        }
        let ink = text(designedInk, Contrast.ink)
        let readableAccent = text(accent)

        return Palette(
            name: name,
            isLight: light,
            ground: ground.color,
            panel: panel.color,
            raised: raised.color,
            hairline: ground.mixed(with: ink, light ? 0.15 : 0.17).color,
            hairlineSoft: ground.mixed(with: ink, light ? 0.09 : 0.10).color,
            codeBackground: codeBackground.color,
            ink: ink.color,
            inkDim: text(ink.mixed(with: ground, 0.28), Contrast.inkDim).color,
            inkFaint: text(ink.mixed(with: ground, 0.48)).color,
            accent: readableAccent.color,
            accentLine: readableAccent.mixed(with: ground, 0.45).color,
            link: text(RGB(linkHex)).color,
            danger: text(RGB(dangerHex)).color,
            success: text(RGB(successHex)).color,
            glow: glow.color,
            code: Highlighter.CodePalette(
                plain: ink.color,
                keyword: text(RGB(hues.keyword)).color,
                string: text(RGB(hues.string)).color,
                number: text(RGB(hues.number)).color,
                comment: text(ink.mixed(with: ground, 0.5)).color,
                type: text(RGB(hues.type)).color,
                function: text(RGB(hues.function)).color
            )
        )
    }
}

/// The themes the app ships with: ten light, then ten dark, no two alike in
/// ground, rail or voice.
public enum Theme {
    public static let palettes: [Palette] = [
        // MARK: Light

        // A white page, a grey rail, magenta. The default.
        .make("Paper", light: true, ground: 0xFFFFFF, panel: 0xF2F2F1, ink: 0x18181B,
              accent: 0xC42D84, link: 0x1D4ED8, danger: 0xC81E1E, success: 0x15803D,
              code: (keyword: 0xC42D84, string: 0x15803D, number: 0xB45309, type: 0x1D4ED8, function: 0x7C3AED)),
        // Grey-beige newsprint, black type, an editor's red.
        .make("Newsprint", light: true, ground: 0xE8E4DA, panel: 0xD9D3C5, ink: 0x111111,
              accent: 0xC8281A, link: 0x1B3F9C, danger: 0xA3001C, success: 0x2E6B1F,
              code: (keyword: 0xC8281A, string: 0x2E6B1F, number: 0x7A4B00, type: 0x1B3F9C, function: 0x5B2A86)),
        // Butter yellow and indigo.
        .make("Butter", light: true, ground: 0xFFF3BF, panel: 0xF5E49A, ink: 0x2A2000,
              accent: 0x4B2BC8, link: 0x9A3412, danger: 0xB42318, success: 0x2F6E13,
              code: (keyword: 0x4B2BC8, string: 0x2F6E13, number: 0x9A3412, type: 0x0E6378, function: 0x8A3FA0)),
        // Sage green and ochre.
        .make("Sage", light: true, ground: 0xDCE7DA, panel: 0xC9D9C6, ink: 0x0F241A,
              accent: 0x8A5A00, link: 0x1F5A96, danger: 0xB3261E, success: 0x1E6B2E,
              code: (keyword: 0x8A5A00, string: 0x1E6B2E, number: 0xA0471B, type: 0x1F5A96, function: 0x7A3E9D)),
        // Blush pink and teal.
        .make("Blush", light: true, ground: 0xFCE6E8, panel: 0xF4D0D5, ink: 0x3A0D17,
              accent: 0x00756A, link: 0x1F5FA8, danger: 0xB71C1C, success: 0x2E7D32,
              code: (keyword: 0x00756A, string: 0x2E7D32, number: 0xA3460A, type: 0x1F5FA8, function: 0xA0185A)),
        // Sky blue and an orange kite.
        .make("Sky", light: true, ground: 0xDDEBFA, panel: 0xC6DAF2, ink: 0x0B1F3A,
              accent: 0xC25400, link: 0x0B57C2, danger: 0xB42318, success: 0x1A7140,
              code: (keyword: 0xC25400, string: 0x1A7140, number: 0x9C2F6E, type: 0x0B57C2, function: 0x6B32B8)),
        // Lilac and leaf green.
        .make("Lilac", light: true, ground: 0xECE4F9, panel: 0xDCCFF2, ink: 0x22123F,
              accent: 0x1F7A4A, link: 0x6A2FC0, danger: 0xB3261E, success: 0x2D7A3A,
              code: (keyword: 0x6A2FC0, string: 0x1F7A4A, number: 0xA34A00, type: 0x0D6E8C, function: 0xB0256E)),
        // Fired clay and denim.
        .make("Clay", light: true, ground: 0xF2DCCB, panel: 0xE6C6AD, ink: 0x3A190B,
              accent: 0x1D5C8C, link: 0xA8330E, danger: 0x9F1D1D, success: 0x3F6B1F,
              code: (keyword: 0x1D5C8C, string: 0x3F6B1F, number: 0xA8330E, type: 0x7B4AA0, function: 0x8A5A00)),
        // Mint and purple.
        .make("Mint", light: true, ground: 0xD5F4E8, panel: 0xBCE9D7, ink: 0x06332A,
              accent: 0x7B1FA2, link: 0x135E9C, danger: 0xB3261E, success: 0x0E7A4F,
              code: (keyword: 0x7B1FA2, string: 0x0E7A4F, number: 0x9A5200, type: 0x135E9C, function: 0xB02E6A)),
        // Cool concrete, near-black type and electric blue: the darkest light.
        .make("Concrete", light: true, ground: 0xCDD2D8, panel: 0xBDC4CC, ink: 0x0B0F14,
              accent: 0x0047E0, link: 0x6A1FB0, danger: 0xA4161A, success: 0x1B6B34,
              code: (keyword: 0x0047E0, string: 0x1B6B34, number: 0x9C4500, type: 0x6A1FB0, function: 0x8A1F5C)),

        // MARK: Dark

        // True black and pure white, with no colour but in code and links.
        .make("Void", light: false, ground: 0x000000, panel: 0x0B0B0D, ink: 0xF4F4F5,
              accent: 0xFFFFFF, link: 0x3DA9FF, danger: 0xFF5A5F, success: 0x3DDC84,
              code: (keyword: 0xFF7AB6, string: 0x3DDC84, number: 0xFFB86B, type: 0x3DA9FF, function: 0xF4E87C)),
        // A green screen: green type on black-green, and acid yellow.
        .make("Phosphor", light: false, ground: 0x030A05, panel: 0x07140B, ink: 0x9DFFB0,
              accent: 0xE4FF3A, link: 0x5CE1E6, danger: 0xFF6B5E, success: 0x4CFF8F,
              code: (keyword: 0xE4FF3A, string: 0x7CFFC4, number: 0xFFD166, type: 0x5CE1E6, function: 0xC3FF7A)),
        // Royal cobalt blue and yellow.
        .make("Cobalt", light: false, ground: 0x112A78, panel: 0x0B1E5C, ink: 0xFFFFFF,
              accent: 0xFFC600, link: 0x9EFFFF, danger: 0xFF628C, success: 0x3AD900,
              code: (keyword: 0xFF9D00, string: 0x3AD900, number: 0xFF628C, type: 0x80FFBB, function: 0xFFC600)),
        // Wine red and mint.
        .make("Oxblood", light: false, ground: 0x3A0B22, panel: 0x2A0718, ink: 0xFCEBEE,
              accent: 0x6EE7B7, link: 0x8FD0FF, danger: 0xFF8A80, success: 0xB5E48C,
              code: (keyword: 0x6EE7B7, string: 0xB5E48C, number: 0xFFB070, type: 0x8FD0FF, function: 0xFFB3C6)),
        // Deep forest and lavender.
        .make("Forest", light: false, ground: 0x07301E, panel: 0x042216, ink: 0xE4F4E8,
              accent: 0xC9A7FF, link: 0x7FD6E0, danger: 0xFF7B72, success: 0x8BE38B,
              code: (keyword: 0xC9A7FF, string: 0xB6E36B, number: 0xF4A261, type: 0x7FD6E0, function: 0xE9C46A)),
        // Synthwave: violet night, magenta and cyan neon.
        .make("Synthwave", light: false, ground: 0x1E0B36, panel: 0x150727, ink: 0xF8EEFF,
              accent: 0xFF5FD2, link: 0x36E9F0, danger: 0xFF5C7A, success: 0x72F1B8,
              code: (keyword: 0xFF5FD2, string: 0x72F1B8, number: 0xF97E72, type: 0x36E9F0, function: 0xFEDE5D)),
        // Espresso brown and caramel.
        .make("Espresso", light: false, ground: 0x261B15, panel: 0x1C130E, ink: 0xF4E7D7,
              accent: 0xE9A84C, link: 0x9DC8B6, danger: 0xF2766B, success: 0xA9CF7E,
              code: (keyword: 0xE9A84C, string: 0xA9CF7E, number: 0xE39B7B, type: 0x9DC8B6, function: 0xF0D6A0)),
        // Graphite grey and cyan: the lightest dark.
        .make("Graphite", light: false, ground: 0x2C2E33, panel: 0x222327, ink: 0xEEEEF0,
              accent: 0x4FD8E8, link: 0xA5B4FF, danger: 0xFF8A8A, success: 0x7FD99A,
              code: (keyword: 0xC792EA, string: 0xC3E88D, number: 0xF78C6C, type: 0xFFCB6B, function: 0x82AAFF)),
        // A deep teal lagoon and coral pink.
        .make("Lagoon", light: false, ground: 0x06303A, panel: 0x04232B, ink: 0xE2FBF8,
              accent: 0xFF8FB1, link: 0x8BE3FF, danger: 0xFF8A5C, success: 0x7BE0A5,
              code: (keyword: 0xFF8FB1, string: 0xB5F2A8, number: 0xFFD580, type: 0x8BE3FF, function: 0xF2B8FF)),
        // Olive drab and a clear sky blue.
        .make("Olive", light: false, ground: 0x35321A, panel: 0x282612, ink: 0xEDEBD7,
              accent: 0x6CB4FF, link: 0xF2A65A, danger: 0xFF6B6B, success: 0xA8D46F,
              code: (keyword: 0x6CB4FF, string: 0xA8D46F, number: 0xF2A65A, type: 0xE9C46A, function: 0xD4B8F0)),
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

    public static let sidebarWidth: CGFloat = 304
    public static let contentWidth: CGFloat = 860
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

/// A field's placeholder, drawn in the theme's faint ink: the system's own
/// is too faint to read on a tinted ground, and takes the field's ink when
/// the field is given one.
private struct Placeholder: ViewModifier {
    @Environment(\.palette) private var palette
    let text: String
    let shown: Bool

    func body(content: Content) -> some View {
        content.overlay(alignment: .topLeading) {
            if shown {
                Text(text)
                    .foregroundStyle(palette.inkFaint)
                    .lineLimit(1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}

extension View {
    /// Shows `text` over an empty field, in the faint ink.
    func placeholder(_ text: String, shown: Bool) -> some View {
        modifier(Placeholder(text: text, shown: shown))
    }
}
