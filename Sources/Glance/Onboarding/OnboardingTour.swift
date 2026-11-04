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
        symbol: "slider.horizontal.3", title: String(localized: "Make It Yours"),
        text: String(localized: "Choose how the notch opens and looks."))
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
    /// The setting it does nothing without, as Settings has it: off, it's dimmed.
    var needs: String?
    var id: String { key }
}

// MARK: - Music

extension OnboardingFeature {
    static var music: OnboardingFeature {
        OnboardingFeature(
            id: "music", title: String(localized: "Music"), symbol: "music.note", color: .pink,
            highlights: [
                OnboardingHighlight(
                    symbol: "music.note", title: String(localized: "What's Playing"),
                    text: String(localized: "Any app's song, with its cover and controls.")),
                OnboardingHighlight(
                    symbol: "quote.bubble", title: String(localized: "Lyrics"), text: String(localized: "The words, lit line by line as they're sung.")),
                OnboardingHighlight(
                    symbol: "waveform", title: String(localized: "Live Activities"),
                    text: String(localized: "Timers, AirDrop and more, beside the camera.")),
            ],
            steps: [
                OnboardingStep(
                    id: "open", title: String(localized: "Choose How the Notch Opens"), scene: .tryOpening,
                    settings: [.openTrigger, .switches([OnboardingSwitch(key: Preferences.haptics, title: String(localized: "Haptic feedback"))])]),
                OnboardingStep(
                    id: "look", title: String(localized: "Choose a Layout and Background"), scene: .layouts, settings: [.look]),
                OnboardingStep(
                    id: "activity", title: String(localized: "See What's Playing at a Glance"), scene: .liveActivity,
                    settings: [
                        .switches([
                            OnboardingSwitch(key: Preferences.liveActivity, title: String(localized: "Cover and waveform")),
                            OnboardingSwitch(key: Preferences.musicTrackPop, title: String(localized: "Announce new audio"), needs: Preferences.liveActivity),
                        ])
                    ]),
            ])
    }
}

// MARK: - Tray

extension OnboardingFeature {
    static var tray: OnboardingFeature {
        OnboardingFeature(
            id: "tray", title: String(localized: "Tray"), symbol: "tray.full.fill", color: .indigo,
            highlights: [
                OnboardingHighlight(
                    symbol: "tray.and.arrow.down", title: String(localized: "Tray"), text: String(localized: "Files you drop and what you copy, close at hand."))
            ],
            steps: [
                OnboardingStep(
                    id: "tray", title: String(localized: "Keep Files and Copies in the Tray"), scene: .tray,
                    settings: [
                        .switches([
                            OnboardingSwitch(key: Preferences.tray, title: String(localized: "Tray")),
                            OnboardingSwitch(key: Preferences.trayClipboard, title: String(localized: "Keep what you copy"), needs: Preferences.tray),
                        ])
                    ])
            ])
    }
}
