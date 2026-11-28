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

    @Test("Beside a bubble, the player opens straight, taking the bubble in at once, and it buds off after closing", arguments: [NotchPage.player, .tray])
    func bubbleChoreography(_ page: NotchPage) async throws {
        let model = model()
        defer { model.cancelActivityTransition() }
        model.timer = .paused(left: 75, total: 120)
        model.page = page
        let order = model.activities
        #expect(model.opensStraight)
        model.open()
        #expect(model.state == .open && model.bubbleMerged && !model.activityFolded)
        #expect(!model.activityControlsHidden && model.activityTransitionTask == nil)
        #expect(model.bubbleReach == 0)
        model.close()
        #expect(model.state == .closed && model.bubbleMerged && !model.activityFolded)
        #expect(!model.activityControlsHidden)
        let closing = try #require(model.activityTransitionTask)
        await closing.value
        #expect(!model.bubbleMerged && model.detached == .timer)
        #expect(model.activities == order)
    }

    @Test("Opened from the bubble, the player folds to the housing first; closing during the fold cancels its opening")
    func interruptedMerge() async throws {
        let model = model()
        defer { model.cancelActivityTransition() }
        model.activity = false
        model.timer = .paused(left: 75, total: 120)
        model.activity = true
        #expect(model.detached == .music)
        model.openedFromBubble = true
        model.open()
        #expect(model.state == .closed && model.activityFolded && model.bubbleMerged)
        let opening = try #require(model.activityTransitionTask)
        model.close()
        let closing = model.activityTransitionTask
        await opening.value
        await closing?.value
        #expect(model.state == .closed && !model.activityControlsHidden)
        #expect(model.detached == .music && !model.bubbleMerged)
        #expect(model.activityTransitionTask == nil)
    }

    @Test("Every compact swells its outline under the pointer, never its size; tall announcements and Reduce Motion don't")
    func scopedHover() {
        let model = model()
        defer { model.cancelActivityTransition() }
        let resting = model.metrics
        model.peek()
        model.hoverPlace = .zero
        #expect(model.metrics.bodyWidth == resting.bodyWidth && model.metrics.height == resting.height)
        let h = model.closedSize.height
        #expect(abs(model.outline.leading - 2.4 * h / 34.5) < 0.01 && abs(model.outline.trailing - 2.4 * h / 34.5) < 0.01)
        #expect(abs(model.outline.bottom - 1.5 * h / 34.5) < 0.01)
        model.activityReducesMotion = true
        #expect(model.outline == .zero)
        model.activityReducesMotion = false
        // An activity's compact swells as the player's does.
        model.activity = false
        model.timer = .paused(left: 75, total: 120)
        #expect(!model.interactingWithTools)
        #expect(model.outline.across > 4)
        #expect(model.metrics.height == model.closedSize.height)
        // As tall as the Alarm, nothing swells.
        model.alert = NotchAlert(kind: .timerDone, content: .timerDone(length: 60, name: "Timer"), spoken: "Timer done", stays: true)
        #expect(model.restingTall && model.outline == .zero)
        model.alert = nil
        model.expanded = .timer
        model.open()
        // Open, it takes no notice of the pointer.
        #expect(!model.activityFolded && model.activityControlsHidden)
        #expect(model.hoverPlace == nil && model.outline == .zero)
        #expect(model.metrics.height == ExpandedTimerView.height(for: model.expandedClock!, restingHeight: model.closedSize.height))
    }
}
