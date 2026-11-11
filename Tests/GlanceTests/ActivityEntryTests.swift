import Foundation
import Testing

@testable import Glance

@MainActor
@Suite("External display entry")
struct ActivityEntryTests {
    @Test("Every registered activity waits inside the housing", arguments: NotchModel.Activity.allCases)
    func waits(_ activity: NotchModel.Activity) {
        let model = NotchModel(closedSize: CGSize(width: 185, height: 32), layout: .top, hasCamera: false)
        switch activity {
        case .music: model.activity = true
        case .timer: model.timer = .running(until: .now + 60, total: 60)
        case .stopwatch: model.stopwatch = .running(since: .now)
        case .airplay: model.airplay = AirPlayRoute(name: "Speaker", symbol: "homepod")
        case .airdrop: model.airdrop = AirDropShown(id: "test", sender: "Phone", preview: nil, fraction: 0.3)
        case .call: model.call = CallShown(name: "Alex", over: "Phone", phase: .connected(since: .now))
        case .screenRecording: model.screenRecording = .recording(since: .now)
        case .voiceMemo: model.voiceMemo = .paused(length: 20)
        }
        model.entering = true
        #expect(model.metrics.bodyWidth == 185)
        #expect(model.metrics.height == 32)
        #expect(model.detached == nil)
        #expect(model.activities == [activity])
        model.entering = false
        #expect(model.wing > 0)
        #expect(model.activities == [activity])
    }

    @Test("Tall alerts and bubbles wait, and fullscreen still hides them after entry")
    func alertAndFullscreen() {
        let model = NotchModel(closedSize: CGSize(width: 185, height: 32), layout: .top, hasCamera: false)
        model.alert = BatteryWatch.lowBattery(.init(percent: 10, onPower: false, charging: false))
        model.alertWing = 90
        model.activity = true
        model.timer = .paused(left: 30, total: 60)
        model.entering = true
        #expect(!model.restingTall)
        #expect(model.detached == nil)
        model.collapsed = true
        model.entering = false
        #expect(model.wing == 0)
        model.collapsed = false
        #expect(model.restingTall)
        #expect(model.alert != nil)
    }
}
