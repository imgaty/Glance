import Combine
import Foundation
import Testing

@testable import Glance

/// In-memory scene and pointer routing only: no native window, event posting or actual media.
@MainActor
@Suite("Activity motion interaction boundaries", .serialized)
struct ActivityMotionInteractionTests {
    private func model() -> NotchModel {
        let model = NotchModel(closedSize: CGSize(width: 185, height: 32), layout: .top, hasCamera: true)
        model.activityReducesMotion = false
        return model
    }

    private func preview() -> SettingsPreview {
        let preview = SettingsPreview()
        preview.feelsOpening = false
        preview.model.activityReducesMotion = false
        preview.setInteractive(true, animated: false)
        preview.model.activity = true
        return preview
    }

    /// Like NotchPreview, the input region keeps the destination while the drawn shape folds.
    private func geometry(_ model: NotchModel) -> SettingsPreview.Geometry {
        SettingsPreview.Geometry(
            rect: { state in
                let metrics = model.metrics(for: state, housingPhase: state != .open)
                return CGRect(x: -metrics.totalWidth / 2, y: 0, width: metrics.totalWidth, height: metrics.height)
            }, scale: 1)
    }

    private func eventually(_ condition: () -> Bool) async throws -> Bool {
        for _ in 0..<80 {
            if condition() { return true }
            try await Task.sleep(for: .milliseconds(25))
        }
        return condition()
    }

    @Test("Controls stay unavailable through both the housing and reveal phases")
    func controlPhases() async throws {
        let model = model()
        defer { model.cancelActivityTransition() }
        model.activity = true
        var phases: [(folded: Bool, opening: Bool)] = []
        let watch = model.$activityFolded.combineLatest(model.$activityOpening).dropFirst().sink {
            phases.append((folded: $0.0, opening: $0.1))
        }
        defer { watch.cancel() }

        model.open()
        #expect(model.activityFolded && model.activityControlsHidden)
        let transition = try #require(model.activityTransitionTask)
        await transition.value

        let reveal = try #require(phases.firstIndex { !$0.folded && $0.opening })
        #expect(phases[..<reveal].contains { $0.folded })
        #expect(phases[reveal..<phases.index(before: phases.endIndex)].allSatisfy { $0.folded || $0.opening })
        #expect(phases.last?.folded == false && phases.last?.opening == false)
        #expect(!model.activityControlsHidden && model.activityTransitionTask == nil)
        #expect(model.state == .open)
    }

    @Test("The first arrival reveals from the bare housing without exposing its controls early")
    func firstArrival() async throws {
        let model = model()
        defer { model.cancelActivityTransition() }
        var folded: [Bool] = []
        let watch = model.$activityFolded.dropFirst().sink { folded.append($0) }
        defer { watch.cancel() }
        model.changeActivityPresentation { model.activity = true }
        #expect(!model.activityFolded && model.activityOpening && model.activityControlsHidden)
        let transition = try #require(model.activityTransitionTask)
        await transition.value
        #expect(!folded.contains(true))
        #expect(!model.activityControlsHidden && model.activityTransitionTask == nil)
        #expect(model.metrics.bodyWidth > model.closedSize.width)
    }

    @Test("Fullscreen cancellation restores the detached activity when the housing returns")
    func fullscreenCancellation() async throws {
        let model = model()
        defer { model.cancelActivityTransition() }
        model.activity = true
        model.timer = .paused(left: 75, total: 120)
        model.expanded = .timer
        model.openedFromBubble = true
        model.open()
        let opening = try #require(model.activityTransitionTask)
        await opening.value

        // The actual keepToCamera route closes, cancels its deferred reveal, then collapses.
        model.close()
        #expect(model.bubbleMerged && model.activityControlsHidden)
        model.cancelActivityTransition()
        model.collapsed = true
        #expect(model.detached == nil)
        model.collapsed = false
        #expect(model.detached == .timer && !model.bubbleMerged)
        #expect(!model.openedFromBubble && model.bubbleReach == 0)
        #expect(!model.activityControlsHidden && model.activityTransitionTask == nil)
    }

    @Test("Canceling an open destination keeps its detached activity merged")
    func cancelOpenDestination() {
        let model = model()
        defer { model.cancelActivityTransition() }
        model.activity = true
        model.timer = .paused(left: 75, total: 120)
        model.open()
        model.cancelActivityTransition()
        #expect(model.state == .open && model.bubbleMerged)
        #expect(model.detached == nil && model.bubbleReach == 0)
        #expect(!model.activityControlsHidden && model.activityTransitionTask == nil)
    }

    @Test("A stationary pointer inside the preview destination does not close its hardware midpoint")
    func previewStationaryPointer() async throws {
        let preview = preview()
        let model = preview.model
        defer { model.cancelActivityTransition() }
        let geometry = geometry(model)
        let point = CGPoint(x: 0, y: model.openSize.height * 0.7)
        model.openNotch()
        #expect(model.activityFolded)
        #expect(point.y > model.metrics.height)
        #expect(geometry.rect(.open).contains(point))
        let transition = try #require(model.activityTransitionTask)
        preview.pointer(at: point, geometry)
        await transition.value
        #expect(model.state == .open)
        #expect(!model.activityControlsHidden && model.activityTransitionTask == nil)
    }

    @Test("A genuine preview exit during the fold is re-evaluated after it without another pointer event")
    func previewDeferredExit() async throws {
        let preview = preview()
        let model = preview.model
        defer { model.cancelActivityTransition() }
        let geometry = geometry(model)
        model.openNotch()
        preview.pointer(at: CGPoint(x: 0, y: model.openSize.height * 0.7), geometry)
        preview.pointer(at: nil, geometry)
        #expect(model.state == .open && model.activityFolded)
        #expect(try await eventually { model.state == .closed })
        if let closing = model.activityTransitionTask { await closing.value }
        #expect(model.state == .closed && !model.activityControlsHidden)
    }
}
