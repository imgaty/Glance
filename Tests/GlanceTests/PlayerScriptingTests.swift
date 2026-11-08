//
//  PlayerScriptingTests.swift
//  GlanceTests
//
//  Created by Gaty on 10/10/2026.
//

import AppKit
import Foundation
import Testing

@testable import Glance

/// The AppleScript Glance sends Music and Spotify, and how it reads their replies.
@Suite("Player scripting")
struct PlayerScriptingTests {
    private let music = PlayerScripting.music
    private let spotify = PlayerScripting.spotify
    private let other = "com.example.SomePlayer"

    @Test("The players' bundle identifiers")
    func identifiers() {
        #expect(music == "com.apple.Music")
        #expect(spotify == "com.spotify.client")
    }

    // MARK: - Repeat

    @Test("Repeat steps through off, all and one, then back to off")
    func repeatCycle() {
        #expect(RepeatMode.off.next == .all)
        #expect(RepeatMode.all.next == .one)
        #expect(RepeatMode.one.next == .off)
    }

    @Test(
        "Repeat's raw values are Music's own words",
        arguments: [
            (RepeatMode.off, "off"), (.all, "all"), (.one, "one"),
        ])
    func repeatRawValues(mode: RepeatMode, raw: String) {
        #expect(mode.rawValue == raw)
        #expect(RepeatMode(rawValue: raw) == mode)
    }

    // MARK: - Reading the options

    @Test("Music's reply gives shuffle, repeat and favorite")
    func musicOptions() {
        #expect(
            PlayerScripting.options(from: "true|all|true", app: music)
                == PlaybackOptions(shuffle: true, repeatMode: .all, favorite: true))
        #expect(
            PlayerScripting.options(from: "false|one|false", app: music)
                == PlaybackOptions(shuffle: false, repeatMode: .one, favorite: false))
        #expect(
            PlayerScripting.options(from: "false|off|false", app: music)
                == PlaybackOptions(shuffle: false, repeatMode: .off, favorite: false))
    }

    @Test("Music's reply without a favorite leaves it unknown")
    func musicWithoutFavorite() {
        #expect(
            PlayerScripting.options(from: "true|all", app: music)
                == PlaybackOptions(shuffle: true, repeatMode: .all, favorite: nil))
    }

    @Test("An unknown repeat word leaves repeat unknown")
    func unknownRepeat() {
        let options = PlayerScripting.options(from: "true|sometimes|true", app: music)
        #expect(options.shuffle == true)
        #expect(options.repeatMode == nil)
        #expect(options.favorite == true)
    }

    @Test("Spotify's reply gives shuffle and repeat, which it only has on or off")
    func spotifyOptions() {
        #expect(
            PlayerScripting.options(from: "true|true", app: spotify)
                == PlaybackOptions(shuffle: true, repeatMode: .all, favorite: nil))
        #expect(
            PlayerScripting.options(from: "false|false", app: spotify)
                == PlaybackOptions(shuffle: false, repeatMode: .off, favorite: nil))
    }

    @Test("Spotify never has a favorite, even if the reply has a third part")
    func spotifyIgnoresFavorite() {
        #expect(PlayerScripting.options(from: "true|false|true", app: spotify).favorite == nil)
    }

    @Test("Spotify's DJ is told by shuffle and repeat not being offered, for its songs and its own words")
    func spotifyDJ() {
        #expect(
            PlayerScripting.options(from: "false|false|false|spotify:track:1UYj8qTWjneZJDVjUMwMub", app: spotify)
                == PlaybackOptions(dj: true))
        #expect(
            PlayerScripting.options(from: "false|false|false|spotify:media:0000000000000000000000", app: spotify)
                == PlaybackOptions(dj: true))
        // A podcast doesn't offer them either, but it isn't the DJ.
        #expect(
            PlayerScripting.options(from: "false|false|false|spotify:episode:4rOoJ6Egrf8K2IrywzwOMk", app: spotify)
                == PlaybackOptions())
        #expect(
            PlayerScripting.options(from: "true|false|true|spotify:track:1UYj8qTWjneZJDVjUMwMub", app: spotify)
                == PlaybackOptions(shuffle: true, repeatMode: .off))
    }

    @Test("Where Spotify's own bar says, an album that reads as not offering shuffle isn't taken for the DJ")
    func spotifyDJFromItsBar() {
        // Spotify 1.3.8 on an album: its scripting says shuffle isn't offered, as for the DJ.
        let album = "false|false|false|spotify:track:7oVEtyuv9NBmnytsCIsY5I"
        #expect(PlayerScripting.options(from: album, app: spotify, dj: false) == PlaybackOptions(shuffle: false, repeatMode: .off))
        #expect(PlayerScripting.options(from: album, app: spotify, dj: true) == PlaybackOptions(dj: true))
        // The DJ's own words, and a podcast, as before.
        #expect(PlayerScripting.options(from: "false|false|false|spotify:media:0000000000000000000000", app: spotify, dj: true) == PlaybackOptions(dj: true))
        #expect(PlayerScripting.options(from: "false|false|false|spotify:episode:4rOoJ6Egrf8K2IrywzwOMk", app: spotify, dj: false) == PlaybackOptions())
        // Shuffle on is never the DJ's, which has none.
        #expect(PlayerScripting.options(from: "true|true|true|spotify:track:7oVEtyuv9NBmnytsCIsY5I", app: spotify, dj: false) == PlaybackOptions(shuffle: true, repeatMode: .all))
    }

    @Test("A reply that isn't options gives none", arguments: ["", "true", "garbage", "missing value"])
    func malformedReply(reply: String) {
        #expect(PlayerScripting.options(from: reply, app: music) == PlaybackOptions())
        #expect(PlayerScripting.options(from: reply, app: spotify) == PlaybackOptions())
    }

    @Test("Anything but \"true\" reads as off")
    func onlyTrueIsOn() {
        #expect(PlayerScripting.options(from: "TRUE|off", app: music).shuffle == false)
        #expect(PlayerScripting.options(from: "yes|off", app: music).shuffle == false)
    }

    // MARK: - Scripts

    @Test("Only Music and Spotify have a script to read their options")
    func readScripts() throws {
        let musicScript = try #require(PlayerScripting.readScript(for: music))
        #expect(musicScript.contains(#"tell application "Music""#))
        #expect(musicScript.contains("shuffle enabled"))
        #expect(musicScript.contains("song repeat"))
        #expect(musicScript.contains("favorited"))

        let spotifyScript = try #require(PlayerScripting.readScript(for: spotify))
        #expect(spotifyScript.contains(#"tell application "Spotify""#))
        #expect(spotifyScript.contains("shuffling"))
        #expect(spotifyScript.contains("repeating"))
        #expect(spotifyScript.contains("shuffling enabled"))
        #expect(spotifyScript.contains("spotify url"))
        #expect(!spotifyScript.contains("favorited"))

        #expect(PlayerScripting.readScript(for: other) == nil)
    }

    @Test("Turning shuffle on and off")
    func shuffleScripts() {
        #expect(PlayerScripting.setShuffle(true, app: music) == #"tell application "Music" to set shuffle enabled to true"#)
        #expect(PlayerScripting.setShuffle(false, app: music) == #"tell application "Music" to set shuffle enabled to false"#)
        #expect(PlayerScripting.setShuffle(true, app: spotify) == #"tell application "Spotify" to set shuffling to true"#)
        #expect(PlayerScripting.setShuffle(false, app: spotify) == #"tell application "Spotify" to set shuffling to false"#)
        #expect(PlayerScripting.setShuffle(true, app: other) == nil)
    }

    @Test("Setting repeat in Music, by its own words")
    func musicRepeatScripts() {
        #expect(PlayerScripting.setRepeat(.off, app: music) == #"tell application "Music" to set song repeat to off"#)
        #expect(PlayerScripting.setRepeat(.all, app: music) == #"tell application "Music" to set song repeat to all"#)
        #expect(PlayerScripting.setRepeat(.one, app: music) == #"tell application "Music" to set song repeat to one"#)
    }

    @Test("Setting repeat in Spotify, on for all and one")
    func spotifyRepeatScripts() {
        #expect(PlayerScripting.setRepeat(.off, app: spotify) == #"tell application "Spotify" to set repeating to false"#)
        #expect(PlayerScripting.setRepeat(.all, app: spotify) == #"tell application "Spotify" to set repeating to true"#)
        #expect(PlayerScripting.setRepeat(.one, app: spotify) == #"tell application "Spotify" to set repeating to true"#)
        #expect(PlayerScripting.setRepeat(.all, app: other) == nil)
    }

    @Test("Only Music can mark a favorite")
    func favoriteScripts() throws {
        let save = try #require(PlayerScripting.setFavorite(true, app: music))
        #expect(save.contains(#"tell application "Music""#))
        #expect(save.contains("set favorited of t to true"))
        #expect(try #require(PlayerScripting.setFavorite(false, app: music)).contains("set favorited of t to false"))
        #expect(PlayerScripting.setFavorite(true, app: spotify) == nil)
        #expect(PlayerScripting.setFavorite(true, app: other) == nil)
    }

    @Test("A streamed song's favorite is read from and set on its copy in the library")
    func favoriteOfLibraryCopy() throws {
        let scripts = try [#require(PlayerScripting.readScript(for: music)), #require(PlayerScripting.setFavorite(false, app: music))]
        for script in scripts {
            #expect(script.contains("if class of t is URL track then"))
            #expect(script.contains("every track of library playlist 1 whose name is songName and artist is songArtist and album is songAlbum"))
            #expect(script.contains("if libraryCopies is not {} then set t to item 1 of libraryCopies"))
            // A word Music's own dictionary uses, which fails as a variable.
            #expect(!script.contains("copies to"))
        }
    }

    @Test(
        "A press of the star stands until Music agrees, the song changes or the time is up",
        arguments: [
            (false as Bool?, true, 5.0, true),
            (true as Bool?, true, 5.0, false),
            (false as Bool?, false, 5.0, false),
            (false as Bool?, true, 11.0, false),
        ])
    func heldFavorite(read: Bool?, sameTrack: Bool, after: Double, holds: Bool) {
        let pressed = Date(timeIntervalSinceReferenceDate: 0)
        #expect(
            NowPlaying.holdsFavorite(true, against: read, sameTrack: sameTrack, until: pressed + 10, at: pressed + after) == holds)
    }

    @Test("The position is asked for in whole milliseconds")
    func positionScripts() {
        let expected = "return (player position * 1000) as integer"
        #expect(PlayerScripting.positionScript(for: music) == #"tell application "Music" to "# + expected)
        #expect(PlayerScripting.positionScript(for: spotify) == #"tell application "Spotify" to "# + expected)
        #expect(PlayerScripting.positionScript(for: other) == nil)
    }

    @Test("Telling an app a command")
    func tell() {
        #expect(PlayerScripting.tell(spotify, "play") == #"tell application "Spotify" to play"#)
        #expect(PlayerScripting.tell(music, "pause") == #"tell application "Music" to pause"#)
    }

    @Test("Music's status script reads the length in milliseconds and has no artwork address")
    func musicStatusScript() {
        let script = PlayerScripting.statusScript(for: music)
        #expect(script.contains(#"tell application "Music""#))
        #expect(script.contains("((duration of t) * 1000) as integer"))
        #expect(script.contains(#"if player state is stopped then return "stopped""#))
        #expect(!script.contains("artwork url"))
        #expect(script.contains("end tell"))
    }

    @Test("Spotify's status script reads its length as is and its artwork address")
    func spotifyStatusScript() {
        let script = PlayerScripting.statusScript(for: spotify)
        #expect(script.contains(#"tell application "Spotify""#))
        #expect(script.contains("(duration of t)"))
        #expect(!script.contains("((duration of t) * 1000)"))
        #expect(script.contains("artwork url of t"))
    }

    @Test("Status fields are split by a separator unlikely in a song's name")
    func statusSeparator() {
        #expect(PlayerScripting.separator == "|~|")
        // State, title, artist, album, length, position: five separators; Spotify adds its artwork.
        let musicSeparators = PlayerScripting.statusScript(for: music).components(separatedBy: PlayerScripting.separator).count - 1
        let spotifySeparators = PlayerScripting.statusScript(for: spotify).components(separatedBy: PlayerScripting.separator).count - 1
        #expect(musicSeparators == 5)
        #expect(spotifySeparators == 6)
    }

    // MARK: - Spotify track IDs

    @Test("A Spotify track's URI gives its ID")
    func spotifyTrackID() {
        #expect(PlayerScripting.spotifyTrackID("spotify:track:4uLU6hMCjMI75M1A2tKUQC") == "4uLU6hMCjMI75M1A2tKUQC")
    }

    @Test(
        "Other Spotify URIs have no track ID",
        arguments: [
            "spotify:local:Artist:Album:Title:180",
            "spotify:episode:0Q86acNRm6V9GYx55SXKwf",
            "spotify:track",
            "spotify:track:id:extra",
            "track:4uLU6hMCjMI75M1A2tKUQC",
            "",
        ])
    func noSpotifyTrackID(uri: String) {
        #expect(PlayerScripting.spotifyTrackID(uri) == nil)
    }

    @Test("The DJ's button is found by the name Spotify gives it in its own word lists")
    func djButtonName() {
        let list = Data(#"{"web-player.your-dj.jumpbutton.tooltip.hover": "Get some different DJ picks", "other": "x"}"#.utf8)
        #expect(SpotifyDJ.name(in: list) == "Get some different DJ picks")
        #expect(SpotifyDJ.name(in: Data("{}".utf8)) == nil)
        #expect(SpotifyDJ.accessibilitySwitch == "--force-renderer-accessibility")
    }

    @Test("Leaving the DJ for a playlist is read again every half second, so Shuffle comes back within the patience")
    func djLeftQuickly() {
        var reading = DJReading()
        let start = Date(timeIntervalSince1970: 0)
        func at(_ seconds: Double) -> Date { start + seconds }
        _ = reading.update(talking: false, inBar: true, now: at(0))
        #expect(!reading.unsure(at: at(0)))
        // Another playlist: Spotify draws its bar anew, unread for a moment, then without the button.
        _ = reading.update(talking: false, inBar: nil, now: at(2))
        #expect(reading.unsure(at: at(2)))
        var now = 2.5
        var on = true
        while on, now < 20 {
            on = reading.update(talking: false, inBar: false, now: at(now))
            if on { #expect(reading.unsure(at: at(now))) }
            now += DJReading.soon
        }
        #expect(!on)
        #expect(now - 2.5 <= DJReading.patience + DJReading.soon * 2)
        // Where Spotify's bar was never read, there's nothing to read sooner.
        var unread = DJReading()
        _ = unread.update(talking: true, inBar: nil, now: at(0))
        #expect(!unread.unsure(at: at(1)))
    }

    @Test("The DJ stays the DJ through Spotify taking its button away as it finds new picks, as recorded on 2026-11-06")
    func djThroughGaps() {
        var reading = DJReading()
        let start = Date(timeIntervalSince1970: 0)
        func at(_ seconds: Double) -> Date { start + seconds }
        // As recorded from Spotify's bar, 20:03:07 on: a song with the button; the DJ talks, the
        // button gone for a second and a half; back; a song; the DJ talks, the button gone nearly six.
        let recorded: [(Double, Bool, Bool)] = [
            (0, false, true), (1, true, true), (2, true, false), (3.5, true, true), (7, false, true),
            (8, true, false), (10, true, true), (23, true, true), (23.5, true, false), (29.3, true, true), (34, false, true),
        ]
        for (seconds, talking, inBar) in recorded {
            let on = reading.update(talking: talking, inBar: inBar, now: at(seconds))
            #expect(on, "at \(seconds) s")
        }
        // A click on the notch's button: Spotify takes its button away before the DJ talks.
        reading.heldUntil = at(40) + DJReading.afterPress
        let on1 = reading.update(talking: false, inBar: false, now: at(40.5))
        #expect(on1)
        let on2 = reading.update(talking: false, inBar: false, now: at(46))
        #expect(on2)
        // Gone a moment while a song plays: still the DJ.
        let on3 = reading.update(talking: false, inBar: true, now: at(50))
        #expect(on3)
        let on4 = reading.update(talking: false, inBar: false, now: at(52))
        #expect(on4)
        // Gone for longer, something else plays: not the DJ any more.
        let on5 = reading.update(talking: false, inBar: false, now: at(55))
        #expect(!on5)
        // Where the bar can't be read, what was thought stays, and the DJ talking says it's the DJ.
        let on6 = reading.update(talking: false, inBar: nil, now: at(60))
        #expect(!on6)
        let on7 = reading.update(talking: true, inBar: nil, now: at(61))
        #expect(on7)
        let on8 = reading.update(talking: false, inBar: nil, now: at(70))
        #expect(on8)
    }

    @Test("Spotify 1.3.8 gives the DJ's button no name, so it's found by the class its stylesheet gives its round DJ-blue look")
    func djButtonStyle() {
        // As in Spotify 1.3.8.620's own stylesheet, between its neighbours.
        let sheet =
            ".Emt7NrkZ4o2yFtQPWOL_{margin:0 auto}.MKFJGfPCySuartS1MoA4{cursor:pointer;background:#0a59b8;border:none;border-radius:50%;min-width:32px}.MKFJGfPCySuartS1MoA4 .o0vUBVdxi5tQBM6yNsFT{background:#1ed76000}"
        #expect(SpotifyDJ.style(in: sheet) == "MKFJGfPCySuartS1MoA4")
        // Another blue, or no such rule: nothing.
        #expect(SpotifyDJ.style(in: ".a{cursor:pointer;background:#1ed760;border:none;border-radius:50%}") == nil)
        #expect(SpotifyDJ.style(in: "") == nil)
    }

    @Test("The DJ's ring follows the waveform's bars: all of them, the low ones and the high ones")
    func djHeard() {
        #expect(DJHeard(levels: [0, 0, 0, 0, 0, 0]) == .silent)
        let low = DJHeard(levels: [0.5, 0.5, 0.5, 0, 0, 0])
        #expect(low.low > 0.8 && low.high == 0 && low.all > 0 && low.all < low.low)
        let high = DJHeard(levels: [0, 0, 0, 0.5, 0.5, 0.5])
        #expect(high.high > 0.8 && high.low == 0)
        // However loud, no further than all the way.
        #expect(DJHeard(levels: [1, 1, 1, 1, 1, 1]).all == 1)
    }

    @Test("The quieter the DJ, the rounder its ring, and the louder, the deeper its corner, to Spotify's own")
    func djRing() {
        let quiet = DJCoverDrawing.dents(.silent)
        #expect(quiet.front < 0.05)
        let loud = DJCoverDrawing.dents(.loudest)
        #expect(abs(loud.front - 0.3) < 1e-9 && abs(loud.teal - 0.12) < 1e-9 && abs(loud.paleBlue + 0.08) < 1e-9)
        // Each crescent shows beyond the ring in front of it, however loud and in whichever bars.
        for heard in [DJHeard.silent, .loudest, DJHeard(all: 0.5, low: 1, high: 0), DJHeard(all: 0.5, low: 0, high: 1)] {
            let dents = DJCoverDrawing.dents(heard)
            #expect(dents.front - dents.teal > 0.15 - 1e-9 && dents.teal - dents.paleBlue > 0.1 - 1e-9)
        }
        #expect(DJCoverDrawing.dents(DJHeard(all: 0.5, low: 0.5, high: 0.5)).front > quiet.front)
    }

    @Test("While the DJ talks the cover is its own and it's no song, and the song's cover comes back after")
    @MainActor
    func djCover() throws {
        let player = NowPlaying()
        let talking: [String: Any] = [
            "direct": true, "app": PlayerScripting.spotify, "playing": true, "title": "Up next", "artist": "DJ X", "album": "DJ", "duration": 0.0,
            "elapsed": 0.0, "mediaType": "music", "artwork": "",
        ]
        player.apply(talking)
        #expect(player.djTalking && player.djPlaying)
        #expect(!player.isSong)
        #expect(player.artwork != nil && player.artwork === DJCover.picture)
        // Said again, a second later, the same picture.
        player.apply(talking)
        #expect(player.artwork === DJCover.picture)
        let picture = try #require(NSImage(size: NSSize(width: 4, height: 4), flipped: false) { _ in true }.tiffRepresentation)
        var song = talking
        // Marked as a video, so that nothing's looked up for it here.
        song.merge(["title": "A Song", "album": "An Album", "duration": 200.0, "mediaType": "video", "artwork": picture.base64EncodedString()]) { _, new in new }
        player.apply(song)
        #expect(!player.djTalking)
        #expect(player.artwork !== DJCover.picture)
        player.apply(talking)
        song["artwork"] = nil
        player.apply(song)
        #expect(player.artwork !== DJCover.picture)
    }

    // MARK: - Where it plays from

    @Test("Spotify's song opens in the playlist it plays from: what was asked to play, else after it in the history")
    @MainActor
    func spotifyContext() {
        let track = "spotify:track:1Q3t9fWvHUXKsMmpD2XpUu"
        let playlist = "spotify:playlist:37i9dQZF1EYkqdzj48dyYq"
        let album = "spotify:album:6i02UIhGdlmQcX6xnL0wCFj"
        let history = ["spotify:track:AAA", album, track, playlist, "spotify:track:BBB", playlist]
        #expect(PlayingSource.context(of: track, history: history, request: []) == playlist)
        // Liked Songs, whose address runs longer.
        let liked = "spotify:user:someone:collection"
        #expect(PlayingSource.context(of: track, history: [track, liked], request: []) == liked)
        // What was asked to play, with any of its songs playing by now, and over a history that's behind.
        #expect(PlayingSource.context(of: track, history: [], request: [playlist, track]) == playlist)
        #expect(PlayingSource.context(of: track, history: [], request: [playlist, "spotify:track:CCC"]) == playlist)
        #expect(PlayingSource.context(of: track, history: [track, album], request: [playlist, "spotify:track:CCC"]) == playlist)
        // The song asked for on its own: the history, or nothing to go on.
        #expect(PlayingSource.context(of: track, history: [track, album], request: [track]) == album)
        #expect(PlayingSource.context(of: track, history: [], request: [track]) == nil)
    }

    @Test("The DJ is known from what Spotify was last asked to play, as written on 2026-11-08 while it played")
    func askedForDJ() {
        let dj = PlayerScripting.djAddress
        // As Spotify wrote it: the DJ, then three of its songs.
        #expect(PlayingSource.askedForDJ(request: [dj, "spotify:track:AAA", "spotify:track:BBB", "spotify:track:CCC"]))
        #expect(!PlayingSource.askedForDJ(request: ["spotify:album:6i02UIhGdlmQcX6xnL0wCFj", "spotify:track:AAA"]))
        // A song asked for on its own isn't the DJ, though the DJ played one like it.
        #expect(!PlayingSource.askedForDJ(request: ["spotify:track:AAA"]))
        // Unread, Spotify's bar gives way to it: off once the DJ's button has been gone the patience.
        var reading = DJReading()
        let start = Date(timeIntervalSince1970: 0)
        let seen = reading.update(talking: false, inBar: true, now: start)
        let gone = reading.update(talking: false, inBar: false, now: start + 1)
        let over = reading.update(talking: false, inBar: false, now: start + 1 + DJReading.patience)
        #expect(seen && gone && !over)
    }

    @Test("A browser's tab is found by what's playing, its title kept whole in the script")
    @MainActor
    func browserTab() {
        let safari = PlayingSource.tabScript(app: "com.apple.Safari", title: #"Say "Hi" \ Bye"#)
        #expect(safari?.contains(#"name of t contains "Say \"Hi\" \\ Bye""#) == true)
        #expect(PlayingSource.tabScript(app: "com.google.Chrome", title: "Song")?.contains("active tab index") == true)
        #expect(PlayingSource.tabScript(app: "org.mozilla.firefox", title: "Song") == nil)
    }
}
