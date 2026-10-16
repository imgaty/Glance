//
//  DeviceWatch.swift
//  Glance
//
//  Created by Gaty on 16/10/2026.
//

import AppKit
import CoreAudio
import IOKit
import IOKit.hid
import UniformTypeIdentifiers

/// Devices connecting, as the iPhone's Dynamic Island shows AirPods connecting, their symbol
/// turning in beside their battery: headphones and speakers over Bluetooth, as Core Audio sees them
/// arrive, by their model and battery as System Information reports them; keyboards, mice,
/// trackpads and game controllers over Bluetooth, as the Mac's list of devices sees them; and the
/// sound going to an AirPlay speaker or TV. None of it needs a permission. What's connected as
/// Glance starts, or reconnects as the Mac wakes, isn't announced.
@MainActor
final class DeviceWatch {
    /// Sound devices there are, by ID.
    private var outputs: Set<AudioDeviceID> = []
    private var defaultOutput: AudioDeviceID = 0
    /// What was announced lately, by name: one device often arrives more than one way.
    private var recent: [String: Date] = [:]
    private var port: IONotificationPortRef?
    private var iterator: io_iterator_t = 0

    func start() {
        outputs = Set(AudioOutput.outputs().map(\.id))
        defaultOutput = AudioOutput.defaultOutput
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice] {
            var address = AudioProperty.address(selector)
            AudioObjectAddPropertyListenerBlock(AudioProperty.system, &address, .main) { [weak self] _, _ in
                MainActor.assumeIsolated {
                    selector == kAudioHardwarePropertyDevices ? self?.devicesChanged() : self?.outputChanged()
                }
            }
        }
        watchAccessories()
    }

    // MARK: Sound

    private func devicesChanged() {
        let now = AudioOutput.outputs()
        let arrived = now.filter { !outputs.contains($0.id) && Self.isBluetooth($0.transport) }
        outputs = Set(now.map(\.id))
        for device in arrived {
            Task { [weak self] in
                // Its battery, which AirPods tell a moment after they connect.
                var info = await Self.bluetooth(named: device.name)
                if info?.battery == nil {
                    try? await Task.sleep(for: .seconds(1.5))
                    info = await Self.bluetooth(named: device.name) ?? info
                }
                let symbol = info?.product.flatMap(Self.symbol(product:)) ?? device.symbol
                let pictures = info?.product.map(DevicePictures.names(product:)) ?? []
                // AirPods turn in 3D: drawn once, before they're shown.
                let earbuds = info?.product.flatMap(Earbuds.init(product:))
                if let earbuds { _ = await EarbudTurn.prepare(earbuds) }
                self?.announce(device.name, symbol: symbol, earbuds: earbuds, pictures: pictures, battery: info?.battery)
            }
        }
    }

    /// To AirPlay: the speaker or TV the sound now plays on.
    private func outputChanged() {
        let id = AudioOutput.defaultOutput
        guard id != defaultOutput else { return }
        defaultOutput = id
        guard let device = AudioOutput.outputs().first(where: { $0.id == id }), device.transport == kAudioDeviceTransportTypeAirPlay
        else { return }
        announce(device.name, symbol: "airplay.audio", kind: .output)
    }

    static func isBluetooth(_ transport: UInt32) -> Bool {
        transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
    }

    // MARK: Keyboards, mice, trackpads

    /// Every input device as it's added to the Mac's list, those over Bluetooth announced. The list
    /// is read, never the devices themselves, which would need Input Monitoring.
    private func watchAccessories() {
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        IONotificationPortSetDispatchQueue(port, .main)
        self.port = port
        let context = Unmanaged.passUnretained(self).toOpaque()
        let result = IOServiceAddMatchingNotification(
            port, kIOFirstMatchNotification, IOServiceMatching(kIOHIDDeviceKey),
            { context, iterator in
                guard let context else { return }
                let watch = Unmanaged<DeviceWatch>.fromOpaque(context).takeUnretainedValue()
                MainActor.assumeIsolated { watch.accessoriesArrived(iterator, announcing: true) }
            }, context, &iterator)
        guard result == KERN_SUCCESS else { return }
        // Those already connected are only counted, which also arms the notification.
        accessoriesArrived(iterator, announcing: false)
    }

    private func accessoriesArrived(_ iterator: io_iterator_t, announcing: Bool) {
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            guard announcing, let accessory = Self.accessory(entry) else { continue }
            // Its battery is told a moment after it connects.
            IOObjectRetain(entry)
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(1.5))
                var battery = Self.battery(of: entry)
                IOObjectRelease(entry)
                // Others tell System Information instead.
                if battery == nil { battery = await Self.bluetooth(named: accessory.name)?.battery }
                self?.announce(accessory.name, symbol: accessory.symbol, battery: battery)
            }
        }
    }

    /// A keyboard, mouse, trackpad or game controller over Bluetooth, by its name and symbol.
    static func accessory(_ entry: io_object_t) -> (name: String, symbol: String)? {
        func property<T>(_ key: String) -> T? {
            IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? T
        }
        guard let transport: String = property(kIOHIDTransportKey), transport.hasPrefix("Bluetooth"),
            let name: String = property(kIOHIDProductKey), !name.isEmpty,
            let symbol = symbol(product: name, usagePage: property(kIOHIDPrimaryUsagePageKey) ?? 0, usage: property(kIOHIDPrimaryUsageKey) ?? 0)
        else { return nil }
        return (name, symbol)
    }

    /// By its name, then by what it says it is; none for anything else, such as headphones' own
    /// buttons, which arrive as sound devices too.
    static func symbol(product: String, usagePage: Int, usage: Int) -> String? {
        let name = product.lowercased()
        if name.contains("trackpad") { return "rectangle.and.hand.point.up.left" }
        if name.contains("magic mouse") { return "magicmouse" }
        if name.contains("mouse") { return "computermouse" }
        if name.contains("keyboard") { return "keyboard" }
        guard usagePage == kHIDPage_GenericDesktop else { return nil }
        switch usage {
        case kHIDUsage_GD_Keyboard, kHIDUsage_GD_Keypad: return "keyboard"
        case kHIDUsage_GD_Mouse, kHIDUsage_GD_Pointer: return "computermouse"
        case kHIDUsage_GD_GamePad, kHIDUsage_GD_Joystick: return "gamecontroller"
        default: return nil
        }
    }

    /// Its battery, as Apple's keyboards, mice and trackpads tell the Mac.
    static func battery(of entry: io_object_t) -> Int? {
        let options = IOOptionBits(kIORegistryIterateRecursively)
        let value = IORegistryEntrySearchCFProperty(entry, kIOServicePlane, "BatteryPercent" as CFString, kCFAllocatorDefault, options)
        return (value as? Int).flatMap { (0...100).contains($0) ? $0 : nil }
    }

    // MARK: Bluetooth's own report

    /// What System Information reports of a connected Bluetooth device, by its name: its battery,
    /// the lower of two earbuds', and its model, by product ID. It asks the Bluetooth service, which
    /// needs no permission of Glance's; it takes a moment, so it's never on the main thread.
    nonisolated static func bluetooth(named name: String) async -> BluetoothInfo? {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            process.arguments = ["SPBluetoothDataType", "-json"]
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return nil }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return connected(in: data)[name.lowercased()]
        }.value
    }

    struct BluetoothInfo: Equatable, Sendable {
        var battery: Int?
        var product: Int?
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
                    let buds = [percent("device_batteryLevelLeft"), percent("device_batteryLevelRight")].compactMap { $0 }
                    let battery = buds.min() ?? percent("device_batteryLevelMain") ?? percent("device_batteryLevelCase")
                    let product = (info["device_productID"] as? String).flatMap { Int($0.replacingOccurrences(of: "0x", with: ""), radix: 16) }
                    // AirPods are listed twice, the second time for their case alone: what the first
                    // told stays, the earbuds' battery and the model.
                    let earlier = found[name.lowercased()]
                    found[name.lowercased()] = BluetoothInfo(
                        battery: buds.isEmpty ? earlier?.battery ?? battery : battery, product: product ?? earlier?.product)
                }
            }
        }
        return found
    }

    /// An Apple or Beats model's own symbol, by its product ID, as macOS names the model.
    static func symbol(product: Int) -> String? {
        let tag = UTTagClass(rawValue: "com.apple.device-model-code")
        guard let model = UTType(tag: "Device1,\(product)", tagClass: tag, conformingTo: nil)?.identifier else { return nil }
        let candidates: [String] =
            if model.contains("airpods-max") {
                ["airpods.max"]
            } else if model.contains("airpods-pro") {
                ["airpods.pro"]
            } else if model.contains("airpods-gen4") || model.contains("airpods-gen5") {
                ["airpods.gen4", "airpods"]
            } else if model.contains("airpods-gen3") {
                ["airpods.gen3", "airpods"]
            } else if model.contains("airpods") {
                ["airpods"]
            } else if model.contains("beats-studio-pro") || model.contains("beats-solo") {
                ["beats.headphones"]
            } else if model.contains("beats-pill") {
                ["beats.pill", "hifispeaker"]
            } else if model.contains("beats") {
                ["beats.earphones", "beats.headphones"]
            } else {
                []
            }
        return candidates.first { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil }
    }

    // MARK: Announcing

    private func announce(
        _ name: String, symbol: String, earbuds: Earbuds? = nil, pictures: [String] = [], battery: Int? = nil,
        kind: NotchAlert.Kind = .device
    ) {
        let now = Date.now
        recent = recent.filter { now.timeIntervalSince($0.value) < 5 }
        guard recent[name] == nil, !Activities.shared.settling, UserDefaults.standard.bool(forKey: Preferences.activityDevices) else {
            return
        }
        recent[name] = now
        Activities.shared.post(
            Self.alert(name: Self.shortName(name), symbol: symbol, earbuds: earbuds, pictures: pictures, battery: battery, kind: kind))
    }

    /// Without its owner's name, as the iPhone names AirPods: Hilário's AirPods Pro as AirPods Pro.
    static func shortName(_ name: String) -> String {
        for mark in ["\u{2019}s ", "'s "] {
            if let range = name.range(of: mark), range.upperBound < name.endIndex { return String(name[range.upperBound...]) }
        }
        return name
    }

    /// A device: its symbol and battery, as AirPods are shown. The sound going to AirPlay: AirPlay's
    /// symbol, in the blue Control Center lights it with, and where it plays.
    static func alert(
        name: String, symbol: String, earbuds: Earbuds? = nil, pictures: [String] = [], battery: Int? = nil,
        kind: NotchAlert.Kind = .device
    )
        -> NotchAlert
    {
        guard kind == .device else {
            return NotchAlert(kind: kind, content: .status(symbol: symbol, tint: .blue, text: name), spoken: "Playing on \(name)")
        }
        let level = battery.map { ", \($0) percent" } ?? ""
        return NotchAlert(
            kind: kind, content: .device(symbol: symbol, earbuds: earbuds, pictures: pictures, battery: battery),
            spoken: "\(name) connected\(level)")
    }
}
