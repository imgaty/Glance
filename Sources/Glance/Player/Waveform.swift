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

/// Six bars that follow the music from bass, at the left, to treble, drawn exactly as Apple's own
/// waveform draws them (`MediaCoreUI`'s `WaveformLayer`, measured from its layers on macOS 27.3):
/// each a dot at rest, as tall as the waveform at full, a little wider the taller it is, round at
/// the ends, each new reading eased in over 80 ms. Paused, they settle over 0.9 s into six dots, as
/// Apple's paused waveform does. They show the cover itself, as Apple's do, through the bars laid
/// across all six at once (see `ArtworkFlow.bars`). Folded, it becomes Apple's lyrics symbol, the way
/// Apple swaps one symbol for another: the bars draw together into a point and are gone, and the
/// symbol springs out of it.
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
            TimelineView(.animation(minimumInterval: 1.0 / Self.demoRate, paused: !isPlaying)) { context in
                glyph(levels: Self.demoLevels(at: context.date.timeIntervalSinceReferenceDate))
            }
        } else {
            HeardLevels { glyph(levels: $0) }
        }
    }

    private func glyph(levels: [Float]) -> some View {
        GeometryReader { proxy in
            let size = proxy.size
            let shown = isPlaying ? levels : Self.resting
            ZStack(alignment: .topLeading) {
                paint(moving: isPlaying)
                    .mask {
                        ZStack(alignment: .topLeading) {
                            ForEach(0..<AudioLevels.bands, id: \.self) { index in
                                let rect = folded ? gathered(in: size) : Self.bar(index, level: shown[index], in: size)
                                // Circular: a continuous curve stretches along a tall bar, so
                                // its ends would grow pointed as it grows.
                                Capsule(style: .circular)
                                    .frame(width: rect.width, height: rect.height)
                                    .position(x: rect.midX, y: rect.midY)
                                    .opacity(folded ? 0 : 1)
                            }
                            .animation(.spring(response: 0.26, dampingFraction: 0.9), value: folded)
                        }
                        // Each reading eased in as the notch on screen eases it (see `LiveBarsView`):
                        // drawn as it came, the bars stepped about twelve times a second.
                        .animation(Self.readingCurve, value: shown)
                        .frame(width: size.width, height: size.height, alignment: .topLeading)
                    }
                lyricsSymbol(in: size)
            }
            .frame(width: size.width, height: size.height)
        }
        .animation(Self.settling, value: isPlaying)
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

    /// Apple's measures, as shares of the waveform's width: a bar at rest is a dot this wide, and at
    /// full height this wide; the bars' middles are evenly apart, the outer ones half a full bar in.
    static let restWidth: CGFloat = 5.0 / 48
    static let fullWidth: CGFloat = 7.0 / 60

    /// Where a bar of `level`, 0 to 1, is: as tall as its share of the waveform, a dot at least, and a
    /// little wider the taller it is.
    static func bar(_ index: Int, level: Float, in size: CGSize) -> CGRect {
        let level = CGFloat(min(max(level, 0), 1))
        let rest = size.width * restWidth, full = size.width * fullWidth
        let width = rest + (full - rest) * level
        // Never shorter than it's wide, so its ends stay round.
        let height = max(width, size.height * level)
        let middle = full / 2 + CGFloat(index) * (size.width - full) / CGFloat(AudioLevels.bands - 1)
        return CGRect(x: middle - width / 2, y: (size.height - height) / 2, width: width, height: height)
    }

    /// The bars while nothing plays: six dots, as Apple's waveform paused (`WaveformState.paused`),
    /// rather than the arch it shows playing with nothing to show.
    static let resting: [Float] = Array(repeating: 0, count: AudioLevels.bands)
    /// How long each new reading takes to ease in, on Apple's ease-out, and how long the bars take to
    /// settle into dots or back out of them, on Apple's own curve for pausing.
    static let readingIn = 0.08
    static let readingCurve = Animation.timingCurve(0, 0, 0.58, 1, duration: readingIn)
    static let settlingIn = 0.9
    static let settling = Animation.timingCurve(0.33, 1, 0.67, 1, duration: settlingIn)
    static let settlingCurve = CAMediaTimingFunction(controlPoints: 0.33, 1, 0.67, 1)

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

    /// The made-up song's bars, for the welcome tour and the test scenes: a made-up beat, as the
    /// analysis would hear it, a reading at a time, as often as music's come.
    static func demoLevels(at t: Double) -> [Float] {
        let reading = (t * demoRate).rounded(.down) / demoRate
        return demoHeard(at: reading).enumerated().map { band, loudness in
            BinnedFFT.height(of: (1 - BinnedFFT.tilt * Float(band)) * Float(0.3 + 0.75 * loudness))
        }
    }

    /// How many times a second the made-up song is read: as often as music is.
    static let demoRate = 48_000 / Double(BinnedFFT.size)

    /// The made-up song's beats a second: a little under two.
    private static let demoTempo = 1.8
    /// How often the made-up song hits hard: on the first of every eight beats, the only kick that
    /// takes the waveform to its full height, and so the only one the colors behind the player pulse
    /// on (see `AudioLevels.bang`).
    private static let demoAccent = 8.0

    /// How loud the made-up song is in each band, 0 to 1, left to right: a kick on every beat, harder
    /// every eight, a bass line on every half beat, a voice wandering through the mids, a snare on
    /// every other beat and hi-hats on every half beat, each a little harder or softer as played.
    static func demoHeard(at t: Double) -> [Double] {
        let beats = t * demoTempo
        let beat = beats.rounded(.down)
        let sinceBeat = (beats - beat) / demoTempo
        let halves = beats * 2
        let half = halves.rounded(.down)
        let sinceHalf = (halves - half) / (demoTempo * 2)
        let played = 0.75 + 0.25 * demoVariation(half)
        let hard = beat.truncatingRemainder(dividingBy: demoAccent) == 0 ? 1 : 0.8
        let kick = hard * (sinceBeat < 0.07 ? 1 : exp(-(sinceBeat - 0.07) / 0.14))
        let snare = beat.truncatingRemainder(dividingBy: 2) == 1 ? exp(-sinceBeat / 0.12) : 0
        let hat = exp(-sinceHalf / 0.06) * played
        let note = exp(-sinceHalf / 0.25) * played
        let voice = 0.55 + 0.2 * sin(t * 2 * .pi / 4.4) + 0.15 * sin(t * 2 * .pi * 2.9 + 2 * sin(t * 1.3))
        let loudness = [
            0.2 + 0.8 * kick, 0.25 + 0.55 * note, voice, 0.2 + 0.3 * voice + 0.45 * snare, 0.2 + 0.5 * snare + 0.3 * hat,
            0.15 + 0.7 * hat,
        ]
        return loudness.map { min(max($0, 0), 1) }
    }

    /// 0 to 1, the same for the same half beat, different from one to the next.
    private static func demoVariation(_ half: Double) -> Double {
        let x = sin(half * 12.9898) * 43758.5453
        return x - x.rounded(.down)
    }

    /// The colors' pulse for the made-up song, 0 to 1, as `AudioLevels` shows music's: nothing but on
    /// its hard kick, every eight beats, up over 70 milliseconds and easing away over about a third
    /// of a second.
    static func demoPulse(at t: Double) -> Double {
        let period = demoAccent / demoTempo, rise = 0.07, fall = 0.36
        let since = t.truncatingRemainder(dividingBy: period)
        return 0.7 * (since < rise ? (1 - cos(.pi * since / rise)) / 2 : exp(-(since - rise) / fall))
    }

    /// Where the bars draw together: a dot in the middle, where the symbol springs from.
    private func gathered(in size: CGSize) -> CGRect {
        let dot = size.width * Self.restWidth
        return CGRect(x: size.width / 2 - dot / 2, y: size.height / 2 - dot / 2, width: dot, height: dot)
    }
}

/// The music's levels, for the waveform in Settings' pictures of the notch.
private struct HeardLevels<Content: View>: View {
    @ObservedObject private var audio = AudioLevels.shared
    @ViewBuilder let content: ([Float]) -> Content

    var body: some View { content(audio.levels) }
}

/// The bars in the notch on the screen, drawn by Core Animation. Through SwiftUI each reading would
/// redraw the whole notch, which took about half of a core with the notch closed. Here each only
/// reshapes one layer over the cover's colors, eased in from where the bars are as Apple's are.
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
            if isPlaying != oldValue { redraw(over: WaveformGlyph.settlingIn, curve: WaveformGlyph.settlingCurve) }
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
            hearing = AudioLevels.shared.$levels.removeDuplicates().sink { [weak self] levels in
                MainActor.assumeIsolated { self?.heard(levels) }
            }
        }
    }

    /// A reading of the music. Paused, the bars stay as they're settling into dots: the music is
    /// still heard for a moment after it pauses, and each reading had cut the settling short, the
    /// bars snapping into dots a tenth of a second in.
    func heard(_ levels: [Float]) {
        self.levels = levels
        if isPlaying { redraw(over: WaveformGlyph.readingIn) }
    }

    /// The made-up song as it is when this frame shows, by the same clock as the colors behind
    /// the player, drawn only when a new reading is due, as music's are.
    @objc private func nextFrame(_ link: CADisplayLink) {
        let t = Date.now.timeIntervalSinceReferenceDate + link.targetTimestamp - CACurrentMediaTime()
        let now = (t * WaveformGlyph.demoRate).rounded(.down)
        guard now != reading else { return }
        reading = now
        levels = WaveformGlyph.demoLevels(at: t)
        redraw(over: WaveformGlyph.readingIn)
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

    /// The bars as they are now, eased in over `duration` from where they show, as Apple's are; at
    /// once with none.
    private func redraw(over duration: Double = 0, curve: CAMediaTimingFunction = CAMediaTimingFunction(controlPoints: 0, 0, 0.58, 1)) {
        guard bounds.width > 0 else { return }
        let shown = isPlaying ? levels : WaveformGlyph.resting
        let path = CGMutablePath()
        for (index, level) in shown.enumerated() {
            WaveformGlyph.addCapsule(WaveformGlyph.bar(index, level: level, in: bounds.size), to: path)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Only a change moves them, so nothing cuts short what's moving them already.
        if duration > 0, shape.path.map({ $0 != path }) ?? true, let from = shape.presentation()?.path ?? shape.path {
            let change = CABasicAnimation(keyPath: "path")
            change.fromValue = from
            change.duration = duration
            // Apple's ease-out for a reading; its own curve for settling into dots and out.
            change.timingFunction = curve
            shape.add(change, forKey: "path")
        }
        shape.path = path
        CATransaction.commit()
    }
}
