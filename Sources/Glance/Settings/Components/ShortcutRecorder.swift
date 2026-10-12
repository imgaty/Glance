//
//  ShortcutRecorder.swift
//  Glance
//
//  Created by Gaty on 12/10/2026.
//

import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A shortcut, as System Settings' Keyboard Shortcuts shows one: its keys, and, clicked, ready for
/// a new one to be typed. Escape leaves it as it was; a shortcut without Command, Option or Control
/// is refused with the alert sound. Its menu puts back the one Glance came with.
struct ShortcutRecorder: View {
    let action: Shortcuts.Action
    @ObservedObject private var shortcuts = Shortcuts.shared
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            Text(recording ? "Type Shortcut" : shortcuts.combos[action]?.symbols ?? "")
                .frame(minWidth: 96)
        }
        .buttonStyle(.bordered)
        .tint(recording ? .accentColor : nil)
        .contextMenu {
            Button("Restore Default") { shortcuts.set(action.standard, for: action) }
                .disabled(shortcuts.combos[action] == action.standard)
        }
        .accessibilityLabel(action.title)
        .accessibilityValue(shortcuts.combos[action]?.symbols ?? "")
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        shortcuts.pause()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated {
                let combo = KeyCombo(event: event)
                if Int(event.keyCode) == kVK_Escape, combo.modifiers == 0 {
                    stop()
                } else if combo.isValid {
                    shortcuts.set(combo, for: action)
                    stop()
                } else {
                    NSSound.beep()
                }
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard recording else { return }
        recording = false
        shortcuts.register()
    }
}
