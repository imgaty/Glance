//
//  PreviewActivitiesTests.swift
//  GlanceTests
//
//  Created by Gaty on 04/11/2026.
//

import Foundation
import Testing

@testable import Glance

/// What the picture on the Live Activities page shows: only what's turned on there.
@Suite("Live Activities page's picture")
struct PreviewActivitiesTests {
    private func defaults(_ values: [String: Bool] = [:]) -> UserDefaults {
        let defaults = UserDefaults(suiteName: "PreviewActivitiesTests-\(UUID().uuidString)")!
        values.forEach { defaults.set($1, forKey: $0) }
        return defaults
    }

    @Test("Everything shows at first, in the order of the page's switches")
    func everything() {
        #expect(
            PreviewActivity.turnedOn(in: defaults(), hasBattery: true) == [
                .announcement, .charging, .lowBattery, .device, .airDrop, .timer, .stopwatch, .screenRecording, .voiceMemo,
            ])
    }

    @Test("Something turned off doesn't show")
    func turnedOff() {
        let shown = PreviewActivity.turnedOn(
            in: defaults([Preferences.activityDevices: false, Preferences.activityStopwatch: false]), hasBattery: true)
        #expect(shown == [.announcement, .charging, .lowBattery, .airDrop, .timer, .screenRecording, .voiceMemo])
    }

    @Test("A new song's name shows only with the cover and waveform on")
    func announcement() {
        let shown = PreviewActivity.turnedOn(in: defaults([Preferences.liveActivity: false]), hasBattery: true)
        #expect(!shown.contains(.announcement))
    }

    @Test("Each switch on the page shows its own activity as it's turned on, and Calls none")
    @MainActor
    func switches() {
        #expect(ActivitiesPage.previews.compactMap(\.shows) == PreviewActivity.allCases)
        #expect(ActivitiesPage.previews.first { $0.key == Preferences.activityCalls }.map { $0.shows == nil } == true)
    }

    @Test("The battery's show only on a Mac with one")
    func battery() {
        let shown = PreviewActivity.turnedOn(in: defaults(), hasBattery: false)
        #expect(shown == [.announcement, .device, .airDrop, .timer, .stopwatch, .screenRecording, .voiceMemo])
    }
}
