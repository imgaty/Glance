import Testing

@testable import Glance

@Suite("No player with nothing playing")
struct EmptyPlayerTests {
    @Test("With no song and no live activity, the player is empty")
    func empty() {
        #expect(NotchController.playerEmpty(hasMedia: false, activities: []))
        #expect(!NotchController.playerEmpty(hasMedia: true, activities: [.music]))
        // A paused song still has the player.
        #expect(!NotchController.playerEmpty(hasMedia: true, activities: []))
        // A live activity has something to open to.
        #expect(!NotchController.playerEmpty(hasMedia: false, activities: [.timer]))
        #expect(!NotchController.playerEmpty(hasMedia: false, activities: [.music, .airdrop]))
    }

    @Test("Opening with an empty player shows the tray, or nothing with the tray off")
    func opening() {
        #expect(NotchController.openingPage(.player, forDrop: false, playerEmpty: true, trayOn: true) == .tray)
        #expect(NotchController.openingPage(.player, forDrop: false, playerEmpty: true, trayOn: false) == nil)
        // With a song, or something to drop, it's as asked.
        #expect(NotchController.openingPage(.player, forDrop: false, playerEmpty: false, trayOn: false) == .player)
        #expect(NotchController.openingPage(.tray, forDrop: true, playerEmpty: true, trayOn: true) == .tray)
        #expect(NotchController.openingPage(.tray, forDrop: false, playerEmpty: true, trayOn: true) == .tray)
    }
}
