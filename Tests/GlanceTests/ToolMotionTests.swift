import Foundation
import Testing

@testable import Glance

@MainActor
@Suite("Tool motion stays independent of activities", .serialized)
struct ToolMotionTests {
    private func model(reduced: Bool = false) -> NotchModel {
        let model = NotchModel(closedSize: CGSize(width: 185, height: 32), layout: .top, hasCamera: true)
        model.activityReducesMotion = reduced
        model.activity = true
        return model
    }

    @Test("Both tool pages open and close without an activity midpoint or input lock", arguments: [NotchPage.player, .tray], [false, true])
    func directTools(page: NotchPage, reduced: Bool) {
        let model = model(reduced: reduced)
        defer { model.cancelActivityTransition() }
        model.page = page
        model.open()
        #expect(model.state == .open && model.page == page)
        #expect(!model.activityControlsHidden && model.activityTransitionTask == nil)
        #expect(model.metrics.height > model.closedSize.height)
        model.close()
        #expect(model.state == .closed && !model.activityControlsHidden)
        #expect(!model.activityReturnsInline && model.activityTransitionTask == nil)
        #expect(model.metrics.bodyWidth > model.closedSize.width)
    }

    @Test("Tool navigation retains tracked deformation and stays responsive during opening")
    func gestureContinuity() {
        let model = model()
        defer { model.cancelActivityTransition() }
        model.stretch = 12
        model.lean = 8
        model.open()
        for page in [NotchPage.tray, .player, .tray] {
            model.pageStretch = 14
            model.turn(to: page)
            #expect(model.page == page && model.state == .open)
            #expect(model.stretch == 12 && model.lean == 8 && model.pageStretch == 0)
            #expect(!model.activityControlsHidden && model.activityTransitionTask == nil)
        }
    }

    @Test("A detached activity merges before tool opening and returns after closing", arguments: [NotchPage.player, .tray])
    func bubbleChoreography(_ page: NotchPage) async throws {
        let model = model()
        defer { model.cancelActivityTransition() }
        model.timer = .paused(left: 75, total: 120)
        model.page = page
        let order = model.activities
        model.open()
        #expect(model.state == .closed && model.bubbleMerged)
        #expect(!model.activityControlsHidden)
        let opening = try #require(model.activityTransitionTask)
        await opening.value
        #expect(model.state == .open && model.bubbleMerged)
        model.close()
        #expect(model.state == .closed && model.bubbleMerged)
        #expect(!model.activityControlsHidden)
        let closing = try #require(model.activityTransitionTask)
        await closing.value
        #expect(!model.bubbleMerged && model.detached == .timer)
        #expect(model.activities == order)
    }

    @Test("Closing during the tool merge cancels its deferred opening")
    func interruptedMerge() async throws {
        let model = model()
        defer { model.cancelActivityTransition() }
        model.timer = .paused(left: 75, total: 120)
        model.open()
        let opening = try #require(model.activityTransitionTask)
        model.close()
        let closing = model.activityTransitionTask
        await opening.value
        await closing?.value
        #expect(model.state == .closed && !model.activityControlsHidden)
        #expect(model.detached == .timer && !model.bubbleMerged)
        #expect(model.activityTransitionTask == nil)
    }

    @Test("Tool hover restores its old swell while activity hover and Reduce Motion stay fixed")
    func scopedHover() {
        let model = model()
        defer { model.cancelActivityTransition() }
        let resting = model.metrics
        model.approach(1)
        #expect(model.metrics.bodyWidth == resting.bodyWidth + 6)
        #expect(model.metrics.height == resting.height + 3)
        model.peek()
        #expect(model.metrics.bodyWidth == resting.bodyWidth + 14)
        #expect(model.metrics.height == resting.height + 7)
        model.activityReducesMotion = true
        #expect(model.metrics.bodyWidth == resting.bodyWidth && model.metrics.height == resting.height)
        model.activityReducesMotion = false
        model.activity = false
        model.timer = .paused(left: 75, total: 120)
        #expect(!model.interactingWithTools)
        #expect(model.metrics.height == model.closedSize.height)
        model.expanded = .timer
        model.open()
        #expect(model.activityFolded && model.activityControlsHidden)
        #expect(model.metrics.bodyWidth == model.closedSize.width && model.metrics.height == model.closedSize.height)
    }
}
