import Foundation
import Testing

@testable import Glance

@MainActor
@Suite("Activity exits")
struct ActivityExitTests {
    @Test("Reopening cancels the delayed return to the bubble")
    func interruptBubbleClose() async throws {
        let model = NotchModel(closedSize: CGSize(width: 185, height: 32), layout: .top, hasCamera: true)
        model.activity = true
        model.timer = .paused(left: 30, total: 60)
        model.expanded = .timer
        model.openedFromBubble = true
        model.open()
        model.close()
        #expect(model.openedFromBubble)
        try await Task.sleep(for: .milliseconds(100))
        model.open()
        try await Task.sleep(for: .milliseconds(400))
        #expect(model.state == .open)
        #expect(model.openedFromBubble)
        #expect(model.bubbleReach == 0)
    }

    @Test("Every test scene folds to the camera before leaving", arguments: [false, true])
    func collapse(camera: Bool) {
        for tall in [false, true] {
            let model = NotchModel(closedSize: CGSize(width: 185, height: 32), layout: .top, hasCamera: camera)
            model.activity = true
            model.voiceMemo = .recording(since: .now)
            model.airplay = AirPlayRoute(name: "Living Room", symbol: "homepod")
            if tall {
                model.alert = BatteryWatch.lowBattery(.init(percent: 20, onPower: false, charging: false))
                model.alertWing = 90
            }
            model.expanded = .voiceMemo
            model.state = .open
            model.bubbleReach = model.bubbleSpan
            model.stretch = 12
            model.lean = 8
            model.pressed = true
            model.collapseAway()
            #expect(model.state == .closed)
            #expect(model.metrics.bodyWidth == 185)
            #expect(model.metrics.height == 32)
            #expect(model.detached == nil)
            #expect(!model.restingTall)
            #expect(model.bubbleReach == 0)
            // Retained until the view finishes fading, never removed mid-transition.
            #expect(model.voiceMemo != nil)
            #expect(model.expanded == .voiceMemo)
        }
    }
}
