//
//  ListeningModeActivity.swift
//  Glance
//
//  Created by Gaty on 18/11/2026.
//

import AppKit
import IOBluetooth
import OSLog
import SwiftUI

/// AirPods' listening mode, as macOS 27 announces a change in its banner under the menu bar and
/// shows it on its own island: the AirPods on the left, the mode's symbol on the right, both white.
/// Read from the AirPods over Bluetooth once it's allowed (see `ListeningModeWatch`), and from
/// macOS's banner, as Focus is (see `FocusWatch`).
enum ListeningMode: CaseIterable, Sendable {
    case noiseCancellation, transparency, adaptive, off

    /// The symbol macOS's banner draws for it, from SystemBannerUI.
    var symbol: String {
        switch self {
        case .noiseCancellation: "person.closed.fill"
        case .transparency: "person.open.fill"
        case .adaptive: "person.and.sparkles.fill"
        case .off: "person.fill"
        }
    }

    /// Its name's key in the banner's own words, SystemBannerUI's table.
    var key: String {
        switch self {
        case .noiseCancellation: "Noise Cancellation"
        case .transparency: "Transparency"
        case .adaptive: "Adaptive"
        case .off: "LISTENING_MODE_OFF"
        }
    }

    static let banner = "listening-mode-system-banner"

    /// The modes' names as the banner says them, in the Mac's language.
    @MainActor
    static func words() -> [ListeningMode: String] {
        let bundle = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/SystemBannerUI.framework")
        var words: [ListeningMode: String] = [:]
        for mode in allCases {
            let word = SystemNotices.words(mode.key, table: "SystemBannerUI", of: bundle).trimmingCharacters(in: .whitespacesAndNewlines)
            if !word.isEmpty, word != mode.key || mode != .off { words[mode] = word }
        }
        return words
    }

    /// Which mode a listening-mode banner tells of: by its symbol, or failing that, its words.
    static func read(_ snapshot: FocusBannerSnapshot, words: [ListeningMode: String]) -> ListeningModeChange? {
        guard snapshot.identifier == banner else { return nil }
        let texts = snapshot.texts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let bySymbol = snapshot.images.compactMap(\.symbol).compactMap { symbol in allCases.first { $0.symbol == symbol } }.first
        let byWord = allCases.first { mode in texts.contains { $0 == words[mode] || $0 == mode.key } }
        guard let mode = bySymbol ?? byWord else { return nil }
        return ListeningModeChange(mode: mode, word: words[mode] ?? texts.last ?? mode.key)
    }
}

/// A listening mode macOS announced.
struct ListeningModeChange: Equatable, Sendable {
    let mode: ListeningMode
    /// The mode's name, in the Mac's language, for VoiceOver.
    let word: String

    /// AirPods Pro, as Apple's own island draws them for it, whichever AirPods they are.
    static let airpods = "airpods.pro"

    @MainActor
    var alert: NotchAlert {
        NotchAlert(kind: .listeningMode, content: .symbols(leading: Self.airpods, trailing: mode.symbol), spoken: word)
    }
}

extension ListeningMode {
    /// The mode by the number the AirPods report over Bluetooth.
    init?(bluetooth value: Int) {
        switch value {
        case 1: self = .off
        case 2: self = .noiseCancellation
        case 3: self = .transparency
        case 4: self = .adaptive
        default: return nil
        }
    }
}

/// AirPods' listening mode read from the AirPods themselves, with Bluetooth allowed, so every change
/// shows: from the stem, Control Center or the Sound menu, which macOS doesn't always announce. Only
/// what's connected and has listening modes is read, twice a second; the first reading after they
/// connect is only noted.
@MainActor
final class ListeningModeWatch {
    static let shared = ListeningModeWatch()
    private var timer: Timer?
    private var devices: [IOBluetoothDevice] = []
    private var listed = Date.distantPast
    private var modes: [String: ListeningMode] = [:]
    private var changed: ((ListeningModeChange) -> Void)?
    private static let log = Logger(subsystem: "dev.vibe.Glance", category: "listeningMode")

    func start(onChange: @escaping (ListeningModeChange) -> Void) {
        changed = onChange
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { _ in MainActor.assumeIsolated { ListeningModeWatch.shared.read() } }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func read() {
        // Never touching Bluetooth before it's allowed, which would ask.
        guard Permissions.bluetoothAllowed else { return modes.removeAll() }
        if Date.now.timeIntervalSince(listed) > 5 {
            listed = .now
            devices = ((IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []).filter {
                $0.isConnected() && $0.responds(to: NSSelectorFromString("listeningMode"))
                    && (($0.value(forKey: "listeningModeConfigs") as? NSNumber)?.intValue ?? 0) != 0
            }
        }
        var seen: Set<String> = []
        for device in devices where device.isConnected() {
            guard let address = device.addressString,
                let value = (device.value(forKey: "listeningMode") as? NSNumber)?.intValue,
                let mode = ListeningMode(bluetooth: value)
            else { continue }
            seen.insert(address)
            if modes[address] != mode { Self.log.info("listening mode \(value, privacy: .public)") }
            let before = modes.updateValue(mode, forKey: address)
            if let before, before != mode {
                changed?(ListeningModeChange(mode: mode, word: ListeningMode.words()[mode] ?? mode.key))
            }
        }
        modes = modes.filter { seen.contains($0.key) }
    }
}
