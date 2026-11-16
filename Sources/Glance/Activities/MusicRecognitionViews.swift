//
//  MusicRecognitionViews.swift
//  Glance
//
//  Created by Gaty on 14/11/2026.
//

import SwiftUI

/// Music recognition beside the camera, as Apple's progress activity: Shazam's mark at the left end,
/// and at the right the ring, going round while it listens, or how it ended; in the bubble, the
/// ring alone.
struct MusicRecognitionCompactView: View {
    let state: MusicRecognitionActivity.State
    var minimal = false
    var leadingOnly = false
    var restingHeight: CGFloat = 32

    static func wing(for state: MusicRecognitionActivity.State, restingHeight: CGFloat) -> CGFloat {
        TaskCompactMark<EmptyView>.wing(restingHeight: restingHeight)
    }

    var body: some View {
        Group {
            if minimal {
                TaskRing(status: MusicRecognitionGlyph.status(for: state), diameter: restingHeight * TimerLayout.ring)
            } else {
                TaskCompactMark(status: MusicRecognitionGlyph.status(for: state), restingHeight: restingHeight, leadingOnly: leadingOnly) {
                    MusicRecognitionGlyph(side: SystemActivityView.side(restingHeight))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Music recognition, \(state.title)"))
    }
}

/// Shazam's mark, white, filling the side given as an app's icon would.
struct MusicRecognitionGlyph: View {
    let side: CGFloat

    /// Going round while it asks for the microphone or listens; a check when it found the song, an
    /// exclamation mark when it found none or couldn't listen, and the stop square when you canceled.
    static func status(for state: MusicRecognitionActivity.State) -> TaskStatus {
        switch state {
        case .idle: .counting(0)
        case .requestingPermission, .recognizing: .working
        case .match: .done
        case .noMatch, .denied, .restricted, .failure: .failed
        case .cancelled: .stopped
        }
    }

    var body: some View {
        Image(systemName: "shazam.logo.fill")
            .resizable()
            .scaledToFit()
            .foregroundStyle(.white)
            .frame(width: side, height: side)
            .accessibilityHidden(true)
    }
}

/// Music recognition opened, in one row, as Apple's progress activity: Shazam's mark at the left end,
/// or the song's cover once it's found, which opens the song; what's happening beside the camera,
/// and under it what to do or who it's by; at the right end the ring, with the square inside it that
/// cancels listening. Once it's over the ring shows how it ended and closes it, as Done, with what
/// else there is to do before it.
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

    enum Action: Hashable {
        case recognize, cancel, openSong, settings, done

        /// Its place in the row: Cancel and Done are the one ring, which goes on from one to the
        /// other, so what changes in it is seen to change.
        var slot: String { self == .cancel || self == .done ? "ring" : String(describing: self) }
    }

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
            ForEach(Array(actions.enumerated()), id: \.element.slot) { index, action in
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

    @ViewBuilder private func button(_ action: Action, control: PlayerControl, _ h: CGFloat) -> some View {
        if action == .cancel || action == .done {
            TaskRingButton(status: MusicRecognitionGlyph.status(for: state), control: control, height: h, label: title(for: action)) {
                perform(action)
            }
            .accessibilityIdentifier("recognition-\(String(describing: action))")
        } else {
            circleButton(action, control: control, h)
        }
    }

    private func circleButton(_ action: Action, control: PlayerControl, _ h: CGFloat) -> some View {
        IslandCircleButton(control: control, height: h, tint: .white, label: title(for: action)) {
            perform(action)
        } glyph: {
            switch action {
            case .cancel, .done:
                EmptyView()
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
