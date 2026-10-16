//
//  OnboardingTour.swift
//  Glance
//
//  Created by Gaty on 10/10/2026.
//

import SwiftUI

/// One of Glance's features, as the welcome tour presents it: a line on the welcome page, then a few
/// steps showing how to use it and letting the user set it up, each with the notch playing a
/// made-up song. A new feature joins the tour by being added to `all`.
struct OnboardingFeature: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let color: Color
    /// What it does, a few lines on the welcome page.
    let highlights: [OnboardingHighlight]
    let steps: [OnboardingStep]

    /// Every feature, in the order the tour shows them.
    static var all: [OnboardingFeature] { [music, tray] }
}

/// A tile on the welcome page, as Apple lists what's new in an app: a symbol, a headline, and a
/// line.
struct OnboardingHighlight: Identifiable {
    let symbol: String
    let title: String
    let text: String
    var id: String { title }

    /// The last line, about the tour itself.
    static let personalize = OnboardingHighlight(
        symbol: "slider.horizontal.3", title: "Make It Yours",
        text: "Choose how the notch opens and looks.")
}

/// A step of a feature's tour: the notch as it looks, a title that says what to do, and what to
/// choose.
struct OnboardingStep: Identifiable {
    let id: String
    let title: String
    let scene: NotchScene
    /// What to choose, in order down the page.
    var settings: [OnboardingSetting] = []
}

/// The notch as a step shows it.
enum NotchScene {
    /// Closed, to be opened right there, as the notch on the screen is.
    case tryOpening
    /// Open on the player, turning from one layout to the other until one is chosen.
    case layouts
    /// Closed, with the cover and the waveform beside the camera, announcing the song now and then.
    case liveActivity
    /// A photo dragged up to the notch and dropped in the tray, round after round.
    case tray
}

/// What a step lets the user choose.
enum OnboardingSetting {
    /// How the notch opens: under the pointer, with a click, or either.
    case openTrigger
    /// The player's layout, and the background behind it.
    case look
    /// Switches, each turning a setting on or off.
    case switches([OnboardingSwitch])
}

/// A setting that's on or off, by its key in the app's settings.
struct OnboardingSwitch: Identifiable {
    let key: String
    let title: String
    var id: String { key }
}

// MARK: - Music

extension OnboardingFeature {
    static var music: OnboardingFeature {
        OnboardingFeature(
            id: "music", title: "Music", symbol: "music.note", color: .pink,
            highlights: [
                OnboardingHighlight(
                    symbol: "music.note", title: "What's Playing",
                    text: "Any app's song, with its cover and controls."),
                OnboardingHighlight(
                    symbol: "quote.bubble", title: "Lyrics", text: "The words, lit line by line as they're sung."),
                OnboardingHighlight(
                    symbol: "waveform", title: "Live Activity",
                    text: "The cover and a waveform beside the camera."),
            ],
            steps: [
                OnboardingStep(
                    id: "open", title: "Choose How the Notch Opens", scene: .tryOpening,
                    settings: [.openTrigger, .switches([OnboardingSwitch(key: Preferences.haptics, title: "Haptic feedback")])]),
                OnboardingStep(
                    id: "look", title: "Choose a Layout and Background", scene: .layouts, settings: [.look]),
                OnboardingStep(
                    id: "activity", title: "See What's Playing at a Glance", scene: .liveActivity,
                    settings: [
                        .switches([
                            OnboardingSwitch(key: Preferences.liveActivity, title: "Live Activities"),
                            OnboardingSwitch(key: Preferences.musicTrackPop, title: "Announce new audio"),
                        ])
                    ]),
            ])
    }
}

// MARK: - Tray

extension OnboardingFeature {
    static var tray: OnboardingFeature {
        OnboardingFeature(
            id: "tray", title: "Tray", symbol: "tray.full.fill", color: .indigo,
            highlights: [
                OnboardingHighlight(
                    symbol: "tray.and.arrow.down", title: "Tray", text: "Files you drop and what you copy, close at hand.")
            ],
            steps: [
                OnboardingStep(
                    id: "tray", title: "Keep Files and Copies in the Tray", scene: .tray,
                    settings: [
                        .switches([
                            OnboardingSwitch(key: Preferences.tray, title: "Tray"),
                            OnboardingSwitch(key: Preferences.trayClipboard, title: "Keep what you copy"),
                        ])
                    ])
            ])
    }
}
