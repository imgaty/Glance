//
//  PlayerScriptingTests.swift
//  GlanceTests
//
//  Created by Gaty on 10/10/2026.
//

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
    func favoriteScripts() {
        #expect(PlayerScripting.setFavorite(true, app: music) == #"tell application "Music" to set favorited of current track to true"#)
        #expect(PlayerScripting.setFavorite(false, app: music) == #"tell application "Music" to set favorited of current track to false"#)
        #expect(PlayerScripting.setFavorite(true, app: spotify) == nil)
        #expect(PlayerScripting.setFavorite(true, app: other) == nil)
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
}
