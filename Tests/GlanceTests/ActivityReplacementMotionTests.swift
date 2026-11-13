import Foundation
import Testing

@testable import Glance

@MainActor
@Suite("Replacing an activity session")
struct ActivityReplacementMotionTests {
    private func model() -> NotchModel {
        let model = NotchModel(closedSize: CGSize(width: 185, height: 32), layout: .top, hasCamera: true)
        model.activityReducesMotion = false
        return model
    }

    @Test("A new transfer folds only when its activity is currently presented", arguments: ["primary", "detached", "expanded", "waiting", "other-page"])
    func nextTransfer(_ place: String) {
        let model = model()
        defer { model.cancelActivityTransition() }
        if place != "primary" { model.activity = true }
        if place == "waiting" { model.timer = .paused(left: 30, total: 60) }
        model.airdrop = AirDropShown(id: "first-transfer", sender: "Alex", preview: nil, fraction: 0.9)
        if place == "expanded" {
            model.state = .open
            model.expanded = .airdrop
        } else if place == "other-page" {
            model.state = .open
        }
        let order = model.activities
        let before = model.activityTransitionID
        model.changeActivityPresentation {
            model.airdrop = AirDropShown(id: "next-transfer", sender: "Sam", preview: nil, fraction: 0.1)
        }
        let visible = place != "waiting" && place != "other-page"
        #expect(model.activityFolded == visible)
        #expect((model.activityTransitionID > before) == visible)
        #expect(model.activities == order)
        if visible {
            #expect(model.metrics.bodyWidth == model.closedSize.width)
            #expect(model.metrics.height == model.closedSize.height)
        }
    }

    @Test("Progress on the same transfer never restarts its presentation", arguments: [false, true])
    func transferProgress(_ expanded: Bool) {
        let model = model()
        defer { model.cancelActivityTransition() }
        model.airdrop = AirDropShown(id: "same-transfer", sender: "Alex", preview: nil, fraction: 0.1)
        if expanded {
            model.state = .open
            model.expanded = .airdrop
        }
        let before = model.activityTransitionID
        model.changeActivityPresentation {
            model.airdrop = AirDropShown(id: "same-transfer", sender: "Alex", preview: nil, fraction: 0.6)
        }
        #expect(model.activityTransitionID == before)
        #expect(!model.activityFolded && !model.activityControlsHidden)
    }
}
