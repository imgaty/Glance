import Foundation
import SwiftUI
import Testing

@testable import Glance

/// Settings > Live Activities' choice of the notch or the menu bar for what macOS has its own menu
/// bar pill for.
@Suite("Live Activities in the notch or the menu bar", .serialized)
struct LiveActivityPlaceTests {
    private static let suite = "dev.vibe.Glance.tests.live-activity-place"

    private func defaults(_ place: LiveActivityPlace?) -> UserDefaults {
        let defaults = UserDefaults(suiteName: Self.suite)!
        defaults.removePersistentDomain(forName: Self.suite)
        if let place { defaults.set(place.rawValue, forKey: Preferences.liveActivityPlace) }
        return defaults
    }

    @Test("Unchosen, it's the notch, as before there was a choice")
    func notchFirst() {
        #expect(LiveActivityPlace.current(in: defaults(nil)) == .notch)
        let stray = defaults(nil)
        stray.set("somewhere", forKey: Preferences.liveActivityPlace)
        #expect(LiveActivityPlace.current(in: stray) == .notch)
    }

    @Test("In the notch, everything shows there")
    func notchShowsAll() {
        let defaults = defaults(.notch)
        for key in LiveActivityPlace.menuBarKinds { #expect(LiveActivityPlace.allows(key, in: defaults)) }
        #expect(LiveActivityPlace.allowsShortcutsElsewhere(in: defaults))
    }

    @Test("In the menu bar, what macOS has a pill for leaves the notch; the rest stays")
    func menuBarLeavesItsOwn() {
        let defaults = defaults(.menuBar)
        for key in [
            Preferences.liveActivity, Preferences.musicTrackPop, Preferences.activityAirDrop, Preferences.activityClockTimers,
            Preferences.activityStopwatch, Preferences.activityAlarms, Preferences.activityScreenRecording, Preferences.activityVoiceMemos,
        ] {
            #expect(!LiveActivityPlace.allows(key, in: defaults), "\(key)")
        }
        for key in [
            Preferences.activityCalls, Preferences.activityCharging, Preferences.activityLowBattery, Preferences.activityDevices,
            Preferences.activityFocus, Preferences.activityRecognition, Preferences.activityShortcuts,
        ] {
            #expect(LiveActivityPlace.allows(key, in: defaults), "\(key)")
        }
        // Shortcuts run from the notch's menu stay; those run elsewhere go to macOS's pill.
        #expect(!LiveActivityPlace.allowsShortcutsElsewhere(in: defaults))
    }

    @Test("The page's picture leaves out what's in the menu bar")
    func previewFollows() {
        let inMenuBar = PreviewActivity.turnedOn(in: defaults(.menuBar), hasBattery: true)
        #expect(inMenuBar == [.charging, .lowBattery, .device, .call, .focus, .recognition, .shortcut])
        #expect(PreviewActivity.turnedOn(in: defaults(.notch), hasBattery: true) == PreviewActivity.allCases)
    }

    @Test("Each place says what it includes, under the choice")
    func footnote() {
        #expect(LiveActivityPlace.allCases.map(\.title) == [String(localized: "Notch"), String(localized: "Menu Bar")])
        for place in LiveActivityPlace.allCases { #expect(place.includes.hasPrefix("**" + place.title)) }
    }

    @Test("With Menu Bar chosen, those switches show off and can't be changed, and their own values come back with Notch")
    func menuBarSwitchesKeepTheirValues() {
        for saved in [true, false] {
            var stored = saved
            var place = LiveActivityPlace.notch
            let shown = ActivitiesPage.placed(Binding(get: { stored }, set: { stored = $0 })) { place }
            #expect(shown.wrappedValue == saved)
            place = .menuBar
            #expect(shown.wrappedValue == false)
            // Grayed out, but should anything still set it, the saved value stays.
            shown.wrappedValue = !saved
            #expect(stored == saved)
            place = .notch
            #expect(shown.wrappedValue == saved)
            shown.wrappedValue = !saved
            #expect(stored == !saved)
        }
    }
}
