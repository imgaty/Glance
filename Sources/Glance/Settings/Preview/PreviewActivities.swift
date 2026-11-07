//
//  PreviewActivities.swift
//  Glance
//
//  Created by Gaty on 04/11/2026.
//

import AppKit
import SwiftUI

/// What the picture on the Live Activities page shows besides what's playing, in the order of the
/// page's switches: each turned on there, made up, one after another.
enum PreviewActivity: CaseIterable {
    case announcement, charging, lowBattery, device, airDrop, timer, stopwatch, screenRecording, voiceMemo

    private var key: String {
        switch self {
        case .announcement: Preferences.musicTrackPop
        case .charging: Preferences.activityCharging
        case .lowBattery: Preferences.activityLowBattery
        case .device: Preferences.activityDevices
        case .airDrop: Preferences.activityAirDrop
        case .timer: Preferences.activityClockTimers
        case .stopwatch: Preferences.activityStopwatch
        case .screenRecording: Preferences.activityScreenRecording
        case .voiceMemo: Preferences.activityVoiceMemos
        }
    }

    /// Those to show now: what's turned on, a new song's name only with the cover and waveform, and
    /// the battery's only on a Mac with one.
    static func turnedOn(in defaults: UserDefaults = .standard, hasBattery: Bool) -> [PreviewActivity] {
        func on(_ key: String) -> Bool { defaults.object(forKey: key) as? Bool ?? true }
        return allCases.filter { activity in
            switch activity {
            case .announcement: on(activity.key) && on(Preferences.liveActivity)
            case .charging, .lowBattery: on(activity.key) && hasBattery
            case .device, .airDrop, .timer, .stopwatch, .screenRecording, .voiceMemo: on(activity.key)
            }
        }
    }
}

extension SettingsPreview {
    /// How long the picture rests between one and the next.
    private static let between = 1.6
    /// How long what stays by itself on screen, like a timer, shows here.
    private static let held = 4.0
    /// How long the notch rests between one activity folding and the next opening.
    private static let switchPause = 0.18

    /// Round after round until it's cancelled, starting with the one given. While the notch is open
    /// under the pointer, it waits. Nothing here touches anything real.
    func playActivities(song: NowPlaying, startingAt first: PreviewActivity?) async {
        let hasBattery = BatteryWatch.hasBattery
        var next = first
        while !Task.isCancelled {
            let round = PreviewActivity.turnedOn(hasBattery: hasBattery)
            if round.isEmpty { await pause(1) }
            let start = next.flatMap(round.firstIndex(of:)) ?? 0
            next = nil
            for activity in round.dropFirst(start) {
                while model.state != .closed, !Task.isCancelled { await pause(0.3) }
                guard !Task.isCancelled else { return }
                // Turned off while its turn came.
                guard PreviewActivity.turnedOn(hasBattery: hasBattery).contains(activity) else { continue }
                await show(activity, song: song)
                await pause(Self.between)
                guard !Task.isCancelled else { return }
            }
        }
    }

    /// Back to what's playing, as the picture rests.
    func clearActivities() {
        let model = model
        withAnimation(IslandMotion.fold) {
            model.alert = nil
            model.switching = false
            model.pop = false
            model.airdrop = nil
            model.timer = nil
            model.stopwatch = nil
            model.screenRecording = nil
            model.voiceMemo = nil
        }
    }

    private func pause(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    private func show(_ activity: PreviewActivity, song: NowPlaying) async {
        switch activity {
        case .announcement:
            await announce(song)
        case .charging:
            let level = BatteryLevel(percent: 64, charging: true)
            await say(NotchAlert(kind: .charging, content: .battery(title: String(localized: "Charging"), level: level), spoken: String(localized: "Charging, 64 percent")))
        case .lowBattery:
            await say(BatteryWatch.lowBattery(BatteryWatch.Reading(percent: 20, onPower: false, charging: false)))
        case .device:
            _ = await DeviceTurn.prepare(.airpodsPro2)
            guard !Task.isCancelled else { return }
            await say(DeviceWatch.alert(name: "AirPods Pro", model: .airpodsPro2, battery: 88))
        case .airDrop:
            await hold(\.airdrop, AirDropShown(id: "preview", sender: "iPhone", preview: ActivityBench.photo(), fraction: 0.35))
        case .timer:
            let timer = NotchTimer.State.running(until: .now + 300, total: 300)
            model.timerWing = SystemActivityView.wing(for: .timer(timer), restingHeight: model.closedSize.height)
            await hold(\.timer, timer)
        case .stopwatch:
            let stopwatch = Stopwatch.running(since: .now)
            model.timerWing = SystemActivityView.wing(for: .stopwatch(stopwatch), restingHeight: model.closedSize.height)
            await hold(\.stopwatch, stopwatch)
        case .screenRecording:
            await hold(\.screenRecording, ScreenRecording.recording(since: .now))
        case .voiceMemo:
            // Its sound made up, unless a real one is being recorded.
            let madeUp = VoiceMemoWatch.shared.memo == nil
            if madeUp {
                RecordingLevels.shared.madeUp = true
                RecordingLevels.shared.start()
            }
            await hold(\.voiceMemo, VoiceMemo.recording(since: .now))
            if madeUp, VoiceMemoWatch.shared.memo == nil { RecordingLevels.shared.stop() }
        }
    }

    /// A new song's name, in the wings widened for it, no wider than the picture: a longer title or
    /// artist scrolls, as it does on screen.
    private func announce(_ song: NowPlaying) async {
        let model = model
        guard model.activity else { return }
        let room = (PreviewHeader.width / NotchPreview.scale(for: PreviewHeader.width, model: model) - model.closedSize.width) / 2 - 12
        let wing = LiveActivityView.popWing(title: song.title, artist: song.artist, restingHeight: model.closedSize.height)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            model.popWing = min(wing, room)
            model.pop = true
        }
        await pause(3.5)
        guard !Task.isCancelled else { return }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { model.pop = false }
    }

    /// Something the Mac announces, as the notch says it: what's beside the camera folds first, and
    /// opens again after.
    private func say(_ alert: NotchAlert) async {
        let model = model
        let wingsShowing = !model.activities.isEmpty
        if wingsShowing {
            withAnimation(IslandMotion.fold) { model.switching = true }
            await pause(Self.switchPause)
            guard !Task.isCancelled else { return }
        }
        let wing = SystemActivityView.wing(for: alert, restingHeight: model.closedSize.height, closedWidth: model.closedSize.width)
        withAnimation(IslandMotion.open) {
            model.switching = false
            model.alertWing = wing
            model.alert = alert
        }
        await pause(alert.stays ? Self.held : alert.seconds)
        guard !Task.isCancelled else { return }
        withAnimation(IslandMotion.fold) {
            model.alert = nil
            model.switching = wingsShowing
        }
        guard wingsShowing else { return }
        await pause(Self.switchPause)
        guard !Task.isCancelled else { return }
        withAnimation(IslandMotion.open) { model.switching = false }
    }

    /// An activity that stays on screen, here for a few seconds.
    private func hold<Value>(_ activity: ReferenceWritableKeyPath<NotchModel, Value?>, _ value: Value) async {
        let model = model
        withAnimation(IslandMotion.open) { model[keyPath: activity] = value }
        await pause(Self.held)
        guard !Task.isCancelled else { return }
        withAnimation(IslandMotion.fold) { model[keyPath: activity] = nil }
    }
}
