//
//  ActivityBench.swift
//  Glance
//
//  Created by Gaty on 31/10/2026.
//

import AppKit

/// One live activity alone on the notch, to try it: a build made from source, started with
/// `--bench airdrop`, shows that activity made up, round after round, and nothing else. Everything
/// else is off for as long as it runs, in a domain that's never saved, so Settings stay as they are;
/// the notch opens only to the activity's own view, never to the player; and its buttons only
/// change what's made up, so nothing real is pressed. A number after its name is how long each round
/// lasts, in seconds. Opened again without it, Glance is as it was.
@MainActor
final class ActivityBench {
    static let shared = ActivityBench()

    enum Scene: String, CaseIterable {
        case airdrop, timer, stopwatch, airplay, charging, lowBattery, headphones, accessories, deviceBattery
    }

    /// The scene and its round's seconds, from the arguments Glance was started with.
    nonisolated static func parse(_ arguments: [String]) -> (scene: Scene, seconds: Double)? {
        guard let flag = arguments.firstIndex(of: "--bench"), flag + 1 < arguments.count,
            let scene = Scene(rawValue: arguments[flag + 1])
        else { return nil }
        let seconds = arguments.dropFirst(flag + 2).first.flatMap(Double.init) ?? 300
        return (scene, max(seconds, 1))
    }

    /// Only in a build made from source.
    private nonisolated static let chosen: (scene: Scene, seconds: Double)? =
        Bundle.main.object(forInfoDictionaryKey: "GlanceSourceDirectory") == nil ? nil : parse(CommandLine.arguments)

    nonisolated static var scene: Scene? { chosen?.scene }
    private var length: Double { Self.chosen?.seconds ?? 300 }

    /// Between one round and the next.
    private static let rest = 3.0
    private var ended = false
    private var run: Task<Void, Never>?

    /// Everything off but what's tried, unsaved.
    func isolate() {
        guard Self.scene != nil else { return }
        var off: [String: Any] = [:]
        for key in [
            Preferences.liveActivity, Preferences.musicTrackPop, Preferences.lyrics, Preferences.tray, Preferences.swipeToSkip,
            Preferences.activityCharging, Preferences.activityLowBattery, Preferences.activityDevices, Preferences.activityAirDrop,
            Preferences.activityClockTimers, Preferences.activityStopwatch,
        ] { off[key] = false }
        Self.keep(off)
    }

    private static func keep(_ values: [String: Any]) {
        let defaults = UserDefaults.standard
        let name = UserDefaults.argumentDomain
        // A domain can only be set once it's gone.
        let arguments = defaults.volatileDomain(forName: name)
        defaults.removeVolatileDomain(forName: name)
        defaults.setVolatileDomain(arguments.merging(values) { _, new in new }, forName: name)
    }

    func start() {
        guard run == nil, let scene = Self.scene else { return }
        run = Task { await play(scene) }
    }

    /// The round is over, from its own button or swiped away: the next one comes after a moment.
    func stopped() {
        ended = true
    }

    private func play(_ scene: Scene) async {
        switch scene {
        case .airdrop: await airDrop()
        case .timer: await timer()
        case .stopwatch: await stopwatch()
        case .airplay: await airPlay()
        case .charging: await announce(Self.charging(), every: 6)
        case .lowBattery: await announce(Self.lowBatteries(), every: 10)
        case .headphones: await announce(Self.headphones(), every: 6)
        case .accessories: await announce(Self.accessories(), every: 6)
        case .deviceBattery: await announce(Self.deviceBatteries(), every: 6)
        }
    }

    private func wait(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    /// Waits out a round, or until it's stopped or `over` says so.
    private func round(over: () -> Bool = { false }) async {
        ended = false
        let end = Date.now + length
        while !ended, !over(), Date.now < end, !Task.isCancelled { await wait(0.2) }
    }

    // MARK: Activities that stay

    /// A file coming in, its ring filling over the round; stopped, the next one starts.
    private func airDrop() async {
        let picture = Self.photo()
        let watch = AirDropWatch.shared
        while !Task.isCancelled {
            ended = false
            let id = UUID().uuidString, start = Date.now
            var fraction = 0.0
            while !ended, fraction < 1, !Task.isCancelled {
                fraction = min(Date.now.timeIntervalSince(start) / length, 1)
                watch.bench(AirDropShown(id: id, sender: "iPhone", preview: picture, fraction: fraction))
                await wait(0.1)
            }
            // In, it shows a moment full.
            if !ended { await wait(1.2) }
            watch.bench(nil)
            await wait(Self.rest)
        }
    }

    /// A timer of the round's length, which rings at the end; cancelled, or answered, it starts
    /// again.
    private func timer() async {
        let clock = ClockActivity.shared
        while !Task.isCancelled {
            ended = false
            clock.bench(timer: .running(until: .now + length, total: length))
            while !ended, !Task.isCancelled, clock.timer != nil || clock.rang != nil {
                if case .running(let until, let total) = clock.timer, until <= .now { clock.benchRing(length: total) }
                await wait(0.2)
            }
            clock.bench(timer: nil)
            await wait(Self.rest)
        }
    }

    /// The stopwatch, running for as long as it's left to; reset, it starts again.
    private func stopwatch() async {
        let clock = ClockActivity.shared
        while !Task.isCancelled {
            ended = false
            clock.bench(stopwatch: .running(since: .now))
            while !ended, !Task.isCancelled, clock.stopwatch != nil { await wait(0.2) }
            clock.bench(stopwatch: nil)
            await wait(Self.rest)
        }
    }

    /// The sound on one speaker after another, a round each.
    private func airPlay() async {
        let watch = AirPlayWatch.shared
        var index = 0
        while !Task.isCancelled {
            let name = ["HomePod", "Living Room TV", "Kitchen", "MacBook Pro"][index % 4]
            watch.bench(AirPlayRoute(name: name, symbol: AirPlayRoute.symbol(for: name)))
            await round()
            watch.bench(nil)
            index += 1
            await wait(Self.rest)
        }
    }

    // MARK: Activities that are announced

    /// One after another, for as long as it runs.
    private func announce(_ alerts: [@MainActor () async -> NotchAlert], every seconds: Double) async {
        var index = 0
        while !Task.isCancelled {
            Activities.shared.post(await alerts[index % alerts.count]())
            index += 1
            await wait(seconds)
        }
    }

    private static func charging() -> [@MainActor () async -> NotchAlert] {
        [(5, false), (19, true), (64, false), (100, false)].enumerated().map { index, level in
            {
                let title = index == 3 ? "Plugged In" : "Charging"
                let battery = BatteryLevel(percent: level.0, charging: index != 3, lowPower: level.1)
                return NotchAlert(kind: .charging, content: .battery(title: title, level: battery), spoken: "\(title), \(level.0) percent")
            }
        }
    }

    private static func lowBatteries() -> [@MainActor () async -> NotchAlert] {
        [20, 10, 5].map { percent in
            {
                LowPowerMode.shared.bench(false)
                return BatteryWatch.lowBattery(BatteryWatch.Reading(percent: percent, onPower: false, charging: false))
            }
        }
    }

    private static func headphones() -> [@MainActor () async -> NotchAlert] {
        let levels = [88, 54, 21, 100, 12]
        let clips: [@MainActor () async -> NotchAlert] = Headphones.allCases.enumerated().map { index, model in
            {
                _ = await DeviceTurn.prepare(model)
                return DeviceWatch.alert(name: model.rawValue, symbol: "airpods", model: model, battery: levels[index % levels.count])
            }
        }
        return clips + [
            { DeviceWatch.alert(name: "AirPods Max", symbol: "airpodsmax", battery: 72) },
            { DeviceWatch.alert(name: "Headphones", symbol: "headphones", battery: 40) },
        ]
    }

    private static func accessories() -> [@MainActor () async -> NotchAlert] {
        [
            ("Magic Keyboard", "keyboard", 91), ("Magic Mouse", "magicmouse", 64),
            ("Magic Trackpad", "rectangle.and.hand.point.up.left", 38), ("Controller", "gamecontroller", 15),
        ].map { name, symbol, level in
            { DeviceWatch.alert(name: name, symbol: symbol, battery: level) }
        }
    }

    private static func deviceBatteries() -> [@MainActor () async -> NotchAlert] {
        [
            ("AirPods Pro", "airpodspro", Headphones.airpodsPro2 as Headphones?, 20), ("AirPods Pro", "airpodspro", .airpodsPro2, 10),
            ("Magic Keyboard", "keyboard", nil, 20), ("Magic Keyboard", "keyboard", nil, 10),
        ].map { name, symbol, model, level in
            {
                if let model { _ = await DeviceTurn.prepare(model) }
                return DeviceWatch.lowBattery(name: name, symbol: symbol, model: model, battery: level)
            }
        }
    }

    /// One of macOS's own desktop pictures, as a photo sent over AirDrop would be.
    private static func photo() -> NSImage? {
        let folder = URL(fileURLWithPath: "/System/Library/Desktop Pictures/.thumbnails")
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.lazy.compactMap { NSImage(contentsOf: $0) }.first
    }
}
