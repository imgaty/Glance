//
//  DeviceWatch.swift
//  Glance
//
//  Created by Gaty on 16/10/2026.
//

import AppKit
import CoreAudio
import UniformTypeIdentifiers

/// Devices connecting, turning in 3D beside their battery: Apple's and Beats' headphones and speakers
/// over Bluetooth with a 3D model of their maker's, as Core Audio sees them arrive, by their model and
/// battery as System Information reports them. Nothing else is announced, and macOS's own banner stays
/// for those (see `MenuBarBanners`). None of it needs a permission. What's connected as Glance starts,
/// or reconnects as the Mac wakes, isn't announced, unless macOS announces it with a banner of its own:
/// then the notch says it in the banner's place.
/// The sound going to AirPlay is an activity of its own (see `AirPlayWatch`). A device whose battery
/// runs down past 20% or 10% is announced the same way, its ring red, as the iPhone announces AirPods
/// running low; macOS's own banner for it, and AirPods' notification, are taken away (see
/// `SystemNotices`). A charging case is announced apart from its earbuds, closed. If it is already
/// low when the earbuds connect, its warning takes the connection announcement's place.
@MainActor
final class DeviceWatch {
    /// Sound devices there are, by ID.
    private var outputs: Set<AudioDeviceID> = []
    /// What was announced lately, by name: one device often arrives more than one way.
    private var recent: [String: Date] = [:]
    /// Each connected device's battery as last read, by name.
    private var batteries: [String: Int] = [:]
    /// Each connected device's case's battery as last read, by name.
    private var caseBatteries: [String: Int] = [:]
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
                if info?.battery == nil || (info?.model?.chargingCase != nil && info?.levels.chargingCase == nil) {
                    try? await Task.sleep(for: .seconds(1.5))
                    info = await Self.bluetooth(named: device.name) ?? info
                }
                guard let battery = info.flatMap(Battery.init) else { return }
                await self?.announce(device.name, battery: battery)
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
        await Task.detached(priority: .utility) { readBluetoothReport() }.value
    }

    /// The report, waiting for it, which takes about a tenth of a second.
    nonisolated static func readBluetoothReport() -> [String: BluetoothInfo] {
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

        /// What the notch shows it turning as. None for another maker's, or a model with no 3D model
        /// of its maker's, and so those aren't shown.
        var model: Headphones? {
            announced ? product.flatMap(Headphones.init(product:)) : nil
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
        MenuBarBanners.shared.watch { [weak self] taken in
            self?.readBatteries()
            if let taken { self?.bannerTaken(taken) }
        }
        readBatteries()
    }

    /// A device's battery as read, with what it's shown as, and its case's, apart from its own.
    struct Battery: Equatable {
        var model: Headphones
        var percent: Int?
        var casePercent: Int?

        /// From System Information's report. The earbuds' own level, or the one battery's: the
        /// case's isn't theirs, even when it's all that's told.
        init?(_ info: BluetoothInfo) {
            guard let model = info.model else { return nil }
            self.model = model
            percent = [info.levels.left, info.levels.right].compactMap { $0 }.min() ?? info.levels.main
            casePercent = info.levels.chargingCase
        }
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
                    found[device.name] = report[device.name.lowercased()].flatMap(Battery.init)
                }
            }
            self?.batteriesRead(found)
        }
    }

    private func batteriesRead(_ found: [String: Battery]) {
        reading = false
        defer {
            // What a reading doesn't tell stays as last told, for as long as the device is connected:
            // a case tells its level only now and then.
            batteries = found.compactMapValues(\.percent).merging(batteries.filter { found[$0.key] != nil }) { new, _ in new }
            caseBatteries = found.compactMapValues(\.casePercent).merging(caseBatteries.filter { found[$0.key] != nil }) { new, _ in new }
        }
        for (name, battery) in found {
            let short = Self.shortName(name)
            if let before = batteries[name], let percent = battery.percent, Self.runsLow(from: before, to: percent) {
                announceLow(Self.lowBattery(name: short, model: battery.model, battery: percent), model: battery.model)
            }
            if let chargingCase = battery.model.chargingCase, let before = caseBatteries[name], let percent = battery.casePercent,
                Self.runsLow(from: before, to: percent)
            {
                announceLow(Self.caseLowBattery(name: short, model: chargingCase, battery: percent), model: chargingCase)
            }
        }
    }

    /// Down past 20% or 10%, as the Mac's own battery is announced.
    static func runsLow(from old: Int, to new: Int) -> Bool {
        BatteryWatch.warnings.contains { new <= $0 && old > $0 }
    }

    /// A device or its case running low, its clip read once before it's shown.
    private func announceLow(_ alert: NotchAlert, model: Headphones) {
        Task {
            guard await DeviceTurn.prepare(model) != nil, !Activities.shared.settling,
                UserDefaults.standard.bool(forKey: Preferences.activityDevices)
            else { return }
            Activities.shared.post(alert)
            SystemNotices.hideBluetoothBanner()
            SystemNotices.closeAirPodsReminder()
        }
    }

    /// Running low: as it connects, its ring red.
    static func lowBattery(name: String, model: Headphones, battery: Int) -> NotchAlert {
        NotchAlert(
            kind: .deviceBattery, content: .device(model: model, battery: battery),
            spoken: String(localized: "\(name) battery low, \(battery) percent"), name: name)
    }

    /// A case running low: on its own, closed, without its earbuds, its ring red.
    static func caseLowBattery(name: String, model: Headphones, battery: Int) -> NotchAlert {
        NotchAlert(
            kind: .caseBattery, content: .device(model: model, battery: battery),
            spoken: String(localized: "\(name) Case battery low, \(battery) percent"), name: String(localized: "\(name) Case"))
    }

    // MARK: Announcing

    /// `news` when macOS announced it too, which it may as the Mac wakes, when what reconnects isn't
    /// otherwise announced.
    private func announce(_ name: String, battery: Battery, news: Bool = false) async {
        guard news || !Activities.shared.settling, UserDefaults.standard.bool(forKey: Preferences.activityDevices),
            let alert = Self.connection(name: Self.shortName(name), battery: battery),
            case .device(let model, _) = alert.content,
            await DeviceTurn.prepare(model) != nil
        else { return }
        let now = Date.now
        recent = recent.filter { now.timeIntervalSince($0.value) < 5 }
        guard recent[name] == nil else { return }
        recent[name] = now
        if alert.kind == .caseBattery { caseBatteries[name] = battery.casePercent }
        Activities.shared.post(alert)
        SystemNotices.hideBluetoothBanner()
    }

    /// An already-low case is more useful than the earbuds' connection level, even when the
    /// earbuds' level has not arrived yet. A case above the warning level stays out of the way.
    static func connection(name: String, battery: Battery) -> NotchAlert? {
        if let chargingCase = battery.model.chargingCase, let percent = battery.casePercent,
            percent <= (BatteryWatch.warnings.max() ?? 20)
        {
            return caseLowBattery(name: name, model: chargingCase, battery: percent)
        }
        guard let percent = battery.percent else { return nil }
        return alert(name: name, model: battery.model, battery: percent)
    }

    /// macOS announced a device with a banner, which was taken away for the notch to say the same.
    /// Just after waking, what reconnects isn't announced otherwise, so the notch says it here; at
    /// other times it already does, as the device connects.
    private func bannerTaken(_ words: [String]) {
        guard Activities.shared.settling else { return }
        Task { [weak self] in
            let report = await Self.bluetoothReport()
            let said = Set(words.map { Self.shortName($0).lowercased() })
            // Named as the Mac names it, rather than in the report's lowercase.
            let devices = AudioOutput.outputs().filter { Self.isBluetooth($0.transport) }
            guard
                let device = devices.first(where: { said.contains(Self.shortName($0.name).lowercased()) && report[$0.name.lowercased()]?.model != nil }),
                let info = report[device.name.lowercased()], let battery = Battery(info)
            else { return }
            await self?.announce(device.name, battery: battery, news: true)
        }
    }

    /// Without its owner's name, as the iPhone names AirPods: Sam's AirPods Pro as AirPods Pro.
    nonisolated static func shortName(_ name: String) -> String {
        for mark in ["\u{2019}s ", "'s "] {
            if let range = name.range(of: mark), range.upperBound < name.endIndex { return String(name[range.upperBound...]) }
        }
        return name
    }

    /// A device: turning, and its battery, as AirPods are shown.
    static func alert(name: String, model: Headphones, battery: Int? = nil) -> NotchAlert {
        return NotchAlert(
            kind: .device, content: .device(model: model, battery: battery),
            spoken: battery.map { String(localized: "\(name) connected, \($0) percent") } ?? String(localized: "\(name) connected"), name: name)
    }
}
