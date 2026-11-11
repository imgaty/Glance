//
//  ListeningMode.swift
//  Glance
//
//  Created by Gaty on 11/11/2026.
//

import AppKit
import CoreAudio

/// The listening modes exposed by a connected Bluetooth audio device. These optional HAL
/// properties are checked before use; devices that do not expose them keep an ordinary output row.
enum ListeningMode: UInt32, CaseIterable, Sendable {
    case off = 1, noiseCancellation = 2, transparency = 3, adaptive = 4

    var title: String {
        let key =
            switch self {
            case .off: "LISTENING_MODE_OFF"
            case .noiseCancellation: "Noise Cancellation"
            case .transparency: "Transparency"
            case .adaptive: "Adaptive"
            }
        return SoundSystemResources.text(key, table: "ListeningMode")
    }

    var symbol: String {
        switch self {
        case .off: "person.fill"
        case .noiseCancellation: "person.closed.fill"
        case .transparency: "person.open.fill"
        case .adaptive: "person.and.sparkles.fill"
        }
    }

    struct Snapshot: Equatable, Sendable {
        let current: ListeningMode?
        let available: [ListeningMode]
        let writable: Bool

        init(current: UInt32, support: UInt32, writable: Bool) {
            self.current = ListeningMode(rawValue: current)
            var modes: [ListeningMode] = []
            // Off can be unavailable in the device's settings. Never infer permission to enable it.
            if current == ListeningMode.off.rawValue { modes.append(.off) }
            if support & 2 != 0 { modes.append(.transparency) }
            if support & 4 != 0 { modes.append(.adaptive) }
            if support & 1 != 0 { modes.append(.noiseCancellation) }
            available = modes
            self.writable = writable
        }
    }

    private static let mode: AudioObjectPropertySelector = 0x6c73_746d  // lstm
    private static let support: AudioObjectPropertySelector = 0x6c73_6d73  // lsms

    static func read(_ device: AudioDeviceID) -> Snapshot? {
        var address = AudioProperty.address(mode)
        var modes = AudioProperty.address(support)
        guard AudioObjectHasProperty(device, &address), AudioObjectHasProperty(device, &modes) else { return nil }
        var current: UInt32 = 0, supported: UInt32 = 0, writable = DarwinBoolean(false)
        guard AudioProperty.read(device, mode, &current), AudioProperty.read(device, support, &supported) else { return nil }
        let canWrite = AudioObjectIsPropertySettable(device, &address, &writable) == noErr && writable.boolValue
        let snapshot = Snapshot(current: current, support: supported, writable: canWrite)
        return snapshot.available.isEmpty ? nil : snapshot
    }

    /// Success means the device reported the requested mode, not merely that the write was accepted.
    static func change(_ device: AudioDeviceID, to target: ListeningMode) async -> Bool {
        await change(
            to: target, read: { read(device) },
            write: { value in
                var address = AudioProperty.address(mode), value = value
                return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
            }, wait: { try? await Task.sleep(for: .milliseconds(100)) })
    }

    /// The confirmation policy is separate from the device calls so tests never touch headphones.
    static func change(to target: ListeningMode, read: () -> Snapshot?, write: (UInt32) -> Bool, wait: () async -> Void) async -> Bool {
        guard let before = read(), before.writable, before.available.contains(target) else { return false }
        if before.current == target { return true }
        guard write(target.rawValue) else { return false }
        for _ in 0..<12 {
            await wait()
            guard !Task.isCancelled else { return false }
            guard let observed = read() else { return false }
            if observed.current == target { return true }
        }
        return false
    }

}

/// Uses the installed system's translated audio labels and glyphs, with ordinary symbols as fallback.
enum SoundSystemResources {
    private static let controls = Bundle(path: "/System/Library/CoreServices/ControlCenter.app")
    private static let glyphs = Bundle(path: "/System/Library/CoreServices/CoreGlyphsPrivate.bundle")

    static func text(_ key: String, table: String = "Sound") -> String {
        let fallback = key == "LISTENING_MODE_OFF" ? "Off" : key
        return controls?.localizedString(forKey: key, value: fallback, table: table) ?? fallback
    }

    static func image(_ name: String) -> NSImage {
        glyphs?.image(forResource: name) ?? NSImage(systemSymbolName: name, accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: "headphones", accessibilityDescription: nil)!
    }
}
