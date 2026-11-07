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
            .keyRing(.lyrics)
            .disabled(!button)
            .help(button ? (lyricsShown ? String(localized: "Hide Lyrics") : String(localized: "Show Lyrics")) : "")
            // Only a picture of the sound, unless it shows the lyrics.
            .accessibilityLabel(lyricsShown ? String(localized: "Hide Lyrics") : String(localized: "Show Lyrics"))
            .accessibilityHidden(!button)
            .onHover { hovering = $0 }
            .notchControl(enabled: button)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }
}

/// Six bars that follow the music from bass to treble, drawn like the iPhone's, measured from it:
/// each bar a third wider than the gaps, with round ends however tall it grows, from a dot up, and
/// dots when nothing plays. As the iPhone fills its waveform, the bars show the cover itself,
/// blurred, laid across all six at once (see `ArtworkFlow.bars`). Folded, it becomes Apple's lyrics symbol, the
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
        if onScreen {
            // The bars go as the rest of the glyph does, without drawing together one by one. The
            // made-up song's too, so it moves exactly as music does.
            ZStack {
                LiveBars(color: NSColor(color), flow: flow, isPlaying: isPlaying, demo: demo)
                    .scaleEffect(folded ? 0.2 : 1)
                    .opacity(folded ? 0 : 1)
                    .animation(.spring(response: 0.26, dampingFraction: 0.9), value: folded)
                GeometryReader { lyricsSymbol(in: $0.size) }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isPlaying)
        } else if demo {
            // As often as music's levels come.
            TimelineView(.animation(minimumInterval: 1.0 / Double(Self.demoRate), paused: !isPlaying)) { context in
                glyph(levels: Self.demoLevels(at: context.date.timeIntervalSinceReferenceDate))
            }
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
                    ? NotchMotion.spring(response: 0.36, dampingFraction: 0.6).delay(0.06)
                    : .spring(response: 0.24, dampingFraction: 0.95), value: folded)
    }

    /// The cover, blurred, across the whole waveform, or the color alone.
    @ViewBuilder private func paint(moving: Bool) -> some View {
        if let flow {
            Image(decorative: flow.bars, scale: 1)
                .resizable()
                .interpolation(.high)
        } else {
            color
        }
    }

    /// A dot when nothing plays or nothing can be heard; a short dash when quiet; full height on the
    /// loudest beats.
    static func bar(_ index: Int, level: Float, playing: Bool, in size: CGSize, width: CGFloat) -> CGRect {
        let level = CGFloat(level)
        let sounding = width + (size.height - width) * min(max(level, 0), 1)
        // Settling into a dot as the sound fades out, rather than stopping at a dash.
        let height = playing ? width + (sounding - width) * min(level / 0.05, 1) : width
        return CGRect(x: CGFloat(index) * width * (1 + 1 / barToGap), y: (size.height - height) / 2, width: width, height: height)
    }

    /// A bar as a capsule drawn the same way whatever its height, a dot included, so that as one
    /// shape turns into another every point has a partner and nothing twists on the way.
    static func addCapsule(_ bar: CGRect, to path: CGMutablePath) {
        let r = bar.width / 2
        let k = r * 0.5523
        let top = bar.minY + r, bottom = max(bar.maxY - r, top)
        path.move(to: CGPoint(x: bar.minX, y: top))
        path.addCurve(to: CGPoint(x: bar.midX, y: top - r), control1: CGPoint(x: bar.minX, y: top - k), control2: CGPoint(x: bar.midX - k, y: top - r))
        path.addCurve(to: CGPoint(x: bar.maxX, y: top), control1: CGPoint(x: bar.midX + k, y: top - r), control2: CGPoint(x: bar.maxX, y: top - k))
        path.addLine(to: CGPoint(x: bar.maxX, y: bottom))
        path.addCurve(to: CGPoint(x: bar.midX, y: bottom + r), control1: CGPoint(x: bar.maxX, y: bottom + k), control2: CGPoint(x: bar.midX + k, y: bottom + r))
        path.addCurve(to: CGPoint(x: bar.minX, y: bottom), control1: CGPoint(x: bar.midX - k, y: bottom + r), control2: CGPoint(x: bar.minX, y: bottom + k))
        path.addLine(to: CGPoint(x: bar.minX, y: top))
        path.closeSubpath()
    }

    /// How wide a bar is, for how wide the waveform is.
    static func barWidth(in width: CGFloat) -> CGFloat { width / (6 + 5 / barToGap) }

    /// How much wider a bar is than the gap beside it: 8 pixels to 6 on the iPhone.
    private static let barToGap: CGFloat = 8.0 / 6

    /// The made-up song's bars, for the welcome tour and the test scenes: a made-up beat as the
    /// analysis would hear it, eased exactly as music's levels are (see `Analyzer.shape`), each bar
    /// rising quickly and falling away slowly, at the same 45 readings a second. The easing only
    /// remembers the last second or so, so the readings of the second before are eased through
    /// again each time, and the bars stay a picture of the moment.
    static func demoLevels(at t: Double) -> [Float] {
        let rate = Double(demoRate)
        let now = (t * rate).rounded(.down)
        var reference: Float? = 0
        var smoothed = [Float](repeating: 0, count: AudioLevels.bands)
        var bars = smoothed
        for reading in stride(from: now - rate, through: now, by: 1) {
            bars = Analyzer.shape(demoHeard(at: reading / rate), reference: &reference, volume: 1, smoothed: &smoothed)
        }
        return bars
    }

    /// How many times a second the made-up song is read: as often as music is.
    static let demoRate = 45

    /// The made-up song's beats a second: a little under two, as the colors behind the player pulse.
    private static let demoTempo = 1.8

    /// How loud the made-up song is in each band, in decibels against its loudest, as the analysis
    /// would hear it: a kick on every beat, a snare on every other, a bass line and hi-hats on every
    /// half beat, each a little harder or softer as played, and a voice wandering through the mids.
    static func demoHeard(at t: Double) -> [Float] {
        let beats = t * demoTempo
        let beat = beats.rounded(.down)
        let sinceBeat = (beats - beat) / demoTempo
        let halves = beats * 2
        let half = halves.rounded(.down)
        let sinceHalf = (halves - half) / (demoTempo * 2)
        let played = 0.75 + 0.25 * demoVariation(half)
        let kick = sinceBeat < 0.07 ? 1 : exp(-(sinceBeat - 0.07) / 0.14)
        let snare = beat.truncatingRemainder(dividingBy: 2) == 1 ? exp(-sinceBeat / 0.12) : 0
        let hat = exp(-sinceHalf / 0.06) * played
        let note = exp(-sinceHalf / 0.25) * played
        let voice = 0.55 + 0.2 * sin(t * 2 * .pi / 4.4) + 0.15 * sin(t * 2 * .pi * 2.9 + 2 * sin(t * 1.3))
        // Bass, low mids, mids, upper mids, presence and air, as `Analyzer.bands`.
        let loudness = [
            0.2 + 0.8 * kick, 0.25 + 0.55 * note, voice, 0.2 + 0.3 * voice + 0.45 * snare, 0.2 + 0.5 * snare + 0.3 * hat,
            0.15 + 0.7 * hat,
        ]
        // Untilted, as the analysis tilts what it hears.
        return loudness.enumerated().map { band, level in
            Analyzer.span * Float(min(max(level, 0), 1) - 1) - Analyzer.tilt * Float(log2(Analyzer.middles[band] / Analyzer.middles[0]))
        }
    }

    /// 0 to 1, the same for the same half beat, different from one to the next.
    private static func demoVariation(_ half: Double) -> Double {
        let x = sin(half * 12.9898) * 43758.5453
        return x - x.rounded(.down)
    }

    /// The made-up song's kick, 0 to 1, a little under twice a second, which the colors behind the
    /// player pulse on: up over its first 70 milliseconds and dying away, as a real kick does once
    /// it's eased (see `Analyzer`).
    static func demoKick(at t: Double) -> Double {
        let period = 1 / demoTempo, rise = 0.07, fall = 0.15
        let since = t.truncatingRemainder(dividingBy: period)
        return since < rise ? (1 - cos(.pi * since / rise)) / 2 : exp(-(since - rise) / fall)
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

/// The bars in the notch on the screen, drawn by Core Animation. The levels come 45 times a second,
/// and through SwiftUI each one would redraw the whole notch, which took about half of a core with
/// the notch closed. Here each only reshapes one layer over the cover's colors.
private struct LiveBars: NSViewRepresentable {
    let color: NSColor
    let flow: ArtworkFlow?
    let isPlaying: Bool
    /// The made-up song's levels rather than the music's.
    var demo = false

    func makeNSView(context: Context) -> LiveBarsView { LiveBarsView() }

    func updateNSView(_ view: LiveBarsView, context: Context) {
        view.show(color: color, colors: flow?.bars)
        view.isPlaying = isPlaying
        view.demo = demo
    }
}

final class LiveBarsView: NSView {
    private let clip = CALayer()
    private let shape = CAShapeLayer()
    private let colors = CALayer()
    private var hearing: AnyCancellable?
    /// For the made-up song: the screen's frames, and the reading last drawn.
    private var frames: CADisplayLink?
    private var reading = -1.0
    private var levels = [Float](repeating: 0, count: AudioLevels.bands)

    var isPlaying = false {
        didSet {
            frames?.isPaused = !isPlaying
            if isPlaying != oldValue { redraw(animated: true) }
        }
    }

    /// The made-up song's levels, made up here, rather than the music's.
    var demo = false {
        didSet {
            if demo != oldValue { listen() }
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
        listen()
    }

    private func listen() {
        hearing = nil
        frames?.invalidate()
        frames = nil
        guard window != nil else { return }
        if demo {
            // Read by the screen's frames, so each reading shows on the first frame due after it.
            let link = displayLink(target: self, selector: #selector(nextFrame(_:)))
            link.isPaused = !isPlaying
            link.add(to: .main, forMode: .common)
            frames = link
        } else {
            hearing = AudioLevels.shared.$levels.sink { [weak self] levels in
                MainActor.assumeIsolated {
                    self?.levels = levels
                    self?.redraw()
                }
            }
        }
    }

    /// The made-up song as it is when this frame shows, by the same clock as the colors behind
    /// the player, drawn only when a new reading is due, as music's are.
    @objc private func nextFrame(_ link: CADisplayLink) {
        let t = Date.now.timeIntervalSinceReferenceDate + link.targetTimestamp - CACurrentMediaTime()
        let now = (t * Double(WaveformGlyph.demoRate)).rounded(.down)
        guard now != reading else { return }
        reading = now
        levels = WaveformGlyph.demoLevels(at: t)
        redraw()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        clip.frame = bounds
        shape.frame = bounds
        // The whole cover across the whole waveform.
        colors.frame = bounds
        CATransaction.commit()
        redraw()
    }

    private func redraw(animated: Bool = false) {
        let width = WaveformGlyph.barWidth(in: bounds.width)
        guard width > 0 else { return }
        let path = CGMutablePath()
        for (index, level) in levels.enumerated() {
            let bar = WaveformGlyph.bar(index, level: level, playing: isPlaying, in: bounds.size, width: width)
            WaveformGlyph.addCapsule(bar, to: path)
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
        CATransaction.commit()
    }
}
