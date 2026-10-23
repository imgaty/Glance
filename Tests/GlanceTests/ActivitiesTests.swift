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
        activities.post(NotchAlert(kind: .timerDone, content: .timerDone(length: 300), spoken: "Timer done", stays: true))
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

    @Test("A timer counts down, pauses, resumes and cancels; done, it says so until it's stopped")
    func timer() {
        let activities = Activities()
        let timer = NotchTimer(activities: activities, sound: nil)
        timer.start(seconds: 300)
        #expect(timer.state?.isRunning == true)
        #expect(abs((timer.state?.left() ?? 0) - 300) < 1)
        timer.pause()
        #expect(timer.state?.isRunning == false)
        #expect(abs((timer.state?.left() ?? 0) - 300) < 1)
        timer.resume()
        #expect(timer.state?.isRunning == true)
        timer.cancel()
        #expect(timer.state == nil)
        timer.start(seconds: 60)
        timer.done()
        #expect(timer.state == nil)
        #expect(timer.ringing)
        #expect(activities.alert?.kind == .timerDone)
        // Opening the notch stops only a timer that's done.
        timer.start(seconds: 60)
        timer.stop(ifDone: true)
        #expect(timer.state != nil)
        timer.done()
        timer.stop(ifDone: true)
        #expect(!timer.ringing)
        #expect(activities.alert == nil)
    }

    @Test("A device arrives as AirPods do on the iPhone: the device and its ring by the notch's height")
    func deviceLayout() {
        // The iPhone's Dynamic Island, 110 pixels tall for AirPods, as for anything else: the AirPods
        // 51 tall, the middle they turn about 70 in from the end; the ring 59 across, concentric with
        // the end; the wings 97 past the island's resting ends.
        let island = DeviceLayout(height: 110)
        #expect(abs(island.picture - 51) < 0.5)
        #expect(abs(island.middle - 70) < 0.5)
        #expect(abs(island.ring - 59) < 0.5)
        #expect(abs(island.trailing - (110 - island.ring) / 2) < 0.001)
        #expect(abs(island.wing - 97) < 0.5)
        // Placed by the middle it turns about.
        #expect(abs(island.leading(toAxis: 30) - (island.middle - 30)) < 0.001)
        #expect(island.leading(toAxis: 200) == 0)
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
        #expect(NotchTimer.name(minutes: 1) == "1 Minute")
        #expect(NotchTimer.name(minutes: 15) == "15 Minutes")
        #expect(NotchTimer.name(minutes: 60) == "1 Hour")
    }

    @Test("The wings widen for an announcement over a song's, and for a timer, as far as their words need")
    func wings() {
        let model = NotchModel(closedSize: CGSize(width: 185, height: 32), layout: .top, hasCamera: true)
        let resting = model.closedSize.height
        #expect(model.wing == 0)
        model.timer = .running(until: .now + 300, total: 300)
        model.timerWing = SystemActivityView.wing(for: model.timer!, restingHeight: resting, island: false)
        #expect(model.wing == model.timerWing)
        // With music, the timer goes in a bubble, and the notch has music's wings.
        model.activity = true
        #expect(model.wing == resting)
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
        let minutes = SystemActivityView.wing(for: .running(until: .now + 300, total: 300), restingHeight: resting, island: false)
        let hours = SystemActivityView.wing(for: .running(until: .now + 3_700, total: 3_700), restingHeight: resting, island: false)
        #expect(hours > minutes)
    }

    @Test("Beside the camera, a timer counts down in whole minutes, then seconds, as the Dynamic Island's does")
    func condensedTime() {
        #expect(NotchTimer.condensed(14 * 60 + 3) == "14m")
        #expect(NotchTimer.condensed(14 * 60 + 59) == "14m")
        #expect(NotchTimer.condensed(60) == "1m")
        #expect(NotchTimer.condensed(59.2) == "59s")
        #expect(NotchTimer.condensed(1) == "1s")
        #expect(NotchTimer.condensed(3600) == "1h")
        #expect(NotchTimer.condensed(3900) == "1h 5m")
    }

    @Test("A done timer is as tall as the Alarm, the closed notch with it; repeating it starts the same length again")
    func doneTimer() {
        let model = NotchModel(closedSize: CGSize(width: 185, height: 32), layout: .top, hasCamera: true)
        #expect(model.restingHeight == 32)
        model.alert = NotchAlert(kind: .timerDone, content: .timerDone(length: 300), spoken: "Timer done", stays: true)
        #expect(model.restingTall)
        #expect(model.restingHeight == (32 * TimerLayout.tall).rounded())
        #expect(model.metrics(for: .closed).height == model.restingHeight)
        let timer = NotchTimer(activities: Activities(), sound: nil)
        timer.start(seconds: 300)
        timer.done()
        #expect(timer.ringing && timer.state == nil)
        timer.repeatLast()
        #expect(!timer.ringing && timer.state?.total == 300)
        timer.cancel()
    }

    @Test("Opened while a timer runs and nothing plays, the notch is as wide as the Timer's expanded view, its row below the camera")
    func expandedTimer() {
        let model = NotchModel(closedSize: CGSize(width: 185, height: 32), layout: .top, hasCamera: true)
        model.timer = .running(until: .now + 300, total: 300)
        model.expanded = .timer
        let open = model.metrics(for: .open)
        #expect(open.height == (32 * TimerLayout.opened).rounded())
        #expect(open.height > 32 * (1 + TimerLayout.button))
        #expect(abs(open.bodyWidth - 32 * TimerLayout.wide) < 1)
        #expect(open.flare == NotchCorners.restingFlare)
        // Past an hour, the time takes more room.
        model.timer = .running(until: .now + 7_200, total: 7_200)
        #expect(model.metrics(for: .open).bodyWidth >= open.bodyWidth)
    }

    @Test("Paused, a timer makes room for its pause symbol; a device not in 3D, for its level; a long name scrolls within the limit")
    func roomForWhatShows() {
        let resting: CGFloat = 32
        let running = SystemActivityView.wing(for: .running(until: .now + 300, total: 300), restingHeight: resting, island: false)
        let paused = SystemActivityView.wing(for: .paused(left: 300, total: 300), restingHeight: resting, island: false)
        #expect(paused > running)
        let layout = DeviceLayout(height: resting)
        let keyboard = NotchAlert(
            kind: .device, content: .device(symbol: "keyboard", pictures: [], battery: 15), spoken: "Magic Keyboard connected, 15 percent")
        #expect(SystemActivityView.wing(for: keyboard, restingHeight: resting, island: false) > layout.ring + layout.trailing + 15)
        let speaker = DeviceWatch.alert(name: "The Living Room Speaker Upstairs, By the Window", symbol: "airplayaudio", kind: .output)
        #expect(SystemActivityView.wing(for: speaker, restingHeight: resting, island: false) == SystemActivityView.maxWing)
        #expect(SystemActivityView.maxWing <= 120)
        // Counting minutes, and in its last minute seconds, a timer's wings stay about as narrow as the
        // iPhone's, a little wider only where the camera housing stops what they show going under it.
        let early = SystemActivityView.wing(for: .running(until: .now + 600, total: 600), restingHeight: resting, island: false)
        let late = SystemActivityView.wing(for: .running(until: .now + 600, total: 600), restingHeight: resting, island: false, at: .now + 550)
        for wing in [early, late] { #expect(wing >= resting * TimerLayout.wing && wing <= resting * 1.3) }
    }

    @Test("With music and a timer, music keeps the notch and the timer goes in a bubble of its own")
    func bubble() {
        let model = NotchModel(closedSize: CGSize(width: 185, height: 32), layout: .top, hasCamera: true)
        model.activity = true
        #expect(model.bubble == nil)
        #expect(!model.opensTimer(fromBubble: false))
        model.timer = .running(until: .now + 300, total: 300)
        model.timerWing = 60
        #expect(model.bubble == .timer)
        #expect(model.opensTimer(fromBubble: true))
        #expect(!model.opensTimer(fromBubble: false))
        // The notch keeps music's wings, and a new song's name, with the timer beside it.
        #expect(model.wing == 32)
        model.pop = true
        #expect(model.bubble == .timer)
        model.pop = false
        // Something announced, or the notch open: it's back in the notch.
        model.alert = NotchAlert(kind: .device, content: .device(symbol: "keyboard", pictures: [], battery: 15), spoken: "")
        #expect(model.bubble == nil)
        model.alert = nil
        model.state = .open
        #expect(model.bubble == nil)
        // A timer alone has the notch, and opens to the timer.
        model.state = .closed
        model.activity = false
        #expect(model.bubble == nil)
        #expect(model.wing == 60)
        #expect(model.opensTimer(fromBubble: false))
    }

    @Test("macOS's own timer is read as the menu bar shows it, with its length from what macOS keeps of it")
    func systemTimer() {
        #expect(SystemTimer.seconds("5:25") == 325)
        #expect(SystemTimer.seconds("1:05:25") == 3_925)
        #expect(SystemTimer.seconds("0:59") == 59)
        #expect(SystemTimer.seconds("Timer") == nil)
        let kept: [[String: Any]] = [
            ["$MTTimer": ["MTTimerState": 1, "MTTimerDuration": 900.0]],
            ["$MTTimer": ["MTTimerState": 3, "MTTimerDuration": 600.0, "MTTimerFireTime": ["$MTTimerDate": ["MTTimerTimeDate": Date.now + 300]]]],
        ]
        let (total, fire) = SystemTimer.length(endingIn: 300, timers: kept)
        #expect(total == 600)
        #expect(fire != nil)
        // Not the one macOS kept: its ring starts full from what's left.
        let (other, none) = SystemTimer.length(endingIn: 120, timers: kept)
        #expect(other == 120)
        #expect(none == nil)
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
