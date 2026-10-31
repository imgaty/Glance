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
        case airdrop, airdropSend, timer, stopwatch, airplay, charging, lowBattery, headphones, deviceBattery
        /// AirDrop alone, nothing made up: for real files, coming in or going out.
        case airdropReal

        /// Said for a moment, with no view of its own to open to.
        var announces: Bool { [.charging, .lowBattery, .headphones, .deviceBattery].contains(self) }
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
    /// What's shown is made up, rather than only alone.
    nonisolated static var fakes: Bool { scene != nil && scene != .airdropReal }
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
        if Self.scene == .airdropReal { off[Preferences.activityAirDrop] = true }
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

    /// Glance started again on another scene, or as usual with none. It waits for this one to go, as
    /// `open` otherwise ignores the arguments.
    static func change(to scene: Scene?) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        let bench = scene == nil ? "" : " --args --bench \"$1\""
        process.arguments = ["-c", "sleep 1; exec /usr/bin/open \"$0\"\(bench)", Bundle.main.bundlePath, scene?.rawValue ?? ""]
        try? process.run()
        NSApp.terminate(nil)
    }

    /// The round is over, from its own button or swiped away: the next one comes after a moment.
    func stopped() {
        ended = true
    }

    private func play(_ scene: Scene) async {
        switch scene {
        case .airdropReal: break
        case .airdrop: await airDrop(sending: false)
        case .airdropSend: await airDrop(sending: true)
        case .timer: await timer()
        case .stopwatch: await stopwatch()
        case .airplay: await airPlay()
        case .charging: await announce(Self.charging(), every: 6)
        case .lowBattery: await announce(Self.lowBatteries(), every: 10)
        case .headphones: await announce(Self.headphones(), every: 6)
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

    /// A file coming in or going out, its ring filling over the round; stopped, the next one starts.
    private func airDrop(sending: Bool) async {
        let picture = Self.photo()
        let watch = AirDropWatch.shared
        while !Task.isCancelled {
            ended = false
            let id = UUID().uuidString, start = Date.now
            var fraction = 0.0
            while !ended, fraction < 1, !Task.isCancelled {
                fraction = min(Date.now.timeIntervalSince(start) / length, 1)
                let recipient = sending ? "iPhone" : nil
                watch.bench(AirDropShown(id: id, sender: "iPhone", preview: picture, fraction: fraction, sending: sending, recipient: recipient))
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
        // AirPods 5 are modelled as AirPods 4.
        let airPods: [Headphones] = [.airpodsPro, .airpodsPro2, .airpodsPro3, .airpods4, .airpods3]
        let beats = Headphones.allCases.filter { !airPods.contains($0) }
        func clips(_ models: [Headphones]) -> [@MainActor () async -> NotchAlert] {
            let levels = [88, 54, 21, 100, 12]
            return models.enumerated().map { index, model in
                {
                    _ = await DeviceTurn.prepare(model)
                    let name = model.rawValue.replacingOccurrences(of: "-", with: " ").capitalized
                    return DeviceWatch.alert(name: name, symbol: "airpods", model: model, battery: levels[index % levels.count])
                }
            }
        }
        // Those with no clip, as macOS pictures them: AirPods Max, then AirPods 2.
        let pictured: [@MainActor () async -> NotchAlert] = [(0x200A, 72), (0x200F, 40)].map { product, level in
            {
                let symbol = SystemDevices.symbols(product: product)?.symbol ?? "airpods"
                return DeviceWatch.alert(name: "AirPods", symbol: symbol, pictures: DevicePictures.names(product: product), battery: level)
            }
        }
        return clips(airPods) + pictured + clips(beats)
    }

    private static func deviceBatteries() -> [@MainActor () async -> NotchAlert] {
        [(Headphones.airpodsPro2, "airpodspro", 20), (.airpodsPro2, "airpodspro", 10), (.beatsSolo4, "headphones", 20), (.beatsSolo4, "headphones", 10)]
            .map { model, symbol, level in
                {
                    _ = await DeviceTurn.prepare(model)
                    return DeviceWatch.lowBattery(name: model.rawValue, symbol: symbol, model: model, battery: level)
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
