//
//  Waveform.swift
//  Glance
//
//  Created by Gaty on 07/10/2026.
//

import AppKit
import Combine
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
    let color: Color
    /// The colors the bars show; without them, the color alone.
    var flow: ArtworkFlow? = nil
    let isPlaying: Bool
    var folded = false
    /// The lyrics are open: the bubble is filled, as Apple's is when lyrics show.
    var filled = false
    /// The welcome tour's made-up song, which moves the bars by itself.
    var demo = false
    @Environment(\.notchOnScreen) private var onScreen

    var body: some View {
        if demo {
            TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !isPlaying)) { context in
                glyph(levels: Self.demoLevels(at: context.date.timeIntervalSinceReferenceDate))
            }
        } else if onScreen {
            // The bars go as the rest of the glyph does, without drawing together one by one.
            ZStack {
                LiveBars(color: NSColor(color), flow: flow, isPlaying: isPlaying)
                    .scaleEffect(folded ? 0.2 : 1)
                    .opacity(folded ? 0 : 1)
                    .animation(.spring(response: 0.26, dampingFraction: 0.9), value: folded)
                GeometryReader { lyricsSymbol(in: $0.size) }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isPlaying)
        } else {
            HeardLevels { glyph(levels: $0) }
        }
    }

    private func glyph(levels: [Float]) -> some View {
        GeometryReader { proxy in
            let size = proxy.size
            let bar = Self.barWidth(in: size.width)
            ZStack(alignment: .topLeading) {
                paint(moving: isPlaying)
                    .mask {
                        ZStack(alignment: .topLeading) {
                            ForEach(0..<AudioLevels.bands, id: \.self) { index in
                                let rect =
                                    folded
                                    ? gathered(in: size, dot: bar) : Self.bar(index, level: levels[index], playing: isPlaying, in: size, width: bar)
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
                lyricsSymbol(in: size)
            }
            .frame(width: size.width, height: size.height)
        }
        // The levels arrive 45 times a second, already eased (each bar with its own attack and
        // release), so they're drawn as they come. Animating each change as well kept SwiftUI
        // animating at the display's full rate the whole time music played: three times the work.
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isPlaying)
    }

    /// Apple's lyrics symbol, in the waveform's colors. Its tail hangs below the bubble, so it's
    /// lowered until the bubble itself sits where the bars do, its sides on theirs. Its colors only
    /// move while it shows.
    private func lyricsSymbol(in size: CGSize) -> some View {
        paint(moving: isPlaying && folded)
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

    /// The flowing colors, or the color alone.
    @ViewBuilder private func paint(moving: Bool) -> some View {
        if let flow {
            FlowingPaint(flow: flow, moving: moving)
        } else {
            color
        }
    }

    /// A dot when nothing plays or nothing can be heard; a short dash when quiet; full height on the
    /// loudest beats.
    static func bar(_ index: Int, level: Float, playing: Bool, in size: CGSize, width: CGFloat) -> CGRect {
        let level = CGFloat(level)
        let sounding = max(width, size.height * (0.3 + 0.7 * level))
        // Settling into a dot as the sound fades out, rather than stopping at a dash.
        let height = playing ? width + (sounding - width) * min(level / 0.05, 1) : width
        return CGRect(x: CGFloat(index) * width * (1 + 1 / barToGap), y: (size.height - height) / 2, width: width, height: height)
    }

    /// How wide a bar is, for how wide the waveform is.
    static func barWidth(in width: CGFloat) -> CGFloat { width / (6 + 5 / barToGap) }

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

/// The music's levels, for the waveform in Settings' pictures of the notch.
private struct HeardLevels<Content: View>: View {
    @ObservedObject private var audio = AudioLevels.shared
    @ViewBuilder let content: ([Float]) -> Content

    var body: some View { content(audio.levels) }
}

/// The bars' colors, the palette turning slowly, apart from the bars' own movement.
private struct FlowingPaint: View {
    let flow: ArtworkFlow
    let moving: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15, paused: !moving || reduceMotion)) { context in
            let turn = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate / ArtworkFlow.barsTurn
            Image(decorative: flow.bars, scale: 1)
                .resizable()
                .interpolation(.high)
                .scaleEffect(sqrt(2) / ArtworkFlow.barsZoom)
                .rotationEffect(.radians(turn.truncatingRemainder(dividingBy: 1) * 2 * .pi))
        }
    }
}

/// The bars in the notch on the screen, drawn by Core Animation. The levels come 45 times a second,
/// and through SwiftUI each one would redraw the whole notch, which took about half of a core with
/// the notch closed. Here each only reshapes one layer, and turns the colors under it.
private struct LiveBars: NSViewRepresentable {
    let color: NSColor
    let flow: ArtworkFlow?
    let isPlaying: Bool

    func makeNSView(context: Context) -> LiveBarsView { LiveBarsView() }

    func updateNSView(_ view: LiveBarsView, context: Context) {
        view.show(color: color, colors: flow?.bars)
        view.isPlaying = isPlaying
    }
}

final class LiveBarsView: NSView {
    private let clip = CALayer()
    private let shape = CAShapeLayer()
    private let colors = CALayer()
    private var hearing: AnyCancellable?
    private var levels = [Float](repeating: 0, count: AudioLevels.bands)

    var isPlaying = false {
        didSet {
            if isPlaying != oldValue { redraw(animated: true) }
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        colors.contentsGravity = .resize
        clip.mask = shape
        clip.addSublayer(colors)
        layer?.addSublayer(clip)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// The button around it takes the clicks.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func show(color: NSColor, colors picture: CGImage?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        colors.contents = picture
        colors.backgroundColor = picture == nil ? color.cgColor : nil
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        let scale = window?.backingScaleFactor ?? 2
        shape.contentsScale = scale
        hearing =
            window == nil
            ? nil
            : AudioLevels.shared.$levels.sink { [weak self] levels in
                MainActor.assumeIsolated {
                    self?.levels = levels
                    self?.redraw()
                }
            }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        clip.frame = bounds
        shape.frame = bounds
        // Large enough to cover the bars however it's turned.
        let side = hypot(bounds.width, bounds.height) / ArtworkFlow.barsZoom
        colors.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        colors.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()
        redraw()
    }

    private func redraw(animated: Bool = false) {
        let width = WaveformGlyph.barWidth(in: bounds.width)
        guard width > 0 else { return }
        let path = CGMutablePath()
        for (index, level) in levels.enumerated() {
            let bar = WaveformGlyph.bar(index, level: level, playing: isPlaying, in: bounds.size, width: width)
            path.addRoundedRect(in: bar, cornerWidth: bar.width / 2, cornerHeight: min(bar.width, bar.height) / 2)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if animated, let shown = shape.path {
            let change = CABasicAnimation(keyPath: "path")
            change.fromValue = shown
            change.duration = 0.3
            change.timingFunction = CAMediaTimingFunction(name: .easeOut)
            shape.add(change, forKey: "path")
        }
        shape.path = path
        if isPlaying, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let turn = (Date.now.timeIntervalSinceReferenceDate / ArtworkFlow.barsTurn).truncatingRemainder(dividingBy: 1)
            colors.setAffineTransform(CGAffineTransform(rotationAngle: turn * 2 * .pi))
        }
        CATransaction.commit()
    }
}
