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
        NotchAlert(kind: kind, content: .status(symbol: "wifi", tint: .blue, text: title), spoken: title)
    }

    @Test("Announcements show one at a time, in turn; the same kind again takes its place in line")
    func queue() {
        let activities = Activities()
        activities.post(alert(.charging))
        #expect(activities.alert?.kind == .charging)
        activities.post(alert(.device, "AirPods"))
        activities.post(alert(.online))
        activities.post(alert(.device, "Magic Mouse"))
        #expect(activities.alert?.kind == .charging)
        #expect(activities.waiting.map(\.spoken) == ["Magic Mouse", "Title"])
        // A short line: the oldest of too many goes.
        activities.post(alert(.offline))
        activities.post(alert(.hotspot))
        #expect(activities.waiting.count == 3)
        #expect(activities.waiting.first?.kind == .online)
    }

    @Test("One that stays shows until it's dismissed")
    func staying() {
        let activities = Activities()
        activities.post(NotchAlert(kind: .timerDone, content: .timerDone, spoken: "Timer done", stays: true))
        activities.dismiss(.charging)
        #expect(activities.alert?.kind == .timerDone)
        activities.dismiss(.timerDone)
        #expect(activities.alert == nil)
    }

    @Test("Plugged in is announced with the level; running low, at 20% and again at 10%")
    func battery() {
        typealias Reading = BatteryWatch.Reading
        let charging = BatteryWatch.alert(from: Reading(percent: 54, onPower: false, charging: false), to: Reading(percent: 54, onPower: true, charging: true))
        #expect(charging?.kind == .charging)
        #expect(charging?.content == .battery(title: "Charging", level: BatteryLevel(percent: 54, charging: true)))
        #expect(charging?.spoken == "Charging, 54 percent")
        // Held at 80% by Optimized Charging: plugged in, not charging.
        let held = BatteryWatch.alert(from: Reading(percent: 80, onPower: false, charging: false), to: Reading(percent: 80, onPower: true, charging: false))
        #expect(held?.content == .battery(title: "Plugged In", level: BatteryLevel(percent: 80, charging: false)))
        // Red at 20% and below, charging or not, as the iPhone's.
        #expect(BatteryLevel(percent: 20, charging: true).color == .red)
        #expect(BatteryLevel(percent: 21, charging: false).color == .green)
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

    @Test("The connection: back after it was said to be lost, and onto a hotspot; a blip says nothing")
    func network() {
        typealias Link = NetworkWatch.Link
        let wifi = Link(online: true, kind: .wifi, hotspot: false)
        let wired = Link(online: true, kind: .wired, hotspot: false)
        let hotspot = Link(online: true, kind: .wifi, hotspot: true)
        let none = Link(online: false, kind: .other, hotspot: false)
        #expect(NetworkWatch.change(from: none, to: wifi, saidOffline: true) == .online(.wifi))
        #expect(NetworkWatch.change(from: none, to: wired, saidOffline: true) == .online(.wired))
        #expect(NetworkWatch.change(from: none, to: wifi, saidOffline: false) == nil)
        #expect(NetworkWatch.change(from: wifi, to: hotspot, saidOffline: false) == .hotspot)
        #expect(NetworkWatch.change(from: none, to: hotspot, saidOffline: true) == .hotspot)
        #expect(NetworkWatch.change(from: hotspot, to: hotspot, saidOffline: false) == nil)
        #expect(NetworkWatch.change(from: wifi, to: none, saidOffline: false) == nil)
        #expect(NetworkWatch.alert(for: .offline).content == .status(symbol: "wifi.slash", tint: .red, text: "No Internet"))
        #expect(NetworkWatch.alert(for: .online(.wired)).content == .status(symbol: "network", tint: .blue, text: "Connected"))
        #expect(NetworkWatch.alert(for: .online(.wired)).spoken == "Ethernet connected")
        #expect(NetworkWatch.alert(for: .hotspot).content == .status(symbol: "personalhotspot", tint: .green, text: "Hotspot"))
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
        // 51 tall, 44 in from the end; the ring 59 across, concentric with the end.
        let island = DeviceLayout(height: 110)
        #expect(island.picture == 51)
        #expect(island.leading == 44)
        #expect(island.ring == 59)
        #expect(abs(island.trailing - 25) <= 1)
        let notch = DeviceLayout(height: 32)
        #expect(notch.picture == 15)
        #expect(notch.ring == 17)
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
        model.activity = true
        #expect(model.wing == resting)
        model.timer = .running(until: .now + 300, total: 300)
        model.timerWing = SystemActivityView.wing(for: model.timer!, restingHeight: resting, island: false)
        #expect(model.wing == model.timerWing)
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
        let minutes = SystemActivityView.wing(for: .running(until: .now, total: 300), restingHeight: resting, island: false)
        let hours = SystemActivityView.wing(for: .running(until: .now, total: 3_700), restingHeight: resting, island: false)
        #expect(hours > minutes)
    }
}
