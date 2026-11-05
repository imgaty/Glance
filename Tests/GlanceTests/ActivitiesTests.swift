//
//  ActivitiesTests.swift
//  GlanceTests
//
//  Created by Gaty on 16/10/2026.
//

import AppKit
import CoreAudio
import Foundation
import Testing

@testable import Glance

/// What the Mac announces beside the camera, and the timer: what's worth announcing, in turn, and
/// how wide the notch grows for it.
@MainActor
@Suite("Live activities", .serialized)
struct ActivitiesTests {
    private func alert(_ kind: NotchAlert.Kind, _ title: String = "Title") -> NotchAlert {
        NotchAlert(kind: kind, content: .status(symbol: "airplay.audio", tint: .blue, text: title), spoken: title)
    }

    @Test("Announcements show one at a time, in turn; the same kind again takes its place in line")
    func queue() {
        let activities = Activities()
        activities.post(alert(.charging))
        #expect(activities.alert?.kind == .charging)
        activities.post(alert(.device, "AirPods"))
        activities.post(alert(.timerDone))
        activities.post(alert(.device, "Magic Mouse"))
        #expect(activities.alert?.kind == .charging)
        #expect(activities.waiting.map(\.spoken) == ["Magic Mouse", "Title"])
        // A short line: the oldest of too many goes.
        activities.post(alert(.lowBattery))
        activities.post(alert(.charging))
        #expect(activities.waiting.count == 3)
        #expect(activities.waiting.first?.kind == .timerDone)
    }

    @Test("One that stays shows until it's dismissed")
    func staying() {
        let activities = Activities()
        activities.post(NotchAlert(kind: .timerDone, content: .timerDone(length: 300, name: "Timer"), spoken: "Timer done", stays: true))
        activities.dismiss(.charging)
        #expect(activities.alert?.kind == .timerDone)
        activities.dismiss(.timerDone)
        #expect(activities.alert == nil)
    }

    @Test("Plugged in is announced with the level; running low, at 20% and again at 10%")
    func battery() {
        typealias Reading = BatteryWatch.Reading
        let charging = BatteryWatch.alert(from: Reading(percent: 54, onPower: false, charging: false), to: Reading(percent: 54, onPower: true, charging: true), lowPower: false)
        #expect(charging?.kind == .charging)
        #expect(charging?.content == .battery(title: "Charging", level: BatteryLevel(percent: 54, charging: true)))
        #expect(charging?.spoken == "Charging, 54 percent")
        // Held at 80% by Optimized Charging: plugged in, not charging.
        let held = BatteryWatch.alert(from: Reading(percent: 80, onPower: false, charging: false), to: Reading(percent: 80, onPower: true, charging: false), lowPower: false)
        #expect(held?.content == .battery(title: "Plugged In", level: BatteryLevel(percent: 80, charging: false)))
        // Red at 20% and below, charging or not, as the iPhone's.
        #expect(BatteryLevel(percent: 20, charging: true).color == BatteryColor.red)
        #expect(BatteryLevel(percent: 21, charging: false).color == BatteryColor.green)
        // Yellow in Low Power Mode, as the iPhone's.
        #expect(BatteryLevel(percent: 6, charging: true, lowPower: true).color == BatteryColor.yellow)
        // One of each, wherever a battery shows.
        #expect(BatteryRing.color(for: 20) == BatteryColor.red)
        #expect(BatteryRing.color(for: 21) == BatteryColor.green)
        // Its level takes the same room whatever its digits, so 15% stays on one line.
        func wing(_ percent: Int) -> CGFloat {
            let level = BatteryLevel(percent: percent, charging: true)
            let alert = NotchAlert(kind: .charging, content: .battery(title: "Charging", level: level), spoken: "")
            return SystemActivityView.wing(for: alert, restingHeight: 32, closedWidth: 185)
        }
        #expect(wing(15) == wing(64))
        #expect(wing(11) == wing(64))
        #expect(LowBatteryLayout.red.level == BatteryColor.red)
        #expect(LowBatteryLayout.yellow.level == BatteryColor.yellow)
        let saving = BatteryWatch.alert(
            from: Reading(percent: 6, onPower: false, charging: false), to: Reading(percent: 6, onPower: true, charging: true), lowPower: true)
        #expect(saving?.content == .battery(title: "Charging", level: BatteryLevel(percent: 6, charging: true, lowPower: true)))
        #expect(BatteryWatch.alert(from: Reading(percent: 80, onPower: true, charging: false), to: Reading(percent: 80, onPower: false, charging: false)) == nil)
        func low(_ from: Int, _ to: Int) -> Bool {
            BatteryWatch.alert(from: Reading(percent: from, onPower: false, charging: false), to: Reading(percent: to, onPower: false, charging: false))?
                .kind == .lowBattery
        }
        #expect(low(21, 20))
        #expect(low(25, 19))
        #expect(!low(20, 19))
        #expect(low(11, 10))
        #expect(!low(10, 9))
        #expect(!low(30, 29))
    }

    @Test("A device is announced with its battery")
    func announced() {
        let beats = DeviceWatch.alert(name: "Beats Solo 4", model: .beatsSolo4, battery: 15)
        #expect(beats.content == .device(model: .beatsSolo4, battery: 15))
        #expect(beats.spoken == "Beats Solo 4 connected, 15 percent")
        #expect(DeviceWatch.alert(name: "AirPods", model: .airpods).content == .device(model: .airpods, battery: nil))
        // AirPlay's device, by its name, as Control Center draws it.
        #expect(AirPlayRoute.symbol(for: "Living Room Apple TV") == "appletv")
        #expect(AirPlayRoute.symbol(for: "Samsung TV") == "tv")
        #expect(AirPlayRoute.symbol(for: "Kitchen HomePod") == "homepod")
        #expect(AirPlayRoute.symbol(for: "Sam's MacBook Pro") == "macbook")
        #expect(AirPlayRoute.symbol(for: "Bedroom") == "hifispeaker")
        #expect(DeviceWatch.shortName("Sam\u{2019}s AirPods Pro") == "AirPods Pro")
        #expect(DeviceWatch.shortName("Sam's Magic Keyboard") == "Magic Keyboard")
        // Running down past 20% or 10% is announced, its ring red; further down, not again.
        #expect(DeviceWatch.runsLow(from: 21, to: 20))
        #expect(DeviceWatch.runsLow(from: 12, to: 9))
        #expect(!DeviceWatch.runsLow(from: 20, to: 19))
        #expect(!DeviceWatch.runsLow(from: 9, to: 30))
        let low = DeviceWatch.lowBattery(name: "AirPods Pro", model: .airpodsPro2, battery: 10)
        #expect(low.kind == .deviceBattery)
        #expect(low.content == .device(model: .airpodsPro2, battery: 10))
        #expect(low.spoken == "AirPods Pro battery low, 10 percent")
        // A case runs low on its own, in its own picture, and waits its turn beside its earbuds'.
        let lowCase = DeviceWatch.caseLowBattery(name: "AirPods Pro", model: .airpodsPro2Case, battery: 20)
        #expect(lowCase.kind == .caseBattery && lowCase.kind != low.kind && lowCase.kind.runsLow && low.kind.runsLow)
        #expect(!NotchAlert.Kind.device.runsLow)
        #expect(lowCase.content == .device(model: .airpodsPro2Case, battery: 20))
        #expect(lowCase.spoken == "AirPods Pro Case battery low, 20 percent")
        #expect(lowCase.name == "AirPods Pro Case")
        #expect(DeviceWatch.shortName("MX Master 3S") == "MX Master 3S")
        #expect(DeviceWatch.isBluetooth(kAudioDeviceTransportTypeBluetoothLE))
        #expect(!DeviceWatch.isBluetooth(kAudioDeviceTransportTypeAirPlay))
    }

    @Test("AirPods' battery and model, from System Information's report: the lower earbud's level")
    func bluetoothReport() throws {
        let report = Data(
            """
            {"SPBluetoothDataType":[{"controller_properties":{},"device_connected":[{"Airpods Pro":{"device_batteryLevelCase":"42%",
            "device_batteryLevelLeft":"31%","device_batteryLevelRight":"39%","device_minorType":"Headphones","device_productID":"0x2024",
            "device_vendorID":"0x004C"}},{"Keychron Q1 Max":{"device_batteryLevelMain":"80%","device_minorType":"Keyboard"}}],
            "device_not_connected":[{"iPad":{}}]}]}
            """.utf8)
        let connected = DeviceWatch.connected(in: report)
        #expect(
            connected["airpods pro"]
                == DeviceWatch.BluetoothInfo(
                    battery: 31, product: 0x2024, vendor: 0x4C, kind: "Headphones", levels: .init(left: 31, right: 39, chargingCase: 42)))
        // Listed again for the case alone, they keep their earbuds' battery and model.
        let twice = DeviceWatch.connected(
            in: Data(
                """
                {"SPBluetoothDataType":[{"device_connected":[{"Airpods Pro":{"device_batteryLevelLeft":"31%","device_batteryLevelRight":"39%",
                "device_productID":"0x2024"}},{"Airpods Pro":{"device_batteryLevelCase":"42%"}}]}]}
                """.utf8))
        #expect(
            twice["airpods pro"]
                == DeviceWatch.BluetoothInfo(battery: 31, product: 0x2024, levels: .init(left: 31, right: 39, chargingCase: 42)))
        // The earbuds' battery and the case's stay apart, even when only the case's is told.
        let both = DeviceWatch.Battery(twice["airpods pro"]!)
        #expect(both?.percent == 31 && both?.casePercent == 42)
        let caseAlone = DeviceWatch.connected(
            in: Data(#"{"SPBluetoothDataType":[{"device_connected":[{"Airpods Pro":{"device_batteryLevelCase":"42%","device_productID":"0x2024"}}]}]}"#.utf8))
        let onlyCase = DeviceWatch.Battery(caseAlone["airpods pro"]!)
        #expect(onlyCase?.percent == nil && onlyCase?.casePercent == 42)
        #expect(connected["keychron q1 max"] == DeviceWatch.BluetoothInfo(battery: 80, product: nil, kind: "Keyboard", levels: .init(main: 80)))
        #expect(connected["ipad"] == nil)
        #expect(DeviceWatch.connected(in: Data("not json".utf8)).isEmpty)
        // As macOS names the models.
        #expect(DeviceWatch.BluetoothInfo(product: 0x2024).modelSymbols?.symbol == "airpods.pro.gen1")
        #expect(DeviceWatch.BluetoothInfo(product: 8223).modelSymbols?.symbol == "airpodsmax")
        #expect(DeviceWatch.BluetoothInfo(product: 0x0001).modelSymbols == nil)
        // Another maker's product number means nothing to macOS, even if it's the same.
        #expect(DeviceWatch.BluetoothInfo(product: 0x2024, vendor: 0x0A12).modelSymbols == nil)
        // It's pictured as what it says it is.
        #expect(DeviceWatch.BluetoothInfo(vendor: 0x0A12, kind: "Speaker").modelSymbols?.symbol == "hifispeaker")
    }

    @Test("Clock's stopwatch is read from what macOS keeps: running from when it started less what was on it, stopped, or reset")
    func stopwatch() {
        func watch(_ state: Int, start: Date? = nil, laps: TimeInterval = 0, lap: TimeInterval = 0) -> [String: Any] {
            var watch: [String: Any] = ["MTStopwatchState": state, "MTStopwatchPreviousLapsTotalInterval": laps, "MTStopwatchOffset": lap]
            if let start { watch["MTStopwatchStartDate"] = start }
            return ["$MTStopwatch": watch]
        }
        let now = Date.now
        #expect(Stopwatch.current(in: []) == nil)
        #expect(Stopwatch.current(in: [watch(0)]) == nil)
        // Running, after a lap of 4.5 seconds and 3 more seconds before it was last stopped.
        let running = Stopwatch.current(in: [watch(2, start: now - 2, laps: 4.5, lap: 3)])
        #expect(running?.isRunning == true)
        #expect(abs((running?.elapsed(at: now) ?? 0) - 9.5) < 0.001)
        let stopped = Stopwatch.current(in: [watch(1, laps: 4.5, lap: 3)])
        #expect(stopped == .stopped(elapsed: 7.5))
        // As Clock shows it: to the second beside the camera, to the hundredth opened.
        #expect(Stopwatch.format(7.41) == "0:07")
        #expect(Stopwatch.format(727.41) == "12:07")
        #expect(Stopwatch.format(3727.41) == "1:02:07")
        #expect(Stopwatch.format(7.416, hundredths: true) == "00:07" + (Locale.current.decimalSeparator ?? ".") + "41")
        // Beside the camera, its hundredths small after the seconds, as wide as its widest reading.
        #expect(Stopwatch.hundredths(7.416) == "41")
        #expect(Stopwatch.hundredths(7.999) == "99")
        #expect(StopwatchReading.width(7, size: 14) > 0)
        #expect(StopwatchReading.width(3_700, size: 14) > StopwatchReading.width(7, size: 14))
        // Started over, it's still running, but from now: what macOS kept from before isn't it yet.
        #expect(Stopwatch.alike(.running(since: now - 0.5), .running(since: now)))
        #expect(!Stopwatch.alike(.running(since: now - 30), .running(since: now)))
        #expect(Stopwatch.alike(.stopped(elapsed: 3), .stopped(elapsed: 7.5)))
        #expect(Stopwatch.alike(nil, nil))
        #expect(!Stopwatch.alike(nil, .running(since: now)))
    }

    @Test("A timer's chime is the tone Clock names, in whichever version macOS has, or Radial; none without one")
    func timerChime() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let rings = folder.appendingPathComponent("Ringtones"), alerts = folder.appendingPathComponent("AlertTones/Modern")
        try FileManager.default.createDirectory(at: rings, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: alerts, withIntermediateDirectories: true)
        for file in [
            rings.appendingPathComponent("Radial-EncoreInfinitum.m4r"), rings.appendingPathComponent("Night Owl.m4r"),
            alerts.appendingPathComponent("Chord.m4r"),
        ] {
            FileManager.default.createFile(atPath: file.path, contents: Data())
        }
        #expect(TimerChime.file(for: "system:Radial", in: folder)?.lastPathComponent == "Radial-EncoreInfinitum.m4r")
        #expect(TimerChime.file(for: "system:Night Owl", in: folder)?.lastPathComponent == "Night Owl.m4r")
        #expect(TimerChime.file(for: "system:Chord", in: folder)?.lastPathComponent == "Chord.m4r")
        #expect(TimerChime.file(for: "system:Gone", in: folder)?.lastPathComponent == "Radial-EncoreInfinitum.m4r")
        #expect(TimerChime.file(for: nil, in: folder) == nil)
    }

    @Test("A Clock timer that rings is told by when macOS notes it rang, the last one's length and label")
    func timerRings() {
        let now = Date.now
        func rung(_ fired: Date?, _ length: TimeInterval, _ title: String) -> [String: Any] {
            var timer: [String: Any] = ["MTTimerState": 1, "MTTimerDuration": length, "MTTimerTitle": title]
            if let fired { timer["MTTimerFiredDate"] = fired }
            return ["$MTTimer": timer]
        }
        #expect(ClockActivity.lastRung(in: [rung(nil, 300, "")]) == nil)
        let last = ClockActivity.lastRung(in: [rung(now - 600, 300, ""), rung(now - 2, 90, "Pasta"), rung(nil, 60, "")])
        #expect(last?.date == now - 2)
        #expect(last?.length == 90)
        #expect(last?.title == "Pasta")
        #expect(last?.dismissed == false)
        #expect(last?.tone == nil)
        // The tone it rings with, which the notch rings with in place of macOS's alert.
        var toned = rung(now - 1, 60, "")
        toned["$MTTimer"] = (toned["$MTTimer"] as! [String: Any]).merging(
            ["MTTimerSound": ["$MTSound": ["MTSoundToneID": "system:Radial", "MTSoundType": 2]]]) { $1 }
        #expect(ClockActivity.lastRung(in: [toned])?.tone == "system:Radial")
        // Stopped or repeated in macOS's own alert, macOS notes when.
        var answered = rung(now - 5, 60, "")
        answered["$MTTimer"] = (answered["$MTTimer"] as! [String: Any]).merging(["MTTimerDismissedDate": now - 2]) { $1 }
        #expect(ClockActivity.lastRung(in: [answered])?.dismissed == true)
        // Started again from Clock's picker, which reads the length last started.
        #expect(ClockActivity.seconds("00:05:00") == 300)
        #expect(ClockActivity.seconds("01:02:03") == 3723)
        #expect(ClockActivity.seconds("5 minutes") == nil)
    }

    @Test("A device arrives as AirPods do on the iPhone: the device and its ring by the notch's height, against the camera")
    func deviceLayout() {
        // The iPhone's Dynamic Island, 110 pixels tall for AirPods, as for anything else: the AirPods
        // 51 tall; the ring 59 across, as far in from the end as from the top and bottom.
        let island = DeviceLayout(height: 110)
        #expect(abs(island.picture - 51) < 0.5)
        #expect(abs(island.ring - 59) < 0.5)
        #expect(abs(island.trailing - (110 - island.ring) / 2) < 0.001)
        // Its wings as wide as the ring and its level need, against the camera, and no wider.
        let pill = NotchAlert(kind: .device, content: .device(model: .beatsPill, battery: 15), spoken: "")
        let layout = DeviceLayout(height: 32)
        let wing = SystemActivityView.wing(for: pill, restingHeight: 32, closedWidth: 185)
        #expect(wing < layout.ring + layout.trailing + 60)
    }

    @Test("Over a full-screen app, nothing shows beside the camera, and it still opens")
    func collapsedNotch() {
        let model = NotchModel(closedSize: CGSize(width: 185, height: 32), layout: .top, hasCamera: true)
        model.alert = DeviceWatch.alert(name: "AirPods", model: .airpods, battery: 50)
        model.alertWing = 80
        model.alertExtended = true
        #expect(model.restingWidth > 185)
        #expect(model.restingHeight > 32)
        let open = model.metrics(for: .open)
        model.collapsed = true
        #expect(model.restingWidth == 185)
        #expect(model.restingHeight == 32)
        #expect(model.metrics(for: .open).bodyWidth == open.bodyWidth)
    }

    @Test("A device extended is the iPhone's size under the pointer, with no swell on top, its device and ring grown")
    func deviceExtended() {
        let model = NotchModel(closedSize: CGSize(width: 185, height: 32), layout: .top, hasCamera: true)
        model.alert = DeviceWatch.alert(name: "AirPods", model: .airpods, battery: 50)
        model.alertExtendedWing = 100
        model.alertExtended = true
        let peek = model.metrics(for: .peek)
        #expect(peek.height == TimerLayout.tallHeight(32))
        #expect(abs(peek.bodyWidth - 385) < 0.001)
        let small = DeviceLayout(height: 32), large = DeviceLayout(height: 32, extended: true)
        #expect(large.picture > small.picture)
        #expect(large.ring > small.ring)
        #expect(large.trailing == PlayerLayout.padding)
    }

    @Test("AirPods and Beats are known by their model, a newer one as the newest of its kind")
    func headphoneModels() {
        // AirPods Pro, the first, the second with Lightning and with USB-C, and the third.
        #expect(Headphones(product: 0x200E) == .airpodsPro)
        #expect(Headphones(product: 0x2014) == .airpodsPro2)
        #expect(Headphones(product: 0x2024) == .airpodsPro2)
        #expect(Headphones(product: 0x2027) == .airpodsPro3)
        // AirPods 3, 4 with and without noise cancellation, and 5.
        #expect(Headphones(product: 0x2013) == .airpods3)
        #expect(Headphones(product: 0x2019) == .airpods)
        #expect(Headphones(product: 0x201B) == .airpods)
        #expect(Headphones(product: 0x2030) == .airpods)
        // Beats.
        #expect(Headphones(product: 0x2010) == .beatsFlex)
        #expect(Headphones(product: 0x2011) == .beatsStudioBudsPlus)
        #expect(Headphones(product: 0x2016) == .beatsStudioBudsPlus)
        #expect(Headphones(product: 0x2017) == .beatsStudioPro)
        #expect(Headphones(product: 0x201A) == .beatsPill)
        #expect(Headphones(product: 0x201D) == .powerbeatsPro2)
        #expect(Headphones(product: 0x2025) == .beatsSolo4)
        #expect(Headphones(product: 0x2026) == .beatsSoloBuds)
        #expect(Headphones(product: 0x202F) == .powerbeatsFit)
        #expect(Headphones(product: 0x2038) == .beats360)
        // AirPods Max, whichever. AirPods 2, and nothing at all, have no model.
        #expect(Headphones(product: 0x200A) == .airpodsMax)
        #expect(Headphones(product: 0x202D) == .airpodsMax)
        #expect(Headphones(product: 0x200F) == nil)
        #expect(Headphones(product: 0x1234) == nil)
    }

    @Test("Earbuds with a case in their maker's model have their own closed clip of it; others none")
    func chargingCases() {
        #expect(Headphones.airpodsPro2.chargingCase == .airpodsPro2Case)
        #expect(Headphones.powerbeatsFit.chargingCase == .powerbeatsFitCase)
        #expect(Headphones.airpodsPro2Case.chargingCase == nil)
        #expect(Headphones.beatsFlex.chargingCase == nil)
        #expect(Headphones.beatsSolo4.chargingCase == nil)
        #expect(Headphones.allCases.filter(\.isChargingCase).count == 9)
        // AirPods Max have a model but no case in it.
        #expect(Headphones.airpodsMax.chargingCase == nil)
    }

    @Test("A case holds face on as it arrives, then gathers speed up to a steady turn")
    func caseHolds() {
        let hold = TurningDevice.caseHold, speed = TurningDevice.degreesPerSecond, gathering = TurningDevice.gathering
        #expect(TurningDevice.degrees(after: 0, holding: hold) == 0)
        #expect(TurningDevice.degrees(after: hold, holding: hold) == 0)
        #expect(TurningDevice.degrees(after: hold + gathering / 2, holding: hold) < speed * gathering / 2)
        let up = TurningDevice.degrees(after: hold + gathering, holding: hold)
        #expect(abs(TurningDevice.degrees(after: hold + gathering + 1, holding: hold) - up - speed) < 0.001)
    }

    /// The clips, as the repository keeps them.
    static func clip(_ headphones: Headphones) -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Resources/Headphones/\(headphones.rawValue).mov")
    }

    @Test("Every device turns as on a turntable, from face on, a frame every degree and a half", arguments: Headphones.allCases)
    func deviceTurn(_ headphones: Headphones) async throws {
        let turn = try #require(await DeviceTurn.load(Self.clip(headphones)))
        #expect(turn.frames.count == 240)
        #expect(CGRect(origin: .zero, size: turn.canvas).contains(turn.rest))
        // Drawn as tall as it shows on a 2× display and then some.
        #expect(abs(turn.rest.height - 44) <= 3)
        #expect(turn.frame(at: 0) === turn.frames[0])
        #expect(turn.frame(at: -360) === turn.frames[0])
        #expect(turn.frame(at: 1.5) === turn.frames[1])
        #expect(turn.frame(at: -1.5) === turn.frames[239])
        // Face on as it arrives, then turning steadily, as fast as the iPhone turns AirPods.
        #expect(TurningDevice.degrees(after: 0) == 0)
        #expect(abs(TurningDevice.degrees(after: 360 / TurningDevice.degreesPerSecond) - 360) < 0.001)
    }

    @Test("Time left reads as a clock shows it, and the lengths are named")
    func timerText() {
        #expect(NotchTimer.format(59) == "0:59")
        #expect(NotchTimer.format(299.2) == "5:00")
        #expect(NotchTimer.format(3725) == "1:02:05")
        #expect(NotchTimer.format(0) == "0:00")
        // A rung timer's length, as its preset is named, in words that start with its number.
        #expect(NotchTimer.length(300).hasPrefix("5 "))
        #expect(NotchTimer.length(3600).hasPrefix("1 "))
        #expect(NotchTimer.length(300) == NotchTimer.length(300).capitalized)
    }

    @Test("The wings widen for an announcement over a song's, and for a timer, as far as their words need")
    func wings() async {
        let model = NotchModel(closedSize: CGSize(width: 185, height: 32), layout: .top, hasCamera: true)
        let resting = model.closedSize.height
        #expect(model.wing == 0)
        model.timer = .running(until: .now + 300, total: 300)
        model.timerWing = SystemActivityView.wing(for: .timer(model.timer!), restingHeight: resting)
        #expect(model.wing == model.timerWing)
        // With music, the timer is detached, and music has the leading side alone.
        model.activity = true
        #expect(model.wing == resting)
        model.pop = true
        model.popWing = 120
        #expect(model.wing == 120)
        _ = await DeviceTurn.prepare(.airpodsPro2, from: Self.clip(.airpodsPro2))
        let alert = NotchAlert(
            kind: .device, content: .device(model: .airpodsPro2, battery: 31),
            spoken: "AirPods Pro connected")
        model.alertWing = SystemActivityView.wing(for: alert, restingHeight: resting, closedWidth: model.closedSize.width)
        model.alert = alert
        #expect(model.wing == model.alertWing)
        #expect(model.alertWing > resting && model.alertWing <= SystemActivityView.maxWing)
        // An hour or more takes more room than minutes.
        let minutes = SystemActivityView.wing(for: .timer(.running(until: .now + 300, total: 300)), restingHeight: resting)
        let hours = SystemActivityView.wing(for: .timer(.running(until: .now + 3_700, total: 3_700)), restingHeight: resting)
        #expect(hours > minutes)
        // The stopwatch gains a digit at an hour.
        let short = SystemActivityView.wing(for: .stopwatch(.running(since: .now - 30)), restingHeight: resting)
        let long = SystemActivityView.wing(for: .stopwatch(.running(since: .now - 3_700)), restingHeight: resting)
        #expect(long > short)
    }

    @Test("Beside the camera, a timer counts down in whole minutes from ten minutes, then in minutes and seconds")
    func condensedTime() {
        #expect(NotchTimer.condensed(14 * 60 + 3) == "14m")
        #expect(NotchTimer.condensed(14 * 60 + 59) == "14m")
        #expect(NotchTimer.condensed(600) == "10m")
        // Under ten minutes, in minutes and seconds.
        #expect(NotchTimer.condensed(599) == "9:59")
        #expect(NotchTimer.condensed(4 * 60 + 49) == "4:49")
        #expect(NotchTimer.condensed(1) == "0:01")
        #expect(NotchTimer.condensed(3600) == "1h")
        #expect(NotchTimer.condensed(3900) == "1h 5m")
    }

    @Test("A done timer is as tall as the Alarm, the closed notch with it; a long label is cut short")
    func doneTimer() {
        let model = NotchModel(closedSize: CGSize(width: 185, height: 32), layout: .top, hasCamera: true)
        #expect(model.restingHeight == 32)
        model.alert = NotchAlert(kind: .timerDone, content: .timerDone(length: 300, name: "Timer"), spoken: "Timer done", stays: true)
        #expect(model.restingTall)
        #expect(model.restingHeight == (32 * TimerLayout.tall).rounded())
        #expect(model.metrics(for: .closed).height == model.restingHeight)
        let plain = TimerDoneView.wing(length: 300, restingHeight: 32)
        let long = TimerDoneView.wing(length: 300, name: String(repeating: "Long label ", count: 10), restingHeight: 32)
        #expect(long >= plain)
        #expect(long <= TimerDoneView.nameEdge(32) + 32 * TimerLayout.titleLimit + LiveActivityView.cameraGap + 2)
    }

    @Test("Each side sits at its wing's end, as far in from it as from the top and bottom, concentric with the round end")
    func concentricEnds() {
        let h: CGFloat = 32
        // The timer's ring and a device's battery ring: as far from the end as from the top.
        #expect(isClose(SystemActivityView.ringEdge(h) * 2 + h * TimerLayout.ring, h))
        let layout = DeviceLayout(height: h)
        #expect(isClose(layout.trailing * 2 + layout.ring, h))
        #expect(isClose(layout.edge * 2 + layout.picture, h))
        // Words, by their line, a little further in than the cover.
        let words = LiveActivityView.textEdge(restingHeight: h)
        #expect(words > LiveActivityView.inset && words < 10)
        let (left, right) = SystemActivityView.insets(
            for: .battery(title: "Charging", level: BatteryLevel(percent: 64, charging: true)), restingHeight: h)
        #expect(left == words && right == words)
        // Opened and done, the round buttons are as far in from the end as from the top and bottom.
        #expect(abs(TimerLayout.buttonEdge(h) - (TimerLayout.tallHeight(h) - TimerLayout.content(h)) / 2) < 0.01)
    }

    @Test("Opened to a timer, the notch is as tall as the Timer's expanded view, each side from its end, concentric with it")
    func expandedTimer() {
        let model = NotchModel(closedSize: CGSize(width: 185, height: 32), layout: .top, hasCamera: true)
        model.timer = .running(until: .now + 300, total: 300)
        model.expanded = .timer
        let open = model.metrics(for: .open)
        #expect(open.height == (32 * TimerLayout.tall).rounded())
        // Either side of the camera, only as wide as the buttons, wider than "5:00", need.
        let buttons = TimerLayout.content(32) * 2 + 32 * TimerLayout.buttonGap
        #expect(abs(open.bodyWidth - (185 + 2 * (TimerLayout.buttonEdge(32) + buttons + LiveActivityView.cameraGap))) < 1)
        // Its top corners in proportion to its height, as the player's are to the player's.
        #expect(abs(open.flare - PlayerLayout.cornerRadius * open.height / 148) < 0.001)
        // Past an hour, the time takes more room.
        model.timer = .running(until: .now + 7_200, total: 7_200)
        #expect(model.metrics(for: .open).bodyWidth >= open.bodyWidth)
        // Opened to the stopwatch, the same, its time to the hundredth.
        model.timer = nil
        model.stopwatch = .running(since: .now - 7)
        model.expanded = .stopwatch
        #expect(model.metrics(for: .open).height == open.height)
        #expect(model.metrics(for: .open).bodyWidth >= open.bodyWidth)
    }

    @Test("Paused, a timer makes room for its pause symbol; a device not in 3D, for its level; a long name scrolls within the limit")
    func roomForWhatShows() {
        let resting: CGFloat = 32
        let running = SystemActivityView.wing(for: .timer(.running(until: .now + 300, total: 300)), restingHeight: resting)
        let paused = SystemActivityView.wing(for: .timer(.paused(left: 300, total: 300)), restingHeight: resting)
        #expect(paused > running)
        let stopped = SystemActivityView.wing(for: .stopwatch(.stopped(elapsed: 7)), restingHeight: resting)
        #expect(stopped > SystemActivityView.wing(for: .stopwatch(.running(since: .now - 7)), restingHeight: resting))
        let layout = DeviceLayout(height: resting)
        let pill = NotchAlert(
            kind: .device, content: .device(model: .beatsPill, battery: 15), spoken: "Beats Pill connected, 15 percent")
        // Its battery as a ring alone, with no level in numbers beside it.
        #expect(SystemActivityView.wing(for: pill, restingHeight: resting, closedWidth: 185) >= layout.ring + layout.trailing)
        #expect(SystemActivityView.wing(for: pill, restingHeight: resting, closedWidth: 185) < layout.ring + layout.trailing + 15)
        let long = "The Living Room Speaker Upstairs, By the Window"
        let speaker = NotchAlert(kind: .charging, content: .status(symbol: "airplay.audio", tint: .blue, text: long), spoken: long)
        #expect(SystemActivityView.wing(for: speaker, restingHeight: resting, closedWidth: 185) == SystemActivityView.maxWing)
        #expect(SystemActivityView.maxWing <= 120)
        // A timer's wings as wide as its time needs as it reads now, from the end, and no wider.
        let early = SystemActivityView.wing(for: .timer(.running(until: .now + 600, total: 600)), restingHeight: resting)
        let late = SystemActivityView.wing(for: .timer(.running(until: .now + 600, total: 600)), restingHeight: resting, at: .now + 550)
        let font = NSFont.monospacedDigitSystemFont(ofSize: LiveActivityView.textSize(for: resting), weight: .semibold)
        func needs(_ reading: String) -> CGFloat {
            LiveActivityView.cameraGap + ceil((reading as NSString).size(withAttributes: [.font: font]).width)
                + LiveActivityView.textEdge(restingHeight: resting)
        }
        #expect(abs(early - needs("00m")) < 0.5)
        #expect(abs(late - needs("0:00")) < 0.5)
        // The notch refits as the time loses a digit: from minutes to seconds, under ten minutes.
        let now = Date.now
        let change = SystemActivityView.widthChange(after: now, of: .timer(.running(until: now + 605, total: 605)))
        #expect(change.map { abs($0.timeIntervalSince(now) - 6) <= 1 } == true)
        // The stopwatch's, as it gains one, at ten minutes; none while it's stopped.
        let gains = SystemActivityView.widthChange(after: now, of: .stopwatch(.running(since: now - 595)))
        #expect(gains.map { abs($0.timeIntervalSince(now) - 5) <= 1 } == true)
        #expect(SystemActivityView.widthChange(after: now, of: .stopwatch(.stopped(elapsed: 595))) == nil)
    }

    @Test("With more than one, the first keeps the leading side and the second is detached, two at most")
    func detached() {
        let model = NotchModel(closedSize: CGSize(width: 185, height: 32), layout: .top, hasCamera: true)
        model.activity = true
        #expect(model.detached == nil)
        #expect(model.metrics.fold == 0)
        #expect(model.expansion(fromBubble: false) == nil)
        model.timer = .running(until: .now + 300, total: 300)
        model.timerWing = 60
        // Music keeps the leading side, as wide as the notch is tall; its trailing side folds away,
        // and the timer is detached off that end.
        #expect(model.detached == .timer)
        #expect(model.wing == 32)
        #expect(model.metrics.fold == 32)
        #expect(model.notchClock == nil)
        // A third waits its turn: nothing's ever detached at the leading side.
        model.stopwatch = .stopped(elapsed: 12)
        #expect(model.detached == .timer)
        // It opens to its own; the notch, to the player.
        #expect(model.expansion(fromBubble: true) == .timer)
        #expect(model.expansion(fromBubble: false) == nil)
        // While a new song's name shows, something else is announced, or the notch is open, it runs
        // back in, and the trailing side comes back.
        model.pop = true
        #expect(model.detached == nil)
        #expect(model.metrics.fold == 0)
        model.pop = false
        model.alert = NotchAlert(kind: .device, content: .device(model: .beatsPill, battery: 15), spoken: "")
        #expect(model.detached == nil)
        model.alert = nil
        model.state = .open
        #expect(model.detached == nil)
        #expect(model.metrics.fold == 0)
        // Nothing playing, the timer has the leading side, and the stopwatch is detached.
        model.state = .closed
        model.activity = false
        #expect(model.notchClock == .timer(model.timer!))
        #expect(model.wing == 32)
        #expect(model.detached == .stopwatch)
        #expect(model.expansion(fromBubble: false) == .timer)
        #expect(model.expansion(fromBubble: true) == .stopwatch)
    }

    @Test("Folded, the notch's trailing end comes back and its leading end stays")
    func foldedShape() {
        let corners = NotchCorners(restingHeight: 32, radius: 29)
        let rect = CGRect(x: 0, y: 0, width: 300, height: 32)
        let whole = NotchShape(corners: corners, wingEnds: 1).path(in: rect).boundingRect
        let folded = NotchShape(corners: corners, wingEnds: 1, fold: 32).path(in: rect).boundingRect
        #expect(isClose(folded.minX, whole.minX))
        #expect(isClose(folded.maxX, whole.maxX - 32))
    }

    @Test("Low Battery is as tall as the Alarm, its level and its capsule against the camera, its offer under it")
    func lowBattery() {
        let alert = BatteryWatch.lowBattery(.init(percent: 10, onPower: false, charging: false))
        #expect(alert.content == .lowBattery(percent: 10))
        #expect(alert.tall)
        let h: CGFloat = 32
        let model = NotchModel(closedSize: CGSize(width: 185, height: h), layout: .top, hasCamera: true)
        model.alert = alert
        #expect(model.restingHeight == TimerLayout.tallHeight(h))
        // The capsule as far in from the end as from the top and bottom.
        let edge = PlayerLayout.padding
        #expect(abs(edge * 2 + LowBatteryLayout.capsule(h).height - TimerLayout.tallHeight(h)) < 0.01)
        // Each wing as wide as the capsule or the level needs against the camera, or the words under it.
        let right = LowBatteryLayout.capsule(h).width + edge
        let left = h * LowBatteryLayout.wordsEdge + LowBatteryLayout.width(LowBatteryView.title(10))
        let words = LowBatteryLayout.width(LowBatteryView.offer)
        let wing = SystemActivityView.wing(for: alert, restingHeight: h, closedWidth: 185)
        #expect(wing == max(LiveActivityView.cameraGap + max(left, right), (h * LowBatteryLayout.wordsEdge + words + h * LowBatteryLayout.wordsGap + right - 185) / 2))
        #expect(wing < h * 4)
        // Tall already, it doesn't swell under the pointer.
        #expect(model.metrics(for: .peek).height == TimerLayout.tallHeight(h))
        #expect(model.metrics(for: .peek).bodyWidth == model.metrics(for: .closed).bodyWidth)
        // A ripple every two seconds: palest early on, and the line gone before the next.
        #expect(abs(LowBatteryLayout.rippleTime(after: 2) - LowBatteryLayout.rippleTime(after: 0)) < 0.001)
        #expect(LowBatteryLayout.along(LowBatteryLayout.pale, at: 0.4) == 1)
        #expect(LowBatteryLayout.along(LowBatteryLayout.pale, at: 1.8) == 0)
        #expect(LowBatteryLayout.along(LowBatteryLayout.line, at: 1.8) == 0)
        // It starts around the level and ends a circle.
        let (start, end) = (LowBatteryLayout.along(LowBatteryLayout.across, at: 0), LowBatteryLayout.along(LowBatteryLayout.up, at: 0))
        #expect(start < end)
        #expect(LowBatteryLayout.along(LowBatteryLayout.across, at: 2) == LowBatteryLayout.along(LowBatteryLayout.up, at: 2))
        // A device running low has a larger ring, for its level in numbers inside.
        #expect(DeviceLayout(height: h, low: true).ring > DeviceLayout(height: h).ring)
    }

    @Test("AirDrop comes right after music: the notch's once nothing plays, otherwise detached, and it opens to it")
    func airDrop() {
        let model = NotchModel(closedSize: CGSize(width: 185, height: 32), layout: .top, hasCamera: true)
        let transfer = AirDropShown(id: "1", sender: "iPhone", preview: nil, fraction: 0.4)
        model.timer = .running(until: .now + 300, total: 300)
        model.airplay = AirPlayRoute(name: "Living Room", symbol: "hifispeaker.fill")
        model.airdrop = transfer
        #expect(model.activities == [.airdrop, .timer, .airplay])
        #expect(model.notchClock == nil)
        #expect(model.wing == 32)
        #expect(model.expansion(fromBubble: false) == .airdrop)
        model.activity = true
        #expect(model.detached == .airdrop)
        #expect(model.expansion(fromBubble: true) == .airdrop)
        model.expanded = .airdrop
        model.airdrop = nil
        #expect(model.expandedGone)
        // Opened, as tall as the Alarm, just wide enough for the picture and AirDrop's name beside the
        // camera; who it's from runs on under the camera, up to the ring.
        let width = AirDropLayout.width(restingHeight: 32, camera: 185)
        #expect((width - 185) / 2 > AirDropLayout.wordsStart(32))
        #expect(AirDropLayout.wordsStart(32) + AirDropLayout.wordsRoom(32, width: width) > (width + 185) / 2)
        #expect(ExpandedAirDropView.spoken(transfer) == "AirDrop from iPhone, 40 percent")
    }

    @Test("One swiped away leaves the notch to the next, and the one after is detached")
    func swipedAway() {
        let model = NotchModel(closedSize: CGSize(width: 185, height: 32), layout: .top, hasCamera: true)
        model.timer = .running(until: .now + 300, total: 300)
        model.stopwatch = .stopped(elapsed: 12)
        model.airplay = AirPlayRoute(name: "Living Room", symbol: "hifispeaker.fill")
        #expect(model.activities == [.timer, .stopwatch, .airplay])
        model.dismissed.insert(.timer)
        #expect(model.activities == [.stopwatch, .airplay])
        #expect(model.notchClock == .stopwatch(.stopped(elapsed: 12)))
        #expect(model.detached == .airplay)
        model.dismissed = [.timer, .stopwatch, .airplay]
        #expect(model.activities.isEmpty)
        #expect(model.wing == 0)
    }

    @Test("AirPlay comes after the rest: the notch's once nothing else shows, its symbols in the cover's wings")
    func airPlay() {
        let model = NotchModel(closedSize: CGSize(width: 185, height: 32), layout: .top, hasCamera: true)
        let route = AirPlayRoute(name: "Living Room", symbol: "appletv.fill")
        model.airplay = route
        #expect(model.activities == [.airplay])
        #expect(model.wing == LiveActivityView.restingWing(restingHeight: 32))
        #expect(model.expansion(fromBubble: false) == .airplay)
        // Behind music, detached, and it opens to it.
        model.activity = true
        #expect(model.detached == .airplay)
        #expect(model.expansion(fromBubble: true) == .airplay)
        // Opened to it, it's gone once the sound leaves AirPlay.
        model.expanded = .airplay
        #expect(!model.expandedGone)
        model.airplay = nil
        #expect(model.expandedGone)
        #expect(ExpandedAirPlayView.width(for: route, restingHeight: 32) == 32 * AirPlayLayout.wide)
        #expect(AirPlayLayout.height(32) > TimerLayout.tallHeight(32))
    }

    @Test("macOS's own timer is read from what macOS keeps: the running one ending first, else the one paused last")
    func clockTimer() {
        func timer(_ state: Int, _ total: TimeInterval, until: Date? = nil, left: TimeInterval? = nil, changed: Date? = nil) -> [String: Any] {
            var timer: [String: Any] = ["MTTimerState": state, "MTTimerDuration": total]
            if let until { timer["MTTimerFireTime"] = ["$MTTimerDate": ["MTTimerTimeDate": until]] }
            if let left { timer["MTTimerFireTime"] = ["$MTTimerTimeInterval": ["MTTimerTimeInterval": left]] }
            if let changed { timer["MTTimerLastModifiedDate"] = changed }
            return ["$MTTimer": timer]
        }
        let now = Date.now
        let stopped = timer(1, 900, left: 900)
        let paused = timer(2, 600, left: 559, changed: now - 60)
        let pausedEarlier = timer(2, 300, left: 200, changed: now - 600)
        let running = timer(3, 300, until: now + 120)
        let runningLonger = timer(3, 600, until: now + 500)
        let ended = timer(3, 300, until: now - 5)
        #expect(ClockActivity.timer(in: [], at: now) == nil)
        #expect(ClockActivity.timer(in: [stopped, ended], at: now) == nil)
        #expect(ClockActivity.timer(in: [stopped, runningLonger, running, paused], at: now)?.state == .running(until: now + 120, total: 300))
        #expect(ClockActivity.timer(in: [pausedEarlier, stopped, paused], at: now)?.state == .paused(left: 559, total: 600))
    }

    @Test("A Clock timer goes by the label it was given, never Clock's placeholder, and a long one is cut short")
    func clockTimerName() {
        func running(_ title: String?) -> [String: Any] {
            var timer: [String: Any] = ["MTTimerState": 3, "MTTimerDuration": 300.0, "MTTimerFireTime": ["$MTTimerDate": ["MTTimerTimeDate": Date.now + 100]]]
            if let title { timer["MTTimerTitle"] = title }
            return ["$MTTimer": timer]
        }
        #expect(ClockActivity.timer(in: [running("Pasta")])?.title == "Pasta")
        #expect(ClockActivity.timer(in: [running("CURRENT_TIMER")])?.title == nil)
        #expect(ClockActivity.timer(in: [running(" ")])?.title == nil)
        #expect(ClockActivity.timer(in: [running(nil)])?.title == nil)
        // Shown and spoken as its label, or Timer; the stopwatch as Stopwatch.
        let model = NotchModel(closedSize: CGSize(width: 185, height: 32), layout: .top, hasCamera: true)
        #expect(model.name(of: .timer) == "Timer")
        model.timerName = "Pasta"
        #expect(model.name(of: .timer) == "Pasta")
        #expect(model.name(of: .stopwatch) == "Stopwatch")
        // Beside the camera it runs under the camera, which the width doesn't change for.
        let state = ClockShown.timer(.paused(left: 300, total: 300))
        #expect(ExpandedTimerView.width(for: state, name: "Pasta", restingHeight: 32, camera: 185) == ExpandedTimerView.width(for: state, restingHeight: 32, camera: 185))
    }
}

/// macOS's own banners, taken away only where the notch says the same.
@Suite("System banners")
struct SystemBannersTests {
    @Test("A call shows the phone and its time, or the caller and a handset, and takes the notch from music")
    @MainActor
    func calls() {
        let ringing = CallShown(name: "Alex Morgan", over: "FaceTime", app: nil, phase: .ringing)
        let connected = CallShown(name: "Alex Morgan", over: "FaceTime", app: nil, phase: .connected(since: .now))
        #expect(ringing.initial == "A" && !ringing.isConnected && connected.isConnected)
        #expect(CallShown(name: "", over: "", phase: .ringing).initial == "")
        let model = NotchModel(closedSize: CGSize(width: 185, height: 32), layout: .top, hasCamera: true)
        model.activity = true
        model.airplay = AirPlayRoute(name: "HomePod", symbol: "homepod")
        #expect(model.activities.first == .music)
        model.call = connected
        #expect(model.activities.first == .call && !model.activities.contains(.music) && !model.musicShown)
        // Nothing detached beside it, and its wings as wide as it needs.
        #expect(model.detached == nil)
        #expect(model.wing == CallLayout.wing(for: connected, restingHeight: 32))
        #expect(CallLayout.wing(for: connected, restingHeight: 32) > CallLook.waveWidth)
        // An hour's time takes more room.
        let longer = CallShown(name: "A", over: "F", phase: .connected(since: .now - 3_700))
        #expect(CallLayout.wing(for: longer, restingHeight: 32) > CallLayout.wing(for: connected, restingHeight: 32))
        // Swiped away, the rest come back.
        model.dismissed.insert(.call)
        #expect(model.activities.first == .music && model.musicShown)
        // A call coming in is as tall as the Alarm, and stays.
        let alert = NotchAlert(kind: .incomingCall, content: .incomingCall(ringing), spoken: "", stays: true)
        #expect(alert.tall && alert.stays)
    }

    @Test("The waveform shows whoever's louder at each moment, in their color")
    func callVoices() {
        #expect(CallVoices.sample(theirs: 0.6, yours: 0.2) == .init(level: 0.6, mine: false))
        #expect(CallVoices.sample(theirs: 0.1, yours: 0.5) == .init(level: 0.5, mine: true))
        #expect(CallVoices.sample(theirs: 0, yours: 0) == .init(level: 0, mine: false))
        #expect(CallVoices.sample(theirs: 3, yours: 0).level == 1)
    }

    @Test("Calling apps are known by their bundle IDs, their helpers too")
    func callApps() {
        #expect(CallAudio.callApp(of: "us.zoom.xos")?.name == "Zoom")
        #expect(CallAudio.callApp(of: "com.hnc.Discord.helper.Renderer")?.name == "Discord")
        #expect(CallAudio.callApp(of: "net.whatsapp.WhatsApp")?.name == "WhatsApp")
        #expect(CallAudio.callApp(of: "com.apple.avconferenced")?.name == "FaceTime")
        #expect(CallAudio.callApp(of: "com.spotify.client") == nil)
        #expect(CallAudio.callApp(of: "com.apple.VoiceMemos") == nil)
    }

    @Test("macOS's popup for a call is told apart by its app and its Accept button")
    func callPopup() {
        let actions = ["AXPress", "Name:Accept", "Name:Decline", "Name:Close"]
        #expect(
            CallBanners.call(description: "FaceTime, Alex Morgan, Incoming FaceTime Audio", actions: actions)
                == .init(name: "Alex Morgan", over: "FaceTime", app: "com.apple.FaceTime"))
        #expect(CallBanners.call(description: "Phone, Mum, mobile", actions: actions)?.name == "Mum")
        // Anything else from those apps, like a missed call, or from another app.
        #expect(CallBanners.call(description: "FaceTime, Alex Morgan, Missed call", actions: ["Name:Close"]) == nil)
        #expect(CallBanners.call(description: "Messages, Alex Morgan, Hello", actions: actions) == nil)
    }

    @Test("A device is shown only with its maker's 3D model; the rest keep macOS's own banner")
    func onlyWithModel() {
        // AirPods 1 and 2 and the first Beats have none. All AirPods Max are one model.
        for product in [0x2002, 0x200F, 0x2003, 0x2005] { #expect(Headphones(product: product) == nil) }
        #expect(Headphones(product: 0x200A) == .airpodsMax)
        #expect(Headphones(product: 0x201F) == .airpodsMax)
        #expect(Headphones(product: 0x202D) == .airpodsMax)
        let withModel = DeviceWatch.BluetoothInfo(product: 0x2024, vendor: 0x4C)
        let withoutModel = DeviceWatch.BluetoothInfo(product: 0x200F, vendor: 0x4C)
        let otherMaker = DeviceWatch.BluetoothInfo(product: 0x2024, vendor: 0x1234, kind: "Headphones")
        #expect(withModel.model == .airpodsPro2)
        #expect(withoutModel.model == nil && withoutModel.announced)
        #expect(otherMaker.model == nil)
        #expect(DeviceWatch.Battery(withModel) != nil)
        #expect(DeviceWatch.Battery(withoutModel) == nil)
        // The banner goes for the device it names, or by what's connected if it names none.
        let connected = ["sam\u{2019}s airpods pro": withModel, "airpods": withoutModel]
        #expect(MenuBarBanners.notchShows(["AirPods Pro", "88", "Connected"], connected: connected))
        #expect(!MenuBarBanners.notchShows(["AirPods", "88", "Connected"], connected: connected))
        #expect(!MenuBarBanners.notchShows(["Other Name", "88"], connected: connected))
        #expect(MenuBarBanners.notchShows(["Other Name", "88"], connected: ["airpods pro": withModel]))
        #expect(MenuBarBanners.notchShows(["Other Name", "88"], connected: [:]))
    }

    @Test("AirPods connecting or running low show their level; a device's name or an offer doesn't count")
    func showsBattery() {
        #expect(MenuBarBanners.showsBattery(["Airpods Pro", "88", "Connected"]))
        #expect(MenuBarBanners.showsBattery(["AirPods 4", "9%", "Low Battery"]))
        #expect(!MenuBarBanners.showsBattery(["AirPods 4", "Moved to iPhone"]))
        #expect(!MenuBarBanners.showsBattery(["", "Airpods Pro"]))
        #expect(!MenuBarBanners.showsBattery([]))
    }
}

/// Choosing what the bench tries, from the arguments Glance was started with.
@Suite("Activity bench")
struct ActivityBenchTests {
    @Test("A scene by its name, five minutes a round unless said")
    func parses() throws {
        let scene = try #require(ActivityBench.parse(["Glance", "--bench", "airdrop"]))
        #expect(scene.scenes == [.airdrop])
        #expect(scene.seconds == 300)
        #expect(ActivityBench.parse(["Glance", "--bench", "lowBattery", "20"])?.seconds == 20)
    }

    @Test("Two together, and no more, the most the notch shows")
    func pairs() {
        #expect(ActivityBench.parse(["Glance", "--bench", "music+timer", "60"])?.scenes == [.music, .timer])
        #expect(ActivityBench.parse(["Glance", "--bench", "music+timer+airplay"]) == nil)
        #expect(ActivityBench.parse(["Glance", "--bench", "music+player"]) == nil)
    }

    @Test("Without one, or with a name it doesn't know, there's no bench")
    func refuses() {
        #expect(ActivityBench.parse(["Glance"]) == nil)
        #expect(ActivityBench.parse(["Glance", "--bench"]) == nil)
        #expect(ActivityBench.parse(["Glance", "--bench", "player"]) == nil)
    }
}

/// A file going out over AirDrop, as how far the service sending it has read.
@Suite("AirDrop sending")
struct AirDropSendingTests {
    private func file(_ path: String, at offset: Int64, of size: Int64 = 1000, descriptor: Int32 = 7) -> AirDropSendWatch.OpenFile {
        AirDropSendWatch.OpenFile(descriptor: descriptor, path: path, offset: offset, size: size)
    }

    @Test("What's sent is the file read on from a moment ago, not one that sat still or macOS's own")
    func picksTheFile() {
        let movie = "/Users/gaty/Downloads/movie.mov"
        #expect(AirDropSendWatch.sent(in: [file(movie, at: 200)], before: [file(movie, at: 100)])?.path == movie)
        #expect(AirDropSendWatch.sent(in: [file(movie, at: 100)], before: [file(movie, at: 100)]) == nil)
        #expect(AirDropSendWatch.sent(in: [file(movie, at: 100)], before: []) == nil)
        #expect(AirDropSendWatch.sent(in: [file("/System/Library/thing", at: 200)], before: [file("/System/Library/thing", at: 100)]) == nil)
        #expect(AirDropSendWatch.sent(in: [file(movie, at: 200)], before: [file(movie, at: 100, descriptor: 8)]) == nil)
    }

    @Test("How far along is how far it's been read, between empty and full")
    func fraction() {
        #expect(AirDropSendWatch.fraction(of: file("/a", at: 250)) == 0.25)
        #expect(AirDropSendWatch.fraction(of: file("/a", at: 2000)) == 1)
        #expect(AirDropSendWatch.fraction(of: file("/a", at: 0, of: 0)) == 0)
    }

    @Test("It says who it's going to once that's known, and until then the file")
    func words() {
        var shown = AirDropShown(id: "1", sender: "", preview: nil, fraction: 0.4, sending: true, file: "movie.mov")
        #expect(ExpandedAirDropView.from(shown) == "movie.mov")
        #expect(ExpandedAirDropView.spoken(shown) == "AirDrop sending, 40 percent")
        shown.recipient = "iCarly"
        #expect(ExpandedAirDropView.from(shown) == "To iCarly")
        #expect(ExpandedAirDropView.spoken(shown) == "AirDrop to iCarly, 40 percent")
    }
}

/// Which headphones and speakers are announced as they connect.
@Suite("Devices announced")
struct DevicesAnnouncedTests {
    private func device(vendor: Int?, product: Int?) -> DeviceWatch.BluetoothInfo {
        DeviceWatch.BluetoothInfo(battery: 80, product: product, vendor: vendor)
    }

    @Test("Apple's and Beats' are, whatever the model; another maker's aren't, as on the iPhone")
    func makers() {
        #expect(device(vendor: 0x4C, product: 0x2024).announced)
        #expect(device(vendor: 0x4C, product: 0x7777).announced)
        #expect(device(vendor: nil, product: 0x2024).announced)
        #expect(!device(vendor: 0x0A12, product: 0x2024).announced)
        #expect(!device(vendor: nil, product: nil).announced)
    }
}
