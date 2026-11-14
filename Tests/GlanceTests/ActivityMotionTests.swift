import Foundation
import Testing

@testable import Glance

/// Model-only motion contracts. No windows, native actions, global preferences or animation pace
/// changes are involved; payloads remain in memory and every delayed task is cancelled on exit.
@MainActor
@Suite("Activity presentation motion", .serialized)
struct ActivityMotionTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func model(reduced: Bool = false) -> NotchModel {
        let model = NotchModel(closedSize: CGSize(width: 185, height: 32), layout: .top, hasCamera: true)
        model.activityReducesMotion = reduced
        return model
    }

    private func install(_ activity: NotchModel.Activity, in model: NotchModel) {
        switch activity {
        case .music: model.activity = true
        case .timer: model.timer = .paused(left: 75, total: 120)
        case .stopwatch: model.stopwatch = .stopped(elapsed: 31)
        case .airdrop: model.airdrop = AirDropShown(id: "motion-transfer", sender: "Alex", preview: nil, fraction: 0.3)
        case .airplay: model.airplay = AirPlayRoute(name: "Fixture Speaker", symbol: "hifispeaker", outputID: 41)
        case .call: model.call = CallShown(name: "Alex", over: "Phone", phase: .connected(since: start))
        case .screenRecording: model.screenRecording = .recording(since: start)
        case .voiceMemo: model.voiceMemo = .recording(since: start)
        case .alarm: model.alarm = ActivityBench.alarmFixture()
        case .printing: model.printing = ActivityBench.printFixture()
        case .shortcut: model.shortcut = .init(run: .fixture())
        case .recognition:
            model.recognitionIdentity = UUID()
            model.recognition = .recognizing
        }
    }

    private func expectHardware(_ model: NotchModel) {
        #expect(model.activityFolded)
        #expect(model.metrics.bodyWidth == model.closedSize.width)
        #expect(model.metrics.height == model.closedSize.height)
        #expect(model.metrics.fold == 0)
        #expect(model.bubbleReach == 0)
        #expect(!model.expandedShown)
        #expect(model.detached == nil)
    }

    private func finishFold(_ model: NotchModel) async throws {
        // Other suites can occupy the main actor before this task begins its bounded sleep.
        // Await the captured transition rather than counting from the caller's wall-clock time.
        let transition = try #require(model.activityTransitionTask)
        await transition.value
    }

    @Test("The player opens and closes directly while other activities keep their hardware midpoint", arguments: NotchModel.Activity.allCases)
    func familyOpenClose(_ activity: NotchModel.Activity) async throws {
        let model = model()
        defer { model.cancelActivityTransition() }
        install(activity, in: model)
        model.expanded = activity == .music ? nil : activity
        let order = model.activities

        // Existing hover/press/gesture deformation must not leak into the hardware midpoint.
        model.state = .peek
        model.proximity = 1
        model.pressed = true
        model.stretch = 12
        model.lean = 9
        model.pageStretch = 7
        model.open()
        if activity == .music {
            #expect(!model.activityFolded && model.activityOpening)
            #expect(model.metrics.bodyWidth == model.openSize.width)
            #expect(model.metrics.height == model.openSize.height)
        } else {
            expectHardware(model)
        }
        #expect(model.state == .open)
        #expect(!model.activityReturnsInline)
        let opening = model.activityTransitionID
        model.pressed = false
        model.stretch = 0
        model.lean = 0
        model.pageStretch = 0
        try await finishFold(model)
        #expect(!model.activityFolded)
        #expect(model.activityTransitionTask == nil)
        #expect(model.metrics.bodyWidth > model.closedSize.width)
        #expect(model.metrics.height > model.closedSize.height)
        #expect(model.expanded == (activity == .music ? nil : activity))

        model.close()
        if activity == .music {
            #expect(!model.activityFolded && !model.activityReturnsInline)
            #expect(model.metrics.bodyWidth > model.closedSize.width)
        } else {
            expectHardware(model)
            #expect(model.activityReturnsInline)
        }
        #expect(model.state == .closed)
        #expect(model.activityTransitionID > opening)
        try await finishFold(model)
        #expect(!model.activityFolded)
        #expect(model.metrics.bodyWidth > model.closedSize.width)
        #expect(model.activities == order)
    }

    @Test("Detached music opens directly and supersedes an unfinished closing")
    func detachedPlayerReopening() async throws {
        let model = model()
        defer { model.cancelActivityTransition() }
        install(.timer, in: model)
        install(.music, in: model)
        model.openedFromBubble = true
        let order = model.activities
        #expect(model.detached == .music)
        var taps = 0
        model.open { taps += 1 }
        #expect(taps == 1)
        #expect(!model.activityFolded && model.activityOpening)
        #expect(model.openedFromBubble && model.bubbleMerged)
        let first = try #require(model.activityTransitionTask)
        model.close()
        #expect(!model.activityFolded && model.bubbleReach == model.bubbleSpan)
        let closing = try #require(model.activityTransitionTask)
        model.open { taps += 1 }
        let reopened = try #require(model.activityTransitionTask)
        #expect(taps == 2)
        #expect(!model.activityFolded && model.activityOpening)
        #expect(model.metrics.height == model.openSize.height)
        await first.value
        await closing.value
        await reopened.value
        #expect(model.state == .open && model.expanded == nil)
        #expect(!model.activityControlsHidden && model.activityTransitionTask == nil)
        #expect(model.activities == order && model.openedFromBubble)
    }

    @Test("Player closing restores its compact pose and detached bubble without a housing excursion", arguments: [false, true], [false, true])
    func playerClosing(reduced: Bool, fromBubble: Bool) async {
        let model = model(reduced: reduced)
        defer { model.cancelActivityTransition() }
        if fromBubble { install(.timer, in: model) }
        install(.music, in: model)
        if !fromBubble { install(.timer, in: model) }
        let order = model.activities
        model.openedFromBubble = fromBubble
        model.open()
        let opening = model.activityTransitionTask
        model.close()
        let closing = model.activityTransitionTask
        #expect(model.state == .closed && !model.activityFolded)
        #expect(!model.activityReturnsInline && !model.bubbleMerged)
        #expect(model.metrics.bodyWidth > model.closedSize.width)
        #expect(model.bubbleReach == (fromBubble && !reduced ? model.bubbleSpan : 0))
        #expect(model.activityControlsHidden == !reduced)
        await opening?.value
        await closing?.value
        #expect(model.state == .closed && !model.activityControlsHidden)
        #expect(model.bubbleReach == 0 && !model.openedFromBubble)
        #expect(model.activities == order && model.detached == order[1])
        #expect(model.activityTransitionTask == nil)
    }

    @Test("The compact return spring cannot leak into arrivals, replacements or a reversed opening")
    func compactReturnScope() {
        let model = model()
        defer { model.cancelActivityTransition() }
        model.changeActivityPresentation { model.timer = .paused(left: 75, total: 120) }
        model.expanded = .timer
        #expect(!model.activityReturnsInline)
        model.open()
        model.close()
        #expect(model.activityReturnsInline)
        model.open()
        #expect(!model.activityReturnsInline)
        model.close()
        #expect(model.activityReturnsInline)
        model.changeActivityPresentation { model.activity = true }
        #expect(!model.activityReturnsInline)
        model.open()
        model.close()
        #expect(model.activityReturnsInline)
        model.cancelActivityTransition()
        #expect(!model.activityReturnsInline)
    }

    @Test("Primary player opening and detached activity opening restore the same activity order", arguments: [false, true])
    func detachedOrigins(_ fromBubble: Bool) async throws {
        let model = model()
        defer { model.cancelActivityTransition() }
        install(.music, in: model)
        install(.timer, in: model)
        #expect(model.detached == .timer)
        model.expanded = fromBubble ? .timer : nil
        model.openedFromBubble = fromBubble
        model.bubbleReach = fromBubble ? model.bubbleSpan : 0
        let order = model.activities

        model.open()
        if fromBubble {
            expectHardware(model)
        } else {
            #expect(!model.activityFolded && model.activityOpening)
            #expect(model.metrics.height == model.openSize.height)
        }
        #expect(model.bubbleMerged)
        try await finishFold(model)
        #expect(model.state == .open && !model.activityFolded)
        #expect(model.openedFromBubble == fromBubble)
        #expect(model.detached == nil)

        model.close()
        if fromBubble { expectHardware(model) } else { #expect(!model.activityFolded) }
        try await finishFold(model)
        #expect(model.detached == .timer)
        #expect(!model.bubbleMerged)
        #expect(!model.openedFromBubble)
        #expect(model.bubbleReach == 0)
        #expect(model.activities == order)
    }

    @Test("Device expansion and settling each pass through hardware without losing the announcement")
    func deviceExpansion() async throws {
        let model = model()
        defer { model.cancelActivityTransition() }
        let alert = NotchAlert(kind: .device, content: .device(model: .airpodsPro, battery: 78), spoken: "Fixture headphones")
        model.alert = alert
        model.alertWing = 60
        model.alertExtendedWing = 130
        model.extend()
        expectHardware(model)
        #expect(model.alertExtended && model.state == .peek)
        try await finishFold(model)
        #expect(model.metrics.height > model.closedSize.height)
        let expanded = model.activityTransitionID

        model.settle(closeness: 0)
        expectHardware(model)
        #expect(model.activityTransitionID > expanded)
        try await finishFold(model)
        #expect(model.state == .closed && !model.alertExtended)
        #expect(model.alert?.id == alert.id)
        #expect(model.metrics.bodyWidth > model.closedSize.width)
    }

    @Test("Replacing and removing an announcement preserve the underlying activity")
    func announcementReplacement() async throws {
        let model = model()
        defer { model.cancelActivityTransition() }
        install(.music, in: model)
        let first = NotchAlert(kind: .device, content: .device(model: .airpodsPro, battery: 78), spoken: "First")
        let second = NotchAlert(kind: .device, content: .device(model: .airpodsMax, battery: 65), spoken: "Second")
        model.alert = first
        model.alertWing = 60
        model.changeActivityPresentation { model.alert = second }
        expectHardware(model)
        #expect(model.alert?.id == second.id)
        try await finishFold(model)
        #expect(model.alert?.id == second.id)
        let replacement = model.activityTransitionID

        model.changeActivityPresentation { model.alert = nil }
        expectHardware(model)
        #expect(model.activityTransitionID > replacement)
        try await finishFold(model)
        #expect(model.alert == nil)
        #expect(model.activities == [.music])
        #expect(model.metrics.bodyWidth > model.closedSize.width)
    }

    @Test("Routine progress, time and capability updates neither start nor restart a fold")
    func routineUpdates() async throws {
        let model = model()
        defer { model.cancelActivityTransition() }
        install(.airdrop, in: model)
        install(.timer, in: model)
        install(.call, in: model)
        install(.voiceMemo, in: model)
        install(.screenRecording, in: model)
        install(.airplay, in: model)
        let initial = model.activityTransitionID
        model.changeActivityPresentation {
            model.airdrop?.fraction = 0.4
            model.timer = .paused(left: 74, total: 120)
            model.call?.phase = .connected(since: start + 1)
            model.voiceMemo = .recording(since: start + 1)
            model.screenRecording = .recording(since: start + 1)
            model.airplay?.stopFailed = true
        }
        #expect(model.activityTransitionID == initial)
        #expect(!model.activityFolded)

        model.expanded = .airdrop
        model.open()
        let opening = model.activityTransitionID
        model.changeActivityPresentation { model.airdrop?.fraction = 0.8 }
        #expect(model.activityTransitionID == opening)
        expectHardware(model)
        try await finishFold(model)
        #expect(!model.activityFolded)
        #expect(model.airdrop?.fraction == 0.8)
    }

    @Test("Tray and player navigation stays open without folding or hiding controls")
    func pageNavigationStaysOpen() async throws {
        let model = model()
        defer { model.cancelActivityTransition() }
        install(.music, in: model)
        model.open()
        try await finishFold(model)
        for page in [NotchPage.tray, .player, .tray, .player] {
            model.turn(to: page)
            #expect(model.state == .open)
            #expect(model.page == page)
            #expect(!model.activityFolded && !model.activityOpening)
            #expect(!model.activityControlsHidden)
            #expect(model.activityTransitionTask == nil)
            #expect(model.metrics.height > model.closedSize.height)
        }
    }

    @Test("Navigating during opening cancels the old deferred presentation")
    func pageNavigationDuringOpening() async throws {
        let model = model()
        defer { model.cancelActivityTransition() }
        install(.timer, in: model)
        model.expanded = .timer
        model.open()
        let oldOpening = try #require(model.activityTransitionTask)
        model.turn(to: .tray)
        await oldOpening.value
        #expect(model.state == .open && model.page == .tray)
        #expect(model.expanded == nil)
        #expect(!model.activityControlsHidden && !model.activityFolded)
        #expect(model.activityTransitionTask == nil)
    }

    @Test("A tray-to-player swipe preserves the pointer's old footprint until it leaves or enters the player")
    func pageNavigationPointer() {
        let tray = CGRect(x: 100, y: 0, width: 700, height: 180)
        let player = CGRect(x: 200, y: 0, width: 500, height: 160)
        let retained = NotchController.pageNavigationZone(from: tray, to: player, pointer: CGPoint(x: 750, y: 100))
        #expect(retained == tray)
        #expect(NotchController.pageNavigationZone(from: tray, to: player, pointer: CGPoint(x: 500, y: 100)) == nil)
        #expect(NotchController.pageNavigationZone(from: tray, to: player, pointer: CGPoint(x: 850, y: 100)) == nil)
        #expect(NotchController.pageNavigationZone(from: tray, to: player, pointer: CGPoint(x: 750, y: 220)) == nil)
    }

    @Test("Rapid reversal and queued selections settle on the latest target without reordering")
    func latestSelectionWins() async throws {
        let model = model()
        defer { model.cancelActivityTransition() }
        install(.music, in: model)
        install(.timer, in: model)
        install(.call, in: model)
        let order = model.activities
        model.open()
        let opening = model.activityTransitionID
        model.close()
        model.open()
        #expect(model.selectActivity(.timer))
        #expect(model.selectActivity(.call))
        let latest = model.activityTransitionID
        #expect(latest > opening)
        expectHardware(model)
        #expect(model.expanded == .call && model.state == .open)
        try await finishFold(model)
        #expect(model.activityTransitionID == latest)
        #expect(!model.activityFolded)
        #expect(model.expanded == .call && model.expandedShown)
        #expect(model.activities == order)
        #expect(model.second == .timer)
    }

    @Test("A source ending during the fold cannot reopen an obsolete expanded page")
    func sourceEnds() async throws {
        let model = model()
        defer { model.cancelActivityTransition() }
        install(.timer, in: model)
        model.expanded = .timer
        model.open()
        let opening = model.activityTransitionID
        model.changeActivityPresentation { model.timer = nil }
        #expect(model.expandedGone)
        model.close()  // Controller's existing expandedGone route.
        #expect(model.activityTransitionID > opening)
        try await finishFold(model)
        #expect(model.state == .closed)
        #expect(model.activities.isEmpty)
        #expect(!model.expandedShown && !model.activityFolded)
        #expect(model.metrics.bodyWidth == model.closedSize.width)
        #expect(model.metrics.height == model.closedSize.height)
    }

    @Test("Teardown invalidates a pending reopen and leaves only the hardware")
    func teardown() async throws {
        let model = model()
        install(.music, in: model)
        model.open()
        let opening = model.activityTransitionID
        model.collapseAway()
        let cancelled = model.activityTransitionID
        #expect(cancelled > opening)
        #expect(model.activityTransitionTask == nil)
        try await Task.sleep(for: .seconds(NotchModel.activityFoldDuration + 0.12))
        #expect(model.activityTransitionID == cancelled)
        #expect(model.state == .closed && model.collapsed)
        #expect(!model.activityFolded && !model.activity)
        #expect(model.metrics.bodyWidth == model.closedSize.width)
        #expect(model.metrics.height == model.closedSize.height)
    }

    @Test("Reduced Motion uses destination geometry without a hardware excursion", arguments: NotchModel.Activity.allCases)
    func reducedMotion(_ activity: NotchModel.Activity) {
        let model = model(reduced: true)
        defer { model.cancelActivityTransition() }
        install(activity, in: model)
        model.expanded = activity == .music ? nil : activity
        model.open()
        #expect(!model.activityFolded && model.activityTransitionTask == nil)
        #expect(model.metrics.bodyWidth > model.closedSize.width)
        #expect(model.metrics.height > model.closedSize.height)
        model.close()
        #expect(!model.activityFolded && model.activityTransitionTask == nil)
        #expect(!model.activityReturnsInline)
        #expect(model.state == .closed)
        #expect(model.metrics.bodyWidth > model.closedSize.width)
    }

    @Test("Enabling Reduce Motion during a fold cancels its deferred destination")
    func reducedMotionDuringFold() async throws {
        let model = model()
        defer { model.cancelActivityTransition() }
        install(.timer, in: model)
        model.expanded = .timer
        model.open()
        expectHardware(model)
        model.activityReducesMotion = true
        model.close()
        #expect(!model.activityFolded)
        #expect(model.metrics.bodyWidth > model.closedSize.width)
        try await Task.sleep(for: .seconds(NotchModel.activityFoldDuration + 0.12))
        #expect(model.state == .closed && !model.activityFolded)
    }
}
