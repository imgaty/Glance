//
//  TimedLyricsTests.swift
//  GlanceTests
//
//  Created by Gaty on 10/10/2026.
//

import Testing

@testable import Glance

/// Reading LRC lyrics into timed lines, pauses and their timings.
@Suite("Timed lyrics")
struct TimedLyricsTests {
    /// The sung lines, in order, leaving out pauses and credits.
    private func lines(_ lyrics: TimedLyrics) -> [String] {
        lyrics.entries.compactMap { if case .line(let text) = $0.item { text } else { nil } }
    }

    // MARK: - What counts as lyrics

    @Test("Empty text has no lyrics")
    func emptyText() {
        #expect(TimedLyrics(lrc: "", duration: 180) == nil)
    }

    @Test("Lines without times have no lyrics")
    func untimedLines() {
        #expect(TimedLyrics(lrc: "Hello\nWorld", duration: 180) == nil)
    }

    @Test("Only tags like [ar:Artist] have no lyrics")
    func onlyTags() {
        let lrc = "[ar:Some Artist]\n[ti:Some Song]\n[al:Some Album]\n[by:Someone]"
        #expect(TimedLyrics(lrc: lrc, duration: 180) == nil)
    }

    @Test("Only empty timed lines have no lyrics")
    func onlyStops() {
        #expect(TimedLyrics(lrc: "[00:01.00]\n[00:05.00]   ", duration: 180) == nil)
    }

    @Test("Tags are left out of the lines around them")
    func tagsAmongLines() throws {
        let lrc = "[ar:Some Artist]\n[00:01.00]First\n[length:03:00]\n[00:02.00]Second"
        let lyrics = try #require(TimedLyrics(lrc: lrc, duration: 180))
        #expect(lines(lyrics) == ["First", "Second"])
    }

    // MARK: - Times

    @Test(
        "Minutes and seconds become seconds",
        arguments: [
            ("[00:00.50]Line", 0.5),
            ("[00:01.00]Line", 1.0),
            ("[00:03.25]Line", 3.25),
            ("[00:03]Line", 3.0),
            ("[01:05.50]Line", 65.5),
            ("[10:00.00]Line", 600.0),
        ])
    func times(lrc: String, seconds: Double) throws {
        let lyrics = try #require(TimedLyrics(lrc: lrc, duration: 900))
        let line = try #require(lyrics.entries.first { $0.item == .line("Line") })
        #expect(isClose(line.start, seconds))
    }

    @Test("Lines are put in time order")
    func sorted() throws {
        let lrc = "[00:03.00]Third\n[00:01.00]First\n[00:02.00]Second"
        let lyrics = try #require(TimedLyrics(lrc: lrc, duration: 180))
        #expect(lines(lyrics) == ["First", "Second", "Third"])
        let starts = lyrics.entries.map(\.start)
        #expect(starts == starts.sorted())
    }

    @Test("A line with several times is sung at each")
    func repeatedLine() throws {
        let lrc = "[00:01.00][00:02.00][00:03.00]Chorus"
        let lyrics = try #require(TimedLyrics(lrc: lrc, duration: 180))
        #expect(lines(lyrics) == ["Chorus", "Chorus", "Chorus"])
        #expect(lyrics.entries.map(\.start) == [1, 2, 3])
    }

    // MARK: - Text

    @Test("Word times like <mm:ss.xx> are left out")
    func wordTimes() throws {
        let lrc = "[00:01.00]<00:01.00>Hello <00:01.40>there <00:01.80>world"
        let lyrics = try #require(TimedLyrics(lrc: lrc, duration: 180))
        #expect(lines(lyrics) == ["Hello there world"])
    }

    @Test("Word times without hundredths are left out too")
    func wordTimesWholeSeconds() throws {
        let lyrics = try #require(TimedLyrics(lrc: "[00:01.00]<00:01>Hi <00:02>you", duration: 180))
        #expect(lines(lyrics) == ["Hi you"])
    }

    @Test("Spaces around a line are trimmed")
    func trimmed() throws {
        let lyrics = try #require(TimedLyrics(lrc: "[00:01.00]   Spaced out   ", duration: 180))
        #expect(lines(lyrics) == ["Spaced out"])
    }

    @Test("Windows line endings read the same")
    func carriageReturns() throws {
        let lyrics = try #require(TimedLyrics(lrc: "[00:01.00]One\r\n[00:02.00]Two\r\n", duration: 180))
        #expect(lines(lyrics) == ["One", "Two"])
    }

    // MARK: - When lines end

    @Test("A line ends about when it has been sung")
    func naturalEnd() throws {
        // "A" is 0.065 s per character plus 0.5 s, given half as long again: 0.8475 s.
        let lyrics = try #require(TimedLyrics(lrc: "[00:01.00]A\n[00:02.00]B", duration: 10))
        #expect(lyrics.entries.count == 2)
        #expect(isClose(lyrics.entries[0].end, 1.8475))
        #expect(isClose(lyrics.entries[1].end, 2.8475))
    }

    @Test("A line never runs into the next one")
    func endBeforeNextLine() throws {
        // Long enough to need about 3 s, but the next line is 1 s later: it ends at 90% of the gap.
        let long = String(repeating: "word ", count: 6).trimmingCharacters(in: .whitespaces)
        let lyrics = try #require(TimedLyrics(lrc: "[00:01.00]\(long)\n[00:02.00]Next", duration: 10))
        #expect(isClose(lyrics.entries[0].end, 1.9))
        #expect(lyrics.entries[0].end < lyrics.entries[1].start)
    }

    @Test("An empty line marks where the singing stops")
    func emptyLineStops() throws {
        // "Hello world" would take 1.8225 s, but the stop half a second later cuts it to 0.45 s.
        let lyrics = try #require(TimedLyrics(lrc: "[00:01.00]Hello world\n[00:01.50]\n", duration: 180))
        #expect(lyrics.entries.count == 1)
        #expect(lyrics.entries[0].item == .line("Hello world"))
        #expect(isClose(lyrics.entries[0].end, 1.45))
    }

    @Test("Every entry ends after it starts")
    func entriesHaveLength() throws {
        let lrc = """
            [00:05.00]Intro line
            [00:07.50]Second line here
            [00:20.00]After a pause
            [00:21.00]
            [00:30.00]Last
            """
        let lyrics = try #require(TimedLyrics(lrc: lrc, duration: 60))
        for entry in lyrics.entries {
            #expect(entry.end > entry.start)
        }
    }

    // MARK: - Pauses

    @Test("A wait of 4 s or more before the first line starts with a pause")
    func leadingInterlude() throws {
        let lyrics = try #require(TimedLyrics(lrc: "[00:10.00]Hello", duration: 100))
        #expect(lyrics.entries.count == 2)
        #expect(lyrics.entries[0] == TimedLyrics.Entry(start: 0, end: 10, item: .interlude))
        #expect(lyrics.entries[1].item == .line("Hello"))
    }

    @Test("The pause before the first line holds from the first moment, however the clock moves as the song loads")
    func leadingInterludeHolds() throws {
        let lyrics = try #require(TimedLyrics(lrc: "[00:10.00]Hello", duration: 100))
        for position in [0, 0.3, 0.6, 0, 0.5, 0.1, 0, 0.9] {
            #expect(lyrics.entries.lastIndex { $0.start <= position } == 0)
        }
    }

    @Test("A first line just at 4 s gets the pause")
    func leadingInterludeBoundary() throws {
        let lyrics = try #require(TimedLyrics(lrc: "[00:04.00]Hello", duration: 100))
        #expect(lyrics.entries.first?.item == .interlude)
    }

    @Test("A first line sooner than 4 s has no pause before it")
    func noLeadingInterlude() throws {
        let lyrics = try #require(TimedLyrics(lrc: "[00:03.99]Hello", duration: 100))
        #expect(lyrics.entries.first?.item == .line("Hello"))
    }

    @Test("A gap of 5 s or more between lines shows a pause")
    func middleInterlude() throws {
        let lyrics = try #require(TimedLyrics(lrc: "[00:01.00]A\n[00:20.00]B", duration: 100))
        #expect(lyrics.entries.map(\.item) == [.line("A"), .interlude, .line("B")])
        let pause = lyrics.entries[1]
        // It starts a moment after the line before has been sung, and ends as the next begins.
        #expect(isClose(pause.start, lyrics.entries[0].end + 0.6))
        #expect(pause.end == 20)
    }

    @Test("A short gap between lines shows no pause")
    func noMiddleInterlude() throws {
        let lyrics = try #require(TimedLyrics(lrc: "[00:01.00]A\n[00:04.00]B", duration: 100))
        #expect(lyrics.entries.map(\.item) == [.line("A"), .line("B")])
    }

    @Test("A pause after a stop runs until the next sung line")
    func interludeAfterStop() throws {
        let lyrics = try #require(TimedLyrics(lrc: "[00:01.00]A\n[00:02.00]\n[00:30.00]B", duration: 100))
        #expect(lyrics.entries.map(\.item) == [.line("A"), .interlude, .line("B")])
        #expect(lyrics.entries[1].end == 30)
    }

    @Test("There's no pause after the last line")
    func noTrailingInterlude() throws {
        let lyrics = try #require(TimedLyrics(lrc: "[00:01.00]Only line", duration: 300))
        #expect(lyrics.entries.last?.item == .line("Only line"))
    }

    // MARK: - Song length

    @Test("Without a length, the last line is still timed")
    func unknownDuration() throws {
        // The song is taken to end 6 s after the last line, so it has its natural length.
        let lyrics = try #require(TimedLyrics(lrc: "[00:01.00]A", duration: 0))
        #expect(lyrics.entries.count == 1)
        #expect(isClose(lyrics.entries[0].end, 1.8475))
    }

    @Test("A last line at the very end of the song still gets time to show")
    func lineAtSongEnd() throws {
        // The song says it ends at 10 s, but the line starts there: it gets at least 4 s.
        let lyrics = try #require(TimedLyrics(lrc: "[00:10.00]A", duration: 10))
        let line = try #require(lyrics.entries.last)
        #expect(isClose(line.end, 10.8475))
    }

    // MARK: - A whole song

    @Test("A realistic file reads into lines and pauses")
    func wholeSong() throws {
        let lrc = """
            [ti:Example]
            [ar:Example Artist]
            [00:12.30]First verse, first line
            [00:15.80]First verse, second line
            [00:19.10]
            [00:31.40]Chorus line
            [00:34.00]Chorus line
            [01:02.00]Last line
            """
        let lyrics = try #require(TimedLyrics(lrc: lrc, duration: 90))
        #expect(
            lyrics.entries.map(\.item) == [
                .interlude,
                .line("First verse, first line"),
                .line("First verse, second line"),
                .interlude,
                .line("Chorus line"),
                .line("Chorus line"),
                .interlude,
                .line("Last line"),
            ])
    }
}
