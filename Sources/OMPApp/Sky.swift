import SwiftUI
import OMPCore

// The sky over the window while an agent works: stars that twinkle, and now
// and then a shower of falling stars. Every part of it is set in Settings.

/// How the sky looks and how often stars fall. Kept in the app's defaults.
struct SkySettings: Codable, Equatable {
    enum Shown: String, Codable, CaseIterable, Identifiable {
        case working, always, never
        var id: String { rawValue }
        var label: String {
            switch self {
            case .working: "While working"
            case .always: "Always"
            case .never: "Never"
            }
        }
    }

    enum Direction: String, Codable, CaseIterable, Identifiable {
        case both, left, right
        var id: String { rawValue }
        var label: String {
            switch self {
            case .both: "Either way"
            case .left: "To the left"
            case .right: "To the right"
            }
        }
    }

    enum Colour: String, Codable, CaseIterable, Identifiable {
        case theme, white, accent
        var id: String { rawValue }
        var label: String {
            switch self {
            case .theme: "Theme light"
            case .white: "White"
            case .accent: "Accent"
            }
        }
    }

    var shown: Shown = .working
    /// The wait between showers, at least and at most, in seconds.
    var fewestSeconds: Double = 12
    var mostSeconds: Double = 24
    /// How many stars fall in a shower, at most; each shower has one up to
    /// this many.
    var meteorsPerShower: Int = 3
    /// How fast they fall: 1 is the usual, 2 twice as fast.
    var speed: Double = 1
    var tailLength: Double = 140
    var thickness: Double = 1.5
    /// From faint, 0.1, to full, 1.
    var brightness: Double = 0.85
    var direction: Direction = .both
    var colour: Colour = .theme
    /// How many stars hang in the sky; none for a clear one.
    var stars: Int = 40
    var twinkle: Bool = true

    static let key = "omp-ui.sky"

    static func load() -> SkySettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(SkySettings.self, from: data) else { return SkySettings() }
        return settings
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }

    /// The wait before the next shower, between the two bounds whichever
    /// way round they were set.
    func nextWait() -> Double {
        let low = max(1, min(fewestSeconds, mostSeconds))
        let high = max(low, max(fewestSeconds, mostSeconds))
        return .random(in: low...high)
    }

    /// The colour stars are drawn in.
    func light(in palette: Palette) -> Color {
        switch colour {
        case .theme: palette.glow
        case .white: .white
        case .accent: palette.accent
        }
    }
}

/// The sky over the whole window, above everything in it, never in the way
/// of a click.
struct SkyView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let settings: SkySettings
    /// Whether an agent is working.
    let working: Bool
    /// Bumped to send a shower at once, from Settings.
    let preview: Int

    private var visible: Bool {
        guard !reduceMotion else { return false }
        switch settings.shown {
        case .working: return working
        case .always: return true
        case .never: return false
        }
    }

    var body: some View {
        ZStack {
            if visible, settings.stars > 0 {
                StarField(count: settings.stars, twinkle: settings.twinkle, settings: settings)
                    .transition(.opacity)
            }
            MeteorShower(settings: settings, active: visible, preview: preview)
        }
        .animation(.easeInOut(duration: 1.2), value: visible)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - The stars

/// Stars scattered over the sky, each twinkling at its own pace. Drawn in one
/// canvas, a dozen times a second, only while the sky is shown.
private struct StarField: View {
    @Environment(\.palette) private var palette
    let count: Int
    let twinkle: Bool
    let settings: SkySettings

    @State private var stars: [Star]

    init(count: Int, twinkle: Bool, settings: SkySettings) {
        self.count = count
        self.twinkle = twinkle
        self.settings = settings
        _stars = State(initialValue: Self.scatter(count))
    }

    struct Star {
        var position: CGPoint
        var radius: CGFloat
        var brightness: Double
        var pace: Double
        var phase: Double
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12, paused: !twinkle)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let light = settings.light(in: palette)
            let strength = settings.brightness * (palette.isLight ? 0.6 : 1)
            Canvas { canvas, size in
                for star in stars {
                    let shimmer = twinkle ? 0.55 + 0.45 * sin(time * star.pace + star.phase) : 1
                    let alpha = star.brightness * shimmer * strength
                    let centre = CGPoint(x: star.position.x * size.width, y: star.position.y * size.height)
                    let rect = CGRect(x: centre.x - star.radius, y: centre.y - star.radius, width: star.radius * 2, height: star.radius * 2)
                    canvas.fill(Path(ellipseIn: rect), with: .color(light.opacity(alpha)))
                }
            }
        }
        .onChange(of: count) { _, count in stars = Self.scatter(count) }
    }

    /// Stars spread over the sky, more of them high than low, a few bright.
    private static func scatter(_ count: Int) -> [Star] {
        (0..<count).map { _ in
            let bright = Double.random(in: 0...1) < 0.12
            return Star(
                position: CGPoint(x: .random(in: 0...1), y: pow(.random(in: 0...1), 1.6)),
                radius: bright ? .random(in: 1.0...1.5) : .random(in: 0.5...0.95),
                brightness: bright ? .random(in: 0.6...0.9) : .random(in: 0.2...0.5),
                pace: .random(in: 0.6...2.2),
                phase: .random(in: 0...(2 * .pi))
            )
        }
    }
}

// MARK: - The falling stars

/// Showers of falling stars: one every so often, several stars each.
private struct MeteorShower: View {
    let settings: SkySettings
    let active: Bool
    let preview: Int

    @State private var meteors: [Meteor] = []

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ForEach(meteors) { meteor in
                    MeteorStreak(meteor: meteor, in: geometry.size, settings: settings)
                }
            }
        }
        .task(id: active) {
            guard active else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(settings.nextWait()))
                guard !Task.isCancelled else { return }
                await shower()
            }
        }
        .onChange(of: preview) { _, _ in
            Task { await shower() }
        }
    }

    /// One shower: a star, and up to the setting more, close behind.
    private func shower() async {
        let count = Int.random(in: 1...max(1, settings.meteorsPerShower))
        var first: Meteor?
        for index in 0..<count {
            let meteor = first.map { Meteor.random(near: $0, settings: settings) } ?? Meteor.random(settings: settings)
            if first == nil { first = meteor }
            meteors.append(meteor)
            if index < count - 1 {
                try? await Task.sleep(for: .seconds(Double.random(in: 0.12...0.6)))
            }
        }
        // Each burns out within its own time; the slowest is gone by then.
        try? await Task.sleep(for: .seconds(2.4 / max(settings.speed, 0.25)))
        let started = first?.created ?? .now
        meteors.removeAll { $0.created >= started.addingTimeInterval(-0.01) && $0.created <= .now }
    }
}

/// Where a star starts, which way it falls, how far and how fast.
struct Meteor: Identifiable, Equatable {
    let id = UUID()
    let created = Date()
    /// The start, as a share of the sky's width and height.
    var start: CGPoint
    /// The direction of travel, in degrees below the horizontal; negative
    /// falls to the left.
    var angle: Double
    var distance: CGFloat
    var length: CGFloat
    var duration: Double

    static func random(settings: SkySettings) -> Meteor {
        let leftward = switch settings.direction {
        case .both: Bool.random()
        case .left: true
        case .right: false
        }
        let length = CGFloat(settings.tailLength) * .random(in: 0.75...1.15)
        return Meteor(
            start: CGPoint(x: leftward ? .random(in: 0.35...0.98) : .random(in: 0.02...0.65), y: .random(in: 0.0...0.3)),
            angle: (leftward ? -1 : 1) * .random(in: 20...38),
            distance: length * .random(in: 2.4...3.4),
            length: length,
            duration: .random(in: 0.9...1.35) / max(settings.speed, 0.25)
        )
    }

    /// Another star from near the first, falling the same way.
    static func random(near first: Meteor, settings: SkySettings) -> Meteor {
        var meteor = random(settings: settings)
        meteor.start = CGPoint(x: first.start.x + .random(in: -0.12...0.12), y: first.start.y + .random(in: -0.04...0.08))
        meteor.angle = first.angle + .random(in: -4...4)
        meteor.length *= .random(in: 0.55...0.9)
        return meteor
    }
}

/// One falling star: a bright head and a tail fading behind it, crossing its
/// path once and gone.
struct MeteorStreak: View {
    @Environment(\.palette) private var palette
    let meteor: Meteor
    let size: CGSize
    let settings: SkySettings
    /// How far along its path, from 0 to 1; driven by the animation, or set
    /// to draw one moment of it.
    @State private var progress: CGFloat

    init(meteor: Meteor, in size: CGSize, settings: SkySettings, at progress: CGFloat = 0) {
        self.meteor = meteor
        self.size = size
        self.settings = settings
        _progress = State(initialValue: progress)
    }

    var body: some View {
        let light = settings.light(in: palette).opacity(settings.brightness * (palette.isLight ? 0.7 : 1))
        let thickness = CGFloat(settings.thickness)
        HStack(spacing: 0) {
            Capsule()
                .fill(LinearGradient(colors: [light.opacity(0), light], startPoint: .leading, endPoint: .trailing))
                .frame(width: meteor.length, height: thickness)
            Circle()
                .fill(light)
                .frame(width: thickness * 1.8, height: thickness * 1.8)
                .shadow(color: light, radius: 2 + thickness * 1.5)
        }
        // The tail trails the head, so the streak points the way it moves.
        .rotationEffect(.degrees(meteor.angle < 0 ? 180 - abs(meteor.angle) : meteor.angle), anchor: .trailing)
        .modifier(Falling(progress: progress, meteor: meteor, size: size))
        .onAppear {
            guard progress == 0 else { return }
            withAnimation(.easeIn(duration: meteor.duration)) { progress = 1 }
        }
    }
}

/// Moves a star along its path and fades it as it goes: brightening quickly,
/// then burning out over the last of the way.
private struct Falling: ViewModifier, Animatable {
    var progress: CGFloat
    let meteor: Meteor
    let size: CGSize

    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let radians = abs(meteor.angle) * .pi / 180
        let direction: CGFloat = meteor.angle < 0 ? -1 : 1
        let travelled = meteor.distance * progress
        let x = meteor.start.x * size.width + direction * cos(radians) * travelled
        let y = meteor.start.y * size.height + sin(radians) * travelled
        let opacity = min(progress / 0.15, 1) * min((1 - progress) / 0.45, 1)
        return content
            .fixedSize()
            .position(x: x, y: y)
            .opacity(max(0, opacity))
    }
}

// MARK: - Settings

/// The sky's part of Settings: when it shows, how often stars fall, and how
/// they look, with a way to see a shower at once.
struct SkySettingsView: View {
    @Environment(\.palette) private var palette
    @Bindable var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Sky")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.ink)
                Spacer(minLength: 0)
                Button {
                    store.skyPreview += 1
                } label: {
                    Label("Preview", systemImage: "sparkles")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(palette.inkDim)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .glass(radius: 999, raised: true)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("Send a shower of falling stars now")
            }

            VStack(alignment: .leading, spacing: 9) {
                choice("Show the sky", selection: $store.sky.shown, help: "When the stars and falling stars appear")
                if store.sky.shown != .never {
                    slider("A shower at least every", value: $store.sky.fewestSeconds, in: 2...120, step: 1, unit: "s",
                           help: "The shortest wait between showers")
                    slider("and at most every", value: $store.sky.mostSeconds, in: 2...180, step: 1, unit: "s",
                           help: "The longest wait between showers")
                    slider("Falling stars per shower, up to", value: Binding(
                        get: { Double(store.sky.meteorsPerShower) },
                        set: { store.sky.meteorsPerShower = Int($0) }
                    ), in: 1...12, step: 1, unit: "", help: "Each shower has one up to this many")
                    slider("Speed", value: $store.sky.speed, in: 0.4...2.5, step: 0.1, unit: "×", help: "How fast they fall")
                    slider("Tail", value: $store.sky.tailLength, in: 40...320, step: 10, unit: " pt", help: "How long a falling star's tail is")
                    slider("Thickness", value: $store.sky.thickness, in: 0.8...4, step: 0.1, unit: " pt", help: "How thick a falling star is")
                    slider("Brightness", value: $store.sky.brightness, in: 0.1...1, step: 0.05, unit: "", help: "From faint to full")
                    choice("They fall", selection: $store.sky.direction, help: "Which way the stars fall")
                    choice("Colour", selection: $store.sky.colour, help: "The light the stars are drawn in")
                    slider("Stars in the sky", value: Binding(
                        get: { Double(store.sky.stars) },
                        set: { store.sky.stars = Int($0) }
                    ), in: 0...200, step: 5, unit: "", help: "How many stars hang in the sky; none for a clear one")
                    Toggle("Stars twinkle", isOn: $store.sky.twinkle)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .font(.system(size: 12))
                        .foregroundStyle(palette.inkDim)
                        .help("Whether the stars shimmer, each at its own pace")
                }
            }
            .padding(12)
            .glass(radius: 10)
        }
        .tint(palette.accent)
    }

    private func slider(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, step: Double, unit: String, help: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer(minLength: 6)
                Text(Self.format(value.wrappedValue, step: step) + unit)
                    .monospacedDigit()
                    .foregroundStyle(palette.ink)
            }
            .font(.system(size: 12))
            .foregroundStyle(palette.inkDim)
            // Snapped to the step as it moves, without the row of ticks a
            // stepped slider draws.
            Slider(value: Binding(
                get: { value.wrappedValue },
                set: { value.wrappedValue = ($0 / step).rounded() * step }
            ), in: range)
                .controlSize(.mini)
        }
        .help(help)
    }

    private func choice<Option: Identifiable & Hashable & CaseIterable>(_ title: String, selection: Binding<Option>, help: String) -> some View
    where Option.AllCases: RandomAccessCollection, Option: SkyOption {
        HStack {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(palette.inkDim)
            Spacer(minLength: 6)
            Picker("", selection: selection) {
                ForEach(Option.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .fixedSize()
        }
        .help(help)
    }

    static func format(_ value: Double, step: Double) -> String {
        step < 1 ? String(format: "%.1f", value) : String(Int(value.rounded()))
    }
}

/// A choice in the sky's settings, with the words it is shown in.
protocol SkyOption { var label: String { get } }
extension SkySettings.Shown: SkyOption {}
extension SkySettings.Direction: SkyOption {}
extension SkySettings.Colour: SkyOption {}
