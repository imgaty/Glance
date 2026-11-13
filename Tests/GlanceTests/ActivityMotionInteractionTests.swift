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

    @Test("The closing rebound stays outside the camera and keeps content inaccessible")
    func housingRebound() async throws {
        let model = model()
        defer { model.cancelActivityTransition() }
        model.activity = true
        model.open()
        let transition = try #require(model.activityTransitionTask)
        #expect(model.activityHousingRebound == 0)
        #expect(model.metrics.bodyWidth == model.closedSize.width)

        try #require(try await eventually { model.activityHousingRebound > 0 })
        #expect(model.activityFolded && model.activityControlsHidden)
        #expect(model.metrics.bodyWidth > model.closedSize.width)
        #expect(model.metrics.bodyWidth <= model.closedSize.width + 12)
        #expect(model.metrics.height > model.closedSize.height)
        #expect(model.metrics.height <= model.closedSize.height + 3)
        #expect(model.detached == nil && !model.expandedShown)

        try #require(try await eventually { model.activityHousingRebound == 0 })
        #expect(model.activityFolded)
        #expect(model.metrics.bodyWidth == model.closedSize.width)
        #expect(model.metrics.height == model.closedSize.height)
        await transition.value
        #expect(model.activityHousingRebound == 0 && !model.activityControlsHidden)
    }

    enum ReboundInterruption: CaseIterable { case teardown, reducedMotion, fullscreen, replacement }

    @Test("Interrupting the rebound cannot leave a pulse or reopen an obsolete destination", arguments: ReboundInterruption.allCases)
    func interruptedRebound(_ interruption: ReboundInterruption) async throws {
        let model = model()
        defer { model.cancelActivityTransition() }
        model.activity = true
        model.timer = .paused(left: 75, total: 120)
        model.open()
        let first = try #require(model.activityTransitionTask)
        try #require(try await eventually { model.activityHousingRebound > 0 })

        switch interruption {
        case .teardown: model.cancelActivityTransition()
        case .reducedMotion:
            model.activityReducesMotion = true
            model.close()
        case .fullscreen: model.close(intoHousing: true)
        case .replacement: #expect(model.selectActivity(.timer))
        }
        #expect(model.activityHousingRebound == 0)
        let current = model.activityTransitionTask
        await first.value
        await current?.value
        #expect(model.activityHousingRebound == 0 && model.activityTransitionTask == nil)
        #expect(!model.activityControlsHidden)
        switch interruption {
        case .teardown: #expect(model.state == .open)
        case .reducedMotion: #expect(model.state == .closed && model.detached == .timer)
        case .fullscreen: #expect(model.collapsed && model.metrics.bodyWidth == model.closedSize.width)
        case .replacement: #expect(model.state == .open && model.expanded == .timer)
        }
    }

    @Test("Fullscreen cancellation restores the detached activity when the housing returns", arguments: [false, true])
    func fullscreenCancellation(_ duringTransition: Bool) async throws {
        let model = model()
        defer { model.cancelActivityTransition() }
        model.activity = true
        model.timer = .paused(left: 75, total: 120)
        model.expanded = .timer
        model.openedFromBubble = true
        model.open()
        let opening = try #require(model.activityTransitionTask)
        if !duringTransition { await opening.value }
        let order = model.activities
        model.proximity = 1
        model.pressed = true
        model.stretch = 12
        model.lean = 9
        model.pageStretch = 7

        // The real fullscreen route is atomic, including cancellation of an in-flight opening.
        model.close(intoHousing: true)
        #expect(model.state == .closed && model.collapsed)
        #expect(model.detached == nil)
        #expect(model.metrics.bodyWidth == model.closedSize.width && model.metrics.height == model.closedSize.height)
        #expect(!model.activityControlsHidden && model.activityTransitionTask == nil)
        await opening.value
        #expect(model.state == .closed && model.collapsed && model.activities == order)
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

    @Test("Releasing a hold early during an unrelated fold cancels the pending pointer opening")
    func releaseHoldDuringFold() async throws {
        let preview = SettingsPreview(opening: {
            Opening(onHover: false, onClick: true, hoverDelay: 0, clickDelay: 0.1, haptics: false)
        })
        preview.feelsOpening = false
        preview.model.activityReducesMotion = false
        preview.setInteractive(true, animated: false)
        let model = preview.model
        defer { model.cancelActivityTransition() }
        model.activity = true
        let geometry = geometry(model)
        let point = CGPoint(x: 0, y: model.closedSize.height / 2)

        preview.press(at: point, geometry)
        #expect(model.pressed)
        model.changeActivityPresentation { model.timer = .paused(left: 75, total: 120) }
        #expect(model.activityFolded)
        let unrelatedTransition = try #require(model.activityTransitionTask)
        let transitionID = model.activityTransitionID
        preview.release(at: point, geometry)
        #expect(!model.pressed && !model.bubblePressed)
        await unrelatedTransition.value

        // Resting inside may produce the ordinary peek, but the abandoned hold must never open.
        #expect(model.state != .open)
        #expect(model.activityTransitionID == transitionID)
        #expect(!model.activityControlsHidden && model.activityTransitionTask == nil)
    }
}
