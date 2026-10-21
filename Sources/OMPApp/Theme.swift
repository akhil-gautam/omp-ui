import SwiftUI

/// The colours and type the interface is built from.
///
/// The palette is omp's own: a near-black ground, hairline borders, one
/// magenta accent and a lot of quiet grey.
public enum Theme {
    // MARK: Colours

    public static let ground = Color(red: 0.039, green: 0.039, blue: 0.043)
    public static let panel = Color(red: 0.055, green: 0.055, blue: 0.059)
    public static let raised = Color(red: 0.078, green: 0.078, blue: 0.086)
    public static let hover = Color(red: 0.102, green: 0.102, blue: 0.110)
    public static let codeBackground = Color(red: 0.031, green: 0.031, blue: 0.035)

    public static let hairline = Color(red: 0.118, green: 0.118, blue: 0.129)
    public static let hairlineSoft = Color(red: 0.086, green: 0.086, blue: 0.094)

    public static let ink = Color(red: 0.933, green: 0.929, blue: 0.937)
    public static let inkDim = Color(red: 0.596, green: 0.592, blue: 0.612)
    public static let inkFaint = Color(red: 0.384, green: 0.380, blue: 0.400)

    public static let accent = Color(red: 0.929, green: 0.310, blue: 0.651)
    public static let accentSoft = accent.opacity(0.14)
    public static let accentLine = accent.opacity(0.40)

    public static let danger = Color(red: 0.925, green: 0.416, blue: 0.435)
    public static let success = Color(red: 0.310, green: 0.702, blue: 0.498)

    // MARK: Type

    /// The small uppercase labels the chrome is built from.
    public static func label(_ size: CGFloat = 10.5) -> Font {
        .system(size: size, weight: .semibold, design: .monospaced)
    }

    /// A heading, set tight the way the site's headings are.
    public static func heading(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .default)
    }

    public static func body(_ size: CGFloat = 13) -> Font {
        .system(size: size, weight: .regular, design: .default)
    }

    public static func code(_ size: CGFloat = 12) -> Font {
        .system(size: size, weight: .regular, design: .monospaced)
    }

    // MARK: Metrics

    public static let railWidth: CGFloat = 52
    public static let sidebarWidth: CGFloat = 268
    public static let contentWidth: CGFloat = 760
}
