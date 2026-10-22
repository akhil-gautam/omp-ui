import SwiftUI
import OMPCore

// The interface's light and glass: surfaces lit from above, a lamp over the
// page, labels set in pills. Everything is drawn from the theme's own
// colours, so every theme — light or dark — gets the same look.

extension Palette {
    /// The colour light is drawn in: white over a dark ground, the accent
    /// over a light one, where white would not show.
    var glow: Color { isLight ? accent : .white }

    /// The colour of a project's status: ready, working, starting, failed.
    func colour(for status: SessionStatus, working: Bool = false) -> Color {
        switch status {
        case .busy: accent
        case .idle: working ? accent : success
        case .starting: accent.opacity(0.6)
        case .error: danger
        case .stopped: inkFaint
        case .asleep: inkFaint.opacity(0.7)
        }
    }
}

// MARK: - Glass

/// A surface lit from above: a body that darkens towards its foot, and an
/// edge that catches the light along its top.
private struct Glass: ViewModifier {
    @Environment(\.palette) private var palette
    let radius: CGFloat
    /// Whether it floats over the page, with a shadow under it.
    let lifted: Bool
    /// Whether it is raised off the surface it sits on, like a bubble.
    let raised: Bool

    private var fill: [Color] {
        switch (palette.isLight, raised) {
        case (true, false): [palette.ground, palette.panel.opacity(0.55)]
        case (true, true): [palette.raised, palette.raised.opacity(0.75)]
        case (false, false): [palette.panel, palette.ground.opacity(0.9)]
        case (false, true): [palette.raised, palette.panel]
        }
    }

    private var edge: [Color] {
        palette.isLight
            ? [Color.black.opacity(0.11), Color.black.opacity(0.06)]
            : [Color.white.opacity(0.18), Color.white.opacity(0.06), Color.white.opacity(0.03)]
    }

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(shape.fill(LinearGradient(colors: fill, startPoint: .top, endPoint: .bottom)))
            .clipShape(shape)
            .overlay(shape.strokeBorder(LinearGradient(colors: edge, startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .shadow(
                color: .black.opacity(lifted ? (palette.isLight ? 0.08 : 0.55) : 0),
                radius: lifted ? 22 : 0,
                y: lifted ? 12 : 0
            )
    }
}

extension View {
    /// Sets the view on glass: lit along its top edge, darker at its foot.
    func glass(radius: CGFloat = 12, lifted: Bool = false, raised: Bool = false) -> some View {
        modifier(Glass(radius: radius, lifted: lifted, raised: raised))
    }
}

// MARK: - Pieces

/// A label in a pill, the way a section is introduced.
struct Chip: View {
    @Environment(\.palette) private var palette
    var icon: String?
    let text: String
    var tint: Color?

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint ?? palette.inkDim)
            }
            Text(text)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(palette.inkDim)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4.5)
        .glass(radius: 999)
    }
}

/// An icon on a small lit plate.
struct IconPlate: View {
    @Environment(\.palette) private var palette
    let symbol: String
    var size: CGFloat = 26

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.44, weight: .medium))
            .foregroundStyle(palette.ink)
            .frame(width: size, height: size)
            .background(
                RadialGradient(
                    colors: [palette.glow.opacity(palette.isLight ? 0.14 : 0.22), .clear],
                    center: .top, startRadius: 0, endRadius: size
                )
            )
            .glass(radius: size * 0.3, raised: true)
    }
}

// MARK: - The lamp

/// A lamp over the page: a bright line at the top, light pooling beneath it,
/// and a beam that widens as it falls.
struct Spotlight: View {
    @Environment(\.palette) private var palette
    /// How bright it is, from nothing to full.
    var strength: Double

    var body: some View {
        GeometryReader { geometry in
            let width = min(geometry.size.width * 0.78, 820)
            let soften = palette.isLight ? 0.55 : 1.0
            let power = strength * soften
            ZStack(alignment: .top) {
                Beam()
                    .fill(LinearGradient(
                        colors: [palette.glow.opacity(0.15 * power), palette.glow.opacity(0.045 * power), .clear],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .frame(width: width, height: min(geometry.size.height * 0.72, 600))
                    .blur(radius: 26)
                Ellipse()
                    .fill(palette.glow.opacity(0.38 * power))
                    .frame(width: width * 0.34, height: 30)
                    .blur(radius: 20)
                    .offset(y: -10)
                Capsule()
                    .fill(LinearGradient(
                        colors: [.clear, palette.glow.opacity(0.9 * power), .clear],
                        startPoint: .leading, endPoint: .trailing
                    ))
                    .frame(width: width * 0.3, height: 1.5)
            }
            .frame(width: geometry.size.width)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The shape of the light below the lamp: narrow where it leaves the lamp,
/// wide where it lands.
private struct Beam: Shape {
    func path(in rect: CGRect) -> Path {
        let top = rect.width * 0.2
        var path = Path()
        path.move(to: CGPoint(x: rect.midX - top / 2, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX + top / 2, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// The name, set enormous and fading out at the foot of an empty page.
struct Wordmark: View {
    @Environment(\.palette) private var palette

    var body: some View {
        let colour = palette.isLight ? palette.ink : palette.glow
        Text("omp")
            .font(.system(size: 280, weight: .heavy))
            .tracking(-14)
            .foregroundStyle(LinearGradient(
                colors: [colour.opacity(palette.isLight ? 0.06 : 0.09), colour.opacity(0)],
                startPoint: .top, endPoint: .bottom
            ))
            .fixedSize()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
