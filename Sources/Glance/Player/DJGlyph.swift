//
//  DJGlyph.swift
//  Glance
//
//  Created by Gaty on 22/10/2026.
//

import AppKit
import SwiftUI

/// Spotify's DJ's colors, measured on the screen where Spotify draws them.
enum DJLook {
    static let blue = Color(.displayP3, red: 0x27 / 255, green: 0x58 / 255, blue: 0xB2 / 255)
    static let green = Color(.displayP3, red: 0x6C / 255, green: 0xE3 / 255, blue: 0x94 / 255)
    /// Behind the ring's pressed-in corner, nearest first.
    static let teal = Color(.displayP3, red: 0x5C / 255, green: 0xC1 / 255, blue: 0xBD / 255)
    static let paleBlue = Color(.displayP3, red: 0x37 / 255, green: 0x75 / 255, blue: 0xC1 / 255)
    /// The fine broken line inside the button's edge.
    static let edge = Color(.displayP3, red: 0x1F / 255, green: 0x4A / 255, blue: 0x9C / 255)

    /// How far the DJ's voice has moved the corner, for one drawn `behind` seconds after it: 0 at
    /// rest, or still, to 1.
    @MainActor
    static func voice(at date: Date, behind: Double = 0) -> Double {
        loudness() * flap(at: date.timeIntervalSinceReferenceDate - behind)
    }

    /// A speaking voice's rise and fall, about four syllables a second, from 0 (at rest) to 1.
    static func flap(at t: Double) -> Double {
        let wave = 0.55 * sin(t * 2 * .pi * 4.1) + 0.3 * sin(t * 2 * .pi * 6.7 + 1.3) + 0.25 * sin(t * 2 * .pi * 2.3 + 0.4)
        return min(max(0.35 + 0.6 * wave, 0), 1)
    }

    /// How loud the DJ is: still between its sentences. Without audio capture there's nothing to
    /// listen to, so it moves as if talking steadily.
    @MainActor
    private static func loudness() -> Double {
        guard Permissions.audioCapture == .granted else { return 0.8 }
        let levels = AudioLevels.shared.levels
        return min(Double(levels.reduce(0, +)) / Double(levels.count) * 2.2, 1)
    }
}

/// Spotify's DJ, in the left button's place while it chooses the music: its ring on a blue circle,
/// as in Spotify. Clicked, it brings Spotify forward, where the DJ's own controls are.
struct DJButton: View {
    /// The DJ is talking, and its corner moves.
    let talking: Bool
    let action: () -> Void

    /// As large as the buttons' contact areas leave room for, the ring half of it across.
    private static let side: CGFloat = 34

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(DJLook.blue)
                Circle()
                    .inset(by: 2)
                    .stroke(DJLook.edge, style: StrokeStyle(lineWidth: 0.5, dash: [3.5, 2]))
                DJGlyph(talking: talking)
                    .frame(width: Self.side / 2, height: Self.side / 2)
            }
            .frame(width: Self.side, height: Self.side)
        }
        .buttonStyle(IslandPress(highlight: false))
        .notchControl()
        .accessibilityLabel("DJ")
        .accessibilityValue(talking ? String(localized: "Talking") : "")
        .accessibilityHint("Opens Spotify")
    }
}

/// The DJ in the button, as Spotify draws it small: a ring and, inside its top right, the curve of
/// that corner pressed in. While the DJ talks, the curve moves out and back with its voice.
struct DJGlyph: View {
    let talking: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let moving = talking && !reduceMotion
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !moving)) { context in
            let voice = moving ? DJLook.voice(at: context.date) : 0
            GeometryReader { proxy in
                let side = min(proxy.size.width, proxy.size.height)
                let line = side * 0.1
                let style = StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round)
                ZStack {
                    DJRing(dent: 0, inset: line / 2).stroke(DJLook.green, style: style)
                    DJRing(dent: 0.3 - 0.16 * voice, inset: line / 2).stroke(DJLook.green, style: style)
                }
                .frame(width: side, height: side)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
        }
    }
}

/// The cover while the DJ talks, as Spotify shows it: its green ring on blue, the corner pressed in,
/// with a teal and a paler blue crescent behind that corner. As it talks, the corner moves out and
/// back with its voice, the crescents follow it a moment later, and the ring swells a little.
struct DJCover: View {
    /// It's talking now, not paused.
    let talking: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// What the rest of the app takes the cover's colors from, and how it's told apart.
    static let key = "dj"
    @MainActor static let picture: NSImage? = {
        let renderer = ImageRenderer(content: DJCoverDrawing(voices: (0, 0, 0)).frame(width: 300, height: 300))
        renderer.scale = 1
        return renderer.nsImage
    }()

    var body: some View {
        let moving = talking && !reduceMotion
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !moving)) { context in
            if moving {
                DJCoverDrawing(
                    voices: (
                        DJLook.voice(at: context.date), DJLook.voice(at: context.date, behind: 0.06),
                        DJLook.voice(at: context.date, behind: 0.12)
                    ))
            } else {
                DJCoverDrawing(voices: (0, 0, 0))
            }
        }
    }
}

private struct DJCoverDrawing: View {
    /// How far its voice has moved each of the three, front to back.
    let voices: (Double, Double, Double)

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let line = side * 0.045
            ZStack {
                DJLook.blue
                ZStack {
                    DJRing(dent: -0.08 - 0.05 * voices.2, inset: line / 2).fill(DJLook.paleBlue)
                    DJRing(dent: 0.12 - 0.1 * voices.1, inset: line / 2).fill(DJLook.teal)
                    DJRing(dent: 0.3 - 0.16 * voices.0, inset: line / 2).fill(DJLook.blue)
                    DJRing(dent: 0.3 - 0.16 * voices.0, inset: line / 2)
                        .stroke(DJLook.green, style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round))
                }
                .frame(width: side * 0.8, height: side * 0.8)
                .scaleEffect(1 + 0.03 * voices.0)
            }
        }
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
