import Testing

@testable import Glance

@Suite("Isolated lyric presentations")
@MainActor
struct LyricsPreviewTests {
    private static let lyrics = TimedLyrics(lrc: "[00:01.00]A local line\n[00:05.00]Another local line", duration: 12)!
    private static let states: [LyricsStore.Content] = [
        .none, .loading, .timed(lyrics), .plain(["A local line", "Another local line"]), .instrumental, .unavailable, .unreachable,
    ]

    @Test("Preview content and credits remain local when a view requests a different song", arguments: states)
    func retainsSeededState(_ content: LyricsStore.Content) {
        let credits = LyricsStore.Credits(writers: "Fixture writer", source: "Local fixture")
        let store = LyricsStore(demoContent: content, credits: credits)

        store.load(title: "Changed fixture title", artist: "Changed fixture artist", album: "Changed fixture album", duration: 60, composer: "Different writer", app: nil)
        #expect(store.content == content)
        #expect(store.credits == credits)

        // An empty report normally clears the content. An isolated preview must keep its state.
        store.load(title: "", artist: "", album: "", duration: 0, composer: "", app: nil)
        #expect(store.content == content)
        #expect(store.credits == credits)
    }

    @Test("The existing timed demo initializer preserves lyrics and credits")
    func timedInitializer() {
        let credits = LyricsStore.Credits(writers: "Fixture writer", source: "Local fixture")
        let store = LyricsStore(demo: Self.lyrics, credits: credits)
        store.load(title: "", artist: "", album: "", duration: 0, composer: "", app: nil)
        #expect(store.content == .timed(Self.lyrics))
        #expect(store.credits == credits)
    }

    @Test("A live lyric store still starts empty")
    func liveInitializer() {
        let store = LyricsStore()
        #expect(store.content == .none)
        #expect(store.credits == LyricsStore.Credits())
    }
}
