import SwiftUI
import OMPCore

/// Now and then, while an agent works, a star falls across the sky over the
/// page: one every twenty to thirty seconds, sometimes two together. Between
/// them nothing is drawn and nothing runs but a sleeping timer.
struct MeteorShower: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Whether an agent is working; the sky is still otherwise.
    let active: Bool

    @State private var meteors: [Meteor] = []

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ForEach(meteors) { meteor in
                    MeteorStreak(meteor: meteor, in: geometry.size)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: active && !reduceMotion) {
            guard active, !reduceMotion else {
                meteors = []
                return
            }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double.random(in: 20...30)))
                guard !Task.isCancelled else { return }
                await fall()
            }
        }
    }

    /// One star, and now and then a second close behind it.
    private func fall() async {
        let first = Meteor.random()
        meteors.append(first)
        if Double.random(in: 0...1) < 0.3 {
            try? await Task.sleep(for: .seconds(Double.random(in: 0.3...0.7)))
            meteors.append(Meteor.random(near: first))
        }
        try? await Task.sleep(for: .seconds(2))
        meteors.removeAll { $0.created <= first.created.addingTimeInterval(1) }
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

    static func random() -> Meteor {
        let leftward = Bool.random()
        return Meteor(
            start: CGPoint(x: leftward ? .random(in: 0.45...0.95) : .random(in: 0.05...0.55), y: .random(in: 0.02...0.22)),
            angle: (leftward ? -1 : 1) * .random(in: 22...36),
            distance: .random(in: 280...440),
            length: .random(in: 90...150),
            duration: .random(in: 0.9...1.35)
        )
    }

    /// A second star from near the first, falling the same way.
    static func random(near first: Meteor) -> Meteor {
        var meteor = random()
        meteor.start = CGPoint(x: first.start.x + .random(in: -0.08...0.08), y: first.start.y + .random(in: 0.02...0.06))
        meteor.angle = first.angle + .random(in: -4...4)
        meteor.length *= 0.7
        return meteor
    }
}

/// One falling star: a bright head and a tail fading behind it, crossing its
/// path once and gone.
struct MeteorStreak: View {
    @Environment(\.palette) private var palette
    let meteor: Meteor
    let size: CGSize
    /// How far along its path, from 0 to 1; driven by the animation, or set
    /// to draw one moment of it.
    @State private var progress: CGFloat

    init(meteor: Meteor, in size: CGSize, at progress: CGFloat = 0) {
        self.meteor = meteor
        self.size = size
        _progress = State(initialValue: progress)
    }

    var body: some View {
        let light = palette.glow.opacity(palette.isLight ? 0.55 : 0.85)
        HStack(spacing: 0) {
            Capsule()
                .fill(LinearGradient(colors: [light.opacity(0), light], startPoint: .leading, endPoint: .trailing))
                .frame(width: meteor.length, height: 1.4)
            Circle()
                .fill(light)
                .frame(width: 2.6, height: 2.6)
                .shadow(color: light, radius: 4)
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
