//
//  IslandFeelTests.swift
//  GlanceTests
//
//  Created by Gaty on 25/11/2026.
//

import AppKit
import Foundation
import Testing

@testable import Glance

/// The swell and lean under the pointer, worked out from where it is, with nothing else involved.
@Suite("The outline leans toward the pointer")
struct IslandSwellTests {
    private let shape = CGRect(x: 100, y: 500, width: 200, height: 40)

    @Test("Where the pointer is on a shape, by its middle, both ways, and no further than its edges")
    func place() {
        #expect(IslandSwell.place(of: CGPoint(x: 200, y: 520), in: shape) == .zero)
        // The screen counts up: the shape's top is its highest y, and down is positive here.
        #expect(IslandSwell.place(of: CGPoint(x: 300, y: 500), in: shape) == CGPoint(x: 1, y: 1))
        #expect(IslandSwell.place(of: CGPoint(x: 100, y: 540), in: shape) == CGPoint(x: -1, y: -1))
        #expect(IslandSwell.place(of: CGPoint(x: 900, y: -40), in: shape) == CGPoint(x: 1, y: 1))
        #expect(IslandSwell.place(of: CGPoint(x: 250, y: 530), in: shape) == CGPoint(x: 0.5, y: -0.5))
        // Right to left, the leading end is on the right.
        #expect(IslandSwell.place(of: CGPoint(x: 250, y: 520), in: shape, rightToLeft: true).x == -0.5)
    }

    @Test("In the middle, an even swell: 2.4 points a side and 1.5 at the bottom of a 34.5 point island")
    func centered() {
        let swell = IslandSwell.island(toward: .zero, height: 34.5)
        #expect(isClose(swell.leading, 2.4, tolerance: 1e-6) && isClose(swell.trailing, 2.4, tolerance: 1e-6))
        #expect(isClose(swell.bottom, 1.5, tolerance: 1e-6))
        // Scaled to the notch's height.
        let notch = IslandSwell.island(toward: .zero, height: 32)
        #expect(isClose(notch.across, 4.8 * 32 / 34.5, tolerance: 1e-6))
    }

    @Test("At an end, the near end reaches out and the far end stays still; low down, the bottom reaches further")
    func leaning() {
        let trailing = IslandSwell.leaning(toward: CGPoint(x: 1, y: 0), side: 2, foot: 1)
        #expect(trailing.leading == 0 && trailing.trailing == 4 && trailing.bottom == 1)
        let leading = IslandSwell.leaning(toward: CGPoint(x: -1, y: 0), side: 2, foot: 1)
        #expect(leading.leading == 4 && leading.trailing == 0)
        // Half way to an end, three quarters out on its side, a quarter on the other.
        let half = IslandSwell.leaning(toward: CGPoint(x: 0.5, y: 0), side: 2, foot: 1)
        #expect(half.leading == 1 && half.trailing == 3)
        // The bottom: more below the middle, never less than its even swell above it, as the top,
        // the screen's edge, can't move.
        #expect(IslandSwell.leaning(toward: CGPoint(x: 0, y: 1), side: 2, foot: 1).bottom == 2)
        #expect(IslandSwell.leaning(toward: CGPoint(x: 0, y: -1), side: 2, foot: 1).bottom == 1)
        // However far off the pointer is reported, it goes no further than at the end.
        #expect(IslandSwell.leaning(toward: CGPoint(x: 7, y: 9), side: 2, foot: 1) == IslandSwell(leading: 0, trailing: 4, bottom: 2))
    }

    @Test("Pressed, it gives back its width and keeps its height; the bubble swells about half as much")
    func pressedAndBubble() {
        let swell = IslandSwell.island(toward: CGPoint(x: 0.3, y: 0.5), height: 34.5)
        #expect(swell.pressed == IslandSwell(leading: 0, trailing: 0, bottom: swell.bottom))
        let bubble = IslandSwell.bubble(toward: .zero, height: 34.5)
        #expect(isClose(bubble.leading, 1, tolerance: 1e-6) && isClose(bubble.bottom, 1, tolerance: 1e-6))
    }
}

/// When the notch goes straight between shapes, and when it passes through the bare housing.
@MainActor
@Suite("Straight, or through the housing", .serialized)
struct IslandRouteTests {
    private func model() -> NotchModel {
        let model = NotchModel(closedSize: CGSize(width: 185, height: 32), layout: .top, hasCamera: true)
        model.activityReducesMotion = false
        return model
    }

    /// A screen recording has the notch, a timer the bubble.
    private func twoActivities() -> NotchModel {
        let model = model()
        model.screenRecording = .recording(since: .now)
        model.timer = .paused(left: 75, total: 120)
        #expect(model.activities == [.screenRecording, .timer] && model.detached == .timer)
        return model
    }

    @Test("The notch's own activity opens straight beside its bubble, the notch's end over the bubble at once")
    func ownOpensStraight() async throws {
        let model = twoActivities()
        defer { model.cancelActivityTransition() }
        model.expanded = .screenRecording
        #expect(model.opensStraight)
        model.open()
        #expect(model.state == .open && !model.activityFolded && model.activityOpening)
        #expect(model.bubbleMerged && model.bubbleReach == 0)
        try await settle { model.activityTransitionTask == nil }
        // Open, the bubble's activity is taken in, not beside it.
        #expect(model.bubbleMerged && !model.bubbleRests)
    }

    @Test("It closes straight back, the bubble budding off the shrinking end a moment after")
    func ownClosesStraight() async throws {
        let model = twoActivities()
        defer { model.cancelActivityTransition() }
        model.expanded = .screenRecording
        model.open()
        try await settle { model.activityTransitionTask == nil }
        #expect(model.closesStraight)
        let started = ContinuousClock.now
        model.close()
        #expect(model.state == .closed && !model.activityFolded)
        #expect(model.bubbleMerged && model.bubbleRests)
        try await settle { !model.bubbleMerged }
        // A delayed task never finishes early.
        #expect(ContinuousClock.now - started >= .seconds(NotchMotion.budDelay))
        #expect(model.detached == .timer)
        try await settle { model.activityTransitionTask == nil }
    }

    @Test("The bubble's activity opens through the housing, and the notch's own buds off beside the open view")
    func bubbleOpensThroughHousing() async throws {
        let model = twoActivities()
        defer { model.cancelActivityTransition() }
        model.expanded = .timer
        model.openedFromBubble = true
        #expect(!model.opensStraight)
        model.open()
        #expect(model.activityFolded && model.bubbleMerged)
        #expect(model.metrics.bodyWidth == model.closedSize.width && model.metrics.height == model.closedSize.height)
        try await settle { !model.activityFolded }
        let grew = ContinuousClock.now
        // Grown out of the housing, the screen recording waits in the notch, then buds off beside it.
        #expect(model.state == .open && model.bubbleRests && model.bubbleMerged)
        try await settle { !model.bubbleMerged }
        #expect(ContinuousClock.now - grew >= .seconds(NotchMotion.budDelay * 0.9))
        #expect(model.state == .open && model.openedFromBubble)
    }

    @Test("Closing back into the bubble passes through the housing, the notch's own growing back")
    func bubbleClosesThroughHousing() async throws {
        let model = twoActivities()
        defer { model.cancelActivityTransition() }
        model.expanded = .timer
        model.openedFromBubble = true
        model.open()
        try await settle { model.activityTransitionTask == nil }
        #expect(!model.closesStraight)
        model.close()
        #expect(model.activityFolded && model.bubbleMerged)
        try await settle { !model.activityFolded }
        #expect(model.state == .closed && !model.openedFromBubble)
        try await settle { !model.bubbleMerged }
        #expect(model.detached == .timer)
    }

    @Test("A new activity taking the notch passes through the housing; the old one buds off")
    func newActivityFolds() async throws {
        let model = model()
        defer { model.cancelActivityTransition() }
        model.timer = .paused(left: 75, total: 120)
        try await settle { model.activityTransitionTask == nil }
        model.changeActivityPresentation { model.timer = nil }
        try await settle { model.activityTransitionTask == nil }
        model.timer = .paused(left: 75, total: 120)
        try await settle { model.activityTransitionTask == nil }
        model.changeActivityPresentation { model.screenRecording = .recording(since: .now) }
        // The recording came second: the timer keeps the notch, and the recording buds off it.
        #expect(model.activities == [.timer, .screenRecording])
        #expect(model.activityFolded && model.bubbleMerged)
        try await settle { !model.activityFolded }
        try await settle { !model.bubbleMerged }
        #expect(model.detached == .screenRecording)
    }

    @Test("Opened from the notch with music beside the camera, the player opens straight; from the bubble, through the housing")
    func playerRoutes() async throws {
        let straight = model()
        defer { straight.cancelActivityTransition() }
        straight.activity = true
        straight.timer = .paused(left: 75, total: 120)
        #expect(straight.opensStraight)
        straight.open()
        #expect(straight.state == .open && !straight.activityFolded && straight.bubbleMerged)

        let folding = model()
        defer { folding.cancelActivityTransition() }
        folding.timer = .paused(left: 75, total: 120)
        folding.activity = true
        folding.openedFromBubble = true
        #expect(!folding.opensStraight)
        folding.open()
        #expect(folding.state == .closed && folding.activityFolded)
        try await settle { folding.state == .open && !folding.activityFolded }
        // The timer, which has the notch, buds off beside the open player.
        try await settle { !folding.bubbleMerged }
        #expect(folding.bubbleRests && folding.activities.first == .timer)
    }

    @Test("Over an announcement, opening changes what the notch shows, so it folds")
    func announcementFolds() {
        let model = model()
        model.timer = .paused(left: 75, total: 120)
        model.alert = NotchAlert(kind: .timerDone, content: .timerDone(length: 60, name: "Timer"), spoken: "Timer done", stays: true)
        model.expanded = .timer
        #expect(!model.opensStraight)
    }

    @Test("Reduce Motion goes straight to where it's going, with no housing and no budding")
    func reducedMotion() {
        let model = twoActivities()
        model.activityReducesMotion = true
        model.expanded = .timer
        model.openedFromBubble = true
        model.open()
        #expect(model.state == .open && !model.activityFolded && model.activityTransitionTask == nil)
        // The notch's own shows beside the open view at once.
        #expect(!model.bubbleMerged && model.bubbleRests)
    }
}

/// The swell's size, the press, the taller arrival and the shadow.
@MainActor
@Suite("Island feel on the notch", .serialized)
struct IslandFeelTests {
    private func model() -> NotchModel {
        let model = NotchModel(closedSize: CGSize(width: 185, height: 32), layout: .top, hasCamera: true)
        model.activityReducesMotion = false
        model.activity = true
        return model
    }

    @Test("One spring for every change of shape, and the housing phase a quarter of a second")
    func timing() {
        #expect(NotchMotion.response == 0.38 && NotchMotion.damping == 0.76)
        #expect(NotchMotion.foldDuration == 0.25 && NotchMotion.budDelay == 0.17)
        #expect(NotchModel.activityFoldDuration == 0.25)
        #expect(NotchModel.activityControlDelay <= 0.26)
    }

    @Test("The bubble sits 0.217 of the notch's height off its end, beside the compact and an open view alike")
    func bubbleGap() {
        #expect(IslandBubble.gap == 0.217)
        let model = model()
        #expect(isClose(model.bubbleSpan, 32 * 1.217, tolerance: 1e-6))
    }

    @Test("Pressed, the swell gives back its width; the bubble goes back to its resting size")
    func press() {
        let model = model()
        model.timer = .paused(left: 75, total: 120)
        model.hoverPlace = .zero
        let swollen = model.outline
        model.pressed = true
        #expect(model.outline == swollen.pressed)
        #expect(model.metrics.bodyWidth == model.restingWidth && model.metrics.height == model.closedSize.height)
        model.bubbleHoverPlace = .zero
        #expect(model.bubbleOutline.across > 1)
        model.bubblePressed = true
        #expect(model.bubbleOutline == .zero)
    }

    @Test("The swell pushes the bubble along by half its own reach")
    func push() {
        let model = model()
        model.timer = .paused(left: 75, total: 120)
        model.hoverPlace = CGPoint(x: 1, y: 0)
        #expect(isClose(model.bubblePush, model.outline.trailing / 2, tolerance: 1e-9) && model.bubblePush > 2)
    }

    @Test("After closing, the compact arrives taller the taller the view was, and relaxes back")
    func arrival() async throws {
        #expect(isClose(NotchModel.arrivalSwell(from: 60.6, to: 34.5), 1.04, tolerance: 0.01))
        #expect(isClose(NotchModel.arrivalSwell(from: 153.1, to: 34.5), 4.5, tolerance: 0.01))
        #expect(NotchModel.arrivalSwell(from: 32, to: 32) == 0)
        let model = model()
        defer { model.cancelActivityTransition() }
        model.open()
        model.close()
        try await settle { model.arrival > 0 }
        #expect(model.outline.bottom == model.arrival)
        try await settle { model.arrival == 0 && model.arrivalTask == nil }
    }

    @Test("Only open views cast a shadow, darker under a taller one")
    func shadow() {
        let h: CGFloat = 32
        #expect(OpenShadow.opacity(height: h, restingHeight: h) == 0)
        let tall = OpenShadow.opacity(height: h * 153.1 / 34.5, restingHeight: h)
        #expect(isClose(tall, 0.42, tolerance: 0.001))
        let short = OpenShadow.opacity(height: h * 60.6 / 34.5, restingHeight: h)
        #expect(short > 0.15 && short < 0.25)
    }
}

/// Opening with a click and staying open, in Settings' picture, which answers as the notch does.
@MainActor
@Suite("Click to open, click outside to close", .serialized)
struct IslandTriggerTests {
    private let geometry = SettingsPreview.Geometry(
        rect: { state in
            switch state {
            case .closed, .peek: CGRect(x: 150, y: 0, width: 100, height: 30)
            case .open: CGRect(x: 50, y: 0, width: 300, height: 150)
            }
        }, scale: 1)

    @Test("A new install opens on a click; one that had Glance keeps opening on hover or click")
    func defaults() throws {
        let name = "dev.vibe.Glance.tests.island-trigger"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(Preferences.earlierDefaults[3]?[Preferences.openTrigger] as? String == OpenTrigger.both.rawValue)
        defaults.set(true, forKey: Preferences.onboardingDone)
        Preferences.keepEarlierDefaults(defaults, domain: name)
        #expect(defaults.persistentDomain(forName: name)?[Preferences.openTrigger] as? String == OpenTrigger.both.rawValue)
        defaults.removePersistentDomain(forName: name)
        Preferences.keepEarlierDefaults(defaults, domain: name)
        #expect(defaults.persistentDomain(forName: name)?[Preferences.openTrigger] == nil)
    }

    @Test("Opened with a click, it stays open with the pointer away, and a click outside closes it")
    func staysOpenAfterClick() async throws {
        let preview = SettingsPreview(opening: { Opening(onHover: false, onClick: true, hoverDelay: 0.2, clickDelay: 0, haptics: false) })
        preview.feelsOpening = false
        preview.setInteractive(true, animated: false)
        preview.model.activityReducesMotion = true
        preview.model.activity = true
        let on = CGPoint(x: 200, y: 15), away = CGPoint(x: 200, y: 220)
        preview.pointer(at: on, geometry)
        try await Task.sleep(for: .milliseconds(400))
        // Resting on it doesn't open it.
        #expect(preview.model.state != .open)
        preview.press(at: on, geometry)
        preview.release(at: on, geometry)
        try await settle { preview.model.state == .open }
        preview.pointer(at: away, geometry)
        try await Task.sleep(for: .milliseconds(500))
        #expect(preview.model.state == .open)
        preview.press(at: away, geometry)
        try await settle { preview.model.state == .closed }
    }

    @Test("Opened by the pointer resting on it, it closes as the pointer leaves")
    func hoverClosesOnLeave() async throws {
        let preview = SettingsPreview(opening: { Opening(onHover: true, onClick: true, hoverDelay: 0.05, clickDelay: 0, haptics: false) })
        preview.feelsOpening = false
        preview.setInteractive(true, animated: false)
        preview.model.activityReducesMotion = true
        preview.model.activity = true
        preview.pointer(at: CGPoint(x: 200, y: 15), geometry)
        try await settle { preview.model.state == .open }
        preview.pointer(at: CGPoint(x: 200, y: 220), geometry)
        try await settle { preview.model.state == .closed }
    }
}
