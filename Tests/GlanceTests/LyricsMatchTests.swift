//
//  LyricsMatchTests.swift
//  GlanceTests
//
//  Created by Gaty on 10/10/2026.
//

import Testing

@testable import Glance

/// Lyrics are only ever shown for the song playing: a record has to agree on the title, an artist
/// and the length.
@Suite("Lyrics matching")
struct LyricsMatchTests {
    private func matches(
        _ title: String, _ artist: String, _ duration: Double,
        record: (title: String?, artist: String?, duration: Double?)
    ) -> Bool {
        LyricsMatch.matches(
            title: title, artist: artist, duration: duration,
            recordTitle: record.title, recordArtist: record.artist, recordDuration: record.duration)
    }

    // MARK: - Never another song

    @Test("A title without an artist matches nothing")
    func noArtist() {
        #expect(!matches("untitled", "", 37, record: ("Untitled", "Some Band", 37)))
        #expect(!matches("untitled", "", 0, record: ("untitled", "", 0)))
    }

    @Test("The same title by another artist doesn't match")
    func otherArtist() {
        #expect(!matches("Hello", "Adele", 295, record: ("Hello", "Lionel Richie", 295)))
    }

    @Test("Another title by the same artist doesn't match")
    func otherTitle() {
        #expect(!matches("Hello", "Adele", 295, record: ("Rolling in the Deep", "Adele", 295)))
    }

    @Test("A version of another length doesn't match", arguments: [291.0, 299.5, 240, 360])
    func otherLength(recordDuration: Double) {
        #expect(!matches("Hello", "Adele", 295, record: ("Hello", "Adele", recordDuration)))
    }

    @Test("A record without a length doesn't match a song whose length is known")
    func unknownRecordLength() {
        #expect(!matches("Hello", "Adele", 295, record: ("Hello", "Adele", nil)))
    }

    @Test("A record missing its title or artist doesn't match")
    func incompleteRecord() {
        #expect(!matches("Hello", "Adele", 295, record: (nil, "Adele", 295)))
        #expect(!matches("Hello", "Adele", 295, record: ("Hello", nil, 295)))
    }

    @Test("A title that only starts the same doesn't match")
    func partialTitle() {
        #expect(!matches("Hello", "Adele", 295, record: ("Hello Again", "Adele", 295)))
    }

    // MARK: - The same song, written differently

    @Test("The same song matches, within a few seconds", arguments: [295.0, 293, 297.9])
    func sameSong(recordDuration: Double) {
        #expect(matches("Hello", "Adele", 295, record: ("Hello", "Adele", recordDuration)))
    }

    @Test("Case, accents and punctuation don't matter")
    func looseSpelling() {
        #expect(matches("Don't Stop Me Now", "Queen", 209, record: ("dont stop me now", "QUEEN", 209)))
        #expect(matches("Água de Beber", "João Gilberto", 150, record: ("Agua De Beber", "Joao Gilberto", 151)))
        #expect(matches("Don’t Stop Me Now", "Queen", 209, record: ("Don't Stop Me Now", "Queen", 209)))
    }

    @Test("What versions add to a title doesn't matter")
    func versionExtras() {
        #expect(matches("Paranoid - 2012 Remaster", "Black Sabbath", 168, record: ("Paranoid", "Black Sabbath", 169)))
        #expect(matches("Stay (with Justin Bieber)", "The Kid LAROI", 141, record: ("STAY", "The Kid LAROI & Justin Bieber", 141)))
    }

    @Test("One artist in common is enough")
    func sharedArtist() {
        #expect(matches("Stay", "The Kid LAROI, Justin Bieber", 141, record: ("Stay", "The Kid LAROI", 141)))
        #expect(matches("Lose Control", "Missy Elliott feat. Ciara & Fat Man Scoop", 227, record: ("Lose Control", "Missy Elliott", 227)))
    }

    @Test("And, & and + are the same")
    func ampersands() {
        #expect(matches("The Boxer", "Simon & Garfunkel", 308, record: ("The Boxer", "Simon and Garfunkel", 308)))
        #expect(matches("Dog Days Are Over", "Florence + the Machine", 252, record: ("Dog Days Are Over", "Florence and the Machine", 252)))
    }

    @Test("Without a length from the player, title and artist decide")
    func unknownSongLength() {
        #expect(matches("Hello", "Adele", 0, record: ("Hello", "Adele", 295)))
        #expect(!matches("Hello", "Adele", 0, record: ("Hello", "Lionel Richie", 295)))
    }

    // MARK: - Timing

    @Test("The last line's start is known, pauses aside")
    func lastLineStart() throws {
        let lyrics = try #require(TimedLyrics(lrc: "[00:10.00]One\n[00:20.00]Two\n[00:40.00]", duration: 60))
        #expect(lyrics.lastLineStart == 20)
    }
}
