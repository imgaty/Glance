//
//  ActivitiesTests.swift
//  GlanceTests
//
//  Created by Gaty on 16/10/2026.
//

import AppKit
import CoreAudio
import Foundation
import SwiftUI
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

    @Test("One that stays with a time limit goes by itself once it's up, as a timer that's done does")
    func expiring() async throws {
        let activities = Activities()
        var alert = NotchAlert(kind: .timerDone, content: .timerDone(length: 300, name: "Timer"), spoken: "Timer done", stays: true)
        alert.expires = 0.2
        activities.post(alert)
        #expect(activities.alert?.kind == .timerDone)
        try await Task.sleep(for: .seconds(0.1))
        #expect(activities.alert?.kind == .timerDone)
        for _ in 0..<20 where activities.alert != nil { try await Task.sleep(for: .milliseconds(50)) }
        #expect(activities.alert == nil)
    }

    @Test("A timer that's done goes by itself after ten seconds")
    func timerRingsFor() {
        #expect(ClockActivity.ringsFor == 10)
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
        // 51 tall; the ring, 59 across there, as large as every other activity's mark beside the
        // camera, as far in from the end as from the top and bottom.
        let island = DeviceLayout(height: 110)
        #expect(abs(island.picture - 51) < 0.5)
        #expect(abs(island.ring - 110 * TimerLayout.ring) < 0.001)
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
        // Music started after it is detached; the timer keeps its own side as it is.
        model.activity = true
        #expect(model.wing == model.timerWing && model.detached == .music)
        // Music first, the timer detached, music keeps its own side as it is.
        model.timer = nil
        model.timer = .running(until: .now + 300, total: 300)
        #expect(model.wing == LiveActivityView.restingWing(restingHeight: resting))
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

    @Test("Opened from the bubble, the notch passes through its housing and restores the bubble when closed")
    @MainActor
    func openFromBubble() async throws {
        let model = NotchModel(closedSize: CGSize(width: 185, height: 32), layout: .top, hasCamera: true)
        model.activityReducesMotion = false
        defer { model.cancelActivityTransition() }
        model.activity = true
        model.timer = .running(until: .now + 300, total: 300)
        model.timerWing = 60
        #expect(model.detached == .timer)
        // From the notch's end to the bubble's far side.
        #expect(abs(model.bubbleSpan - 32 * (1 + IslandBubble.gap)) < 0.001)
        // Clicked, the detached origin folds into the hardware before opening to its own size.
        model.openedFromBubble = true
        model.expanded = .timer
        model.bubbleReach = model.bubbleSpan
        model.open()
        #expect(model.bubbleReach == 0 && model.state == .open)
        #expect(model.activityFolded && model.detached == nil)
        #expect(model.metrics.bodyWidth == 185 && model.metrics.height == 32)
        let opening = try #require(model.activityTransitionTask)
        await opening.value
        #expect(!model.activityFolded && model.openedFromBubble)
        // Closing uses the same midpoint before the detached activity returns.
        model.close()
        #expect(model.activityFolded && model.bubbleReach == 0 && model.openedFromBubble)
        #expect(model.metrics.bodyWidth == 185 && model.metrics.height == 32)
        #expect(model.detached == nil)
        let closing = try #require(model.activityTransitionTask)
        await closing.value
        #expect(model.bubbleReach == 0 && !model.openedFromBubble)
        #expect(!model.activityFolded && model.detached == .timer)
        // Opened from the notch, it never reaches out.
        model.expanded = nil
        model.open()
        model.close()
        #expect(model.bubbleReach == 0)
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
        // Music keeps its leading side as it is; its trailing side folds away,
        // and the timer is detached off that end.
        #expect(model.detached == .timer)
        #expect(model.wing == LiveActivityView.restingWing(restingHeight: 32))
        // Folded back to just past the camera housing (see `pastHousing`).
        #expect(model.metrics.fold == model.wing - model.pastHousing)
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
        #expect(model.wing == max(model.timerWing, LiveActivityView.restingWing(restingHeight: 32)))
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

    @Test("AirDrop takes its turn: the notch's when it came first, otherwise detached, and it opens to it")
    func airDrop() {
        let model = NotchModel(closedSize: CGSize(width: 185, height: 32), layout: .top, hasCamera: true)
        let transfer = AirDropShown(id: "1", sender: "iPhone", preview: nil, fraction: 0.4)
        model.airdrop = transfer
        model.timer = .running(until: .now + 300, total: 300)
        model.airplay = AirPlayRoute(name: "Living Room", symbol: "hifispeaker.fill")
        #expect(model.activities == [.airdrop, .timer, .airplay])
        #expect(model.notchClock == nil)
        #expect(model.wing == LiveActivityView.restingWing(restingHeight: 32))
        #expect(model.expansion(fromBubble: false) == .airdrop)
        // After music, it's detached.
        model.timer = nil
        model.airplay = nil
        model.airdrop = nil
        model.activity = true
        model.airdrop = transfer
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

    @Test("The order activities started in is kept as Glance opens again: one still going takes its place back")
    func orderKept() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: NotchModel.orderKey)
        defer { defaults.removeObject(forKey: NotchModel.orderKey) }
        let call = CallShown(name: "Alex Morgan", over: "Discord", phase: .connected(since: .now - 600))
        // A call, then music beside it.
        let before = NotchModel(closedSize: CGSize(width: 185, height: 32), layout: .top, hasCamera: true)
        before.keepsOrder = true
        before.call = call
        before.activity = true
        #expect(before.activities == [.call, .music])
        // Opened again, music is found first, the call a few seconds later: the call keeps the notch.
        let after = NotchModel(closedSize: CGSize(width: 185, height: 32), layout: .top, hasCamera: true)
        after.keepsOrder = true
        after.activity = true
        #expect(after.activities == [.music])
        after.call = call
        #expect(after.activities == [.call, .music])
        #expect(after.detached == .music)
        // Anything new comes after what was going on before.
        let again = NotchModel(closedSize: CGSize(width: 185, height: 32), layout: .top, hasCamera: true)
        again.keepsOrder = true
        again.timer = .running(until: .now + 300, total: 300)
        again.activity = true
        #expect(again.activities == [.music, .timer])
        // Settings' pictures of the notch keep nothing.
        defaults.removeObject(forKey: NotchModel.orderKey)
        let picture = NotchModel(closedSize: CGSize(width: 185, height: 32), layout: .top, hasCamera: true)
        picture.activity = true
        #expect(defaults.stringArray(forKey: NotchModel.orderKey) == nil)
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

    @Test("AirPlay takes its turn: the notch's when it came first, its symbols in the cover's wings")
    func airPlay() {
        let model = NotchModel(closedSize: CGSize(width: 185, height: 32), layout: .top, hasCamera: true)
        let route = AirPlayRoute(name: "Living Room", symbol: "appletv.fill")
        model.airplay = route
        #expect(model.activities == [.airplay])
        #expect(model.wing == LiveActivityView.restingWing(restingHeight: 32))
        #expect(model.expansion(fromBubble: false) == .airplay)
        // Behind music that started first, detached, and it opens to it.
        model.airplay = nil
        model.activity = true
        model.airplay = route
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
    @Test("A call shows the phone and its time, or the caller and a handset, and takes its turn after music")
    @MainActor
    func calls() {
        let ringing = CallShown(name: "Alex Morgan", over: "FaceTime", app: nil, phase: .ringing)
        let connected = CallShown(name: "Alex Morgan", over: "FaceTime", app: nil, phase: .connected(since: .now))
        #expect(ringing.initials == "A" && !ringing.isConnected && connected.isConnected)
        #expect(CallShown(name: "", over: "", phase: .ringing).initials == "")
        let model = NotchModel(closedSize: CGSize(width: 185, height: 32), layout: .top, hasCamera: true)
        model.activity = true
        model.airplay = AirPlayRoute(name: "HomePod", symbol: "homepod")
        #expect(model.activities.first == .music)
        model.call = connected
        // Both show, in the order they came: music keeps the notch, AirPlay detached, the call next.
        #expect(model.activities == [.music, .airplay, .call] && model.musicShown)
        // Music stops: AirPlay has the notch and the call is detached; music again comes after.
        model.activity = false
        #expect(model.activities == [.airplay, .call] && model.detached == .call)
        model.airplay = nil
        model.activity = true
        model.airplay = AirPlayRoute(name: "HomePod", symbol: "homepod")
        // The call first, with the notch, music detached in its trailing side's place.
        #expect(model.activities == [.call, .music, .airplay] && !model.musicShown)
        #expect(model.detached == .music)
        #expect(model.wing == CallLayout.wing(for: connected, restingHeight: 32) && model.metrics.fold == model.wing - model.pastHousing)
        // Without music, AirPlay is detached instead; alone, the call has both wings, as wide as it needs.
        model.activity = false
        #expect(model.detached == .airplay)
        model.airplay = nil
        #expect(model.detached == nil)
        #expect(model.wing == CallLayout.wing(for: connected, restingHeight: 32))
        model.activity = true
        model.airplay = AirPlayRoute(name: "HomePod", symbol: "homepod")
        #expect(CallLayout.wing(for: connected, restingHeight: 32) > CallLook.waveWidth)
        // An hour's time takes more room.
        let longer = CallShown(name: "A", over: "F", phase: .connected(since: .now - 3_700))
        #expect(CallLayout.wing(for: longer, restingHeight: 32) > CallLayout.wing(for: connected, restingHeight: 32))
        // Swiped away, the rest come back.
        model.dismissed.insert(.call)
        #expect(model.activities.first != .call)
        // Still going, it comes back by itself a couple of seconds later.
        #expect(NotchController.swipedAway == .seconds(2))
        model.dismissed.remove(.call)
        #expect(model.activities.first == .call)
        model.dismissed.insert(.call)
        // A call coming in is as tall as the Alarm, and stays.
        let alert = NotchAlert(kind: .incomingCall, content: .incomingCall(ringing), spoken: "", stays: true)
        #expect(alert.tall && alert.stays)
    }

    @Test("Opened, a FaceTime or Phone call is laid out as the player: padded all around, its time on the circle's bottom edge")
    @MainActor
    func openedCall() {
        let h: CGFloat = 32
        let ringing = CallShown(name: "Alex Morgan", over: "Phone", app: CallAudio.phone, phase: .ringing)
        #expect(ExpandedCallView.wing(for: ringing, restingHeight: h) == IncomingCallView.wing(for: ringing, restingHeight: h))
        #expect(ExpandedCallView.height(for: ringing, restingHeight: h) == TimerLayout.tallHeight(h))
        let model = NotchModel(closedSize: CGSize(width: 185, height: h), layout: .top, hasCamera: true)
        model.call = CallShown(name: "Alex Morgan", over: "Phone", app: CallAudio.phone, phase: .connected(since: .now))
        model.expanded = .call
        model.state = .open
        // The padding all around, 14 at the top and the bottom alike; the caller's row as tall as the
        // circle; a phone's gap between the rows, to a whole point, and the buttons.
        let side = TimerLayout.content(h)
        let tall = PlayerLayout.padding * 2 + side + (side * 50 / 150).rounded() + side
        #expect(tall == 142)
        #expect(model.metrics.height == tall)
        #expect(ExpandedCallView.height(for: model.call!, restingHeight: h) == tall)
        #expect(model.metrics.bodyWidth == 185 + 2 * ExpandedCallView.wing(for: model.call!, restingHeight: h))
        // As wide as the caller's circle needs to stay as far from the camera as the player's cover,
        // or the buttons, 14 in from each end, if they need more: one more for ending it.
        var ending = model.call!
        ending.canEnd = true
        let buttons = CGFloat(ExpandedCallView.connectedButtons(for: ending))
        #expect(Int(buttons) == ExpandedCallView.connectedButtons(for: model.call!) + 1)
        let circle = PlayerLayout.padding + side + PlayerLayout.besideCamera
        // The buttons as far apart as on a phone: 63 pixels for its 150 pixel buttons.
        let row = 28 + buttons * side + (buttons - 1) * side * 63 / 150
        #expect(isClose(ExpandedCallView.width(for: ending, restingHeight: h, closedWidth: 185), 185 + 2 * max(circle, (row - 185) / 2), tolerance: 0.01))
        #expect(ExpandedCallView.width(for: ending, restingHeight: h, closedWidth: 185) > 350)
        #expect(ExpandedCallView.wing(for: ending, restingHeight: h) >= circle)
    }

    @Test("Opened, a FaceTime or Phone call's time stands on the caller's circle's bottom edge, the name above it clear of the camera")
    @MainActor
    func openedCallTimeOnCircle() throws {
        let h: CGFloat = 32
        // Seventeen seconds: a 1 and a 7, whose bottoms are flat, on the baseline.
        let call = CallShown(name: "ALEX", over: "Phone", app: CallAudio.phone, phase: .connected(since: .now - 17.5))
        let width = ExpandedCallView.width(for: call, restingHeight: h, closedWidth: 185)
        let view = ExpandedCallView(call: call, restingHeight: h, width: width)
            .environment(\.colorScheme, .dark)
            .background(Color.black)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        let w = image.width, rows = image.height
        var pixels = [UInt8](repeating: 0, count: w * rows * 4)
        pixels.withUnsafeMutableBytes { raw in
            let context = CGContext(
                data: raw.baseAddress, width: w, height: rows, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: rows))
        }
        func pixel(_ x: Int, _ y: Int) -> (Int, Int, Int) {
            let at = (y * w + x) * 4
            return (Int(pixels[at]), Int(pixels[at + 1]), Int(pixels[at + 2]))
        }
        // The circle: its colors, in the corner. The words: everything lit to its right, down to the circle's bottom and a little past.
        let edge = Int(PlayerLayout.padding * 2), side = Int(TimerLayout.content(h) * 2)
        let circleRows = (0..<rows).filter { y in
            (edge..<(edge + side)).contains { x in
                let c = pixel(x, y)
                return max(c.0, c.1, c.2) > 60
            }
        }
        let circleBottom = try #require(circleRows.max())
        let wordsFrom = edge + side + Int(CallLayout.wordsGap(h) * 2)
        let lit = (0..<min(circleBottom + 12, rows)).filter { y in (wordsFrom..<(wordsFrom + 120)).contains { x in max(pixel(x, y).0, pixel(x, y).1) > 90 } }
        let wordsTop = try #require(lit.min()), wordsBottom = try #require(lit.max())
        // The time's flat digits end on the circle's last row; the name's capitals start 4 below the camera.
        #expect(abs(wordsBottom - circleBottom) <= 1)
        #expect(CGFloat(wordsTop) / 2 >= h + PlayerLayout.cameraGap - 0.5)
        #expect(CGFloat(circleRows.min() ?? 0) / 2 == PlayerLayout.padding)
    }

    @Test("Hover and proximity keep the compact footprint fixed before opening")
    @MainActor
    func fixedHoverFootprint() {
        let model = NotchModel(closedSize: CGSize(width: 185, height: 32), layout: .top, hasCamera: true)
        model.airplay = AirPlayRoute(name: "HomePod", symbol: "homepod")
        let rest = model.metrics
        for proximity: CGFloat in [0, 0.5, 1] {
            model.proximity = proximity
            for state in [NotchState.closed, .peek] {
                let target = model.metrics(for: state)
                #expect(target.bodyWidth == rest.bodyWidth && target.height == rest.height)
            }
        }
    }

    @Test("Pointer feedback preserves activity geometry and whether a recording can open")
    @MainActor
    func activityHoverFootprint() {
        let model = NotchModel(closedSize: CGSize(width: 185, height: 32), layout: .top, hasCamera: true)
        model.screenRecording = .countdown(from: 3, until: .now + 3)
        let rest = model.metrics(for: .closed)
        model.proximity = 1
        // A countdown keeps its footprint and opens to nothing.
        #expect(model.opensToNothing)
        #expect(model.metrics(for: .closed).height == rest.height && model.metrics(for: .peek).height == rest.height)
        // In the bubble beside a timer, the same.
        model.timer = .running(until: .now + 300, total: 300)
        model.screenRecording = nil
        model.screenRecording = .countdown(from: 3, until: .now + 3)
        #expect(model.detached == .screenRecording)
        #expect(model.opensToNothing(fromBubble: true) && !model.opensToNothing(fromBubble: false))
        model.timer = nil
        // Recording, it has its opened view.
        model.screenRecording = .recording(since: .now)
        #expect(!model.opensToNothing)
        #expect(model.metrics(for: .closed).height == model.restingHeight)
        // A rung timer is as tall as it gets.
        model.screenRecording = nil
        model.alert = NotchAlert(kind: .timerDone, content: .timerDone(length: 300, name: "Timer"), spoken: "Timer done", stays: true)
        #expect(model.restingTall)
        #expect(model.metrics(for: .closed).height == model.restingHeight)
    }

    @Test("Beside a bubble, the notch's folded end reaches past the camera housing, its corner as round as the other end's covering the housing's")
    @MainActor
    func foldedEndPastHousing() {
        let model = NotchModel(closedSize: CGSize(width: 185, height: 32), layout: .top, hasCamera: true)
        model.timer = .running(until: .now + 300, total: 300)
        model.timerWing = SystemActivityView.wing(for: .timer(model.timer!), restingHeight: 32)
        #expect(model.metrics(for: .closed).fold == 0)
        model.stopwatch = .running(since: .now)
        let m = model.metrics(for: .closed)
        let round = model.corners.radii(forHeight: 32, wingEnds: 1).bottom, housing = model.corners.radii(forHeight: 32, wingEnds: 0).bottom
        #expect(round > housing)
        #expect(isClose(model.pastHousing, (round - housing) * 1.25))
        // Its end, from the middle: past the housing's by that much.
        #expect(isClose(m.bodyWidth / 2 - m.fold, 185 / 2 + model.pastHousing))
    }

    @Test("macOS's own Live Activities in the menu bar are known by their pills' names")
    @MainActor
    func menuBarLiveActivities() {
        #expect("live-activity-pill-com.apple.MediaRemoteUIService".hasPrefix(MenuBarLiveActivities.pillPrefix))
        #expect(!"av-module-pill-45E3385A".hasPrefix(MenuBarLiveActivities.pillPrefix))
        #expect(Preferences.hideMenuBarLiveActivities == "hideMenuBarLiveActivities")
    }

    @Test("Opened, another app's call is one row as tall as the Alarm: the name, the speaker and, where it can be done, End")
    @MainActor
    func openedOtherAppCall() {
        let h: CGFloat = 32
        let side = TimerLayout.content(h)
        var call = CallShown(name: "Alex Morgan", over: "Discord", app: "com.hnc.Discord", phase: .connected(since: .now))
        #expect(!call.throughApple)
        #expect(ExpandedCallView.height(for: call, restingHeight: h) == TimerLayout.tallHeight(h))
        // The speaker alone, then End too: each wing as wide as the buttons need, from the camera to the end.
        #expect(ExpandedCallView.connectedButtons(for: call) == 1)
        #expect(isClose(ExpandedCallView.wing(for: call, restingHeight: h), LiveActivityView.cameraGap + side + PlayerLayout.padding))
        call.canEnd = true
        #expect(ExpandedCallView.connectedButtons(for: call) == 2)
        #expect(
            isClose(
                ExpandedCallView.wing(for: call, restingHeight: h),
                LiveActivityView.cameraGap + side * 2 + h * TimerLayout.buttonGap + PlayerLayout.padding))
        // No wider for a long name, which runs on under the camera.
        var long = call
        long.name = "Alexandra Montgomery-Fitzgerald"
        #expect(ExpandedCallView.wing(for: long, restingHeight: h) == ExpandedCallView.wing(for: call, restingHeight: h))
    }

    @Test("Only a FaceTime or Phone caller has a picture, as the iPhone pictures one; other apps' have none")
    @MainActor
    func callPicture() {
        let h: CGFloat = 32
        #expect(CallShown(name: "A", over: "Phone", app: CallAudio.phone, phase: .ringing).throughApple)
        #expect(CallShown(name: "A", over: "FaceTime", app: CallAudio.faceTime, phase: .ringing).throughApple)
        let other = CallShown(name: "A", over: "Discord", app: "com.hnc.Discord", phase: .ringing)
        #expect(!other.throughApple)
        // Where the first line decides the width, without the picture the words start at the padding.
        var long = other
        long.line = "Incoming video call from a long way away"
        var apple = long
        apple.app = CallAudio.faceTime
        #expect(
            abs(
                IncomingCallView.wing(for: apple, restingHeight: h) - IncomingCallView.wing(for: long, restingHeight: h)
                    - (CallLayout.round(h) + CallLayout.wordsGap(h))) < 0.01)
        // The serif initial is half the circle, for the iPhone's cap height of about 0.35 of it.
        #expect(CallLook.pictureInitials == 0.5)
    }

    /// A made-up contact's photo, one color, or, with `half`, two: never a real contact's.
    private func photo(_ color: NSColor, half: NSColor? = nil) -> Data {
        let image = NSImage(size: NSSize(width: 60, height: 60), flipped: false) { rect in
            color.setFill()
            rect.fill()
            if let half {
                half.setFill()
                NSRect(x: 0, y: 0, width: 60, height: 30).fill()
                NSColor.white.setFill()
                NSRect(x: 10, y: 35, width: 15, height: 15).fill()
            }
            return true
        }
        return NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
    }

    @MainActor
    private func settle(_ photos: CallPhotos, until done: @escaping @MainActor () -> Bool) async {
        for _ in 0..<100 where !done() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    @Test("A FaceTime or Phone caller's photo comes from Contacts: one contact's, none without one or without permission")
    @MainActor
    func callPhotos() async {
        let call = CallShown(name: "Alex Morgan", over: "Phone", app: CallAudio.phone, phase: .connected(since: .now))
        let card = CallPhotos.Card(photo: photo(.systemBlue))
        // One contact with a photo: it shows.
        let one = CallPhotos(book: .init(allowed: { true }, ask: { true }, cards: { name, _ in name == "Alex Morgan" ? [card] : [] }))
        one.look(for: call, face: nil)
        await settle(one) { one.photo(for: call) != nil }
        #expect(one.photo(for: call) != nil)
        // Only for that caller.
        var other = call
        other.name = "Sam Rivers"
        #expect(one.photo(for: other) == nil)
        // A contact without a photo: the initial.
        let plain = CallPhotos(book: .init(allowed: { true }, ask: { true }, cards: { _, _ in [CallPhotos.Card(photo: nil)] }))
        plain.look(for: call, face: nil)
        await settle(plain) { false }
        #expect(plain.photo(for: call) == nil)
        // Contacts not allowed: never read, the initial.
        let denied = CallPhotos(
            book: .init(
                allowed: { false }, ask: { true },
                cards: { _, _ in
                    Issue.record("read without permission")
                    return [card]
                }))
        denied.look(for: call, face: nil)
        await settle(denied) { false }
        #expect(denied.photo(for: call) == nil)
        // Not asked yet: asked once, and refused, the initial.
        let refused = CallPhotos(book: .init(allowed: { nil }, ask: { false }, cards: { _, _ in [card] }))
        refused.look(for: call, face: nil)
        await settle(refused) { false }
        #expect(refused.photo(for: call) == nil)
        // Another app's caller is never looked up.
        let discord = CallShown(name: "Alex Morgan", over: "Discord", app: "com.hnc.Discord", phase: .connected(since: .now))
        one.forget()
        one.look(for: discord, face: nil)
        await settle(one) { false }
        #expect(one.photo(for: discord) == nil)
    }

    @Test("Two contacts with the caller's name are told apart by the popup's own picture of the caller")
    @MainActor
    func callPhotoSameName() async throws {
        let call = CallShown(name: "Alex Morgan", over: "FaceTime", app: CallAudio.faceTime, phase: .connected(since: .now))
        let blue = photo(.systemBlue, half: .systemOrange)
        let green = photo(.systemGreen, half: .systemPurple)
        let photos = CallPhotos(book: .init(allowed: { true }, ask: { true }, cards: { _, _ in [.init(photo: blue), .init(photo: green)] }))
        // Until the popup's picture is read, no one's photo.
        photos.look(for: call, face: nil)
        await settle(photos) { false }
        #expect(photos.photo(for: call) == nil)
        // The popup shows the second contact's photo, a little darker and smaller.
        let shown = try #require(NSImage(data: green)?.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let face = try #require(CallFace.cells(of: shown)).map { UInt8(Double($0) * 0.85) }
        photos.look(for: call, face: face)
        let chosen = try #require(photos.photo(for: call))
        #expect(chosen.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0) }?.colorAt(x: 50, y: 5) != nil)
        let greenCells = CallFace.cells(of: shown)!
        let blueCells = CallFace.cells(of: NSImage(data: blue)!.cgImage(forProposedRect: nil, context: nil, hints: nil)!)!
        #expect(CallFace.pick(face, among: [blueCells, greenCells]) == 1)
        // An initial in the popup is like neither: no one's photo.
        let initial = [UInt8](repeating: 90, count: face.count)
        #expect(CallFace.pick(initial, among: [blueCells, greenCells]) == nil)
        // Two photos as like it: no one's.
        #expect(CallFace.pick(greenCells, among: [greenCells, greenCells]) == nil)
        // A number is looked up as a number.
        #expect(CallPhotos.isNumber("+351 912 345 678") && !CallPhotos.isNumber("Alex Morgan") && !CallPhotos.isNumber("R2"))
        #expect(CallPhotos.same("Álex  Morgan".replacingOccurrences(of: "  ", with: " "), "alex morgan") && !CallPhotos.same("Alex", "Alex Morgan"))
    }

    @Test("Mute mutes the microphone, and what the notch muted is unmuted as the call ends")
    @MainActor
    func callMute() {
        // Faked: a test never touches the real microphone.
        let microphone = CallMicrophone(fakes: true)
        #expect(microphone.available && !microphone.muted)
        microphone.toggle()
        #expect(microphone.muted && microphone.mutedHere)
        microphone.callEnded()
        #expect(!microphone.muted && !microphone.mutedHere)
        // Unmuted again before the end, nothing's left to undo.
        microphone.toggle()
        microphone.toggle()
        #expect(!microphone.muted && !microphone.mutedHere)
        microphone.callEnded()
        #expect(!microphone.muted)
    }

    @Test("Both voices cross the whole waveform from their own side, fading as they go, and overlap rather than split it")
    func callVoices() {
        let count = CallLook.bars
        #expect(count == 14)
        // Both speaking steadily, as loud as can be.
        let steady = CallVoices.shaped(theirs: Array(repeating: 1, count: count), yours: Array(repeating: 1, count: count))
        #expect(steady.count == 14)
        // The other person's, strongest at the left end, fading to the right, and still there at the right end.
        #expect(steady[0].theirs == 1 && steady[13].theirs == CallLook.farthest)
        #expect(zip(steady, steady.dropFirst()).allSatisfy { $0.theirs > $1.theirs })
        // Yours the other way round.
        #expect(steady[13].yours == 1 && steady[0].yours == CallLook.farthest)
        #expect(zip(steady, steady.dropFirst()).allSatisfy { $0.yours < $1.yours })
        // Not cut in half: each voice is still taller than a dot past the middle, and reaches the far
        // side, faint there, as the iPhone's middle bars are little more than dots.
        let core = CallLook.core / CallLook.waveHeight
        #expect(steady[7].theirs > core && steady[6].yours > core)
        #expect(steady.allSatisfy { $0.theirs > 0 && $0.yours > 0 })
        // Each newest at its own end, older moments further in: one word goes across.
        let word = [CGFloat(1)] + Array(repeating: 0, count: count - 1)
        let spoke = CallVoices.shaped(theirs: word, yours: [])
        #expect(spoke[0].theirs == 1 && spoke[1...].allSatisfy { $0.theirs == 0 } && spoke.allSatisfy { $0.yours == 0 })
        let older = CallVoices.shaped(theirs: Array(repeating: 0, count: 5) + [1] + Array(repeating: 0, count: count - 6), yours: word)
        #expect(older[5].theirs == CallLook.fade(across: 5.0 / 13) && older[13].yours == 1)
        // Drawn overlapping: the louder in its color, yellow as far as the quieter overlaps it.
        let parts = CallLook.layers(CallBar(theirs: 0.3, yours: 0.8))
        #expect(parts.louder == 0.8 && !parts.theirs && parts.overlap == 0.3)
        // Nobody speaking: both dots, overlapping, a yellow dot.
        #expect(CallLook.layers(CallBar()).overlap == 0)
        // Louder than loud is as loud as can be.
        #expect(CallVoices.shaped(theirs: Array(repeating: 3, count: count), yours: [])[0].theirs == 1)
        // Not an even ramp: each bar flickers on its own, between most and all of the voice.
        for time in stride(from: 0.0, through: 3, by: 0.1) {
            let ripples = (0..<count).map { CallVoices.ripple($0, theirs: true, at: time) }
            #expect(ripples.allSatisfy { $0 >= CallVoices.rippleFloor - 0.0001 && $0 <= 1.0001 })
            #expect(Set(ripples.map { Int($0 * 100) }).count > 4)
        }
        #expect(CallVoices.ripple(3, theirs: true, at: 1) != CallVoices.ripple(3, theirs: false, at: 1))
        // Nobody speaking: still dots, however it flickers.
        let quiet = CallVoices.shaped(theirs: [], yours: [], ripples: Array(repeating: (theirs: 0.7, yours: 0.9), count: count))
        #expect(quiet.allSatisfy { $0.theirs == 0 && $0.yours == 0 })
    }

    @Test("Closed, the phone stands as the iPhone's and both ends are as far in as its")
    @MainActor
    func callClosedEnds() {
        let call = CallShown(name: "Caller", over: "Phone", phase: .connected(since: .now - 30))
        let wing = CallLayout.wing(for: call, restingHeight: 32)
        #expect(CallLook.phoneTilt == 15)
        // The waveform's side: its bars, the iPhone's distance from the end, and the camera's gap.
        #expect(wing >= CallLook.waveWidth + 32 * CallLook.waveEdge + LiveActivityView.cameraGap)
        #expect(abs(32 * (CallLook.phoneEdge + 0.078) - 8.44) < 0.05)
        #expect(abs(32 * CallLook.waveEdge - 9.31) < 0.05)
    }

    @Test("A bar is the louder voice's color past the yellow where both overlap, and a yellow dot when quiet")
    @MainActor
    func callBarColors() throws {
        let them = try #require(CallLook.voice(theirs: true).usingColorSpace(.displayP3))
        let you = try #require(CallLook.voice(theirs: false).usingColorSpace(.displayP3))
        let yellow = try #require(CallLook.yellow.usingColorSpace(.displayP3))
        #expect(them.greenComponent > them.redComponent && you.redComponent > you.greenComponent)
        #expect(them.alphaComponent == 1 && you.alphaComponent == 1)
        // The iPhone's yellow is about the green and the orange together, the lighter of each.
        #expect(abs(yellow.redComponent - max(them.redComponent, you.redComponent)) < 12.0 / 255)
        #expect(abs(yellow.greenComponent - max(them.greenComponent, you.greenComponent)) < 12.0 / 255)
        #expect(abs(yellow.blueComponent - max(them.blueComponent, you.blueComponent)) < 12.0 / 255)
        // Quiet: a dot, the smallest a bar is, all yellow; loud: as tall as the waveform, on its middle,
        // its yellow thinner than a dot, as the iPhone's tall bars are.
        let quiet = CallLook.barFrame(0, level: 0, height: 14, core: 3.7)
        let loud = CallLook.barFrame(0, level: 1, height: 14, core: 3.7)
        #expect(quiet.height == 3.7 && loud.height == 14 && quiet.midY == loud.midY)
        #expect(CallLook.yellowFrame(of: quiet, overlap: 0, core: 3.7, height: 14) == quiet)
        let thin = CallLook.yellowFrame(of: loud, overlap: 0, core: 3.7, height: 14)
        #expect(abs(thin.height - 3.7 * 0.6) < 0.001 && thin.midY == loud.midY)
        // Where the quieter voice overlaps more, as much yellow.
        #expect(CallLook.yellowFrame(of: loud, overlap: 0.5, core: 3.7, height: 14).height == 7)
    }

    @Test("macOS's popup's waveform is read for each voice: the other person on its left, you on its right")
    func callPopupLevels() {
        let width = 180, height = 36, rowBytes = width * 4
        var pixels = [UInt8](repeating: 20, count: rowBytes * height)
        // The first bar, on the left, at its tallest; the rest dots.
        for y in 4..<31 { for x in 1..<6 { pixels[y * rowBytes + x * 4 + 1] = 220 } }
        let levels = pixels.withUnsafeBufferPointer { CallPopup.levels(pixels: $0, width: width, height: height, rowBytes: rowBytes) }
        #expect(levels.theirs == 1)
        #expect(levels.yours == 0)
    }

    @Test("Clicked, a call goes to the app it's in, not to the helper its sound comes from")
    func callGoesToItsApp() {
        #expect(CallAudio.appBundle(of: "com.hnc.Discord.helper.Renderer") == "com.hnc.Discord")
        #expect(CallAudio.appBundle(of: "us.zoom.xos") == "us.zoom.xos")
    }

    @Test("On a call, an output chosen is put back twice at most, for a few seconds, if macOS takes it away")
    func callOutputKept() {
        let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let choice = AudioOutput.Choice(device: 72, at: t0, left: AudioOutput.Choice.putBacks)
        #expect(choice.putsBack(84, at: t0 + 1.3))
        #expect(!choice.putsBack(72, at: t0 + 1.3))
        #expect(!choice.putsBack(84, at: t0 + AudioOutput.Choice.keptFor + 0.1))
        var spent = choice
        spent.left = 0
        #expect(!spent.putsBack(84, at: t0 + 1))
    }

    @Test("macOS's hidden aggregate, made while an app records and plays at once, isn't an output")
    func hiddenAggregateIsNoOutput() {
        #expect(AudioOutput.isSystemAggregate(uid: "CADefaultDeviceAggregate-4348-0"))
        #expect(!AudioOutput.isSystemAggregate(uid: "BuiltInSpeakerDevice"))
    }

    @Test("AirPods playing are pictured as their model, kept when a later report leaves it out, and asked for again for a while")
    func outputModelKept() {
        var first = DeviceWatch.BluetoothInfo()
        first.product = 0x2024
        first.vendor = 0x4C
        first.kind = "Headphones"
        // Listed again with their battery but not yet their model: the model stays.
        var later = DeviceWatch.BluetoothInfo()
        later.battery = 80
        let kept = AudioOutput.kept(first, later)
        #expect(kept.product == 0x2024 && kept.vendor == 0x4C && kept.kind == "Headphones" && kept.battery == 80)
        #expect(kept.modelSymbols?.symbol == first.modelSymbols?.symbol)
        // Their model is macOS's own symbol for them, not headphones.
        #expect(first.modelSymbols?.symbol.hasPrefix("airpods") == true)
        // Not told the model yet, macOS is asked again over about twenty seconds.
        #expect(AudioOutput.modelRetries.reduce(0, +) >= 15)
    }

    @Test("Opened, a call is no wider for a long name, which runs on under the camera")
    @MainActor
    func openedCallName() {
        let h: CGFloat = 32
        func call(_ name: String, _ phase: CallShown.Phase) -> CallShown { CallShown(name: name, over: "Phone", phase: phase, canEnd: true) }
        let since = Date.now - 14
        #expect(
            ExpandedCallView.wing(for: call("Alexandra Montgomery-Fitzgerald", .connected(since: since)), restingHeight: h)
                == ExpandedCallView.wing(for: call("Al", .connected(since: since)), restingHeight: h))
        #expect(
            IncomingCallView.wing(for: call("Alexandra Montgomery-Fitzgerald", .ringing), restingHeight: h)
                == IncomingCallView.wing(for: call("Al", .ringing), restingHeight: h))
    }

    @Test("A waveform's bar is drawn the same way whether it's a dot or tall, so one turns into the other cleanly")
    func waveformCapsule() {
        func elements(_ rect: CGRect) -> [CGPathElementType] {
            let path = CGMutablePath()
            WaveformGlyph.addCapsule(rect, to: path)
            var types: [CGPathElementType] = []
            path.applyWithBlock { types.append($0.pointee.type) }
            return types
        }
        #expect(elements(CGRect(x: 0, y: 0, width: 4, height: 4)) == elements(CGRect(x: 0, y: 0, width: 4, height: 20)))
        #expect(CGMutablePath().isEmpty)
    }

    @Test("Swiped up, what's being done stays, a call or a recording; anything else going on steps away")
    func swipeUp() {
        for activity: NotchModel.Activity in [.call, .screenRecording, .voiceMemo] {
            #expect(!NotchController.stepsAway(activity))
        }
        for activity: NotchModel.Activity in [.music, .airdrop, .timer, .stopwatch, .airplay] {
            #expect(NotchController.stepsAway(activity))
        }
    }

    @Test("What a swipe puts away, and a call or a recording too, can be put away from the menu by name")
    func putAwayFromMenu() {
        #expect(NotchController.putAwayTitle(alert: nil, first: .music) == "Hide Music")
        #expect(NotchController.putAwayTitle(alert: nil, first: .airplay) == "Hide AirPlay")
        #expect(NotchController.putAwayTitle(alert: .incomingCall, first: .music) == "Hide Call")
        #expect(NotchController.putAwayTitle(alert: .lowBattery, first: nil) == "Hide Low Battery")
        // A rung timer has the menu's own Stop; an announcement that's gone in a moment, nothing.
        #expect(NotchController.putAwayTitle(alert: .timerDone, first: .timer) == nil)
        #expect(NotchController.putAwayTitle(alert: .charging, first: .music) == nil)
        #expect(NotchController.putAwayTitle(alert: nil, first: nil) == nil)
    }

    @Test("Low Battery waits while its button's being reached; announcements without one don't")
    func lowBatteryWaits() {
        #expect(NotchAlert.Kind.lowBattery.hasButton)
        #expect(!NotchAlert.Kind.charging.hasButton && !NotchAlert.Kind.device.hasButton)
    }

    @Test("With Increase Contrast, Accept's phone reads on a darker green")
    func acceptWithContrast() {
        #expect(CallLook.accept(.increased) == CallLook.acceptContrast)
        #expect(CallLook.accept(.standard) == CallLook.accept)
    }

    @Test("A call in the bubble shows its time as large as fits, never under the Mac's smallest text, and the phone only where both fit")
    func callBubble() {
        #expect(CallBubbleMark.text(5) == "0:05")
        #expect(CallBubbleMark.text(754) == "12:34")
        #expect(CallBubbleMark.text(3753) == "62:33")
        #expect(CallBubbleMark.text(100 * 60 + 5) == "1:40")
        let short = CallBubbleMark.fit("0:05", restingHeight: 32), long = CallBubbleMark.fit("12:34", restingHeight: 32)
        #expect(short.size <= LiveActivityView.textSize(for: 32) && short.size > long.size)
        #expect(long.size >= StopwatchReading.smallest)
        // At the usual notch, the phone and the time don't fit together.
        #expect(!short.phone && !long.phone)
        // A notch twice as tall has room for both.
        #expect(CallBubbleMark.fit("0:05", restingHeight: 64).phone)
    }

    @Test("The stopwatch's hundredths are never under the Mac's smallest text")
    func stopwatchSmallest() {
        #expect(13.6 * StopwatchReading.share(13.6) >= 10)
        #expect(StopwatchReading.share(30) == StopwatchReading.small)
    }

    @Test("A call's own time always wins: a reading missed keeps it, and a relaunch takes it, never zero")
    func callClock() throws {
        let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
        func shown(_ start: Date?, at date: Date) -> Int? { start.map { Int(date.timeIntervalSince($0)) } }
        // Glance opened mid-call: Discord's time, not zero.
        var clock = CallClock()
        let first = clock.going(shown: 1725, at: t0, waitsForTime: true)
        let start = try #require(first)
        #expect(shown(start, at: t0) == 1725)
        // A reading missed keeps it.
        let missed = clock.going(shown: nil, at: t0 + 5, waitsForTime: true)
        #expect(missed == start)
        #expect(shown(missed, at: t0 + 5) == 1730)
        // Each reading narrows it to Discord's tick, partway through a second, and it then says
        // what Discord does.
        let ticks = t0 - 1725.4
        for step in 1...12 {
            let at = t0 + Double(step) * 1.37
            let discord = Int(at.timeIntervalSince(ticks))
            let read = clock.going(shown: discord, at: at, waitsForTime: true)
            #expect(shown(read, at: at) == discord)
        }
        // Discord's time wins over Glance's own count.
        var own = CallClock()
        let counted = own.going(shown: nil, at: t0, waitsForTime: false)
        #expect(counted == t0)
        let corrected = own.going(shown: 300, at: t0 + 2, waitsForTime: false)
        #expect(shown(corrected, at: t0 + 2) == 300)
        // Discord's time is waited for a moment, then counted from when the call was heard.
        var waiting = CallClock()
        let soon = waiting.going(shown: nil, at: t0, waitsForTime: true)
        let still = waiting.going(shown: nil, at: t0 + 2, waitsForTime: true)
        let after = waiting.going(shown: nil, at: t0 + 3.5, waitsForTime: true)
        #expect(soon == nil && still == nil && after == t0)
        // Gone a moment, the same call keeps its time; gone longer, it's forgotten.
        var back = CallClock()
        let kept = back.going(shown: 90, at: t0, waitsForTime: true)
        back.ended(at: t0 + 1)
        back.ended(at: t0 + 6)
        let returned = back.going(shown: nil, at: t0 + 7, waitsForTime: true)
        #expect(returned == kept)
        back.ended(at: t0 + 8)
        back.ended(at: t0 + 19)
        #expect(back == CallClock())
        // Another time altogether, moving on: another call, taken once it's seen to move.
        var other = CallClock()
        _ = other.going(shown: 500, at: t0, waitsForTime: true)
        let doubted = other.going(shown: 3, at: t0 + 10, waitsForTime: true)
        #expect(shown(doubted, at: t0 + 10) == 510)
        let next = other.going(shown: 4, at: t0 + 11, waitsForTime: true)
        #expect(shown(next, at: t0 + 11) == 4)
        // Behind a full-screen app, Discord stopped drawing and went on saying 41:28: read once a
        // second, that started the time again every other second (the user's video, 2026-11-07).
        // Now it counts on from the call's start, and takes Discord's time back once it moves.
        var hidden = CallClock()
        let callStart = t0 - 2484.4
        var readAt = t0
        while readAt < t0 + 14 {
            let frozen = readAt >= t0 + 4.3 && readAt < t0 + 12.5
            let discord = frozen ? 2488 : Int(readAt.timeIntervalSince(callStart))
            let going = hidden.going(shown: discord, at: readAt, waitsForTime: true)
            let read = try #require(going)
            #expect(abs(read.timeIntervalSince(callStart)) < 0.7)
            readAt += 1.03
        }
        // Opened while its time was frozen, it counts from what it said, then takes the real time
        // once it moves.
        var late = CallClock()
        _ = late.going(shown: 100, at: t0, waitsForTime: true)
        _ = late.going(shown: 100, at: t0 + 2, waitsForTime: true)
        _ = late.going(shown: 160, at: t0 + 3, waitsForTime: true)
        let caughtUp = late.going(shown: 161, at: t0 + 4, waitsForTime: true)
        #expect(shown(caughtUp, at: t0 + 4) == 161)
        // macOS's popup: only its time seen ticking on twice, a second apart and agreeing, says
        // when it started; a still picture, or two of its frames read in turn, never does.
        var stillPicture = CallPopup.Ticks(last: 2488, at: t0)
        for step in 1...30 {
            let seconds = step.isMultiple(of: 2) ? 2488 : 2487
            #expect(stillPicture.saw(seconds, at: t0 + Double(step) * 0.1) == nil)
        }
        let popupStart = t0 - 2487.55
        var ticking = CallPopup.Ticks(last: 2487, at: t0)
        var found: Date?
        var at = t0
        while found == nil, at < t0 + 3 {
            at += 0.1
            found = ticking.saw(Int(at.timeIntervalSince(popupStart)), at: at)
        }
        let settled = try #require(found)
        #expect(abs(settled.timeIntervalSince(popupStart)) < 0.1)
        #expect(at.timeIntervalSince(t0) < 2.1)
        // Past an hour, in either way of writing it.
        #expect(CallPopup.elapsed(in: "Voice Connected 59:59") == 3599)
        #expect(CallPopup.elapsed(in: "Voice Connected 1:00:00") == 3600)
        #expect(CallPopup.elapsed(in: "01:02:03") == 3723)
        #expect(CallPopup.elapsed(in: "60:00") == 3600)
    }

    @Test("Discord's call link gives the name and the time, in whatever words it's in")
    @MainActor
    func discordReading() {
        #expect(DiscordCall.reading(name: "Gilberto Fuseta", time: "05:42") == .init(name: "Gilberto Fuseta", elapsed: 342))
        #expect(DiscordCall.reading(name: "  ", time: "05:42") == nil)
        #expect(DiscordCall.reading(name: "Gilberto", time: nil) == .init(name: "Gilberto", elapsed: nil))
        // The link's words: with one person, their name on its own; on a group call, the names in
        // one line beside the time.
        let one = DiscordCall.words(afterStatus: 1, in: ["Voice Connected", "Gilberto Fuseta", "04:05"])
        #expect(one.name == "Gilberto Fuseta" && one.time == "04:05")
        let group = DiscordCall.words(afterStatus: 1, in: ["Voice Connected", "Alex Morgan, Sam Lee, sam_99", "19:28"])
        #expect(group.name == "Alex Morgan, Sam Lee, sam_99" && group.time == "19:28")
        let untimed = DiscordCall.words(afterStatus: 1, in: ["Voice Connected", "Alex Morgan"])
        #expect(untimed.name == "Alex Morgan" && untimed.time == nil)
        #expect(DiscordCall.words(afterStatus: 1, in: ["Voice Connected", "19:28"]).name == nil)
        // Discord's call coming in, by who it's from.
        #expect(DiscordCall.ringingName(from: "unread, Gilberto Fuseta (direct message), Incoming Call, Online") == "Gilberto Fuseta")
        #expect(DiscordCall.ringingName(from: "Gilberto Fuseta (direct message), Ongoing Call, Online") == nil)
        #expect(CallVoices.eased(0, towards: 1) > CallVoices.eased(1, towards: 0) - 0.5)
    }

    @Test("macOS's banners that say what the notch says are told from the rest, by their names")
    func systemBanners() {
        #expect(MenuBarBanners.Banner(identifier: "low-battery-system-banner") == .lowBattery)
        #expect(MenuBarBanners.Banner(identifier: "smart-routing-system-banner") == .device)
        #expect(MenuBarBanners.Banner(identifier: "accessory-system-banner-keyboard") == .device)
        for other in ["volume-system-banner", "display-brightness-system-banner", "focus-system-banner", "listening-mode-system-banner"] {
            #expect(MenuBarBanners.Banner(identifier: other) == nil)
        }
        #expect(MenuBarBanners.Banner(identifier: nil) == nil)
    }

    @Test("Notification Center's window keeps one row of points on screen while it's held")
    func notificationWindowAway() {
        #expect(NotificationWindow.away(from: .zero, height: 982) == CGPoint(x: 0, y: -981))
        #expect(NotificationWindow.away(from: CGPoint(x: 1512, y: -300), height: 1080) == CGPoint(x: 1512, y: -1379))
    }

    @Test("A caller's circle has their name's first letter, as the iPhone's had for three words, and none for a number")
    func callInitials() {
        func initials(_ name: String) -> String { CallShown(name: name, over: "Phone", phase: .ringing).initials }
        #expect(initials("Morgan") == "M")
        #expect(initials("Alex Morgan") == "A")
        #expect(initials("  maria da Silva") == "M")
        #expect(initials("+351 912 345 678") == "")
        #expect(initials("") == "")
    }

    @Test("Every state of a call can be tried on its own, each by its name")
    func callScenes() {
        for name in ["call", "callRinging", "callSwiped", "callOutgoing", "callOngoing", "callLong", "callNumber", "callOtherApp", "callUnread"] {
            #expect(ActivityBench.parse(["Glance", "--bench", name])?.scenes.first?.rawValue == name)
        }
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

    @Test("The words on macOS's popup for a call are told from what else it reads, as a real call's were")
    func callPopupWords() {
        let lines = [
            CallPopup.Line(text: "Ac", box: CGRect(x: 0.05, y: 0.62, width: 0.08, height: 0.2)),
            CallPopup.Line(text: "Using Your iPhone - 0:11", box: CGRect(x: 0.2, y: 0.58, width: 0.39, height: 0.12)),
            CallPopup.Line(text: "Silva", box: CGRect(x: 0.2, y: 0.71, width: 0.08, height: 0.09)),
            CallPopup.Line(text: "si", box: CGRect(x: 0.25, y: 0.12, width: 0.05, height: 0.1)),
        ]
        let words = CallPopup.words(in: lines)
        #expect(words.name == "Silva")
        #expect(words.detail == "Using Your iPhone - 0:11")
        #expect(CallPopup.words(in: []).name == nil)
    }

    @Test("A call's time is read from the end of its popup's line")
    func callPopupTime() {
        #expect(CallPopup.elapsed(in: "Using Your iPhone - 4:37") == 277)
        #expect(CallPopup.elapsed(in: "Using Your iPhone - 1:02:03") == 3723)
        #expect(CallPopup.elapsed(in: "Using Your iPhone") == nil)
        #expect(CallPopup.elapsed(in: "Calling...") == nil)
        #expect(CallPopup.elapsed(in: nil) == nil)
        // Between the two readings either side of its changing.
        let before = Date(timeIntervalSinceReferenceDate: 1000)
        let started = CallPopup.started(changedBetween: before, and: before + 0.2, to: 60)
        #expect(started == before + 0.1 - 60)
    }

    @Test("A call's connected once it shows a time, or uses the microphone with nothing left to accept")
    func callPopupPhase() {
        let shown = CallPopup(name: "Silva", detail: "Using Your iPhone - 0:11", red: CGPoint(x: 0.87, y: 0.65))
        #expect(CallWatch.connected(shown, microphone: false))
        #expect(shown.readable)
        let ringing = CallPopup(name: "Silva", red: CGPoint(x: 0.7, y: 0.5), green: CGPoint(x: 0.87, y: 0.5))
        #expect(!CallWatch.connected(ringing, microphone: true))
        #expect(CallWatch.connected(CallPopup(), microphone: true))
        #expect(!CallWatch.connected(CallPopup(), microphone: false))
        #expect(!CallPopup(name: "Silva").readable)
        #expect(CallWatch.appleApp(detail: "Using Your iPhone - 0:11", phoneRunning: true).name == "Phone")
        #expect(CallWatch.appleApp(detail: "FaceTime Audio - 0:11", phoneRunning: true).name == "FaceTime")
        #expect(CallWatch.appleApp(detail: nil, phoneRunning: false).name == "FaceTime")
    }

    @Test("A call's popup has its buttons found by color, big and on its right, nothing else")
    func callPopupButtons() {
        let width = 100
        let height = 40
        func picture(_ marks: [(CGRect, [UInt8])]) -> (red: CGPoint?, green: CGPoint?) {
            var pixels = [UInt8](repeating: 30, count: width * height * 4)
            for (rect, color) in marks {
                for y in Int(rect.minY)..<Int(rect.maxY) {
                    for x in Int(rect.minX)..<Int(rect.maxX) {
                        for (channel, value) in color.enumerated() { pixels[(y * width + x) * 4 + channel] = value }
                    }
                }
            }
            return pixels.withUnsafeBufferPointer { CallPopup.buttons(pixels: $0, width: width, height: height) }
        }
        let red: [UInt8] = [196, 10, 10]
        let green: [UInt8] = [40, 190, 80]
        let both = picture([(CGRect(x: 60, y: 10, width: 10, height: 10), red), (CGRect(x: 80, y: 10, width: 10, height: 10), green)])
        #expect(abs((both.red?.x ?? 0) - 0.645) < 0.01)
        #expect(abs((both.red?.y ?? 0) - 0.3625) < 0.02)
        #expect(abs((both.green?.x ?? 0) - 0.845) < 0.01)
        // A red picture of the caller, on the left; the waveform's bright green, and small.
        let neither = picture([(CGRect(x: 5, y: 5, width: 20, height: 20), red), (CGRect(x: 60, y: 5, width: 2, height: 4), green)])
        #expect(neither.red == nil)
        #expect(neither.green == nil)
    }

    @Test("A call that can't be answered from the notch doesn't ring, and isn't connected yet")
    func callCalling() {
        let calling = CallShown(name: "Silva", over: "Phone", phase: .calling)
        #expect(!calling.rings)
        #expect(!calling.isConnected)
        #expect(CallShown(name: "Silva", over: "Phone", phase: .ringing).rings)
        #expect(CallShown(name: "Silva", over: "Phone", phase: .connected(since: .now)).isConnected)
    }

    @Test("A device is shown only with its maker's 3D model; the rest keep macOS's own banner")
    func onlyWithModel() {
        // AirPods 1 and 2 and the first Beats have none. All AirPods Max are one model.
        for product in [0x2002, 0x200F, 0x2003, 0x2005] { #expect(Headphones(product: product) == nil) }
        #expect(Headphones(product: 0x200A) == .airpodsMax)
        #expect(Headphones(product: 0x201F) == .airpodsMax)
        #expect(Headphones(product: 0x202D) == .airpodsMax)
        let withModel = DeviceWatch.BluetoothInfo(product: 0x2024, vendor: 0x4C, levels: .init(main: 88))
        let withoutModel = DeviceWatch.BluetoothInfo(product: 0x200F, vendor: 0x4C)
        let otherMaker = DeviceWatch.BluetoothInfo(product: 0x2024, vendor: 0x1234, kind: "Headphones")
        #expect(withModel.model == .airpodsPro2)
        #expect(withoutModel.model == nil && withoutModel.announced)
        #expect(otherMaker.model == nil)
        #expect(DeviceWatch.Battery(withModel) != nil)
        #expect(DeviceWatch.Battery(withoutModel) == nil)
        // Only a positively named supported device can replace the native banner.
        let connected = ["sam\u{2019}s airpods pro": withModel, "airpods": withoutModel]
        #expect(MenuBarBanners.notchShows(["AirPods Pro", "88", "Connected"], connected: connected, canRender: { _ in true }))
        #expect(!MenuBarBanners.notchShows(["AirPods", "88", "Connected"], connected: connected))
        #expect(!MenuBarBanners.notchShows(["Other Name", "88"], connected: connected))
        #expect(!MenuBarBanners.notchShows(["Other Name", "88"], connected: ["airpods pro": withModel]))
        #expect(!MenuBarBanners.notchShows(["Other Name", "88"], connected: [:]))
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

    @Test("Every recording can be tried on its own, each state by its name")
    func recordingScenes() {
        for name in ["screenRecording", "screenCountdown", "screenSaving", "screenSaved", "voiceMemo", "voiceMemoPaused"] {
            #expect(ActivityBench.parse(["Glance", "--bench", name])?.scenes.first?.rawValue == name)
        }
        #expect(ActivityBench.parse(["Glance", "--bench", "voiceMemo+music"])?.scenes == [.voiceMemo, .music])
        #expect(!ActivityBench.Scene.screenSaved.announces)
    }

    @Test("The menu lists every scene once, under a label, each by a name of its own")
    @MainActor
    func menuLabels() {
        let listed = ActivityBench.Scene.groups.flatMap(\.scenes)
        #expect(listed.count == ActivityBench.Scene.allCases.count)
        #expect(Set(listed) == Set(ActivityBench.Scene.allCases))
        #expect(ActivityBench.Scene.groups.allSatisfy { !$0.label.isEmpty && !$0.scenes.isEmpty })
        for group in ActivityBench.Scene.groups {
            let titles = group.scenes.map(\.title)
            #expect(Set(titles).count == titles.count, "\(group.label) names two alike")
            #expect(titles.allSatisfy { !$0.isEmpty && $0 != $0.lowercased() })
        }
    }
}

/// The screen and a voice memo being recorded, as the iPhone shows them.
@MainActor
@Suite("Recordings")
struct RecordingTests {
    @Test("The countdown shows each whole second left, from where it starts down to none")
    func countdownSteps() {
        let start = Date(timeIntervalSinceReferenceDate: 1000)
        let until = start + 3
        #expect(ScreenRecording.step(from: 3, until: until, at: start) == 3)
        #expect(ScreenRecording.step(from: 3, until: until, at: start + 0.99) == 3)
        #expect(ScreenRecording.step(from: 3, until: until, at: start + 1) == 2)
        #expect(ScreenRecording.step(from: 3, until: until, at: start + 2.5) == 1)
        #expect(ScreenRecording.step(from: 3, until: until, at: until) == 0)
        #expect(ScreenRecording.step(from: 3, until: until, at: until + 5) == 0)
        // Never more than it started from, early or late.
        #expect(ScreenRecording.step(from: 5, until: until, at: start - 9) == 5)
    }

    @Test("Voice Memos' time reads 0:14 and the screen's 00:08, as the iPhone's do")
    func readings() {
        let english = Locale(identifier: "en_US")
        #expect(ClockText.of(14, locale: english) == "0:14")
        #expect(ClockText.of(8, paddingMinutes: true, locale: english) == "00:08")
        #expect(Recording.reading(14.9, memo: true).hasSuffix("14"))
        #expect(Recording.reading(3725, memo: false).filter(\.isNumber).count == 5)
    }

    @Test("A recording's length runs while it records, and holds paused, stopped and counting down")
    func lengths() {
        let start = Date(timeIntervalSinceReferenceDate: 1000)
        #expect(VoiceMemo.recording(since: start).length(at: start + 20) == 20)
        #expect(VoiceMemo.paused(length: 20).length(at: start + 99) == 20)
        #expect(ScreenRecording.recording(since: start).length(at: start + 8) == 8)
        #expect(ScreenRecording.saving(length: 11).length(at: start + 99) == 11)
        #expect(ScreenRecording.countdown(from: 3, until: start + 3).length(at: start) == 0)
        #expect(VoiceMemo.recording(since: start).length(at: start - 5) == 0)
    }

    @Test("The waveform's newest bar is last, quiet places are dots, and those to come are dots after")
    func waveform() {
        let spec = MemoBars.Spec(slots: 26, recorded: 15, height: 27, scale: 77, open: true)
        let frames = spec.frames([0.2, 1, 0.5])
        #expect(frames.count == 26)
        // Fewer heard than recorded places: the oldest ones are dots.
        #expect(frames[0].height == spec.least)
        #expect(frames[12].height > spec.least)
        #expect(frames[13].height == spec.height)
        #expect(frames[14].height < frames[13].height)
        #expect(frames[15...].allSatisfy { $0.height == spec.least })
        // Evenly spaced, each on the middle.
        #expect(abs(frames[1].minX - frames[0].minX - spec.pitch) < 0.001)
        #expect(frames.allSatisfy { abs($0.midY - spec.height / 2) < 0.001 })
        #expect(abs(frames[25].maxX - spec.width) < 0.001)
        // More levels than places: only the newest show.
        let full = spec.frames((0..<40).map { $0 == 39 ? 1 : 0 })
        #expect(full[14].height == spec.height)
        #expect(full[0..<14].allSatisfy { $0.height == spec.least })
    }

    @Test("Beside the camera, the waveform's quiet bars are a little taller than wide, as the iPhone's")
    func closedDots() {
        let spec = MemoBars.Spec(slots: 15, recorded: 15, height: 32 * RecordingLook.barMost, scale: 32, open: false)
        #expect(spec.least > spec.barWidth)
        #expect(spec.frames([]).allSatisfy { $0.height == spec.least })
    }

    @Test("Loudness shows by decibels: silence as none, a raised voice as all")
    func loudness() {
        #expect(RecordingLevels.level(rms: 0) == 0)
        #expect(RecordingLevels.level(rms: 0.001) == 0)
        #expect(RecordingLevels.level(rms: 1) == 1)
        let quiet = RecordingLevels.level(rms: 0.01), loud = RecordingLevels.level(rms: 0.1)
        #expect(quiet > 0 && quiet < loud && loud < 1)
        #expect((0..<200).map(RecordingLevels.madeUpLevel).allSatisfy { $0 >= 0 && $0 <= 1 })
    }

    @Test("Activities take the notch in the order they start, whatever they are, as on the iPhone")
    func order() {
        let model = NotchModel(closedSize: CGSize(width: 185, height: 32), layout: .top, hasCamera: true)
        // Music first, then a timer, then a voice memo, then AirDrop.
        model.activity = true
        model.timer = .running(until: .now + 300, total: 300)
        model.voiceMemo = .recording(since: .now)
        model.airdrop = AirDropShown(id: "a", sender: "iPhone", fraction: 0.2)
        #expect(model.activities == [.music, .timer, .voiceMemo, .airdrop])
        #expect(model.second == .timer)
        // Music stops: the timer has the notch, the voice memo the bubble.
        model.activity = false
        #expect(model.activities == [.timer, .voiceMemo, .airdrop])
        // Music again: it's the newest, at the back.
        model.activity = true
        #expect(model.activities == [.timer, .voiceMemo, .airdrop, .music])
        // A call comes after what was there too.
        model.call = CallShown(name: "Alex Morgan", over: "Phone", phase: .connected(since: .now))
        #expect(model.activities.last == .call)
        // Changing, it keeps its place: paused, the timer is still first.
        model.timer = .paused(left: 200, total: 300)
        #expect(model.activities.first == .timer)
        // Swiped away, it steps aside, and comes back to its place.
        model.dismissed.insert(.timer)
        #expect(model.activities.first == .voiceMemo)
        model.dismissed.remove(.timer)
        #expect(model.activities.first == .timer)
        #expect(model.recording(of: .voiceMemo) == model.voiceMemo.map(Recording.voiceMemo))
        #expect(model.recording(of: .music) == nil)
    }

    @Test("Each opens to its own view; gone, the notch knows to close")
    func opens() {
        let model = NotchModel(closedSize: CGSize(width: 185, height: 32), layout: .top, hasCamera: true)
        model.voiceMemo = .recording(since: .now)
        #expect(model.expansion(fromBubble: false) == .voiceMemo)
        model.expanded = .voiceMemo
        #expect(!model.expandedGone)
        model.voiceMemo = nil
        #expect(model.expandedGone)
        model.screenRecording = .saving(length: 4)
        model.expanded = .screenRecording
        #expect(!model.expandedGone)
        #expect(model.name(of: .screenRecording) == "Screen Recording")
    }

    @Test("Each side is as wide as what it shows: the dot alone narrower than the countdown, the waveform wider than its time")
    func wings() {
        let h: CGFloat = 32
        let dot = RecordingLook.wing(for: .screen(.recording(since: .now)), restingHeight: h)
        let countdown = RecordingLook.wing(for: .screen(.countdown(from: 3, until: .now + 3)), restingHeight: h)
        let saving = RecordingLook.wing(for: .screen(.saving(length: 3)), restingHeight: h)
        #expect(dot < countdown)
        #expect(abs(dot - (LiveActivityView.concentric(h * RecordingLook.dot, in: h) + h * RecordingLook.dot + LiveActivityView.cameraGap)) < 0.01)
        #expect(saving >= SystemActivityView.ringEdge(h) + h * TimerLayout.ring)
        let memo = RecordingLook.wing(for: .voiceMemo(.recording(since: .now - 14)), restingHeight: h)
        #expect(abs(memo - (h * RecordingLook.waveEdge + RecordingLook.waveWidth(h) + LiveActivityView.cameraGap)) < 0.01)
        // An hour in, its time is wider than its waveform.
        let long = RecordingLook.wing(for: .voiceMemo(.recording(since: .now - 3725)), restingHeight: h)
        #expect(long > memo)
    }

    @Test("Opened, Voice Memos is as wide as the iPhone's island for its height, or more, for its recorded bars to end beside the camera housing; the screen as its first line needs")
    func openWidths() {
        let h: CGFloat = 32
        let tall = TimerLayout.tallHeight(h)
        // Beside a small camera, as the iPhone's island; beside a Mac's housing, wider.
        #expect(RecordingLook.memoWidth(restingHeight: h, camera: 100) == (tall * 374 / 84).rounded(.up))
        let memo = RecordingLook.memoWidth(restingHeight: h, camera: 185)
        let recordedEnd = PlayerLayout.padding + tall * (RecordingLook.openPitch * CGFloat(RecordingLook.openRecorded - 1) + RecordingLook.openBarWidth)
        #expect(recordedEnd + LiveActivityView.cameraGap <= (memo - 185) / 2)
        let short = RecordingLook.screenWidth(restingHeight: h, camera: 185, length: 8)
        let long = RecordingLook.screenWidth(restingHeight: h, camera: 185, length: 3725)
        #expect(short >= 185 + 2 * (TimerLayout.content(h) + TimerLayout.buttonEdge(h)))
        #expect(long > short)
        // Its waveform and time fit beside its button.
        let room = memo - PlayerLayout.padding - ExpandedRecordingView.memoTimeEdge(h)
        #expect(RecordingLook.openWaveWidth(h) + RecordingLook.timeWidth("0:00:00", size: NotchType.size * RecordingLook.memoTime) < room)
    }

    @Test("Being saved and saved, the screen recording says so under its time, and the menu can hide it")
    func saved() {
        let saving = ScreenRecording.saving(length: 11)
        let saved = ScreenRecording.saved(length: 11, folder: "Desktop", preview: nil)
        #expect(ScreenRecording.recording(since: .now).title == "Screen Recording")
        #expect(saving.title == "Saving Recording…" && saving.isSaving && !saving.isRecording)
        #expect(saved.title == "Recording Saved to Desktop" && saved.isSaved && saved.length() == 11)
        #expect(Recording.screen(saved).spoken().hasPrefix("Screen recording saved to Desktop"))
        // Saved, it keeps the dot's side by the camera.
        #expect(RecordingLook.wing(for: .screen(saved), restingHeight: 32) == RecordingLook.wing(for: .screen(.recording(since: .now)), restingHeight: 32))
        #expect(NotchController.putAwayTitle(alert: nil, first: .screenRecording) == "Hide Screen Recording")
        #expect(NotchController.putAwayTitle(alert: nil, first: .voiceMemo) == "Hide Voice Memo")
        #expect(ScreenRecordingWatch.savedFor >= 3)
    }

    @Test("The dot pulses slightly and slowly, beside the camera and opened alike; the stop ring is fine")
    func pulses() {
        #expect(RecordingLook.pulseDim > RecordingLook.dim && RecordingLook.pulseDim >= 0.7)
        #expect(RecordingLook.pulse >= 2)
        #expect(RecordingLook.screenRing * TimerLayout.content(32) < 2.5)
        #expect(RecordingLook.memoRing < 0.0645)
    }

    @Test("Screenshot's countdown is read from its menu bar item, and its stop button is anything else")
    func screenshotCountdown() {
        #expect(ScreenRecordingWatch.countdown(in: "5s") == 5)
        #expect(ScreenRecordingWatch.countdown(in: " 10 s ") == 10)
        #expect(ScreenRecordingWatch.countdown(in: "3") == 3)
        #expect(ScreenRecordingWatch.countdown(in: "Stop Screen Recording") == nil)
        #expect(ScreenRecordingWatch.countdown(in: "") == nil)
        #expect(ScreenRecordingWatch.isRecordingItem("com.apple.menuextra.screencapture"))
        #expect(!ScreenRecordingWatch.isRecordingItem("com.apple.menuextra.clock"))
        #expect(!ScreenRecordingWatch.isRecordingItem(nil))
        // macOS 27.3: the recording as a Live Activity in the menu bar, whose own stop button is in
        // what opens from it (read live, 2026-11-07).
        #expect(ScreenRecordingWatch.isRecordingItem("live-activity-pill-com.apple.screencaptureui"))
        #expect(!ScreenRecordingWatch.isRecordingItem("live-activity-pill-com.apple.MediaRemoteUIService"))
        #expect(ScreenRecordingWatch.isOpenedStopButton("ScreenRecording.BannerView"))
        #expect(!ScreenRecordingWatch.isOpenedStopButton("NowPlaying.BannerView"))
        #expect(!ScreenRecordingWatch.isOpenedStopButton(nil))
    }

    @Test("A voice memo pauses while Voice Memos shows Resume, goes on while it shows Done, and resumed it carries on from where it was")
    func voiceMemoSteps() {
        let start = Date(timeIntervalSinceReferenceDate: 1000)
        let recording = VoiceMemo.recording(since: start)
        func next(_ memo: VoiceMemo?, microphone: Bool, resume: Bool = false, done: Bool = false, after seconds: Double) -> VoiceMemo? {
            VoiceMemoWatch.next(after: memo, recording: microphone, resume: resume, done: done, at: start + seconds)
        }
        #expect(next(nil, microphone: true, after: 0) == recording)
        #expect(next(recording, microphone: true, after: 5) == recording)
        // Paused at 10 seconds.
        let paused = next(recording, microphone: false, resume: true, done: true, after: 10)
        #expect(paused == .paused(length: 10))
        // Resumed: the Resume button has gone before the microphone comes back.
        #expect(next(paused, microphone: false, done: true, after: 16) == paused)
        #expect(next(paused, microphone: true, after: 17) == .recording(since: start + 7))
        #expect(next(paused, microphone: true, after: 17)?.length(at: start + 18) == 11)
        // Stopping, the microphone goes before the buttons change, then Done goes too.
        #expect(next(recording, microphone: false, done: true, after: 20) == recording)
        #expect(next(recording, microphone: false, after: 21) == nil)
        #expect(next(paused, microphone: false, after: 21) == nil)
        #expect(next(nil, microphone: false, done: true, after: 30) == nil)
    }

    @Test("Voice Memos' own buttons are named as Voice Memos names them")
    func voiceMemosButtons() {
        #expect(!VoiceMemoWatch.resume.isEmpty && VoiceMemoWatch.resume != "AX_RESUME")
        #expect(!VoiceMemoWatch.done.isEmpty && VoiceMemoWatch.done != "AX_DONE_BUTTON")
    }

    @Test("Said to VoiceOver in words")
    func spoken() {
        #expect(Recording.screen(.countdown(from: 3, until: .now + 2.5)).spoken() == "Screen recording starts in 3")
        #expect(Recording.screen(.saving(length: 3)).spoken() == "Saving the screen recording")
        #expect(Recording.voiceMemo(.paused(length: 20)).spoken().hasPrefix("Voice memo paused"))
        #expect(Recording.voiceMemo(.recording(since: .now - 20)).spoken().hasPrefix("Recording a voice memo"))
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

/// Walking another app's interface, which can lead back into itself.
@Suite("Walking an app's interface")
struct InterfaceWalkTests {
    @Test("A tree is walked root first, each one's children in order")
    func order() {
        let tree = [0: [1, 4], 1: [2, 3], 4: [5]]
        #expect(SystemNotices.walk(from: 0, children: { tree[$0] ?? [] }, where: { _ in true }) == [0, 1, 2, 3, 4, 5])
        #expect(SystemNotices.walk(from: 0, children: { tree[$0] ?? [] }, where: { $0 % 2 == 1 }) == [1, 3, 5])
    }

    @Test("A tree that leads back into itself ends, each element once")
    func loop() {
        let tree = [0: [1], 1: [2, 0], 2: [1, 2]]
        #expect(SystemNotices.walk(from: 0, children: { tree[$0] ?? [] }, where: { _ in true }) == [0, 1, 2])
    }

    @Test("A chain without end stops at the deepest, and a vast tree at the most")
    func endless() {
        let chain = SystemNotices.walk(from: 0, children: { [$0 + 1] }, where: { _ in true })
        #expect(chain.count == SystemNotices.deepest + 1)
        let wide = SystemNotices.walk(from: "", children: { path in (0..<10).map { path + String($0) } }, where: { _ in true })
        #expect(wide.count == SystemNotices.most)
    }
}

/// The native slider's binding must not be overwritten by an older volume read.
@Suite("Volume slider binding")
struct VolumeSliderBindingTests {
    @Test("A refresh begun before an edit cannot restore its old volume")
    func staleRefresh() {
        var sent: [Double] = []
        let level = VolumeMenuSlider.VolumeSlider.Level(0.2) { sent.append($0) }
        let started = level.revision
        level.move(to: 0.65)
        level.show(0.2, since: started)
        #expect(level.value == 0.65)
        #expect(sent == [0.65])
        level.show(0.5, since: level.revision)
        #expect(level.value == 0.5)
        #expect(sent == [0.65])
    }
}
