//
//  MusicRecognitionViews.swift
//  Glance
//
//  Created by Gaty on 14/11/2026.
//

import SwiftUI

/// Music Recognition, as iOS 27 draws it in the Dynamic Island (`MusicRecognition.app`'s own
/// drawings and its views' names): Shazam's mark alone in Shazam's blue beside the camera, light
/// passing through it while it listens, and a waveform of what it hears at the right; opened, the
/// mark white on a blue disc, light running round it, and "Listening…", then "Working on it…" and
/// "Still trying…" as it goes on.
enum ShazamLook {
    /// Shazam's blue, as Apple names it (`ShazamColor`), and its buttons' circle: the blue at about a
    /// quarter, measured on iOS 27.
    static let blue = Color(.sRGB, red: 0, green: 0x88 / 255, blue: 1)
    static let dim = Color(.sRGB, red: 8 / 255, green: 34 / 255, blue: 67 / 255)
    /// The light passing through the mark, and how long it takes to cross.
    static let light = Color(.sRGB, red: 0x8C / 255, green: 0xE8 / 255, blue: 1)
    static let crossing: TimeInterval = 1.0033 / 0.7
    /// The opened disc, from iOS 27's `expanded-listening.ca`: a deeper blue, a cyan arc glow going
    /// round the other way from a clock's hands once every 5 seconds, the mark breathing, and sparkles
    /// coming and going in it and just outside it.
    static let disc = Color(.sRGB, red: 0, green: 117 / 255, blue: 237 / 255)
    static let discLight = Color(.sRGB, red: 0, green: 215 / 255, blue: 1)
    static let discTurn: TimeInterval = 5
    /// How long the mark takes to breathe out, and again in.
    static let breath: TimeInterval = 1.0533
    /// Beside the camera, by the island's height, as iOS 27's: the mark's height and how far in it
    /// starts; the waveform's six bars, their width, pitch, shortest and tallest, and how far in.
    static let mark: CGFloat = 0.553
    static let markEdge: CGFloat = 0.237
    static let bars = 6
    static let bar: CGFloat = 2 / 36.7
    static let pitch: CGFloat = 3.9 / 36.7
    static let tallest: CGFloat = 11.3 / 36.7
    static let waveEdge: CGFloat = 0.21
    /// Opened, by the same height: its bars wider and taller, and how far before the ✕ they stop.
    static let openBar: CGFloat = 3.5 / 36.7
    static let openPitch: CGFloat = 5.3 / 36.7
    static let openTallest: CGFloat = 18.7 / 36.7
    static let waveGap: CGFloat = 20.7 / 36.7
    /// Its buttons' glyphs, by the island's height: the ✕ and its line, and the retry arrow.
    static let cross: CGFloat = 18.7 / 36.7
    static let crossLine: CGFloat = 2.36 / 36.7
    static let retry: CGFloat = 23.5 / 36.7
    /// The mark on its disc, by the disc's side.
    static let discMark: CGFloat = 0.667
    /// How much of its symbol's square the mark fills, tall and wide: the symbol leaves room for a
    /// circle round it, which isn't drawn.
    static let symbolInk: CGFloat = 0.59
    static let symbolWidth: CGFloat = 0.545
    /// After how long listening says it's still at it, and then that it's still trying.
    static let workingAfter: TimeInterval = 4
    static let tryingAfter: TimeInterval = 9
    /// How long the notch opens to it as it starts listening, and to "No song found." before it goes.
    static let opensAtStart: TimeInterval = 2.5
    static let showsNoMatch: TimeInterval = 4.7

    /// The waveform's width at that height, beside the camera or opened.
    static func waveWidth(_ h: CGFloat, opened: Bool = false) -> CGFloat {
        h * ((opened ? openPitch : pitch) * CGFloat(bars - 1) + (opened ? openBar : bar))
    }
    /// The mark's width at that height.
    static func markWidth(_ h: CGFloat) -> CGFloat { h * mark * symbolWidth / symbolInk }
}

/// Music recognition beside the camera, as iOS 27's: Shazam's mark at the left end, and at the right
/// a waveform of what it hears while it listens, or the cover of the song it found; in the bubble,
/// the mark.
struct MusicRecognitionCompactView: View {
    let state: MusicRecognitionActivity.State
    var minimal = false
    var leadingOnly = false
    var restingHeight: CGFloat = 32
    @ObservedObject private var activity = MusicRecognitionActivity.shared

    static func wing(for state: MusicRecognitionActivity.State, restingHeight h: CGFloat) -> CGFloat {
        let gap = LiveActivityView.cameraGap
        let left = h * ShazamLook.markEdge + ShazamLook.markWidth(h) + gap
        let right = gap + ShazamLook.waveWidth(h) + h * ShazamLook.waveEdge
        return max(left, right)
    }

    var body: some View {
        let h = restingHeight
        Group {
            if minimal {
                ShazamMark(listening: state.isWorking, side: h * 0.5)
            } else {
                ZStack {
                    ShazamMark(listening: state.isWorking, side: h * ShazamLook.mark)
                        .frame(width: ShazamLook.markWidth(h))
                        .padding(.leading, h * ShazamLook.markEdge)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    trailing(h)
                        .padding(.trailing, h * ShazamLook.waveEdge)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .islandFade(!leadingOnly)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Music recognition, \(state.title)"))
    }

    @ViewBuilder private func trailing(_ h: CGFloat) -> some View {
        if state.isWorking {
            ShazamWave(levels: activity.levels, height: h)
        } else if case .match(let song) = state, let url = song.artworkURL {
            AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.white.opacity(0.2) }
                .frame(width: h * ShazamLook.mark, height: h * ShazamLook.mark)
                .clipShape(RoundedRectangle(cornerRadius: h * ShazamLook.mark * ArtworkShape.restingRadius, style: .continuous))
        }
    }
}

/// Shazam's mark alone, in Shazam's blue, or white; while it listens, light passes through it.
struct ShazamMark: View {
    let listening: Bool
    let side: CGFloat
    var tint: Color = ShazamLook.blue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        mark(tint)
            .overlay {
                if listening, !reduceMotion {
                    TimelineView(.animation) { context in
                        let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: ShazamLook.crossing) / ShazamLook.crossing
                        mark(ShazamLook.light)
                            .mask {
                                LinearGradient(
                                    stops: [.init(color: .clear, location: 0), .init(color: .white, location: 0.5), .init(color: .clear, location: 1)],
                                    startPoint: .bottomLeading, endPoint: .topTrailing
                                )
                                .frame(width: side * 0.9, height: side * 0.9)
                                .offset(x: side * (phase * 2.2 - 1.1), y: -side * (phase * 2.2 - 1.1))
                            }
                            .blur(radius: side * 0.03)
                    }
                }
            }
            .frame(width: side, height: side)
            // Breathing as it listens, as the island's own mark does.
            .modifier(ShazamBreath(on: listening && !reduceMotion))
            .accessibilityHidden(true)
    }

    private func mark(_ color: Color) -> some View {
        Image(systemName: "shazam.logo")
            .resizable()
            .scaledToFit()
            .symbolRenderingMode(.palette)
            .foregroundStyle(color, .clear)
            .frame(width: side / ShazamLook.symbolInk, height: side / ShazamLook.symbolInk)
            .frame(width: side, height: side)
    }
}

/// The mark white on a Shazam blue disc, as opened; while it listens, light runs round its edge.
struct ShazamDisc: View {
    let listening: Bool
    let side: CGFloat
    var fill: Color = ShazamLook.disc
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().fill(fill)
            if listening, !reduceMotion {
                TimelineView(.animation) { context in
                    let now = context.date.timeIntervalSinceReferenceDate
                    let turn = now.truncatingRemainder(dividingBy: ShazamLook.discTurn) / ShazamLook.discTurn
                    // Screen angles run with a clock's hands, so a falling one goes the other way.
                    let angle = Angle.degrees(-turn * 360)
                    ZStack {
                        // Two copies of the arc glow, one sharp and one far softer, cyan at half, added
                        // onto the blue (`expanded-listening.ca`, "arc glow.png" and its copy).
                        ShazamArcGlow(side: side).blur(radius: side * 0.023).opacity(0.5)
                        ShazamArcGlow(side: side).blur(radius: side * 0.117).opacity(0.5)
                    }
                    .rotationEffect(angle)
                    .blendMode(.plusLighter)
                    .frame(width: side * 0.985, height: side * 0.985)
                    .clipShape(Circle())
                }
            }
            ShazamMark(listening: false, side: side * ShazamLook.discMark, tint: .white)
                .modifier(ShazamBreath(on: listening && !reduceMotion))
        }
        .frame(width: side, height: side)
        // Its soft blue halo, under it (`Layer 5`: the blue at 40%, blurred, a little off its middle).
        .background {
            if listening, !reduceMotion {
                Circle().fill(ShazamLook.disc)
                    .frame(width: side * 0.6, height: side * 0.6)
                    .blur(radius: side * 0.27)
                    .opacity(0.4)
                    .offset(x: side * 0.051, y: side * 0.018)
                    .blendMode(.plusLighter)
            }
        }
        // Laid over it, so those past the rim don't make the disc any bigger.
        .overlay {
            if listening, !reduceMotion {
                TimelineView(.animation) { context in
                    ShazamSparkles(side: side, time: context.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// The light that turns round the disc, redrawn from iOS 27's "arc glow": a soft glow with one hard
/// straight edge, brightest on that edge at 0.71 of the radius from the middle, fading 0.46 of the
/// disc across the edge and 0.58 along it, in cyan; mirrored, as its layer is.
private struct ShazamArcGlow: View {
    let side: CGFloat

    var body: some View {
        Canvas { context, size in
            let d = side
            let middle = CGPoint(x: size.width / 2, y: size.height / 2)
            // The brightest point and the edge's way, as the image lies once mirrored.
            let bright = CGPoint(x: middle.x - 0.207 * d, y: middle.y + 0.287 * d)
            let along = CGVector(dx: 0.636, dy: 0.771)
            let into = CGVector(dx: 0.771, dy: -0.636)
            // Only on the glow's side of its edge.
            var half = Path()
            let far = d * 2
            half.move(to: CGPoint(x: bright.x - along.dx * far, y: bright.y - along.dy * far))
            half.addLine(to: CGPoint(x: bright.x + along.dx * far, y: bright.y + along.dy * far))
            half.addLine(to: CGPoint(x: bright.x + along.dx * far + into.dx * far, y: bright.y + along.dy * far + into.dy * far))
            half.addLine(to: CGPoint(x: bright.x - along.dx * far + into.dx * far, y: bright.y - along.dy * far + into.dy * far))
            half.closeSubpath()
            context.clip(to: half)
            // An ellipse along the edge, fading out from the brightest point.
            context.translateBy(x: bright.x, y: bright.y)
            context.rotate(by: .radians(atan2(along.dy, along.dx)))
            context.scaleBy(x: 0.58 / 0.46, y: 1)
            let r = 0.46 * d
            context.fill(
                Path(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2)),
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: ShazamLook.discLight, location: 0),
                        .init(color: ShazamLook.discLight.opacity(0.68), location: 0.25),
                        .init(color: ShazamLook.discLight.opacity(0.32), location: 0.5),
                        .init(color: ShazamLook.discLight.opacity(0.1), location: 0.75),
                        .init(color: ShazamLook.discLight.opacity(0), location: 1),
                    ]), center: .zero, startRadius: 0, endRadius: r))
        }
        .frame(width: side, height: side)
    }
}

/// The mark breathing while it listens: 1.02 to 1.06 its size and back, 1.05 seconds each way, eased,
/// as iOS 27's.
private struct ShazamBreath: ViewModifier {
    let on: Bool

    func body(content: Content) -> some View {
        if on {
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: ShazamLook.breath * 2) / ShazamLook.breath
                let way = t <= 1 ? t : 2 - t
                let eased = way * way * (3 - 2 * way)
                content.scaleEffect(1.02 + 0.04 * eased)
            }
        } else {
            content
        }
    }
}

/// Small soft points of light coming and going on the disc while it listens, a few faint ones just
/// past its rim, as iOS 27's.
private struct ShazamSparkles: View {
    let side: CGFloat
    let time: TimeInterval
    /// Where each is, by its angle and its distance out as a share of the radius, how long it takes to
    /// come and go, and when.
    private static let points: [(angle: Double, out: CGFloat, period: Double, phase: Double)] = [
        (20, 0.62, 1.7, 0.1), (75, 0.88, 2.3, 0.55), (130, 0.45, 1.9, 0.3), (160, 0.93, 2.6, 0.8),
        (205, 0.7, 2.1, 0.15), (250, 0.35, 1.6, 0.65), (300, 0.82, 2.4, 0.4), (340, 0.5, 2.0, 0.9),
        (110, 1.14, 2.8, 0.2), (230, 1.12, 3.1, 0.7),
    ]

    var body: some View {
        Canvas { context, size in
            let r = side / 2
            let dot = side * 0.045
            context.addFilter(.blur(radius: side * 0.01))
            for point in Self.points {
                let wave = sin((time / point.period + point.phase) * 2 * .pi)
                let shown = max(wave, 0) * (point.out > 1 ? 0.4 : 1)
                guard shown > 0.01 else { continue }
                let a = point.angle * .pi / 180
                let center = CGPoint(x: size.width / 2 + r * point.out * cos(a), y: size.height / 2 - r * point.out * sin(a))
                context.opacity = shown
                context.fill(
                    Path(ellipseIn: CGRect(x: center.x - dot / 2, y: center.y - dot / 2, width: dot, height: dot)),
                    with: .color(ShazamLook.discLight))
            }
        }
        .frame(width: side * 1.3, height: side * 1.3)
        .allowsHitTesting(false)
    }
}

/// A waveform of what it hears, in Shazam's blue, as iOS 27's: six bars, newest at the right, dots
/// when it's quiet. `height` is the island's height beside the camera; opened, its bars are wider
/// and taller, as measured.
struct ShazamWave: View {
    @ObservedObject var levels: RecordingLevels
    let height: CGFloat
    var opened = false

    var body: some View {
        let look = ShazamLook.self
        let h = height
        let bar = h * (opened ? look.openBar : look.bar)
        let pitch = h * (opened ? look.openPitch : look.pitch)
        let tallest = h * (opened ? look.openTallest : look.tallest)
        let count = look.bars
        let shown = Array(levels.levels.suffix(count))
        let padded = Array(repeating: CGFloat(0), count: max(count - shown.count, 0)) + shown
        HStack(spacing: pitch - bar) {
            ForEach(Array(padded.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(look.blue)
                    .frame(width: bar, height: bar + (tallest - bar) * min(level * 1.6, 1))
                    .animation(.easeOut(duration: 0.12), value: level)
            }
        }
        .frame(width: look.waveWidth(h, opened: opened), height: tallest)
        .accessibilityHidden(true)
    }
}

/// Music recognition opened, in one row, as the iPhone's: Shazam's mark on its blue disc at the left
/// end, light running round it while it listens, or the song's cover once it's found, which opens
/// the song; beside the camera "Listening…", then "Working on it…" and "Still trying…", or the
/// song and who it's by; at the right end the ✕ that cancels listening, and once it's over, what
/// there is to do next and Done.
struct MusicRecognitionActivityView: View {
    @ObservedObject var activity: MusicRecognitionActivity
    private let stateOverride: MusicRecognitionActivity.State?
    let restingHeight: CGFloat
    let camera: CGFloat
    var revealed = true
    @Environment(\.activityPreview) private var preview

    init(
        activity: MusicRecognitionActivity? = nil, stateOverride: MusicRecognitionActivity.State? = nil, restingHeight: CGFloat = 32,
        camera: CGFloat = 185, revealed: Bool = true
    ) {
        self.activity = activity ?? .shared
        self.stateOverride = stateOverride
        self.restingHeight = restingHeight
        self.camera = camera
        self.revealed = revealed
    }

    private var state: MusicRecognitionActivity.State { stateOverride ?? activity.state }

    enum Action: Hashable { case recognize, cancel, openSong, settings, done }

    /// In the order they stand. Opening a song found is its cover, at the left end.
    static func actions(for state: MusicRecognitionActivity.State) -> [Action] {
        if state.isWorking { return [.cancel] }
        switch state {
        case .idle: return [.recognize]
        case .match(let song): return song.musicURL != nil || song.webURL != nil ? [.openSong, .done] : [.done]
        case .denied: return [.settings, .done]
        case .restricted, .failure(.configuration): return [.done]
        // As the iPhone's: Try Again alone, and it goes by itself.
        case .noMatch: return [.recognize]
        default: return [.recognize, .done]
        }
    }

    static func controls(for state: MusicRecognitionActivity.State) -> [PlayerControl] {
        Array([PlayerControl.activityFirst, .activitySecond, .activityThird].prefix(actions(for: state).count))
    }

    /// Short enough to stop at the camera: what's happening, or the song found. The state's full
    /// name is said under the pointer and to VoiceOver.
    static func title(for state: MusicRecognitionActivity.State) -> String {
        switch state {
        case .idle: state.title
        case .noMatch: String(localized: "No song found.")
        case .requestingPermission, .denied, .restricted: String(localized: "Microphone")
        case .recognizing: listening(after: 0)
        case .match(let song): song.title
        case .failure: String(localized: "Unavailable")
        case .cancelled: String(localized: "Canceled")
        }
    }

    /// While it listens, as the iPhone's says it: "Listening…", then that it's working on it, then
    /// that it's still trying.
    static func listening(after seconds: TimeInterval) -> String {
        if seconds >= ShazamLook.tryingAfter { return String(localized: "Still trying…") }
        if seconds >= ShazamLook.workingAfter { return String(localized: "Working on it…") }
        return String(localized: "Listening…")
    }

    /// One short line under the title, where the iPhone has one: nothing while it listens, or when
    /// no song was found and Try Again is beside it.
    static func detail(for state: MusicRecognitionActivity.State) -> String {
        switch state {
        case .idle: String(localized: "Sends an audio signature to Shazam")
        case .requestingPermission: String(localized: "Allow microphone access")
        case .recognizing: ""
        case .match(let song): song.artist ?? String(localized: "Song Found")
        case .noMatch: ""
        case .denied: String(localized: "Allow it in System Settings")
        case .restricted: String(localized: "Restricted on this Mac")
        case .failure(.connection): String(localized: "Check your internet connection")
        case .failure(.recognition): String(localized: "Try again in a moment")
        case .failure(.configuration): String(localized: "Not available in this build")
        case .cancelled: String(localized: "Stopped listening")
        }
    }

    /// The whole of it, under the pointer and to VoiceOver: the state's full name, and what to do.
    static func explanation(for state: MusicRecognitionActivity.State) -> String {
        let more: String? =
            switch state {
            case .idle: String(localized: "Identifies a song with your microphone. An audio signature is sent to Shazam.")
            case .requestingPermission: String(localized: "Allow microphone access to recognize music.")
            case .denied: String(localized: "Allow Glance to use the microphone in System Settings, then try again.")
            case .restricted: String(localized: "Microphone access is restricted on this Mac.")
            case .failure(let failure): failure.message
            default: detail(for: state)
            }
        return [state.title, more].compactMap { $0 }.joined(separator: "\n")
    }

    private static func trailing(for state: MusicRecognitionActivity.State) -> [Action] { actions(for: state).filter { $0 != .openSong } }

    /// While it listens, as wide as the longest of its words, so the notch holds still as they change.
    @MainActor
    static func width(for state: MusicRecognitionActivity.State, restingHeight h: CGFloat, camera: CGFloat) -> CGFloat {
        let titles = state == .recognizing ? [0, ShazamLook.workingAfter, ShazamLook.tryingAfter].map(listening(after:)) : [title(for: state)]
        return titles.map {
            ActivityRowLayout.width(
                title: $0, detail: detail(for: state), buttons: trailing(for: state).count, extra: state.isWorking ? waveRoom(h) : 0,
                metrics: metrics(for: state, restingHeight: h), restingHeight: h, camera: camera)
        }.max() ?? 0
    }

    /// As the iPhone measures it: "No song found." on its own, taller row.
    static func metrics(for state: MusicRecognitionActivity.State, restingHeight h: CGFloat) -> ActivityRowMetrics {
        state == .noMatch ? .noMatch(h) : .recognition(h)
    }

    static func height(for state: MusicRecognitionActivity.State, restingHeight h: CGFloat) -> CGFloat { metrics(for: state, restingHeight: h).height }

    /// The waveform before the ✕ while it listens, and the room between them, as the iPhone's.
    static func waveRoom(_ h: CGFloat) -> CGFloat { ShazamLook.waveWidth(h, opened: true) + h * ShazamLook.waveGap }

    /// Its own blue for listening and trying again, as the iPhone's; white otherwise.
    static func tinted(_ action: Action, in state: MusicRecognitionActivity.State) -> Bool {
        (action == .cancel && state.isWorking) || (action == .recognize && state == .noMatch)
    }

    var body: some View {
        let h = restingHeight
        let actions = Self.actions(for: state)
        let controls = Self.controls(for: state)
        let failure = stateOverride == nil ? activity.actionFailure : nil
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let title =
                state == .recognizing
                ? Self.listening(after: (stateOverride == nil ? activity.listeningSince : nil).map { context.date.timeIntervalSince($0) } ?? 0)
                : Self.title(for: state)
            let metrics = Self.metrics(for: state, restingHeight: h)
            ActivityRow(
                restingHeight: h, camera: camera, width: Self.width(for: state, restingHeight: h, camera: camera), metrics: metrics,
                title: title, detail: failure ?? Self.detail(for: state), explanation: failure ?? Self.explanation(for: state),
                buttons: Self.trailing(for: state).count, extra: state.isWorking ? Self.waveRoom(h) : 0, revealed: revealed
            ) {
                if state != .noMatch { picture(metrics.pictureSide, opens: actions.first == .openSong) }
            } trailing: {
                if state.isWorking {
                    ShazamWave(levels: activity.levels, height: h, opened: true)
                        .padding(.trailing, h * ShazamLook.waveGap - metrics.buttonGap)
                }
                ForEach(Array(actions.enumerated()), id: \.element) { index, action in
                    if action != .openSong { button(action, control: controls[index], h) }
                }
            }
        }
        .accessibilityLabel(String(localized: "Music Recognition"))
    }

    @ViewBuilder private func picture(_ side: CGFloat, opens: Bool) -> some View {
        if case .match(let song) = state, let url = song.artworkURL {
            let cover = AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color.white.opacity(0.2)
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: side * 0.2237, style: .continuous))
            if opens {
                Button { perform(.openSong) } label: { cover.contentShape(Rectangle()) }
                    .buttonStyle(IslandPress(highlight: false, contactSize: nil))
                    .notchControl()
                    .keyControl(.activityFirst, in: RoundedRectangle(cornerRadius: side * 0.2237, style: .continuous), outset: CGSize(width: 3, height: 3), spoken: title(for: .openSong)) {
                        perform(.openSong)
                    }
                    .accessibilityLabel(title(for: .openSong))
                    .help(title(for: .openSong))
                    .accessibilityIdentifier("recognition-openSong")
            } else {
                cover.accessibilityHidden(true)
            }
        } else if opens {
            Button { perform(.openSong) } label: { ShazamDisc(listening: false, side: side).contentShape(Circle()) }
                .buttonStyle(IslandPress(highlight: false, contactSize: nil))
                .notchControl()
                .keyControl(.activityFirst, outset: CGSize(width: 3, height: 3), spoken: title(for: .openSong)) { perform(.openSong) }
                .accessibilityLabel(title(for: .openSong))
                .help(title(for: .openSong))
                .accessibilityIdentifier("recognition-openSong")
        } else {
            ShazamDisc(listening: state.isWorking, side: side)
        }
    }

    private func title(for action: Action) -> String {
        switch action {
        case .recognize: return state == .idle ? String(localized: "Recognize Music") : String(localized: "Try Again")
        case .cancel: return String(localized: "Cancel")
        case .openSong:
            if case .match(let song) = state, song.musicURL != nil { return String(localized: "Open in Music") }
            return String(localized: "Open in Shazam")
        case .settings: return String(localized: "Microphone Settings")
        case .done: return String(localized: "Done")
        }
    }

    private func button(_ action: Action, control: PlayerControl, _ h: CGFloat) -> some View {
        let tinted = Self.tinted(action, in: state)
        let ink = tinted ? ShazamLook.blue : .white
        let side = Self.metrics(for: state, restingHeight: h).buttonSide
        return IslandCircleButton(control: control, height: h, tint: .white, label: title(for: action), fill: tinted ? ShazamLook.dim : nil, side: side) {
            perform(action)
        } glyph: {
            switch action {
            case .cancel, .done:
                CrossGlyph(height: h, color: ink, size: h * ShazamLook.cross, weight: h * ShazamLook.crossLine)
            case .recognize:
                Image(systemName: state == .idle ? "shazam.logo.fill" : "arrow.clockwise")
                    .font(.system(size: state == .idle ? h * 0.62 : h * ShazamLook.retry, weight: .medium))
                    .foregroundStyle(ink)
            case .settings:
                Image(systemName: "gearshape.fill")
                    .font(.system(size: h * 0.55, weight: .semibold))
                    .foregroundStyle(.white)
            case .openSong:
                EmptyView()
            }
        }
        .accessibilityIdentifier("recognition-\(String(describing: action))")
    }

    private func perform(_ action: Action) {
        guard !preview, stateOverride == nil else { return }
        switch action {
        case .recognize: activity.recognize()
        case .cancel: activity.cancel()
        case .openSong: activity.openSong()
        case .settings: activity.openMicrophoneSettings()
        case .done: activity.dismiss()
        }
    }
}
