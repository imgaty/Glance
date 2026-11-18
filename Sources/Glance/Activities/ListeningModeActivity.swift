//
//  ListeningModeActivity.swift
//  Glance
//
//  Created by Gaty on 18/11/2026.
//

import AppKit
import SwiftUI

/// AirPods' listening mode, as macOS 27 announces a change in its banner under the menu bar and
/// shows it on its own island: the AirPods on the left, the mode's symbol on the right, both white.
/// Read from the banner, as Focus is (see `FocusWatch`): Glance asks nothing of the AirPods.
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
