//
//  DeviceWatch.swift
//  Glance
//
//  Created by Gaty on 16/10/2026.
//

import AppKit
import CoreAudio
import UniformTypeIdentifiers

/// Devices connecting, as the iPhone's Dynamic Island shows AirPods connecting, their symbol
/// turning in beside their battery: Apple's and Beats' headphones and speakers over Bluetooth, as
/// Core Audio sees them arrive, by their model and battery as System Information reports them.
/// Nothing else is announced, as the Dynamic Island shows nothing else. None of it needs a
/// permission. What's connected as Glance starts, or reconnects as the Mac wakes, isn't announced.
/// The sound going to AirPlay is an activity of its own (see `AirPlayWatch`). A device whose battery
/// runs down past 20% or 10% is announced the same way, its ring red, as the iPhone announces AirPods
/// running low; macOS's own banner for it, and AirPods' notification, are taken away (see
/// `SystemNotices`).
@MainActor
final class DeviceWatch {
    /// Sound devices there are, by ID.
    private var outputs: Set<AudioDeviceID> = []
    /// What was announced lately, by name: one device often arrives more than one way.
    private var recent: [String: Date] = [:]
    /// Each connected device's battery as last read, by name.
    private var batteries: [String: Int] = [:]
    private var batteryTimer: Timer?
    private var reading = false

    func start() {
        outputs = Set(AudioOutput.outputs().map(\.id))
        var address = AudioProperty.address(kAudioHardwarePropertyDevices)
        AudioObjectAddPropertyListenerBlock(AudioProperty.system, &address, .main) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.devicesChanged() }
        }
        watchBatteries()
    }

    // MARK: Sound

    private func devicesChanged() {
        let now = AudioOutput.outputs()
        let arrived = now.filter { !outputs.contains($0.id) && Self.isBluetooth($0.transport) }
        outputs = Set(now.map(\.id))
        if !arrived.isEmpty { MenuBarBanners.shared.follow() }
        for device in arrived {
            Task { [weak self] in
                // Its battery, which AirPods tell a moment after they connect.
                var info = await Self.bluetooth(named: device.name)
                if info?.battery == nil {
                    try? await Task.sleep(for: .seconds(1.5))
                    info = await Self.bluetooth(named: device.name) ?? info
                }
                guard info?.announced == true else { return }
                let symbol = info?.modelSymbols?.symbol ?? device.symbol
                let pictures = info?.product.map(DevicePictures.names(product:)) ?? []
                // AirPods and Beats turn in 3D, from a clip read once, before they're shown.
                let model = info?.product.flatMap(Headphones.init(product:))
                if let model { _ = await DeviceTurn.prepare(model) }
                self?.announce(device.name, symbol: symbol, model: model, pictures: pictures, battery: info?.battery)
            }
        }
    }

    static func isBluetooth(_ transport: UInt32) -> Bool {
        transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
    }

    // MARK: Bluetooth's own report

    /// What System Information reports of a connected Bluetooth device, by its name: its battery,
    /// the lower of two earbuds', and its model, by product ID. It asks the Bluetooth service, which
    /// needs no permission of Glance's; it takes a moment, so it's never on the main thread.
    nonisolated static func bluetooth(named name: String) async -> BluetoothInfo? {
        await bluetoothReport()[name.lowercased()]
    }

    /// Every connected device in System Information's report, by its name in lowercase.
    nonisolated static func bluetoothReport() async -> [String: BluetoothInfo] {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            process.arguments = ["SPBluetoothDataType", "-json"]
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return [:] }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return connected(in: data)
        }.value
    }

    struct BluetoothInfo: Equatable, Sendable {
        var battery: Int?
        var product: Int?
        /// Who made it, as its Bluetooth company ID: only Apple's and Beats' models are macOS's to
        /// picture.
        var vendor: Int?
        /// What it is, as it tells the Mac: all there is to go by for another maker's.
        var kind: String?
        /// Each part's level, as the Sound menu shows AirPods': each earbud's and the case's, or
        /// the one battery of headphones that have one.
        var levels = Levels()

        /// Apple's or Beats', which the iPhone announces too. With no maker told, a model macOS
        /// knows is one of theirs.
        var announced: Bool {
            vendor == 0x4C || (vendor == nil && product.flatMap(SystemDevices.symbols(product:)) != nil)
        }

        /// How macOS pictures this model, or for another maker's, what it is.
        var modelSymbols: DeviceSymbols? {
            let model = vendor == nil || vendor == 0x4C ? product.flatMap(SystemDevices.symbols(product:)) : nil
            return model ?? kind.flatMap { Self.kinds[$0] }.map { DeviceSymbols(symbol: $0) }
        }

        /// What System Information calls each kind of device.
        private static let kinds = [
            "Headphones": "headphones", "Headset": "headphones", "Speaker": "hifispeaker", "Portable Audio": "hifispeaker",
            "Hi-Fi Audio": "hifispeaker",
        ]
    }

    struct Levels: Equatable, Sendable {
        var left: Int?
        var right: Int?
        var chargingCase: Int?
        var main: Int?
    }

    /// Each connected device in System Information's report, by its name in lowercase.
    nonisolated static func connected(in report: Data) -> [String: BluetoothInfo] {
        guard let json = try? JSONSerialization.jsonObject(with: report) as? [String: Any],
            let controllers = json["SPBluetoothDataType"] as? [[String: Any]]
        else { return [:] }
        var found: [String: BluetoothInfo] = [:]
        for devices in controllers.compactMap({ $0["device_connected"] as? [[String: [String: Any]]] }) {
            for device in devices {
                for (name, info) in device {
                    func percent(_ key: String) -> Int? {
                        (info[key] as? String).flatMap { Int($0.trimmingCharacters(in: CharacterSet(charactersIn: "% "))) }
                    }
                    let left = percent("device_batteryLevelLeft"), right = percent("device_batteryLevelRight")
                    let main = percent("device_batteryLevelMain"), chargingCase = percent("device_batteryLevelCase")
                    let buds = [left, right].compactMap { $0 }
                    let battery = buds.min() ?? main ?? chargingCase
                    func identifier(_ key: String) -> Int? {
                        (info[key] as? String).flatMap { Int($0.replacingOccurrences(of: "0x", with: ""), radix: 16) }
                    }
                    let product = identifier("device_productID")
                    // AirPods are listed twice, the second time for their case alone: what the first
                    // told stays, the earbuds' battery and the model.
                    let earlier = found[name.lowercased()]
                    let levels = Levels(
                        left: left ?? earlier?.levels.left, right: right ?? earlier?.levels.right,
                        chargingCase: chargingCase ?? earlier?.levels.chargingCase, main: main ?? earlier?.levels.main)
                    found[name.lowercased()] = BluetoothInfo(
                        battery: buds.isEmpty ? earlier?.battery ?? battery : battery, product: product ?? earlier?.product,
                        vendor: identifier("device_vendorID") ?? earlier?.vendor,
                        kind: info["device_minorType"] as? String ?? earlier?.kind, levels: levels)
                }
            }
        }
        return found
    }

    // MARK: Running low

    /// Connected devices' batteries, read every two minutes, and the moment macOS's own banner for a
    /// device shows; the first reading only counts them.
    private func watchBatteries() {
        let timer = Timer(timeInterval: 120, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.readBatteries() } }
        timer.tolerance = 20
        RunLoop.main.add(timer, forMode: .common)
        batteryTimer = timer
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) {
            [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.bundleIdentifier == SystemNotices.bluetoothBanners else { return }
            MainActor.assumeIsolated { self?.readBatteries() }
        }
        MenuBarBanners.shared.watch { [weak self] in self?.readBatteries() }
        readBatteries()
    }

    /// A device's battery as read, with what it's shown as.
    struct Battery {
        var symbol: String
        var product: Int?
        var percent: Int
    }

    private func readBatteries() {
        guard !reading else { return }
        reading = true
        // System Information takes a moment, so it's asked only while headphones are connected.
        let headphones = AudioOutput.outputs().filter { Self.isBluetooth($0.transport) }
        Task { [weak self] in
            var found: [String: Battery] = [:]
            if !headphones.isEmpty {
                let report = await Self.bluetoothReport()
                for device in headphones {
                    guard let info = report[device.name.lowercased()], info.announced, let percent = info.battery else { continue }
                    let symbol = info.modelSymbols?.symbol ?? device.symbol
                    found[device.name] = Battery(symbol: symbol, product: info.product, percent: percent)
                }
            }
            self?.batteriesRead(found)
        }
    }

    private func batteriesRead(_ found: [String: Battery]) {
        reading = false
        defer { batteries = found.mapValues(\.percent) }
        for (name, battery) in found {
            guard let before = batteries[name], Self.runsLow(from: before, to: battery.percent) else { continue }
            Task { [weak self] in
                let model = battery.product.flatMap(Headphones.init(product:))
                if let model { _ = await DeviceTurn.prepare(model) }
                self?.announceLow(name, battery: battery, model: model)
            }
        }
    }

    /// Down past 20% or 10%, as the Mac's own battery is announced.
    static func runsLow(from old: Int, to new: Int) -> Bool {
        BatteryWatch.warnings.contains { new <= $0 && old > $0 }
    }

    private func announceLow(_ name: String, battery: Battery, model: Headphones?) {
        guard !Activities.shared.settling, UserDefaults.standard.bool(forKey: Preferences.activityDevices) else { return }
        let pictures = battery.product.map(DevicePictures.names(product:)) ?? []
        Activities.shared.post(
            Self.lowBattery(name: Self.shortName(name), symbol: battery.symbol, model: model, pictures: pictures, battery: battery.percent))
        SystemNotices.hideBluetoothBanner()
        if model != nil { SystemNotices.closeAirPodsReminder() }
    }

    /// Running low: as it connects, its ring red.
    static func lowBattery(name: String, symbol: String, model: Headphones? = nil, pictures: [String] = [], battery: Int) -> NotchAlert {
        NotchAlert(
            kind: .deviceBattery, content: .device(symbol: symbol, model: model, pictures: pictures, battery: battery),
            spoken: "\(name) battery low, \(battery) percent")
    }

    // MARK: Announcing

    private func announce(_ name: String, symbol: String, model: Headphones? = nil, pictures: [String] = [], battery: Int? = nil) {
        let now = Date.now
        recent = recent.filter { now.timeIntervalSince($0.value) < 5 }
        guard recent[name] == nil, !Activities.shared.settling, UserDefaults.standard.bool(forKey: Preferences.activityDevices) else {
            return
        }
        // A device is announced with its battery, as AirPods are; one that doesn't tell it, not at all.
        guard battery != nil else { return }
        recent[name] = now
        Activities.shared.post(Self.alert(name: Self.shortName(name), symbol: symbol, model: model, pictures: pictures, battery: battery))
        // macOS's own banner for it says the same.
        SystemNotices.hideBluetoothBanner()
    }

    /// Without its owner's name, as the iPhone names AirPods: Sam's AirPods Pro as AirPods Pro.
    static func shortName(_ name: String) -> String {
        for mark in ["\u{2019}s ", "'s "] {
            if let range = name.range(of: mark), range.upperBound < name.endIndex { return String(name[range.upperBound...]) }
        }
        return name
    }

    /// A device: its symbol and battery, as AirPods are shown.
    static func alert(name: String, symbol: String, model: Headphones? = nil, pictures: [String] = [], battery: Int? = nil) -> NotchAlert {
        let level = battery.map { ", \($0) percent" } ?? ""
        return NotchAlert(
            kind: .device, content: .device(symbol: symbol, model: model, pictures: pictures, battery: battery),
            spoken: "\(name) connected\(level)")
    }
}
