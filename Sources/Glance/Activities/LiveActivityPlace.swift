//
//  LiveActivityPlace.swift
//  Glance
//
//  Created by Gaty on 19/11/2026.
//

import Foundation

/// Where the Live Activities show that macOS 27.3 has a menu bar pill of its own for: in the notch,
/// as Glance's, or left to macOS's menu bar. Those macOS has no pill for (calls, the battery,
/// devices, Focus) and those started from the notch's own menu (Recognize Music, Run Shortcut)
/// stay in the notch either way, as nothing else would show them.
enum LiveActivityPlace: String, CaseIterable, Identifiable {
    case notch, menuBar

    var id: Self { self }

    var title: String {
        switch self {
        case .notch: String(localized: "Notch")
        case .menuBar: String(localized: "Menu Bar")
        }
    }

    /// What it includes, as the Live Activities page says under its choice, its name in bold.
    var includes: String {
        switch self {
        case .notch: String(localized: "**Notch:** all Live Activities show beside the camera.")
        case .menuBar:
            String(
                localized:
                    "**Menu Bar:** Now Playing, Clock, recordings, AirDrop and shortcuts run elsewhere stay in the menu bar, as macOS shows them. The notch keeps calls, battery, devices, Focus, and what you start from its menu."
            )
        }
    }

    static func current(in defaults: UserDefaults = .standard) -> LiveActivityPlace {
        defaults.string(forKey: Preferences.liveActivityPlace).flatMap(Self.init(rawValue:)) ?? .notch
    }

    /// The switches of the activities macOS shows in the menu bar itself: Now Playing and its
    /// announcements, AirDrop, Clock's timers, stopwatch and alarms, and recordings.
    static let menuBarKinds: Set<String> = [
        Preferences.liveActivity, Preferences.musicTrackPop, Preferences.activityAirDrop, Preferences.activityClockTimers,
        Preferences.activityStopwatch, Preferences.activityAlarms, Preferences.activityScreenRecording, Preferences.activityVoiceMemos,
    ]

    /// Whether the place lets the notch show a kind of activity, by its switch's key: anything with
    /// Notch chosen; with Menu Bar, only what macOS has no pill of its own for. Its own switch is
    /// read beside this, where it always was.
    static func allows(_ key: String, in defaults: UserDefaults = .standard) -> Bool {
        current(in: defaults) == .notch || !menuBarKinds.contains(key)
    }

    /// Whether shortcuts run outside Glance show in the notch; those run from its menu always do.
    static func allowsShortcutsElsewhere(in defaults: UserDefaults = .standard) -> Bool { current(in: defaults) == .notch }
}
