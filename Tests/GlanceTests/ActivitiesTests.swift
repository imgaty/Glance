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
        activities.post(alert(.output))
        activities.post(alert(.device, "Magic Mouse"))
        #expect(activities.alert?.kind == .charging)
        #expect(activities.waiting.map(\.spoken) == ["Magic Mouse", "Title"])
        // A short line: the oldest of too many goes.
        activities.post(alert(.lowBattery))
        activities.post(alert(.timerDone))
        #expect(activities.waiting.count == 3)
        #expect(activities.waiting.first?.kind == .output)
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
        #expect(BatteryLevel(percent: 20, charging: true).color == .red)
        #expect(BatteryLevel(percent: 21, charging: false).color == .green)
        // Yellow in Low Power Mode, as the iPhone's.
        #expect(BatteryLevel(percent: 6, charging: true, lowPower: true).color == .yellow)
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

    @Test("Accessories are named by what they are; headphones' own buttons aren't announced twice")
    func accessories() {
        #expect(DeviceWatch.symbol(product: "Magic Keyboard with Touch ID", usagePage: 1, usage: 6) == "keyboard")
        #expect(DeviceWatch.symbol(product: "Magic Mouse", usagePage: 1, usage: 2) == "magicmouse")
        #expect(DeviceWatch.symbol(product: "Magic Trackpad", usagePage: 1, usage: 2) == "rectangle.and.hand.point.up.left")
        #expect(DeviceWatch.symbol(product: "MX Master 3S", usagePage: 1, usage: 2) == "computermouse")
        #expect(DeviceWatch.symbol(product: "DualSense Wireless Controller", usagePage: 1, usage: 5) == "gamecontroller")
        #expect(DeviceWatch.symbol(product: "Hilário's AirPods Pro", usagePage: 12, usage: 1) == nil)
        let mouse = DeviceWatch.alert(name: "Magic Mouse", symbol: "magicmouse", battery: 15)
        #expect(mouse.content == .device(symbol: "magicmouse", pictures: [], battery: 15))
        #expect(mouse.spoken == "Magic Mouse connected, 15 percent")
        #expect(DeviceWatch.alert(name: "AirPods", symbol: "airpods").content == .device(symbol: "airpods", pictures: [], battery: nil))
        let airPlay = DeviceWatch.alert(name: "Living Room", symbol: "airplay.audio", kind: .output)
        #expect(airPlay.content == .status(symbol: "airplay.audio", tint: .blue, text: "Living Room"))
        #expect(DeviceWatch.shortName("Hilário\u{2019}s AirPods Pro") == "AirPods Pro")
        #expect(DeviceWatch.shortName("Sam's Magic Keyboard") == "Magic Keyboard")
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
        #expect(connected["airpods pro"] == DeviceWatch.BluetoothInfo(battery: 31, product: 0x2024))
        // Listed again for the case alone, they keep their earbuds' battery and model.
        let twice = DeviceWatch.connected(
            in: Data(
                """
                {"SPBluetoothDataType":[{"device_connected":[{"Airpods Pro":{"device_batteryLevelLeft":"31%","device_batteryLevelRight":"39%",
                "device_productID":"0x2024"}},{"Airpods Pro":{"device_batteryLevelCase":"42%"}}]}]}
                """.utf8))
        #expect(twice["airpods pro"] == DeviceWatch.BluetoothInfo(battery: 31, product: 0x2024))
        // Pictured as macOS pictures them, earbud by earbud, or a model it doesn't picture, none.
        #expect(DevicePictures.names(product: 0x2024) == ["airpod_left", "airpod_right"])
        #expect(DevicePictures.names(product: 0x201F) == ["B515d-Default"])
        #expect(DevicePictures.names(product: 0x2019).isEmpty)
        #expect(connected["keychron q1 max"] == DeviceWatch.BluetoothInfo(battery: 80, product: nil))
        #expect(connected["ipad"] == nil)
        #expect(DeviceWatch.connected(in: Data("not json".utf8)).isEmpty)
        // As macOS names the models.
        #expect(DeviceWatch.symbol(product: 0x2024) == "airpods.pro")
        #expect(DeviceWatch.symbol(product: 8223) == "airpods.max")
        #expect(DeviceWatch.symbol(product: 0x0001) == nil)
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
        #expect(Stopwatch.format(7.416, hundredths: true) == "0:07" + (Locale.current.decimalSeparator ?? ".") + "41")
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
        for file in [rings.appendingPathComponent("Radial-EncoreInfinitum.m4r"), rings.appendingPathComponent("Night Owl.m4r"),
            alerts.appendingPathComponent("Chord.m4r")]
        {
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
        let keyboard = NotchAlert(kind: .device, content: .device(symbol: "keyboard", pictures: [], battery: 15), spoken: "")
        let layout = DeviceLayout(height: 32)
        let wing = SystemActivityView.wing(for: keyboard, restingHeight: 32, island: false)
        #expect(wing < layout.ring + layout.trailing + 60)
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
        #expect(Headphones(product: 0x2019) == .airpods4)
        #expect(Headphones(product: 0x201B) == .airpods4)
        #expect(Headphones(product: 0x2030) == .airpods4)
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
        // AirPods 2, AirPods Max, and nothing at all.
        #expect(Headphones(product: 0x200F) == nil)
        #expect(Headphones(product: 0x200A) == nil)
        #expect(Headphones(product: 0x202D) == nil)
        #expect(Headphones(product: 0x1234) == nil)
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
    func wings() {
        let model = NotchModel(closedSize: CGSize(width: 185, height: 32), layout: .top, hasCamera: true)
        let resting = model.closedSize.height
        #expect(model.wing == 0)
        model.timer = .running(until: .now + 300, total: 300)
        model.timerWing = SystemActivityView.wing(for: .timer(model.timer!), restingHeight: resting, island: false)
        #expect(model.wing == model.timerWing)
        // With music, the timer goes in a bubble, and the notch has music's wings.
        model.activity = true
        #expect(model.wing == LiveActivityView.restingWing(restingHeight: resting, island: false))
        model.pop = true
        model.popWing = 120
        #expect(model.wing == 120)
        let alert = NotchAlert(
            kind: .device, content: .device(symbol: "airpods.pro", pictures: ["airpod_left", "airpod_right"], battery: 31),
            spoken: "AirPods Pro connected")
        model.alertWing = SystemActivityView.wing(for: alert, restingHeight: resting, island: false)
        model.alert = alert
        #expect(model.wing == model.alertWing)
        #expect(model.alertWing > resting && model.alertWing <= SystemActivityView.maxWing)
        // An hour or more takes more room than minutes.
        let minutes = SystemActivityView.wing(for: .timer(.running(until: .now + 300, total: 300)), restingHeight: resting, island: false)
        let hours = SystemActivityView.wing(for: .timer(.running(until: .now + 3_700, total: 3_700)), restingHeight: resting, island: false)
        #expect(hours > minutes)
        // The stopwatch gains a digit at an hour.
        let short = SystemActivityView.wing(for: .stopwatch(.running(since: .now - 30)), restingHeight: resting, island: false)
        let long = SystemActivityView.wing(for: .stopwatch(.running(since: .now - 3_700)), restingHeight: resting, island: false)
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
        #expect(words > LiveActivityView.edgeInset(island: false, restingHeight: h) && words < 10)
        let (left, right) = SystemActivityView.insets(
            for: .battery(title: "Charging", level: BatteryLevel(percent: 64, charging: true)), restingHeight: h, island: false)
        #expect(left == words && right == words)
        // Opened and done, the round buttons are concentric with the round ends, the Dynamic
        // Island's 44 points.
        let round = min(TimerLayout.tallHeight(h) / 2, h * TimerLayout.corner)
        #expect(abs(TimerLayout.buttonEdge(h) + h * TimerLayout.button / 2 - round) < 0.5)
    }

    @Test("Opened to a timer, the notch is as tall as the Timer's expanded view, each side from its end, concentric with it")
    func expandedTimer() {
        let model = NotchModel(closedSize: CGSize(width: 185, height: 32), layout: .top, hasCamera: true)
        model.timer = .running(until: .now + 300, total: 300)
        model.expanded = .timer
        let open = model.metrics(for: .open)
        #expect(open.height == (32 * TimerLayout.tall).rounded())
        // Either side of the camera, only as wide as the buttons, wider than "5:00", need.
        let buttons = 32 * (TimerLayout.button * 2 + TimerLayout.buttonGap)
        #expect(abs(open.bodyWidth - (185 + 2 * (TimerLayout.buttonEdge(32) + buttons + LiveActivityView.cameraGap))) < 1)
        #expect(open.flare == NotchCorners.restingFlare)
        // Past an hour, the time takes more room.
        model.timer = .running(until: .now + 7_200, total: 7_200)
        #expect(model.metrics(for: .open).bodyWidth >= open.bodyWidth)
        // Opened to the stopwatch, the same, its time to the hundredth.
        model.timer = nil
        model.stopwatch = .running(since: .now - 7)
        model.expanded = .stopwatch
        #expect(model.metrics(for: .open).height == open.height)
        #expect(model.metrics(for: .open).bodyWidth >= open.bodyWidth)
        // On an island, which has no camera, as wide as the iPhone's.
        let island = NotchModel(closedSize: CGSize(width: 126, height: 32), layout: .top, hasCamera: false, island: true)
        island.timer = .running(until: .now + 300, total: 300)
        island.expanded = .timer
        #expect(abs(island.metrics(for: .open).bodyWidth - 32 * TimerLayout.wide) < 1)
    }

    @Test("Paused, a timer makes room for its pause symbol; a device not in 3D, for its level; a long name scrolls within the limit")
    func roomForWhatShows() {
        let resting: CGFloat = 32
        let running = SystemActivityView.wing(for: .timer(.running(until: .now + 300, total: 300)), restingHeight: resting, island: false)
        let paused = SystemActivityView.wing(for: .timer(.paused(left: 300, total: 300)), restingHeight: resting, island: false)
        #expect(paused > running)
        let stopped = SystemActivityView.wing(for: .stopwatch(.stopped(elapsed: 7)), restingHeight: resting, island: false)
        #expect(stopped > SystemActivityView.wing(for: .stopwatch(.running(since: .now - 7)), restingHeight: resting, island: false))
        let layout = DeviceLayout(height: resting)
        let keyboard = NotchAlert(
            kind: .device, content: .device(symbol: "keyboard", pictures: [], battery: 15), spoken: "Magic Keyboard connected, 15 percent")
        // Its battery as a ring alone, with no level in numbers beside it.
        #expect(SystemActivityView.wing(for: keyboard, restingHeight: resting, island: false) >= layout.ring + layout.trailing)
        #expect(SystemActivityView.wing(for: keyboard, restingHeight: resting, island: false) < layout.ring + layout.trailing + 15)
        let speaker = DeviceWatch.alert(name: "The Living Room Speaker Upstairs, By the Window", symbol: "airplayaudio", kind: .output)
        #expect(SystemActivityView.wing(for: speaker, restingHeight: resting, island: false) == SystemActivityView.maxWing)
        #expect(SystemActivityView.maxWing <= 120)
        // A timer's wings as wide as its time needs as it reads now, from the end, and no wider.
        let early = SystemActivityView.wing(for: .timer(.running(until: .now + 600, total: 600)), restingHeight: resting, island: false)
        let late = SystemActivityView.wing(for: .timer(.running(until: .now + 600, total: 600)), restingHeight: resting, island: false, at: .now + 550)
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

    @Test("Activities after the first go in bubbles of their own, right then left; each opens to its own")
    func bubbles() {
        let model = NotchModel(closedSize: CGSize(width: 185, height: 32), layout: .top, hasCamera: true)
        model.activity = true
        #expect(model.bubbles.isEmpty)
        #expect(model.expansion(fromBubble: nil) == nil)
        model.timer = .running(until: .now + 300, total: 300)
        model.timerWing = 60
        // Music keeps the notch, and its wings; the timer goes off its right end.
        #expect(model.bubbles == [.timer])
        #expect(model.bubble(.trailing) == .timer)
        #expect(model.bubble(.leading) == nil)
        #expect(model.wing == LiveActivityView.restingWing(restingHeight: 32, island: false))
        #expect(model.notchClock == nil)
        // The stopwatch goes off its left end.
        model.stopwatch = .stopped(elapsed: 12)
        #expect(model.bubbles == [.timer, .stopwatch])
        #expect(model.bubble(.leading) == .stopwatch)
        // Each opens to its own; the notch, to the player.
        #expect(model.expansion(fromBubble: .trailing) == .timer)
        #expect(model.expansion(fromBubble: .leading) == .stopwatch)
        #expect(model.expansion(fromBubble: nil) == nil)
        // While a new song's name shows, something else is announced, or the notch is open, they run
        // back into it.
        model.pop = true
        #expect(model.bubbles.isEmpty)
        model.pop = false
        model.alert = NotchAlert(kind: .device, content: .device(symbol: "keyboard", pictures: [], battery: 15), spoken: "")
        #expect(model.bubbles.isEmpty)
        model.alert = nil
        model.state = .open
        #expect(model.bubbles.isEmpty)
        // Nothing playing, the timer has the notch, and the stopwatch a bubble.
        model.state = .closed
        model.activity = false
        #expect(model.notchClock == .timer(model.timer!))
        #expect(model.wing == 60)
        #expect(model.bubbles == [.stopwatch])
        #expect(model.expansion(fromBubble: nil) == .timer)
        #expect(model.expansion(fromBubble: .trailing) == .stopwatch)
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
        // Beside the camera it runs under the camera, which the width doesn't change for; on an
        // island, it widens the notch only so far.
        let state = ClockShown.timer(.paused(left: 300, total: 300))
        #expect(ExpandedTimerView.width(for: state, name: "Pasta", restingHeight: 32, camera: 185) == ExpandedTimerView.width(for: state, restingHeight: 32, camera: 185))
        let long = String(repeating: "Long label ", count: 10)
        let plain = 32 * TimerLayout.wide
        #expect(ExpandedTimerView.width(for: state, name: long, restingHeight: 32, camera: 0) <= plain + 32 * TimerLayout.titleLimit)
    }

    @Test("The bubble buds off the notch's end joined to it, thins away, and rests apart")
    func bubbleNeck() {
        let rect = CGRect(x: 0, y: 0, width: 32 * (2 + IslandBubble.gap), height: 32)
        #expect(BubbleNeck(out: 0).path(in: rect).isEmpty)
        #expect(!BubbleNeck(out: 0.6).path(in: rect).isEmpty)
        #expect(BubbleNeck(out: 1).path(in: rect).isEmpty)
        // Just before it breaks, the bridge is thinner than as the two first part.
        let late = BubbleNeck(out: 0.95).path(in: rect).boundingRect
        let early = BubbleNeck(out: 0.88).path(in: rect).boundingRect
        #expect(late.height < early.height)
    }
}
