//
//  ActivityBench.swift
//  Glance
//
//  Created by Gaty on 31/10/2026.
//

import AppKit

/// One live activity alone on the notch, to try it, or two together, the most the notch shows: a
/// build made from source, started with `--bench airdrop` or `--bench airdrop+timer`, shows them
/// made up, round after round, and nothing else. Everything
/// else is off for as long as it runs, in a domain that's never saved, so Settings stay as they are;
/// the notch opens only to the activity's own view, never to the player; and its buttons only
/// change what's made up, so nothing real is pressed. A number after its name is how long each round
/// lasts, in seconds. Opened again without it, Glance is as it was.
@MainActor
final class ActivityBench {
    static let shared = ActivityBench()

    enum Scene: String, CaseIterable {
        case music, airdrop, airdropSend, timer, stopwatch, airplay, call, charging, lowBattery, headphones, deviceBattery, caseBattery
        /// A call in one state, held for the round: coming in, swiped away while it rings, going out,
        /// going on, with someone whose name is too long and for over an hour, with a number, in an app
        /// that says nothing about it, and with nothing read from macOS's popup.
        case callRinging, callSwiped, callOutgoing, callOngoing, callLong, callNumber, callOtherApp, callUnread
        /// The screen recorded: counting down, recording until it's stopped, saved; and each state held
        /// for the round.
        case screenRecording, screenCountdown, screenSaving, screenSaved
        /// A voice memo recorded until it's stopped, and one paused.
        case voiceMemo, voiceMemoPaused
        /// AirDrop alone, nothing made up: for real files, coming in or going out.
        case airdropReal
        /// Low Battery made up, its button the real one: it changes the Mac's Low Power Mode.
        case lowBatteryReal

        /// Said for a moment, with no view of its own to open to.
        var announces: Bool { [.charging, .lowBattery, .lowBatteryReal, .headphones, .deviceBattery, .caseBattery].contains(self) }

        /// How the menu names it, in English, as the menu is only in builds made from source.
        var title: String {
            switch self {
            case .music: "Music"
            case .call: "Whole Call"
            case .callRinging: "Ringing"
            case .callSwiped: "Ringing, Swiped Away"
            case .callOutgoing: "Calling"
            case .callOngoing: "On a Call"
            case .callLong: "Long Name, Over an Hour"
            case .callNumber: "A Number"
            case .callOtherApp: "Another App"
            case .callUnread: "Popup Not Read"
            case .screenRecording: "Screen Recording"
            case .screenCountdown: "Countdown"
            case .screenSaving: "Saving"
            case .screenSaved: "Saved"
            case .voiceMemo: "Voice Memo"
            case .voiceMemoPaused: "Voice Memo, Paused"
            case .airdrop: "Coming In"
            case .airdropSend: "Going Out"
            case .airdropReal: "Real Files, Nothing Made Up"
            case .timer: "Timer"
            case .stopwatch: "Stopwatch"
            case .airplay: "AirPlay"
            case .charging: "Charging"
            case .lowBattery: "Low Battery"
            case .lowBatteryReal: "Low Battery, Real Button"
            case .headphones: "Headphones"
            case .deviceBattery: "Headphones Low"
            case .caseBattery: "Case Low"
            }
        }

        /// The menu's groups, each under its label, in the order the notch takes them.
        static let groups: [(label: String, scenes: [Scene])] = [
            ("Calls", [.call, .callRinging, .callSwiped, .callOutgoing, .callOngoing, .callLong, .callNumber, .callOtherApp, .callUnread]),
            ("Recording", [.screenRecording, .screenCountdown, .screenSaving, .screenSaved, .voiceMemo, .voiceMemoPaused]),
            ("Music", [.music]),
            ("AirDrop", [.airdrop, .airdropSend, .airdropReal]),
            ("Clock", [.timer, .stopwatch]),
            ("AirPlay", [.airplay]),
            ("Announced", [.charging, .lowBattery, .lowBatteryReal, .headphones, .deviceBattery, .caseBattery]),
        ]

        /// What can be tried beside another: all but those that touch something real.
        static var seconds: [Scene] { allCases.filter { $0 != .airdropReal && $0 != .lowBatteryReal } }
    }

    /// The most the notch shows at once.
    nonisolated static let most = 2

    /// The scenes and each round's seconds, from the arguments Glance was started with.
    nonisolated static func parse(_ arguments: [String]) -> (scenes: [Scene], seconds: Double)? {
        guard let flag = arguments.firstIndex(of: "--bench"), flag + 1 < arguments.count else { return nil }
        let names = arguments[flag + 1].split(separator: "+").map(String.init)
        let scenes = names.compactMap(Scene.init(rawValue:))
        guard !scenes.isEmpty, scenes.count == names.count, scenes.count <= most else { return nil }
        let seconds = arguments.dropFirst(flag + 2).first.flatMap(Double.init) ?? 300
        return (scenes, max(seconds, 1))
    }

    /// Only in a build made from source.
    private nonisolated static let chosen: (scenes: [Scene], seconds: Double)? =
        Bundle.main.object(forInfoDictionaryKey: "GlanceSourceDirectory") == nil ? nil : parse(CommandLine.arguments)

    nonisolated static var scenes: [Scene] { chosen?.scenes ?? [] }
    nonisolated static var scene: Scene? { scenes.first }
    /// What's shown is made up, rather than only alone.
    nonisolated static var fakes: Bool { !scenes.isEmpty && !scenes.contains(.airdropReal) }
    /// Low Power Mode is only said, and the Mac's stays as it is.
    nonisolated static var fakesPower: Bool { !scenes.isEmpty && !scenes.contains(.lowBatteryReal) }
    /// The notch can open to the player: unless what's tried stays, with nothing to open to but itself.
    nonisolated static var opensToPlayer: Bool { scenes.isEmpty || scenes.contains { $0.announces || $0 == .music } }
    private var length: Double { Self.chosen?.seconds ?? 300 }

    /// Between one round and the next.
    private static let rest = 3.0
    /// What was stopped, from its own button or swiped away, each till its next round.
    private var ended: Set<NotchModel.Activity> = []
    private var runs: [Task<Void, Never>] = []
    private var callAnswered = false

    /// Everything off but what's tried, unsaved.
    func isolate() {
        guard Self.scene != nil else { return }
        var off: [String: Any] = [:]
        for key in [
            Preferences.liveActivity, Preferences.musicTrackPop, Preferences.lyrics, Preferences.tray, Preferences.swipeToSkip,
            Preferences.activityCharging, Preferences.activityLowBattery, Preferences.activityDevices, Preferences.activityAirDrop,
            Preferences.activityClockTimers, Preferences.activityStopwatch, Preferences.activityScreenRecording, Preferences.activityVoiceMemos,
        ] { off[key] = false }
        if Self.scenes.contains(.airdropReal) { off[Preferences.activityAirDrop] = true }
        if Self.scenes.contains(.music) { off[Preferences.liveActivity] = true }
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
        guard runs.isEmpty else { return }
        runs = Self.scenes.map { scene in Task { await play(scene) } }
    }

    /// Glance started again on other scenes, or as usual with none. It waits for this one to go, as
    /// `open` otherwise ignores the arguments.
    static func change(to scenes: [Scene]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        let bench = scenes.isEmpty ? "" : " --args --bench \"$1\""
        let names = scenes.map(\.rawValue).joined(separator: "+")
        process.arguments = ["-c", "sleep 1; exec /usr/bin/open \"$0\"\(bench)", Bundle.main.bundlePath, names]
        try? process.run()
        NSApp.terminate(nil)
    }

    /// Its round is over, from its own button or swiped away: the next one comes after a moment.
    func stopped(_ activity: NotchModel.Activity) {
        ended.insert(activity)
    }

    private func play(_ scene: Scene) async {
        switch scene {
        case .airdropReal, .music: break
        case .airdrop: await airDrop(sending: false)
        case .airdropSend: await airDrop(sending: true)
        case .timer: await timer()
        case .stopwatch: await stopwatch()
        case .airplay: await airPlay()
        case .call: await call()
        case .callRinging, .callSwiped, .callOutgoing, .callOngoing, .callLong, .callNumber, .callOtherApp, .callUnread: await callState(scene)
        case .screenRecording: await screenRecording()
        case .screenCountdown, .screenSaving: await screenState(scene)
        case .screenSaved: await screenState(scene)
        case .voiceMemo: await voiceMemo(paused: false)
        case .voiceMemoPaused: await voiceMemo(paused: true)
        case .charging: await announce(Self.charging(), every: 6)
        case .lowBattery, .lowBatteryReal: await announce(Self.lowBatteries(), every: 10)
        case .headphones: await announce(Self.headphones(), every: 6)
        case .deviceBattery: await announce(Self.deviceBatteries(), every: 6)
        case .caseBattery: await announce(Self.caseBatteries(), every: 6)
        }
    }

    private func wait(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    /// Waits out a round, or until it's stopped.
    private func round(of activity: NotchModel.Activity) async {
        ended.remove(activity)
        let end = Date.now + length
        while !ended.contains(activity), Date.now < end, !Task.isCancelled { await wait(0.2) }
    }

    // MARK: Activities that stay

    /// A file coming in or going out, its ring filling over the round; stopped, the next one starts.
    private func airDrop(sending: Bool) async {
        let picture = Self.photo()
        let watch = AirDropWatch.shared
        while !Task.isCancelled {
            ended.remove(.airdrop)
            let id = UUID().uuidString, start = Date.now
            var fraction = 0.0
            while !ended.contains(.airdrop), fraction < 1, !Task.isCancelled {
                fraction = min(Date.now.timeIntervalSince(start) / length, 1)
                let recipient = sending ? "iPhone" : nil
                watch.bench(AirDropShown(id: id, sender: "iPhone", preview: picture, fraction: fraction, sending: sending, recipient: recipient))
                await wait(0.1)
            }
            // In, it shows a moment full.
            if !ended.contains(.airdrop) { await wait(1.2) }
            watch.bench(nil)
            await wait(Self.rest)
        }
    }

    /// A timer of the round's length, which rings at the end; cancelled, or answered, it starts
    /// again.
    private func timer() async {
        let clock = ClockActivity.shared
        while !Task.isCancelled {
            ended.remove(.timer)
            clock.bench(timer: .running(until: .now + length, total: length))
            while !ended.contains(.timer), !Task.isCancelled, clock.timer != nil || clock.rang != nil {
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
            ended.remove(.stopwatch)
            clock.bench(stopwatch: .running(since: .now))
            while !ended.contains(.stopwatch), !Task.isCancelled, clock.stopwatch != nil { await wait(0.2) }
            clock.bench(stopwatch: nil)
            await wait(Self.rest)
        }
    }

    // MARK: Recordings

    /// The screen recorded as on the iPhone: three seconds counted down, then recording for the
    /// round or until it's stopped, a moment saving, then saved, and again.
    private func screenRecording() async {
        let watch = ScreenRecordingWatch.shared
        while !Task.isCancelled {
            watch.bench(.countdown(from: 3, until: .now + 3))
            await wait(3)
            let start = Date.now
            watch.bench(.recording(since: start))
            await round(of: .screenRecording)
            let length = Date.now.timeIntervalSince(start)
            watch.bench(.saving(length: length))
            await wait(1.5)
            watch.bench(Self.saved(length: length))
            await wait(ScreenRecordingWatch.savedFor)
            watch.bench(nil)
            await wait(Self.rest)
        }
    }

    /// The countdown again and again, or a recording being saved, held for the round.
    private func screenState(_ scene: Scene) async {
        let watch = ScreenRecordingWatch.shared
        while !Task.isCancelled {
            if scene == .screenCountdown {
                watch.bench(.countdown(from: 3, until: .now + 3))
                await wait(4)
            } else {
                watch.bench(scene == .screenSaved ? Self.saved() : .saving(length: 11))
                await round(of: .screenRecording)
                watch.bench(nil)
                await wait(Self.rest)
            }
        }
    }

    /// Saved, with one of macOS's own pictures for its first frame.
    private static func saved(length: TimeInterval = 11) -> ScreenRecording {
        .saved(length: length, folder: FileManager.default.displayName(atPath: NSHomeDirectory() + "/Desktop"), preview: photo())
    }

    /// A voice memo recording for the round, or until it's stopped; or paused at 20 seconds.
    private func voiceMemo(paused: Bool) async {
        let watch = VoiceMemoWatch.shared
        while !Task.isCancelled {
            watch.bench(paused ? .paused(length: 20) : .recording(since: .now))
            await round(of: .voiceMemo)
            watch.bench(nil)
            await wait(Self.rest)
        }
    }

    /// The sound on one speaker after another, a round each.
    /// A call made up: coming in, then going on, then over; again and again. Its buttons do as they
    /// would: Accept answers it at once, Decline and End finish it.
    private func call() async {
        let watch = CallWatch.shared
        while !Task.isCancelled {
            ended.remove(.call)
            callAnswered = false
            watch.bench(Self.madeUpCall(.ringing))
            let answer = Date.now + 8
            while !ended.contains(.call), !callAnswered, Date.now < answer, !Task.isCancelled { await wait(0.2) }
            if !ended.contains(.call) {
                Activities.shared.dismiss(.incomingCall)
                watch.bench(Self.madeUpCall(.connected(since: .now), canEnd: true))
                await round(of: .call)
            }
            watch.bench(nil)
            await wait(2)
        }
    }

    /// One state of a call, held for the round. Coming in, Accept moves on to going on.
    private func callState(_ scene: Scene) async {
        let watch = CallWatch.shared
        while !Task.isCancelled {
            ended.remove(.call)
            callAnswered = false
            switch scene {
            case .callRinging, .callSwiped:
                watch.bench(Self.madeUpCall(.ringing))
                if scene == .callSwiped { Activities.shared.dismiss(.incomingCall) }
                let end = Date.now + length
                while !ended.contains(.call), !callAnswered, Date.now < end, !Task.isCancelled { await wait(0.2) }
                if callAnswered {
                    watch.bench(Self.madeUpCall(.connected(since: .now), canEnd: true))
                    await round(of: .call)
                }
            case .callOutgoing:
                watch.bench(Self.madeUpCall(.calling, canEnd: true))
                await round(of: .call)
            case .callOngoing:
                watch.bench(Self.madeUpCall(.connected(since: .now), canEnd: true))
                await round(of: .call)
            case .callLong:
                watch.bench(Self.madeUpCall(.connected(since: .now - 3_725), canEnd: true, name: "Alexandra Montgomery-Fitzgerald"))
                await round(of: .call)
            case .callNumber:
                watch.bench(Self.madeUpCall(.connected(since: .now), canEnd: true, name: "+351 912 345 678"))
                await round(of: .call)
            case .callOtherApp:
                watch.bench(CallShown(name: "Zoom", over: "Zoom", app: "us.zoom.xos", phase: .connected(since: .now)))
                await round(of: .call)
            case .callUnread:
                watch.bench(CallShown(name: "Phone", over: "Phone", app: CallAudio.phone, phase: .connected(since: .now)))
                await round(of: .call)
            default: return
            }
            watch.bench(nil)
            await wait(2)
        }
    }

    private static func madeUpCall(_ phase: CallShown.Phase, canEnd: Bool = false, name: String = "Alex Morgan") -> CallShown {
        CallShown(name: name, over: "Phone", app: CallAudio.phone, phase: phase, canEnd: canEnd, line: phase == .ringing ? "mobile" : nil)
    }

    /// A made-up call's Accept was pressed.
    func answered() {
        callAnswered = true
    }

    private func airPlay() async {
        let watch = AirPlayWatch.shared
        var index = 0
        while !Task.isCancelled {
            let name = ["HomePod", "Living Room TV", "Kitchen", "MacBook Pro"][index % 4]
            watch.bench(AirPlayRoute(name: name, symbol: AirPlayRoute.symbol(for: name)))
            await round(of: .airplay)
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
                if fakesPower { LowPowerMode.shared.bench(false) }
                return BatteryWatch.lowBattery(BatteryWatch.Reading(percent: percent, onPower: false, charging: false))
            }
        }
    }

    private static func headphones() -> [@MainActor () async -> NotchAlert] {
        let airPods: [Headphones] = [.airpodsPro, .airpodsPro2, .airpodsPro3, .airpods, .airpods3, .airpodsMax]
        let beats = Headphones.allCases.filter { !airPods.contains($0) && !$0.isChargingCase }
        func clips(_ models: [Headphones]) -> [@MainActor () async -> NotchAlert] {
            let levels = [88, 54, 21, 100, 12]
            return models.enumerated().map { index, model in
                {
                    _ = await DeviceTurn.prepare(model)
                    let name = model.rawValue.replacingOccurrences(of: "-", with: " ").capitalized
                        .replacingOccurrences(of: "Airpods", with: "AirPods")
                    return DeviceWatch.alert(name: name, model: model, battery: levels[index % levels.count])
                }
            }
        }
        // Each kind in turn, the widest first, so that all of them come round soon.
        let order = beats.reversed().enumerated().flatMap { index, model in
            index < airPods.count ? [model, airPods[index]] : [model]
        }
        return clips(order)
    }

    private static func deviceBatteries() -> [@MainActor () async -> NotchAlert] {
        [(Headphones.airpodsPro2, 20), (.airpodsPro2, 10), (.beatsSolo4, 20), (.beatsSolo4, 10)]
            .map { model, level in
                {
                    _ = await DeviceTurn.prepare(model)
                    return DeviceWatch.lowBattery(name: model.rawValue, model: model, battery: level)
                }
            }
    }

    /// Each case in turn, at 20% or 10%.
    private static func caseBatteries() -> [@MainActor () async -> NotchAlert] {
        Headphones.allCases.filter(\.isChargingCase).enumerated().map { index, model in
            {
                _ = await DeviceTurn.prepare(model)
                let name = model.rawValue.replacingOccurrences(of: "-case", with: "").replacingOccurrences(of: "-", with: " ").capitalized
                    .replacingOccurrences(of: "Airpods", with: "AirPods")
                return DeviceWatch.caseLowBattery(name: name, model: model, battery: index.isMultiple(of: 2) ? 20 : 10)
            }
        }
    }

    /// One of macOS's own desktop pictures, as a photo sent over AirDrop would be.
    static func photo() -> NSImage? {
        let folder = URL(fileURLWithPath: "/System/Library/Desktop Pictures/.thumbnails")
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.lazy.compactMap { NSImage(contentsOf: $0) }.first
    }
}
