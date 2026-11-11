import Foundation
import Testing

@testable import Glance

@Suite("Playing source navigation")
@MainActor
struct PlayingSourceTests {
    @Test("Spotify's own navigation wins over stale cached contexts")
    func nativeNavigation() async {
        var read = false
        var opened = false
        let result = await PlayingSource.revealSpotify(
            navigate: { true },
            track: {
                read = true
                return "spotify:track:song"
            },
            context: { _ in URL(string: "spotify:playlist:stale") },
            open: { _ in
                opened = true
                return true
            }
        )
        #expect(result)
        #expect(!read)
        #expect(!opened)
    }

    @Test("Unavailable native navigation falls back to the song's context")
    func contextFallback() async {
        var lookedUp = ""
        var opened: URL?
        let result = await PlayingSource.revealSpotify(
            navigate: { false }, track: { "  spotify:track:song\n" },
            context: {
                lookedUp = $0
                return URL(string: "spotify:playlist:source")
            },
            open: {
                opened = $0
                return true
            }
        )
        #expect(result)
        #expect(lookedUp == "spotify:track:song")
        #expect(opened?.absoluteString == "spotify:playlist:source")
    }

    @Test("A missing context opens the trimmed track link and rejects other schemes")
    func trackFallback() async {
        var opened: [URL] = []
        for (reply, expected) in [(" spotify:track:song\n", true), ("https://example.com", false), ("", false)] {
            let result = await PlayingSource.revealSpotify(
                navigate: { false }, track: { reply }, context: { _ in nil },
                open: {
                    opened.append($0)
                    return true
                }
            )
            #expect(result == expected)
        }
        #expect(opened.map(\.absoluteString) == ["spotify:track:song"])
    }
}
