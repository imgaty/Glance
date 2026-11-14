import Foundation
import Testing

@testable import Glance

@MainActor
@Suite("Shortcut activity integration")
struct ShortcutIntegrationTests {
    private func model() -> NotchModel {
        let model = NotchModel(closedSize: CGSize(width: 185, height: 32), layout: .top, hasCamera: true)
        model.activityReducesMotion = true
        return model
    }

    @Test("A Shortcut detaches behind music, opens by name, and preserves arrival order")
    func detachedPresentation() {
        let model = model()
        model.activity = true
        model.shortcut = .init(run: .fixture())
        #expect(model.activities == [.music, .shortcut])
        #expect(model.detached == .shortcut)
        #expect(model.name(of: .shortcut) == model.shortcut?.run.shortcut.name)
        #expect(model.selectActivity(.shortcut))
        model.open()
        #expect(model.expanded == .shortcut)
        #expect(!model.expandedGone)
        #expect(model.metrics.height == ShortcutRunView.height(restingHeight: model.closedSize.height, shown: model.shortcut))
        #expect(model.activities == [.music, .shortcut])
        model.close()
        #expect(model.detached == .shortcut)
    }

    @Test("A third activity can be selected while the first two retain their arrival order")
    func waitingPresentation() {
        let model = model()
        model.activity = true
        model.timer = .paused(left: 60, total: 60)
        model.shortcut = .init(run: .fixture())
        #expect(model.activities == [.music, .timer, .shortcut])
        #expect(model.detached == .timer)
        #expect(model.openableActivities.contains(.shortcut))
        #expect(model.selectActivity(.shortcut))
        #expect(model.expanded == .shortcut)
        #expect(model.activities == [.music, .timer, .shortcut])
    }

    @Test("Run state and selection updates preserve activity order and current result availability")
    func payloadUpdates() {
        let model = model()
        model.shortcut = .init(run: .fixture())
        model.activity = true
        model.expanded = .shortcut
        model.state = .open
        let order = model.activities
        model.shortcut = .init(run: .fixture(state: .stopping))
        #expect(model.activities == order)
        #expect(!model.expandedGone)
        model.shortcut = .init(run: .fixture(state: .completed, ordinal: 1, withOutput: true))
        #expect(model.activities == order)
        #expect(model.name(of: .shortcut) == model.shortcut?.run.shortcut.name)
        #expect(model.shortcut?.run.exit?.output != nil)
        model.shortcut = nil
        #expect(model.expandedGone)
        #expect(model.activities == [.music])
    }
}
