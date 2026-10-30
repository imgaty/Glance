//
//  Waveform.swift
//  Glance
//
//  Created by Gaty on 07/10/2026.
//

import AppKit
import SwiftUI

/// The one waveform that flies between the closed notch and the player. In the player, pointing at
/// it turns it into the lyrics button.
struct HeroWaveform: View {
    @EnvironmentObject private var nowPlaying: NowPlaying
    @AppStorage(Preferences.musicAccentSource) private var accentSource = AccentSource.artwork
    @Environment(\.notchPaused) private var paused
    let isOpen: Bool
    let lyricsShown: Bool
    /// Only a song has lyrics; otherwise it stays a waveform, and isn't a button.
    let lyricsAvailable: Bool
    let toggleLyrics: () -> Void
    @State private var hovering = false
    @Environment(\.demoPointer) private var demoPointer

    var body: some View {
        let button = isOpen && lyricsAvailable
        // Exactly the size of its place. The button around it is like every other: the same
        // contact area centered on it, the same press.
        GeometryReader { proxy in
            let place = proxy.frame(in: .named(NotchView.bodySpace))
            let hitbox = NowPlayingView.hitbox
            let contact = CGRect(x: place.midX - hitbox / 2, y: place.midY - hitbox / 2, width: hitbox, height: hitbox)
            Button(action: toggleLyrics) {
                WaveformGlyph(
                    color: nowPlaying.accent(from: accentSource),
                    flow: nowPlaying.flow(from: accentSource),
                    isPlaying: nowPlaying.isPlaying && !paused,
                    folded: button && (hovering || contact.holds(demoPointer)), filled: lyricsShown, demo: nowPlaying.isDemo
                )
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            // It shrinks when pressed, like the others, but without the circle behind it.
            .buttonStyle(IslandPress(highlight: false))
            .disabled(!button)
            .help(button ? (lyricsShown ? "Hide Lyrics" : "Show Lyrics") : "")
            // Only a picture of the sound, unless it shows the lyrics.
            .accessibilityLabel(lyricsShown ? "Hide Lyrics" : "Show Lyrics")
            .accessibilityHidden(!button)
            .onHover { hovering = $0 }
            .notchControl(enabled: button)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }
}

/// Six bars that follow the music's loudness from bass to treble, drawn like the iPhone's: each bar
/// 1.6 times as wide as the gaps, with round ends however tall it grows, and dots when nothing
/// plays. As the iPhone fills its waveform, the bars show the same colors that flow behind the
/// player (see `ArtworkFlow`), across all six at once. Folded, it becomes Apple's lyrics symbol, the
/// way Apple swaps one symbol for another: the bars draw together into a point and are gone, and
/// the symbol springs out of it.
struct WaveformGlyph: View {
    @ObservedObject private var audio = AudioLevels.shared
    let color: Color
    /// The colors the bars show; without them, the color alone.
    var flow: ArtworkFlow? = nil
    let isPlaying: Bool
    var folded = false
    /// The lyrics are open: the bubble is filled, as Apple's is when lyrics show.
    var filled = false
    /// The welcome tour's made-up song, which moves the bars by itself.
    var demo = false

    var body: some View {
        if demo {
            TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !isPlaying)) { context in
                glyph(levels: Self.demoLevels(at: context.date.timeIntervalSinceReferenceDate))
            }
        } else {
            glyph(levels: audio.levels)
        }
    }

    private func glyph(levels: [Float]) -> some View {
        GeometryReader { proxy in
            let size = proxy.size
            let bar = size.width / (6 + 5 / Self.barToGap)
            ZStack(alignment: .topLeading) {
                paint
                    .mask {
                        ZStack(alignment: .topLeading) {
                            ForEach(0..<AudioLevels.bands, id: \.self) { index in
                                let rect = folded ? gathered(in: size, dot: bar) : self.bar(index, level: levels[index], in: size, width: bar)
                                // Circular: a continuous curve stretches along a tall bar, so
                                // its ends would grow pointed as it grows.
                                Capsule(style: .circular)
                                    .frame(width: rect.width, height: rect.height)
                                    .position(x: rect.midX, y: rect.midY)
                                    .opacity(folded ? 0 : 1)
                            }
                            .animation(.spring(response: 0.26, dampingFraction: 0.9), value: folded)
                        }
                        .frame(width: size.width, height: size.height, alignment: .topLeading)
                    }
                // Apple's lyrics symbol, in the waveform's colors. Its tail hangs below the bubble, so
                // it's lowered until the bubble itself sits where the bars do, its sides on theirs.
                paint
                    .mask {
                        Image(systemName: filled ? "quote.bubble.fill" : "quote.bubble")
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: .infinity, alignment: .center)
                            .offset(y: size.height * 0.09)
                    }
                    .scaleEffect(folded ? 1 : 0.2)
                    .blur(radius: folded ? 0 : 2)
                    .opacity(folded ? 1 : 0)
                    .animation(
                        folded
                            ? .spring(response: 0.36, dampingFraction: 0.6).delay(0.06)
                            : .spring(response: 0.24, dampingFraction: 0.95), value: folded)
            }
            .frame(width: size.width, height: size.height)
        }
        // The levels arrive 45 times a second, already eased (each bar with its own attack and
        // release), so they're drawn as they come. Animating each change as well kept SwiftUI
        // animating at the display's full rate the whole time music played: three times the work.
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isPlaying)
    }

    /// The flowing colors, or the color alone.
    @ViewBuilder private var paint: some View {
        if let flow {
            FlowingPaint(flow: flow, moving: isPlaying)
        } else {
            color
        }
    }

    /// A dot when nothing plays or nothing can be heard; a short dash when quiet; full height on the
    /// loudest beats.
    private func bar(_ index: Int, level: Float, in size: CGSize, width: CGFloat) -> CGRect {
        let level = CGFloat(level)
        let sounding = max(width, size.height * (0.3 + 0.7 * level))
        // Settling into a dot as the sound fades out, rather than stopping at a dash.
        let height = isPlaying ? width + (sounding - width) * min(level / 0.05, 1) : width
        return CGRect(x: CGFloat(index) * width * (1 + 1 / Self.barToGap), y: (size.height - height) / 2, width: width, height: height)
    }

    /// How much wider a bar is than the gap beside it.
    private static let barToGap: CGFloat = 1.6

    /// A made-up beat, for the welcome tour: every bar at its own pace, and the bass's bar the kick,
    /// a little under twice a second.
    static func demoLevels(at t: Double) -> [Float] {
        let kick = demoKick(at: t)
        let paces: [Double] = [5.3, 6.1, 3.7, 2.9, 2.3, 4.4]
        return paces.enumerated().map { bar, pace in
            if bar == Analyzer.beatBar { return Float(max(kick, 0.2)) }
            let level = 0.42 + 0.22 * sin(t * pace + Double(bar) * 1.7) + 0.14 * sin(t * pace * 2.3 + Double(bar))
            return Float(min(max(level, 0.1), 1))
        }
    }

    /// The made-up song's kick, 0 to 1, a little under twice a second, which the colors behind the
    /// player pulse on too.
    static func demoKick(at t: Double) -> Double {
        pow(max(0, sin(t * 2 * .pi * 1.8)), 6)
    }

    /// Where the bars draw together: a dot in the middle, where the symbol springs from.
    private func gathered(in size: CGSize, dot: CGFloat) -> CGRect {
        CGRect(x: size.width / 2 - dot / 2, y: size.height / 2 - dot / 2, width: dot, height: dot)
    }
}

/// The bars' colors, moving at the pace they're drawn at, apart from the bars' own movement.
private struct FlowingPaint: View {
    let flow: ArtworkFlow
    let moving: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15, paused: !moving || reduceMotion)) { context in
            if let frame = flow.frame(at: reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate) {
                Image(decorative: frame.bars, scale: 1)
                    .resizable()
                    .interpolation(.high)
            }
        }
    }
}
