//
//  PreferencesTests.swift
//  GlanceTests
//
//  Created by Gaty on 10/10/2026.
//

import Foundation
import Testing

@testable import Glance

/// The keys settings are stored under, and the values stored. Both are kept in people's defaults,
/// so changing either would lose their choices; these tests make that a deliberate decision.
@Suite("Stored settings", .serialized)
struct PreferencesTests {
    @Test(
        "Settings keys stay the same",
        arguments: [
            (Preferences.showOnPlainDisplays, "showOnDisplaysWithoutNotch"),
            (Preferences.glassFollowsSystem, "glassFollowsSystem"),
            (Preferences.glassDarkness, "glassDarkness"),
            (Preferences.glassBlur, "glassBlur"),
            (Preferences.musicAccentTimeline, "musicAccentTimeline"),
            (Preferences.musicLayout, "musicLayout"),
            (Preferences.musicAccentSource, "musicAccentSource"),
            (Preferences.musicLeftButton, "musicLeftButton"),
            (Preferences.musicRightButton, "musicRightButton"),
            (Preferences.lyrics, "lyrics"),
            (Preferences.liveActivity, "liveActivity"),
            (Preferences.musicBackground, "musicBackground"),
            (Preferences.musicAnimatedArtwork, "musicAnimatedArtwork"),
            (Preferences.musicHiddenApps, "musicHiddenApps"),
            (Preferences.musicSeenApps, "musicSeenApps"),
            (Preferences.musicShowsNewApps, "musicShowsNewApps"),
            (Preferences.musicAppBadge, "musicAppBadge"),
            (Preferences.sameLook, "sameLookEverywhere"),
            (Preferences.musicTrackPop, "musicTrackPop"),
            (Preferences.notchEnabled, "notchEnabled"),
            (Preferences.notchStyle, "notchStyle"),
            (Preferences.swipeToOpen, "swipeToOpen"),
            (Preferences.swipeToSkip, "swipeToSkip"),
            (Preferences.onboardingDone, "onboardingDone"),
            (Preferences.openTrigger, "openTrigger"),
            (Preferences.hoverDelay, "hoverDelay"),
            (Preferences.clickDelay, "clickDelay"),
            (Preferences.haptics, "haptics"),
            (Preferences.hideInFullScreen, "hideInFullScreen"),
        ])
    func keys(key: String, stored: String) {
        #expect(key == stored)
    }

    @Test("Each display keeps its own look")
    func perDisplayKeys() {
        #expect(
            Preferences.perDisplay == [
                Preferences.glassFollowsSystem, Preferences.glassDarkness, Preferences.glassBlur, Preferences.musicBackground,
            ])
    }

    @Test("A display's own key adds its ID after a colon, never a dot")
    func displayKey() {
        #expect(Preferences.key("glassBlur", for: "1") == "glassBlur:1")
        #expect(
            Preferences.key(Preferences.glassDarkness, for: "37D8832A-2D66-02CA-B9F7-8F30A301B230")
                == "glassDarkness:37D8832A-2D66-02CA-B9F7-8F30A301B230")
        for key in Preferences.perDisplay {
            #expect(!Preferences.key(key, for: "42").contains("."))
        }
    }

    @Test("A look's key is the display's own while displays look different")
    func lookKeyPerDisplay() {
        preservingDefaults([Preferences.sameLook]) {
            UserDefaults.standard.set(false, forKey: Preferences.sameLook)
            #expect(Preferences.lookKey(Preferences.glassBlur, display: "7") == "glassBlur:7")
        }
    }

    @Test("A look's key is the shared one while every display looks the same")
    func lookKeyShared() {
        preservingDefaults([Preferences.sameLook]) {
            UserDefaults.standard.set(true, forKey: Preferences.sameLook)
            #expect(Preferences.lookKey(Preferences.glassBlur, display: "7") == Preferences.glassBlur)
        }
    }

    @Test("Without a display, a look's key is the shared one")
    func lookKeyWithoutDisplay() {
        preservingDefaults([Preferences.sameLook]) {
            UserDefaults.standard.set(false, forKey: Preferences.sameLook)
            #expect(Preferences.lookKey(Preferences.glassBlur, display: nil) == Preferences.glassBlur)
        }
    }

    @Test("A new display starts from the shared look, keeping whatever it already has")
    func seed() {
        let display = "notch-tests-\(UUID().uuidString)"
        let ownKeys = Preferences.perDisplay.map { Preferences.key($0, for: display) }
        preservingDefaults(Preferences.perDisplay + ownKeys) {
            let defaults = UserDefaults.standard
            defaults.set(0.25, forKey: Preferences.glassBlur)
            defaults.set(0.75, forKey: Preferences.glassDarkness)
            // The display already has its own darkness: that one stays.
            defaults.set(0.5, forKey: Preferences.key(Preferences.glassDarkness, for: display))

            Preferences.seed(display)

            #expect(defaults.double(forKey: Preferences.key(Preferences.glassBlur, for: display)) == 0.25)
            #expect(defaults.double(forKey: Preferences.key(Preferences.glassDarkness, for: display)) == 0.5)
        }
    }

    // MARK: - Stored values

    @Test("Player layouts are stored by name")
    func layoutValues() {
        #expect(PlayerLayout.allCases.map(\.rawValue) == ["top", "side"])
    }

    @Test(
        "Backgrounds keep the names earlier versions stored",
        arguments: [
            (MusicBackground.replaceGlass, "artwork"),
            (.fullscreen, "spotlight"),
            (.spotlight, "cover"),
            (.none, "none"),
        ])
    func backgroundValues(background: MusicBackground, stored: String) {
        #expect(background.rawValue == stored)
        #expect(MusicBackground(rawValue: stored) == background)
    }

    @Test("Accent colors are stored by name")
    func accentValues() {
        #expect(
            AccentSource.allCases.map(\.rawValue) == [
                "artwork", "system", "blue", "purple", "pink", "red", "orange", "yellow", "green", "graphite",
            ])
    }

    @Test(
        "Player controls are stored by name",
        arguments: [
            (PlayerSlot.favorite, "favorite"),
            (.shuffle, "shuffle"),
            (.repeatMode, "repeat"),
            (.output, "output"),
            (.lyrics, "lyrics"),
            (.empty, "none"),
        ])
    func slotValues(slot: PlayerSlot, stored: String) {
        #expect(slot.rawValue == stored)
        #expect(PlayerSlot(rawValue: stored) == slot)
    }

    @Test("Opening triggers are stored by name")
    func triggerValues() {
        #expect(OpenTrigger.allCases.map(\.rawValue) == ["hover", "click", "both"])
    }

    // MARK: - Defaults

    @Test("Settings start as they should")
    func registeredDefaults() {
        Preferences.registerDefaults()
        let registered = UserDefaults.standard.volatileDomain(forName: UserDefaults.registrationDomain)
        #expect(registered[Preferences.showOnPlainDisplays] as? Bool == true)
        #expect(registered[Preferences.liveActivity] as? Bool == true)
        #expect(registered[Preferences.musicBackground] as? String == MusicBackground.replaceGlass.rawValue)
        #expect(registered[Preferences.musicAnimatedArtwork] as? Bool == true)
        #expect(registered[Preferences.musicShowsNewApps] as? Bool == true)
        #expect(registered[Preferences.musicAppBadge] as? Bool == false)
        #expect(registered[Preferences.musicTrackPop] as? Bool == true)
        #expect(registered[Preferences.notchEnabled] as? Bool == true)
        #expect(registered[Preferences.swipeToOpen] as? Bool == true)
        #expect(registered[Preferences.swipeToSkip] as? Bool == true)
        #expect(registered[Preferences.lyrics] as? Bool == true)
        #expect(registered[Preferences.musicLayout] as? String == PlayerLayout.top.rawValue)
        #expect(registered[Preferences.openTrigger] as? String == OpenTrigger.both.rawValue)
        #expect(registered[Preferences.hoverDelay] as? Double == 0.2)
        #expect(registered[Preferences.clickDelay] as? Double == 0.0)
        #expect(registered[Preferences.haptics] as? Bool == false)
        #expect(registered[Preferences.hideInFullScreen] as? Bool == true)
    }

    @Test("The layout falls back to the cover on top")
    func currentLayout() {
        preservingDefaults([Preferences.musicLayout]) {
            let defaults = UserDefaults.standard
            defaults.set("side", forKey: Preferences.musicLayout)
            #expect(PlayerLayout.current == .side)
            defaults.set("top", forKey: Preferences.musicLayout)
            #expect(PlayerLayout.current == .top)
            defaults.set("something else", forKey: Preferences.musicLayout)
            #expect(PlayerLayout.current == .top)
        }
    }
}

/// Which apps' music shows in the notch.
@Suite("Music apps", .serialized)
struct MusicAppsTests {
    private let keys = [Preferences.musicHiddenApps, Preferences.musicSeenApps, Preferences.musicShowsNewApps]
    private let first = "com.example.notch-tests.First"
    private let second = "com.example.notch-tests.Second"

    /// Runs `body` with no apps seen or hidden, putting the real lists back afterwards.
    private func withEmptyLists(_ body: () -> Void) {
        preservingDefaults(keys) {
            let defaults = UserDefaults.standard
            defaults.removeObject(forKey: Preferences.musicHiddenApps)
            defaults.removeObject(forKey: Preferences.musicSeenApps)
            defaults.removeObject(forKey: Preferences.musicShowsNewApps)
            body()
        }
    }

    @Test("With nothing stored, no apps are seen or hidden")
    func empty() {
        withEmptyLists {
            #expect(MusicApps.hidden.isEmpty)
            #expect(MusicApps.seen.isEmpty)
            #expect(MusicApps.signature == "")
        }
    }

    @Test("A helper apps play through, like WebKit's GPU process, is never listed as an app")
    func helpers() {
        withEmptyLists {
            MusicApps.remember("com.apple.WebKit.GPU")
            #expect(MusicApps.seen.isEmpty)
            // One saved before helpers were told apart isn't listed either.
            UserDefaults.standard.set("\(first),com.apple.WebKit.GPU", forKey: Preferences.musicSeenApps)
            #expect(MusicApps.seen == [first])
            #expect(!MusicApps.isHelper(first))
        }
    }

    @Test("New apps show unless that's turned off")
    func showsNewAppsDefault() {
        withEmptyLists {
            #expect(MusicApps.showsNewApps)
            UserDefaults.standard.set(false, forKey: Preferences.musicShowsNewApps)
            #expect(!MusicApps.showsNewApps)
        }
    }

    @Test("Music with no app known always shows")
    func unknownAppShows() {
        withEmptyLists {
            #expect(MusicApps.shows(nil))
        }
    }

    @Test("Hiding and showing an app")
    func hideAndShow() {
        withEmptyLists {
            MusicApps.set(first, shown: false)
            #expect(!MusicApps.shows(first))
            #expect(MusicApps.shows(second))
            #expect(MusicApps.hidden == [first])

            // Hiding it again doesn't list it twice.
            MusicApps.set(first, shown: false)
            #expect(MusicApps.hidden == [first])

            MusicApps.set(first, shown: true)
            #expect(MusicApps.shows(first))
            #expect(MusicApps.hidden.isEmpty)
        }
    }

    @Test("The lists are stored comma separated")
    func storedFormat() {
        withEmptyLists {
            MusicApps.set(first, shown: false)
            MusicApps.set(second, shown: false)
            #expect(UserDefaults.standard.string(forKey: Preferences.musicHiddenApps) == "\(first),\(second)")
        }
    }

    @Test("The signature changes with the hidden apps, not their order")
    func signature() {
        withEmptyLists {
            MusicApps.set(second, shown: false)
            MusicApps.set(first, shown: false)
            let signature = MusicApps.signature
            #expect(signature == [first, second].sorted().joined(separator: ","))
            MusicApps.set(first, shown: true)
            #expect(MusicApps.signature != signature)
        }
    }

    @Test("An app playing for the first time joins the list, shown")
    func rememberShown() {
        withEmptyLists {
            MusicApps.remember(first)
            #expect(MusicApps.seen == [first])
            #expect(MusicApps.shows(first))
        }
    }

    @Test("An app playing for the first time joins hidden when new apps don't show")
    func rememberHidden() {
        withEmptyLists {
            UserDefaults.standard.set(false, forKey: Preferences.musicShowsNewApps)
            MusicApps.remember(first)
            #expect(MusicApps.seen == [first])
            #expect(!MusicApps.shows(first))
        }
    }

    @Test("An app already listed keeps its choice when it plays again")
    func rememberKnown() {
        withEmptyLists {
            MusicApps.remember(first)
            MusicApps.set(first, shown: false)
            UserDefaults.standard.set(true, forKey: Preferences.musicShowsNewApps)
            MusicApps.remember(first)
            #expect(MusicApps.seen == [first])
            #expect(!MusicApps.shows(first))
        }
    }

    @Test("Adding an app lists it, shown, even if it was hidden")
    func add() {
        withEmptyLists {
            MusicApps.set(first, shown: false)
            MusicApps.add(first)
            #expect(MusicApps.seen == [first])
            #expect(MusicApps.shows(first))
        }
    }

    @Test("Forgetting an app takes it off the list and shows it")
    func forget() {
        withEmptyLists {
            MusicApps.remember(first)
            MusicApps.remember(second)
            MusicApps.set(first, shown: false)
            MusicApps.forget(first)
            #expect(MusicApps.seen == [second])
            #expect(MusicApps.shows(first))
        }
    }

    @Test("An app that isn't installed is named from its identifier")
    func nameOfMissingApp() {
        #expect(MusicApps.name(of: "com.example.notch-tests.NotARealPlayer") == "NotARealPlayer")
        #expect(MusicApps.name(of: "NoDots") == "NoDots")
    }

    @Test("Music, which is always installed, can't be taken off the list")
    func musicNotRemovable() {
        #expect(!MusicApps.removable(PlayerScripting.music))
    }

    @Test("Any other app can be taken off the list")
    func otherRemovable() {
        #expect(MusicApps.removable(first))
    }

    @Test("Music and Spotify come first, then the other apps by name")
    func listedOrder() {
        let zed = "com.example.notch-tests.Zed"
        let alpha = "org.example.notch-tests.Alpha"
        let middle = "net.example.notch-tests.middle"
        let listed = MusicApps.listed(seen: [zed, alpha, middle])
        // Music is always installed; Spotify only shows when it is, or has played.
        #expect(listed.first == PlayerScripting.music)
        #expect(Array(listed.suffix(3)) == [alpha, middle, zed])
        #expect(listed.filter { $0 == PlayerScripting.music }.count == 1)
    }

    @Test("Spotify is listed once it has played, installed or not")
    func listedSpotifyOnce() {
        let listed = MusicApps.listed(seen: [PlayerScripting.spotify, first])
        #expect(listed.contains(PlayerScripting.spotify))
        #expect(listed.filter { $0 == PlayerScripting.spotify }.count == 1)
        #expect(listed.last == first)
    }
}
