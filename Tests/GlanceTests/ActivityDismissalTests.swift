import Testing

@testable import Glance

@MainActor
@Suite("Dismissing the visible activity")
struct ActivityDismissalTests {
    @Test("An expanded activity is the target even when another activity arrived first", arguments: NotchModel.Activity.allCases)
    func expandedTarget(_ activity: NotchModel.Activity) {
        let target = NotchController.putAwayTarget(
            state: .open, page: .player, expanded: activity == .music ? nil : activity,
            alert: .lowBattery, first: activity == .music ? .airdrop : .music, hasMedia: true)
        #expect(target == .activity(activity))
    }

    @Test("An open Music player can be hidden even while a call announcement waits behind it")
    func openPlayer() {
        #expect(
            NotchController.putAwayTarget(
                state: .open, page: .player, expanded: nil,
                alert: .incomingCall, first: .call, hasMedia: true) == .activity(.music))
    }

    @Test("The tray and an empty player do not offer to hide an activity behind them")
    func noVisibleActivity() {
        #expect(
            NotchController.putAwayTarget(
                state: .open, page: .tray, expanded: .airdrop,
                alert: .incomingCall, first: .music, hasMedia: true) == nil)
        #expect(
            NotchController.putAwayTarget(
                state: .open, page: .player, expanded: nil,
                alert: .lowBattery, first: .airplay, hasMedia: false) == nil)
    }

    @Test("Closed and peeking menus target their visible announcement or first activity", arguments: [NotchState.closed, .peek])
    func compactTarget(_ state: NotchState) {
        #expect(
            NotchController.putAwayTarget(
                state: state, page: .player, expanded: .airdrop,
                alert: .lowBattery, first: .music, hasMedia: true) == .alert(.lowBattery))
        #expect(
            NotchController.putAwayTarget(
                state: state, page: .player, expanded: .airdrop,
                alert: nil, first: .airplay, hasMedia: true) == .activity(.airplay))
        #expect(
            NotchController.putAwayTarget(
                state: state, page: .player, expanded: nil,
                alert: nil, first: nil, hasMedia: false) == nil)
    }
}
