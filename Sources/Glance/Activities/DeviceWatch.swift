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

/// Devices connecting, as the iPhone's Dynamic Island shows AirPods connecting: headphones and
/// speakers over Bluetooth, as Core Audio sees them arrive; keyboards, mice, trackpads and game
/// controllers over Bluetooth, as the Mac's list of devices sees them, with their battery when they
/// tell it; and the sound going to an AirPlay speaker or TV. Neither needs a permission. What's
/// connected as Glance starts, or reconnects as the Mac wakes, isn't announced.
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
        for device in arrived { announce(device.name, symbol: device.symbol) }
    }

    /// To AirPlay: the speaker or TV the sound now plays on.
    private func outputChanged() {
        let id = AudioOutput.defaultOutput
        guard id != defaultOutput else { return }
        defaultOutput = id
        guard let device = AudioOutput.outputs().first(where: { $0.id == id }), device.transport == kAudioDeviceTransportTypeAirPlay
        else { return }
        announce(device.name, symbol: "airplay.audio", detail: "AirPlay", kind: .output)
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
                let battery = Self.battery(of: entry)
                IOObjectRelease(entry)
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

    // MARK: Announcing

    private func announce(_ name: String, symbol: String, detail: String = "Connected", battery: Int? = nil, kind: NotchAlert.Kind = .device) {
        let now = Date.now
        recent = recent.filter { now.timeIntervalSince($0.value) < 5 }
        guard recent[name] == nil, !Activities.shared.settling, UserDefaults.standard.bool(forKey: Preferences.activityDevices) else {
            return
        }
        recent[name] = now
        Activities.shared.post(Self.alert(name: Self.shortName(name), symbol: symbol, detail: detail, battery: battery, kind: kind))
    }

    /// Without its owner's name, as the iPhone names AirPods: Hilário's AirPods Pro as AirPods Pro.
    static func shortName(_ name: String) -> String {
        for mark in ["\u{2019}s ", "'s "] {
            if let range = name.range(of: mark), range.upperBound < name.endIndex { return String(name[range.upperBound...]) }
        }
        return name
    }

    static func alert(
        name: String, symbol: String, detail: String = "Connected", battery: Int? = nil, kind: NotchAlert.Kind = .device
    )
        -> NotchAlert
    {
        guard let battery else { return NotchAlert(kind: kind, symbol: symbol, title: name, detail: detail) }
        return NotchAlert(
            kind: kind, symbol: symbol, title: name, detail: "\(battery)%", detailTint: battery <= 20 ? .red : .green,
            battery: BatteryLevel(percent: battery, charging: false))
    }
}
