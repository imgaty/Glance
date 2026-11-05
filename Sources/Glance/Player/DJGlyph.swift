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
}

/// Spotify's DJ, in the left button's place while it chooses the music. Clicked, it gets different
/// picks.
struct DJButton: View {
    let color: Color
    /// It moves whenever the music plays, the DJ talking or not.
    let moving: Bool
    /// The DJ is talking, as VoiceOver says.
    let talking: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            DJGlyph(color: color, moving: moving)
                .frame(width: PlayerLayout.optionGlyph * 1.2, height: PlayerLayout.optionGlyph * 1.2)
        }
        .buttonStyle(IslandPress())
        .notchControl()
        .help(String(localized: "Get different DJ picks"))
        .accessibilityLabel("DJ")
        .accessibilityValue(talking ? String(localized: "Talking") : "")
        .accessibilityHint("Get different DJ picks")
    }
}

/// The DJ drawn as Spotify draws it: a ring with its top right pressed in, and two fainter rings
/// trailing behind that corner, the nearer pressed in less, the farther bowed out. While it moves,
/// its corner comes out as the sound falls and presses back in as it rises, as the cover's does, and
/// the trailing rings follow it a moment later. Still, it's Spotify's symbol, as at its loudest.
struct DJGlyph: View {
    let color: Color
    let moving: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Front to back: how far each ring's corner is pressed in at rest and at its loudest, as a share
    /// of its radius (bowed out below zero), how far out it comes when quiet, and how strongly it
    /// shows.
    private static let rings: [(dent: Double, reach: Double, opacity: Double)] = [
        (0.3, 0.16, 1), (0.12, 0.1, 0.6), (-0.08, 0.05, 0.35),
    ]
    /// How far behind the ring in front each one follows, in seconds.
    private static let trail = 0.06

    var body: some View {
        let animates = moving && !reduceMotion
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animates)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let strength = animates ? Self.strength() : 0
            GeometryReader { proxy in
                let side = min(proxy.size.width, proxy.size.height)
                let line = side * 0.1
                ZStack {
                    ForEach(Self.rings.indices.reversed(), id: \.self) { index in
                        let ring = Self.rings[index]
                        let out = animates ? 1 - strength * Self.flap(at: t - Double(index) * Self.trail) : 0
                        DJRing(dent: ring.dent - ring.reach * out, inset: line / 2)
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

    /// How far in it goes: never still while it animates, and further the louder the sound.
    private static func strength() -> Double {
        guard Permissions.audioCapture == .granted else { return 0.8 }
        let levels = AudioLevels.shared.levels
        return max(min(Double(levels.reduce(0, +)) / Double(levels.count) * 2.2, 1), 0.5)
    }
}

/// The cover while the DJ talks, as Spotify shows it: its green ring on blue, the corner pressed in,
/// with a teal and a paler blue crescent behind that corner. It follows the same sound the waveform
/// shows: the quieter the voice, the rounder the ring, and the louder, the deeper its corner and the
/// larger the ring, one crescent widening with the low bars and the other with the high ones. Still,
/// it's Spotify's own picture, which is how it looks at its loudest.
struct DJCover: View {
    /// It's talking now, not paused.
    let talking: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// What the rest of the app takes the cover's colors from, and how it's told apart.
    static let key = "dj"
    @MainActor static let picture: NSImage? = {
        let renderer = ImageRenderer(content: DJCoverDrawing(heard: .loudest).frame(width: 300, height: 300))
        renderer.scale = 1
        return renderer.nsImage
    }()

    var body: some View {
        let moving = talking && !reduceMotion
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !moving)) { context in
            DJCoverDrawing(heard: moving ? Self.heard(at: context.date) : .loudest)
        }
    }

    /// As the waveform hears it. With audio capture off the waveform has nothing to show, so the
    /// ring moves as a voice does.
    private static func heard(at date: Date) -> DJHeard {
        guard Permissions.audioCapture == .granted else {
            let t = date.timeIntervalSinceReferenceDate
            return DJHeard(all: 0.8 * DJGlyph.flap(at: t), low: 0.8 * DJGlyph.flap(at: t - 0.06), high: 0.8 * DJGlyph.flap(at: t - 0.12))
        }
        return DJHeard(levels: AudioLevels.shared.levels)
    }
}

/// The sound the DJ's ring follows, each from 0 to 1.
struct DJHeard: Equatable {
    var all: Double
    var low: Double
    var high: Double

    static let silent = DJHeard(all: 0, low: 0, high: 0)
    /// All the bars full: the ring as Spotify draws it.
    static let loudest = DJHeard(all: 1, low: 1, high: 1)

    /// From the waveform's bars, low to high. Speech fills only part of them, so it's boosted to
    /// move the ring as far as the bars move.
    init(levels: [Float]) {
        func loudness(_ bars: ArraySlice<Float>) -> Double {
            bars.isEmpty ? 0 : min(Double(bars.reduce(0, +)) / Double(bars.count) * 1.8, 1)
        }
        let half = levels.count / 2
        self.init(all: loudness(levels[...]), low: loudness(levels[..<half]), high: loudness(levels[half...]))
    }

    init(all: Double, low: Double, high: Double) {
        self.all = all
        self.low = low
        self.high = high
    }
}

struct DJCoverDrawing: View {
    let heard: DJHeard

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let line = side * 0.045
            let dents = Self.dents(heard)
            ZStack {
                DJLook.blue
                ZStack {
                    DJRing(dent: dents.paleBlue, inset: line / 2).fill(DJLook.paleBlue)
                    DJRing(dent: dents.teal, inset: line / 2).fill(DJLook.teal)
                    DJRing(dent: dents.front, inset: line / 2).fill(DJLook.blue)
                    DJRing(dent: dents.front, inset: line / 2)
                        .stroke(DJLook.green, style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round))
                }
                .frame(width: side * 0.8, height: side * 0.8)
                .scaleEffect(0.95 + 0.05 * heard.all)
            }
        }
    }

    /// How far in the green ring's corner is pressed, and the crescents' rings behind it: nearly
    /// round when quiet, to Spotify's own corner when loud. Each crescent stays out beyond the ring
    /// in front of it, wide enough to show past the green line.
    static func dents(_ heard: DJHeard) -> (front: Double, teal: Double, paleBlue: Double) {
        let front = 0.04 + 0.26 * heard.all
        let teal = front - 0.15 - 0.03 * heard.low
        return (front, teal, teal - 0.1 - 0.1 * heard.high)
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
