//
//  ToolMotion.swift
//  Glance
//
//  Created by Gaty on 14/11/2026.
//

import AppKit
import SwiftUI

/// The player, lyrics and tray motion. They open and close on the island's one spring; their
/// gestures, page turns and lyrics keep their own.
enum ToolMotion {
    static var open: Animation {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? Animation.spring(response: 0.42, dampingFraction: 1).paced : NotchMotion.island
    }

    static var close: Animation {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? Animation.spring(response: 0.315, dampingFraction: 1.18).paced : NotchMotion.island
    }
    static var settle: Animation { NotchMotion.spring(response: 0.35, dampingFraction: 0.8) }
    static var release: Animation { NotchMotion.spring(response: 0.45, dampingFraction: 0.5) }
    static var tracking: Animation { interactive(response: 0.18, damping: 0.86) }
    static var approach: Animation { interactive(response: 0.3, damping: 0.8) }
    static var bubble: Animation { close }

    private static func interactive(response: Double, damping: Double) -> Animation {
        .interactiveSpring(response: response, dampingFraction: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 1 : damping).paced
    }
}
