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
    /// Shazam's blue, as Apple names it (`ShazamColor`).
    static let blue = Color(.sRGB, red: 0, green: 0x88 / 255, blue: 1)
    /// The light passing through the mark, and how long it takes to cross.
    static let light = Color(.sRGB, red: 0x8C / 255, green: 0xE8 / 255, blue: 1)
    static let crossing: TimeInterval = 1.6
    /// Beside the camera, by the island's height: the mark as large as Shortcuts' icon there and as
    /// far in, the waveform as Shortcuts' ring is.
    static let mark: CGFloat = ShortcutRunLook.icon
    static let markEdge: CGFloat = ShortcutRunLook.iconEdge
    static let wave: CGFloat = ShortcutRunLook.ring
    static let waveEdge: CGFloat = ShortcutRunLook.ringEdge
    static let bars = 5
    /// The mark on its disc, by the disc's side.
    static let discMark: CGFloat = 0.55
    /// How much of its symbol's square the mark fills: the symbol leaves room for a circle round
    /// it, which isn't drawn.
    static let symbolInk: CGFloat = 0.506
    /// After how long listening says it's still at it, and then that it's still trying.
    static let workingAfter: TimeInterval = 4
    static let tryingAfter: TimeInterval = 9
}

/// Music recognition beside the camera: Shazam's mark at the left end, and at the right a waveform
/// of what it hears while it listens, or the cover of the song it found; in the bubble, the mark.
struct MusicRecognitionCompactView: View {
    let state: MusicRecognitionActivity.State
    var minimal = false
    var leadingOnly = false
    var restingHeight: CGFloat = 32
    @ObservedObject private var activity = MusicRecognitionActivity.shared

    static func wing(for state: MusicRecognitionActivity.State, restingHeight h: CGFloat) -> CGFloat {
        let gap = LiveActivityView.cameraGap
        let left = h * (ShazamLook.markEdge + ShazamLook.mark) + gap
        let right = gap + h * (ShazamLook.wave + ShazamLook.waveEdge)
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
                        .padding(.leading, h * ShazamLook.markEdge)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    trailing(h)
                        .frame(width: h * ShazamLook.wave, height: h * ShazamLook.wave)
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
            ShazamWave(levels: activity.levels, height: h * ShazamLook.wave)
        } else if case .match(let song) = state, let url = song.artworkURL {
            AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.white.opacity(0.2) }
                .clipShape(RoundedRectangle(cornerRadius: h * ShazamLook.wave * ArtworkShape.restingRadius, style: .continuous))
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
    var fill: Color = ShazamLook.blue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().fill(fill)
            if listening, !reduceMotion {
                // A soft light going round inside its edge.
                TimelineView(.animation) { context in
                    let turn = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: ShazamLook.crossing * 1.5) / (ShazamLook.crossing * 1.5)
                    let angle = turn * 2 * .pi
                    Circle()
                        .fill(ShazamLook.light.opacity(0.55))
                        .frame(width: side * 0.5, height: side * 0.5)
                        .blur(radius: side * 0.14)
                        .offset(x: side * 0.32 * cos(angle), y: side * 0.32 * sin(angle))
                }
                .clipShape(Circle())
            }
            ShazamMark(listening: false, side: side * ShazamLook.discMark, tint: .white)
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

/// A waveform of what it hears, in Shazam's blue: the loudest of each tenth of a second, newest at
/// the right.
struct ShazamWave: View {
    @ObservedObject var levels: RecordingLevels
    let height: CGFloat

    var body: some View {
        let count = ShazamLook.bars
        let shown = Array(levels.levels.suffix(count))
        let padded = Array(repeating: CGFloat(0), count: max(count - shown.count, 0)) + shown
        let bar = height * 0.14
        HStack(spacing: (height - bar * CGFloat(count)) / CGFloat(count - 1)) {
            ForEach(Array(padded.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(ShazamLook.blue)
                    .frame(width: bar, height: max(bar, height * (0.25 + 0.75 * min(level * 1.6, 1))))
                    .animation(.easeOut(duration: 0.12), value: level)
            }
        }
        .frame(width: height, height: height)
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
        case .idle, .noMatch: state.title
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
            ActivityRowLayout.width(title: $0, detail: detail(for: state), buttons: trailing(for: state).count, restingHeight: h, camera: camera)
        }.max() ?? 0
    }

    static func height(restingHeight h: CGFloat) -> CGFloat { TimerLayout.tallHeight(h) }

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
            ActivityRow(
                restingHeight: h, camera: camera, width: Self.width(for: state, restingHeight: h, camera: camera),
                title: title, detail: failure ?? Self.detail(for: state), explanation: failure ?? Self.explanation(for: state),
                buttons: Self.trailing(for: state).count, revealed: revealed
            ) {
                picture(h, opens: actions.first == .openSong)
            } trailing: {
                ForEach(Array(actions.enumerated()), id: \.element) { index, action in
                    if action != .openSong { button(action, control: controls[index], h) }
                }
            }
        }
        .accessibilityLabel(String(localized: "Music Recognition"))
    }

    @ViewBuilder private func picture(_ h: CGFloat, opens: Bool) -> some View {
        let side = TimerLayout.content(h)
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
        IslandCircleButton(control: control, height: h, tint: .white, label: title(for: action)) {
            perform(action)
        } glyph: {
            switch action {
            case .cancel, .done:
                CrossGlyph(height: h)
            case .recognize:
                Image(systemName: state == .idle ? "shazam.logo.fill" : "arrow.clockwise")
                    .font(.system(size: h * (state == .idle ? 0.62 : 0.55), weight: .semibold))
                    .foregroundStyle(.white)
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
