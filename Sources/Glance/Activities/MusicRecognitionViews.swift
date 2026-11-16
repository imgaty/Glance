//
//  MusicRecognitionViews.swift
//  Glance
//
//  Created by Gaty on 14/11/2026.
//

import SwiftUI

/// Music recognition beside the camera: its state at the left end, a word for it at the right; in the
/// bubble, the state alone.
struct MusicRecognitionCompactView: View {
    let state: MusicRecognitionActivity.State
    var minimal = false
    var leadingOnly = false
    var restingHeight: CGFloat = 32

    @MainActor
    static func wing(for state: MusicRecognitionActivity.State, restingHeight: CGFloat) -> CGFloat {
        CompactActivityLayout.wing(caption: MusicRecognitionGlyph.caption(for: state), restingHeight: restingHeight)
    }

    var body: some View {
        Group {
            if minimal {
                MusicRecognitionGlyph(state: state, minimal: true, restingHeight: restingHeight)
            } else {
                CompactActivityMark(caption: MusicRecognitionGlyph.caption(for: state), restingHeight: restingHeight, leadingOnly: leadingOnly) {
                    MusicRecognitionGlyph(state: state, restingHeight: restingHeight)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Music recognition, \(state.title)"))
    }
}

/// A state's mark, which still says what's happening when the words beside it are hidden.
struct MusicRecognitionGlyph: View {
    let state: MusicRecognitionActivity.State
    var minimal = false
    var restingHeight: CGFloat = 32
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static func symbol(for state: MusicRecognitionActivity.State) -> String {
        switch state {
        case .idle: "shazam.logo.fill"
        case .requestingPermission: "mic"
        case .recognizing: "waveform"
        case .match: "checkmark.circle.fill"
        case .noMatch: "questionmark.circle"
        case .denied, .restricted: "mic.slash"
        case .failure: "exclamationmark.triangle.fill"
        case .cancelled: "stop.circle.fill"
        }
    }

    static func caption(for state: MusicRecognitionActivity.State) -> String {
        switch state {
        case .idle: String(localized: "Recognize")
        case .requestingPermission: String(localized: "Microphone")
        case .recognizing: String(localized: "Listening…")
        case .match: String(localized: "Song Found")
        case .noMatch: String(localized: "No Match")
        case .denied: String(localized: "Mic Off")
        case .restricted: String(localized: "Restricted")
        case .failure: String(localized: "Unavailable")
        case .cancelled: String(localized: "Stopped")
        }
    }

    var body: some View {
        Group {
            if state == .recognizing, !minimal, !reduceMotion {
                ProgressView().controlSize(.small).tint(.white)
            } else {
                Image(systemName: Self.symbol(for: state))
                    .font(.system(size: minimal ? restingHeight * 0.5 : LiveActivityView.textSize(for: restingHeight) + 2, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Music recognition opened, in one row: Shazam's mark at the left end, or the song's cover once
/// it's found, which opens the song; what's happening beside the camera, and under it what to do or
/// who it's by; at the right end, the one or two things to do next.
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
        case .recognizing: String(localized: "Listening…")
        case .match(let song): song.title
        case .failure: String(localized: "Unavailable")
        case .cancelled: String(localized: "Canceled")
        }
    }

    /// One short line under the title.
    static func detail(for state: MusicRecognitionActivity.State) -> String {
        switch state {
        case .idle: String(localized: "Sends an audio signature to Shazam")
        case .requestingPermission: String(localized: "Allow microphone access")
        case .recognizing: String(localized: "Keep your Mac near the music")
        case .match(let song): song.artist ?? String(localized: "Song Found")
        case .noMatch: String(localized: "Try again while music plays")
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

    @MainActor
    static func width(for state: MusicRecognitionActivity.State, restingHeight h: CGFloat, camera: CGFloat) -> CGFloat {
        ActivityRowLayout.width(title: title(for: state), detail: detail(for: state), buttons: trailing(for: state).count, restingHeight: h, camera: camera)
    }

    static func height(restingHeight h: CGFloat) -> CGFloat { TimerLayout.tallHeight(h) }

    var body: some View {
        let h = restingHeight
        let actions = Self.actions(for: state)
        let controls = Self.controls(for: state)
        let failure = stateOverride == nil ? activity.actionFailure : nil
        ActivityRow(
            restingHeight: h, camera: camera, width: Self.width(for: state, restingHeight: h, camera: camera),
            title: Self.title(for: state), detail: failure ?? Self.detail(for: state), explanation: failure ?? Self.explanation(for: state),
            buttons: Self.trailing(for: state).count, revealed: revealed
        ) {
            picture(h, opens: actions.first == .openSong)
        } trailing: {
            ForEach(Array(actions.enumerated()), id: \.element) { index, action in
                if action != .openSong { button(action, control: controls[index], h) }
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
        } else {
            ActivityRowPicture(restingHeight: h, label: opens ? title(for: .openSong) : nil, open: opens ? { perform(.openSong) } : nil) {
                Image(systemName: "shazam.logo.fill")
                    .font(.system(size: h * 0.62, weight: .semibold))
                    .foregroundStyle(.white)
            }
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
