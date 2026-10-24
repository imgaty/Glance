//
//  DJGlyph.swift
//  Glance
//
//  Created by Gaty on 22/10/2026.
//

import SwiftUI

/// Spotify's DJ, in the left button's place while it chooses the music. Clicked, it brings Spotify
/// forward, where the DJ's own controls are.
struct DJButton: View {
    let color: Color
    /// The DJ is talking, and its corner moves.
    let talking: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            DJGlyph(color: color, talking: talking)
                .frame(width: PlayerLayout.optionGlyph * 1.2, height: PlayerLayout.optionGlyph * 1.2)
        }
        .buttonStyle(IslandPress())
        .notchControl()
        .accessibilityLabel("DJ")
        .accessibilityValue(talking ? "Talking" : "")
        .accessibilityHint("Opens Spotify")
    }
}

/// The DJ drawn as Spotify draws it: a ring with its top right pressed in, and two fainter rings
/// trailing behind that corner, the nearer pressed in less, the farther bowed out. While the DJ
/// talks, the corner moves out and back a little with its voice, and the trailing rings follow it
/// a moment later.
struct DJGlyph: View {
    let color: Color
    let talking: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Front to back: how far each ring's corner is pressed in at rest, as a share of its radius
    /// (bowed out below zero), how far it moves out as the DJ talks, and how strongly it shows.
    private static let rings: [(dent: Double, reach: Double, opacity: Double)] = [
        (0.3, 0.16, 1), (0.12, 0.1, 0.6), (-0.08, 0.05, 0.35),
    ]
    /// How far behind the ring in front each one follows, in seconds.
    private static let trail = 0.06

    var body: some View {
        let moving = talking && !reduceMotion
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !moving)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let loudness = moving ? Self.loudness() : 0
            GeometryReader { proxy in
                let side = min(proxy.size.width, proxy.size.height)
                let line = side * 0.1
                ZStack {
                    ForEach(Self.rings.indices.reversed(), id: \.self) { index in
                        let ring = Self.rings[index]
                        let flap = loudness * Self.flap(at: t - Double(index) * Self.trail)
                        DJRing(dent: ring.dent - ring.reach * flap, inset: line / 2)
                            .stroke(color.opacity(ring.opacity), style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round))
                    }
                }
                .frame(width: side, height: side)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
        }
    }

    /// A speaking voice's rise and fall, about four syllables a second, from 0 (at rest) to 1.
    static func flap(at t: Double) -> Double {
        let wave = 0.55 * sin(t * 2 * .pi * 4.1) + 0.3 * sin(t * 2 * .pi * 6.7 + 1.3) + 0.25 * sin(t * 2 * .pi * 2.3 + 0.4)
        return min(max(0.35 + 0.6 * wave, 0), 1)
    }

    /// How loud the DJ is: still between its sentences. Without audio capture there's nothing to
    /// listen to, so it moves as if talking steadily.
    private static func loudness() -> Double {
        guard Permissions.audioCapture == .granted else { return 0.8 }
        let levels = AudioLevels.shared.levels
        return min(Double(levels.reduce(0, +)) / Double(levels.count) * 2.2, 1)
    }
}

/// A ring pressed in at its top right by `dent`, a share of its radius, or bowed out when it's
/// below zero; drawn `inset` in from its frame, with room left for the farthest a corner bows out.
struct DJRing: Shape {
    var dent: Double
    var inset: CGFloat

    /// Where the corner is, counterclockwise from the right, and how far round either way the dent
    /// reaches: from a little past the top to a little above the right side.
    private static let corner = 0.28 * Double.pi
    private static let spread = 0.31 * Double.pi
    private static let room = 1.12

    var animatableData: Double {
        get { dent }
        set { dent = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let radius = (min(rect.width, rect.height) / 2 - inset) / Self.room
        var path = Path()
        let steps = 120
        for step in 0..<steps {
            let angle = Double(step) / Double(steps) * 2 * .pi
            let gap = abs(angle - Self.corner)
            let away = min(gap, 2 * .pi - gap) / Self.spread
            let share = away < 1 ? pow(cos(away * .pi / 2), 2) : 0
            let r = radius * (1 - dent * share)
            let point = CGPoint(x: rect.midX + r * cos(angle), y: rect.midY - r * sin(angle))
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}
