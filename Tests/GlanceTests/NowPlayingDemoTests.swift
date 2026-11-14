import Foundation
import Testing

@testable import Glance

@MainActor
@Suite("Isolated player controls")
struct NowPlayingDemoTests {
    private func report(app: String? = PlayerScripting.spotify) -> [String: Any] {
        var report: [String: Any] = [
            "title": "Fixture song", "artist": "Fixture artist", "album": "Fixture album",
            "duration": 180.0, "elapsed": 30.0, "playing": false, "mediaType": "music", "artwork": "",
        ]
        report["app"] = app
        return report
    }

    @Test("Spotify repeat can cycle through one song without pressing Spotify or requesting access")
    func spotifyRepeat() {
        var commands: [NowPlaying.DemoCommand] = []
        let player = NowPlaying(followsPlayers: false, onDemoCommand: { commands.append($0) })
        player.apply(report())
        player.setDemoOptions(PlaybackOptions(repeatMode: .off))

        for expected in [RepeatMode.all, .one, .off] {
            player.cycleRepeat()
            #expect(player.options.repeatMode == expected)
        }
        #expect(commands == [.repeatMode(.all), .repeatMode(.one), .repeatMode(.off)])
    }

    @Test("Demo transport, source and DJ requests are observable while playback stays made up")
    func transport() {
        var commands: [NowPlaying.DemoCommand] = []
        let player = NowPlaying(followsPlayers: false, onDemoCommand: { commands.append($0) })
        player.apply(report())
        player.previous()
        player.next()
        player.togglePlayPause()
        #expect(player.isPlaying)
        player.togglePlayPause()
        #expect(!player.isPlaying)
        player.seek(to: 73)
        #expect(player.position(at: .now) == 73)
        player.openSource()
        player.differentDJPicks()

        #expect(commands == [.previous, .next, .playPause, .playPause, .seek(73), .openSource, .differentDJPicks])
        #expect(player.isDemo && player.appBundleID == PlayerScripting.spotify)
    }

    @Test("Demo option toggles report their requested values and update the rendered state")
    func options() {
        var commands: [NowPlaying.DemoCommand] = []
        let player = NowPlaying(followsPlayers: false, onDemoCommand: { commands.append($0) })
        player.apply(report(app: PlayerScripting.music))
        player.setDemoOptions(PlaybackOptions(shuffle: false, favorite: false, dj: true))

        player.toggleShuffle()
        player.toggleFavorite()
        #expect(player.options == PlaybackOptions(shuffle: true, favorite: true, dj: true))
        player.toggleShuffle()
        player.toggleFavorite()
        #expect(player.options == PlaybackOptions(shuffle: false, favorite: false, dj: true))
        #expect(commands == [.shuffle(true), .favorite(true), .shuffle(false), .favorite(false)])
    }

    @Test("Unavailable controls and source-less options do not manufacture requests")
    func unavailable() {
        var commands: [NowPlaying.DemoCommand] = []
        let player = NowPlaying(followsPlayers: false, onDemoCommand: { commands.append($0) })
        player.apply(report())
        player.toggleShuffle()
        player.cycleRepeat()
        player.toggleFavorite()
        #expect(commands.isEmpty)

        player.apply(report(app: nil))
        let seeded = PlaybackOptions(shuffle: false, repeatMode: .all, favorite: true)
        player.setDemoOptions(seeded)
        player.toggleShuffle()
        player.cycleRepeat()
        player.toggleFavorite()
        player.openSource()
        #expect(commands.isEmpty)
        #expect(player.options == seeded)
    }

    @Test("A demo report never registers a made-up source in the user's app list")
    func sourceIsolation() {
        let app = "dev.vibe.Glance.tests.player." + UUID().uuidString
        let player = NowPlaying(followsPlayers: false)
        #expect(!MusicApps.seen.contains(app))
        // Intentionally no direct flag: isolation is a property of the model, not its caller.
        player.apply(report(app: app))
        #expect(player.title == "Fixture song" && player.appBundleID == app)
        #expect(!MusicApps.seen.contains(app))
    }

    @Test("Fixture options cannot replace a live player's source state")
    func liveOptionsAreNotSeeded() {
        let player = NowPlaying()
        player.setDemoOptions(PlaybackOptions(shuffle: true, repeatMode: .one, favorite: true, dj: true))
        #expect(!player.isDemo)
        #expect(player.options == PlaybackOptions())
    }

    @Test("The tour and native activity bench demo has a source identity for its enabled options")
    func nativeDemoOptions() {
        let player = NowPlaying.demo(.tour, looksUpSong: false)
        #expect(player.isDemo && player.appBundleID == PlayerScripting.music)
        #expect(player.hasMedia && player.options.shuffle == false && player.options.repeatMode == .off)

        player.toggleShuffle()
        #expect(player.options.shuffle == true)
        player.toggleShuffle()
        #expect(player.options.shuffle == false)
        for expected in [RepeatMode.all, .one, .off] {
            player.cycleRepeat()
            #expect(player.options.repeatMode == expected)
        }
    }
}
