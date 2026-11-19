//
//  MacSettings.swift
//  Glance
//
//  Created by Gaty on 18/11/2026.
//

import AppKit

/// The Mac's own settings that a Glance setting has an equivalent of. A new install starts each of
/// those Glance settings as the Mac has its own (see `Preferences.keepEarlierDefaults`); after
/// that, they're Glance's alone.
struct MacSettings: Equatable {
    /// Reduce motion, in Accessibility settings, under Display.
    var reducesMotion: Bool
    /// Force Click and haptic feedback, in Trackpad settings.
    var hapticFeedback: Bool

    /// The Glance settings that start as the Mac has its own, with their first values.
    var firstValues: [String: Any] {
        [
            Preferences.haptics: hapticFeedback,
            // The moving cover never plays with Reduce motion on, so its switch starts off, as it is.
            Preferences.musicAnimatedArtwork: !reducesMotion,
        ]
    }

    /// As the Mac has them now, read as they're kept, so nothing is asked for and nothing changes.
    static var current: MacSettings {
        MacSettings(reducesMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, hapticFeedback: trackpadHaptics())
    }

    /// Where Trackpad settings keeps Force Click and haptic feedback, which macOS hands to the
    /// trackpad itself.
    static let trackpad = "com.apple.AppleMultitouchTrackpad"

    /// Whether the trackpad taps back. Trackpad settings keeps its switch as two values:
    /// `ActuateDetents`, the taps, and `ForceSuppressed`, Force Click turned off. With neither
    /// kept, it's on, as a new Mac has it.
    static func trackpadHaptics(_ value: (String) -> Any? = { CFPreferencesCopyAppValue($0 as CFString, trackpad as CFString) }) -> Bool {
        if let taps = value("ActuateDetents") as? Bool { return taps }
        return !(value("ForceSuppressed") as? Bool ?? false)
    }
}
