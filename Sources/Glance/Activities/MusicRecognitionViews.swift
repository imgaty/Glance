//
//  MusicRecognitionViews.swift
//  Glance
//
//  Created by Gaty on 14/11/2026.
//

import SwiftUI

struct MusicRecognitionCompactView: View {
    let state: MusicRecognitionActivity.State
    var minimal = false
    var leadingOnly = false
    var restingHeight: CGFloat = 32
    static let wing: CGFloat = 96

    var body: some View {
        Group {
            if minimal {
                MusicRecognitionGlyph(state: state, minimal: true)
            } else {
                ZStack {
                    MusicRecognitionGlyph(state: state)
                        .frame(width: max(restingHeight - LiveActivityView.inset * 2, 0))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !leadingOnly {
                        Text(MusicRecognitionGlyph.caption(for: state))
                            .lineLimit(1)
                            .frame(width: Self.wing - LiveActivityView.inset * 2, alignment: .trailing)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .padding(.horizontal, LiveActivityView.inset)
            }
        }
        .font(.body)
        .foregroundStyle(.primary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Music recognition, \(state.title)"))
    }
}

/// A native state cue stays meaningful when the activity loses its text wing.
struct MusicRecognitionGlyph: View {
    let state: MusicRecognitionActivity.State
    var minimal = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static func symbol(for state: MusicRecognitionActivity.State) -> String {
        switch state {
        case .idle: "music.note"
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
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: Self.symbol(for: state))
            }
        }
        .font(.body)
        .foregroundStyle(.primary)
        .accessibilityHidden(true)
    }
}

struct MusicRecognitionActivityView: View {
    @ObservedObject var activity: MusicRecognitionActivity
    private let stateOverride: MusicRecognitionActivity.State?
    @Environment(\.activityPreview) private var preview
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(activity: MusicRecognitionActivity? = nil, stateOverride: MusicRecognitionActivity.State? = nil) {
        self.activity = activity ?? .shared
        self.stateOverride = stateOverride
    }

    private var state: MusicRecognitionActivity.State { stateOverride ?? activity.state }
    static func width(camera: CGFloat) -> CGFloat { max(440, camera + PlayerLayout.padding * 2) }
    static func height(restingHeight: CGFloat) -> CGFloat { restingHeight + LiveActivityView.cameraGap + 210 }

    enum Action: Hashable { case recognize, cancel, openSong, settings, done }

    static func actions(for state: MusicRecognitionActivity.State) -> [Action] {
        if state.isWorking { return [.cancel] }
        switch state {
        case .idle: return [.recognize]
        case .match(let song): return song.musicURL != nil || song.webURL != nil ? [.openSong, .done] : [.done]
        case .denied: return [.settings, .recognize, .done]
        case .restricted, .failure(.configuration): return [.done]
        default: return [.recognize, .done]
        }
    }

    static func controls(for state: MusicRecognitionActivity.State) -> [PlayerControl] {
        Array([PlayerControl.activityFirst, .activitySecond, .activityThird].prefix(actions(for: state).count))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                if case .match(let song) = state, let url = song.artworkURL {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        Image(systemName: "music.note").font(.title2).foregroundStyle(.secondary)
                    }
                    .frame(width: 48, height: 48)
                    .accessibilityHidden(true)
                } else {
                    Image(systemName: "music.note")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(state.title)
                        .font(.headline)
                        .lineLimit(2)
                    detail
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if state.isWorking, !reduceMotion {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(state.title)
            }
            if stateOverride == nil, let failure = activity.actionFailure {
                Text(failure)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                ForEach(Array(Self.actions(for: state).enumerated()), id: \.element) { index, action in
                    if action == .done { Spacer(minLength: 8) }
                    actionButton(action, control: Self.controls(for: state)[index])
                }
            }
            .controlSize(.regular)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Music Recognition")
    }

    @ViewBuilder private var detail: some View {
        switch state {
        case .idle:
            Text("Identify a song using your microphone. An audio signature is sent to Shazam.")
        case .requestingPermission:
            Text("Allow microphone access to recognize music.")
        case .recognizing:
            Text("Keep your Mac near the music.")
        case .match(let song):
            if let artist = song.artist { Text(artist) }
        case .noMatch:
            Text("Try again while music is playing.")
        case .denied:
            Text("Allow Glance to use the microphone in System Settings, then try again.")
        case .restricted:
            Text("Microphone access is restricted on this Mac.")
        case .failure(let failure):
            Text(failure.message)
        case .cancelled:
            Text("Music recognition has stopped.")
        }
    }

    private func title(for action: Action) -> String {
        switch action {
        case .recognize: return state == .idle ? String(localized: "Recognize Music") : String(localized: "Try Again")
        case .cancel: return String(localized: "Cancel")
        case .openSong:
            if case .match(let song) = state, song.musicURL != nil { return String(localized: "Open in Music") }
            return String(localized: "Open in Shazam")
        case .settings: return String(localized: "Microphone Settings…")
        case .done: return String(localized: "Done")
        }
    }

    private func actionButton(_ action: Action, control: PlayerControl) -> some View {
        let button = Button(title(for: action), role: action == .cancel ? .cancel : nil) { perform(action) }
        return Group {
            if [.recognize, .openSong, .settings].contains(action) { button.buttonStyle(.borderedProminent) } else { button.buttonStyle(.bordered) }
        }
        .notchControl()
        .keyControl(control, in: RoundedRectangle(cornerRadius: 6), spoken: title(for: action)) { perform(action) }
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
