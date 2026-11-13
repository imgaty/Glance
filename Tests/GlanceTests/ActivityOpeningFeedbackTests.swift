import Foundation
import Testing

@testable import Glance

/// Feedback is a callback spy here, never the physical trackpad performer.
@MainActor
@Suite("Activity opening feedback", .serialized)
struct ActivityOpeningFeedbackTests {
    private func model() -> NotchModel {
        let model = NotchModel(closedSize: CGSize(width: 185, height: 32), layout: .top, hasCamera: true)
        model.activityReducesMotion = false
        return model
    }

    @Test("An opening taps once at the housing, not at the initial request")
    func collapseBeat() async throws {
        let model = model()
        defer { model.cancelActivityTransition() }
        model.activity = true
        var taps = 0
        model.open {
            taps += 1
            #expect(model.activityFolded && model.activityControlsHidden)
            #expect(model.metrics.bodyWidth == model.closedSize.width)
            #expect(model.metrics.height == model.closedSize.height)
        }
        #expect(taps == 0)
        let task = try #require(model.activityTransitionTask)
        model.open { Issue.record("A duplicate open must not add feedback") }
        await task.value
        #expect(taps == 1)
        #expect(model.state == .open && !model.activityControlsHidden)
        model.close()
        await model.activityTransitionTask?.value
        #expect(taps == 1)
    }

    enum Interruption: CaseIterable { case close, teardown, fullscreen, replacement }

    @Test("A superseded opening never emits its delayed tap", arguments: Interruption.allCases)
    func cancelledBeat(_ interruption: Interruption) async throws {
        let model = model()
        defer { model.cancelActivityTransition() }
        model.activity = true
        model.timer = .paused(left: 75, total: 120)
        var taps = 0
        model.open { taps += 1 }
        let first = try #require(model.activityTransitionTask)
        switch interruption {
        case .close: model.close()
        case .teardown: model.cancelActivityTransition()
        case .fullscreen: model.close(intoHousing: true)
        case .replacement: #expect(model.selectActivity(.timer))
        }
        let next = model.activityTransitionTask
        await first.value
        await next?.value
        #expect(taps == 0)
    }

    @Test("Bare housing and Reduce Motion give immediate feedback without a fake wait", arguments: [false, true])
    func noFold(reduced: Bool) async {
        let model = model()
        defer { model.cancelActivityTransition() }
        model.activity = reduced
        model.activityReducesMotion = reduced
        var taps = 0
        model.open { taps += 1 }
        #expect(taps == 1)
        #expect(!model.activityFolded)
        await model.activityTransitionTask?.value
        #expect(taps == 1)
    }

    enum PreviewFeedback: CaseIterable { case enabled, disabled, disabledDuringFold, demonstration }

    @Test("The preview checks its current haptic setting at the collapse point", arguments: PreviewFeedback.allCases)
    func previewPreference(_ scenario: PreviewFeedback) async throws {
        var enabled = scenario != .disabled
        var taps = 0
        let preview = SettingsPreview(
            opening: { Opening(onHover: true, onClick: true, hoverDelay: 0, clickDelay: 0, haptics: enabled) },
            openingFeedback: { taps += 1 })
        preview.feelsOpening = scenario != .demonstration
        preview.model.activityReducesMotion = false
        preview.setInteractive(true, animated: false)
        preview.model.activity = true
        defer { preview.model.cancelActivityTransition() }
        preview.model.openNotch()
        let task = try #require(preview.model.activityTransitionTask)
        #expect(taps == 0)
        if scenario == .disabledDuringFold { enabled = false }
        await task.value
        #expect(taps == (scenario == .enabled ? 1 : 0))
    }
}
