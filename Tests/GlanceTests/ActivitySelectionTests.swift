import Foundation
import Testing

@testable import Glance

@MainActor
@Suite("Selecting waiting activities")
struct ActivitySelectionTests {
    @Test("A third activity opens without changing which two arrived first")
    func waitingActivity() {
        let model = NotchModel(closedSize: CGSize(width: 185, height: 32), layout: .top, hasCamera: true)
        model.activity = true
        model.timer = .paused(left: 75, total: 120)
        model.airdrop = AirDropShown(id: "fixture", sender: "Alex", preview: nil, fraction: 0.4)
        let order = model.activities
        #expect(order == [.music, .timer, .airdrop])
        #expect(model.openableActivities == order)
        #expect(model.selectActivity(.airdrop))
        #expect(model.expanded == .airdrop && model.page == .player)
        #expect(model.activities == order && model.second == .timer)
        #expect(model.selectActivity(.music))
        #expect(model.expanded == nil)
    }

    @Test("Ended, hidden and countdown-only activities cannot be opened from stale choices")
    func staleSelection() {
        let model = NotchModel(closedSize: CGSize(width: 185, height: 32), layout: .top, hasCamera: true)
        model.timer = .paused(left: 75, total: 120)
        model.screenRecording = .countdown(from: 3, until: .now + 3)
        #expect(!model.selectActivity(.screenRecording))
        model.dismissed.insert(.timer)
        #expect(!model.selectActivity(.timer))
        model.dismissed.remove(.timer)
        model.timer = nil
        #expect(!model.selectActivity(.timer))
        model.screenRecording = .recording(since: .now)
        #expect(model.selectActivity(.screenRecording))
        model.alert = BatteryWatch.lowBattery(.init(percent: 10, onPower: false, charging: false))
        #expect(model.openableActivities.isEmpty)
    }
}
