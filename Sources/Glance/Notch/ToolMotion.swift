//
//  ToolMotion.swift
//  Glance
//
//  Created by Gaty on 14/11/2026.
//

import AppKit
import SwiftUI

/// The original player, lyrics and tray motion. Activity presentation timing is independent.
enum ToolMotion {
    static var open: Animation {
        (NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? Animation.spring(response: 0.42, dampingFraction: 1)
            : .spring(response: 0.5, dampingFraction: 0.68)).paced
    }

    static var close: Animation { Animation.spring(response: 0.315, dampingFraction: 1.18).paced }
    static var peek: Animation { NotchMotion.spring(response: 0.3, dampingFraction: 0.6) }
    static var settle: Animation { NotchMotion.spring(response: 0.35, dampingFraction: 0.8) }
    static var release: Animation { NotchMotion.spring(response: 0.45, dampingFraction: 0.5) }
    static var tracking: Animation { interactive(response: 0.18, damping: 0.86) }
    static var approach: Animation { interactive(response: 0.3, damping: 0.8) }
    static var bubble: Animation {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? close : NotchMotion.spring(response: 0.55, dampingFraction: 0.8)
    }

    static func press(_ down: Bool) -> Animation {
        NotchMotion.spring(response: down ? 0.2 : 0.4, dampingFraction: down ? 0.7 : 0.5)
    }

    private static func interactive(response: Double, damping: Double) -> Animation {
        .interactiveSpring(response: response, dampingFraction: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 1 : damping).paced
    }
}
