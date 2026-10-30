//
//  ShortcutRecorder.swift
//  Glance
//
//  Created by Gaty on 12/10/2026.
//

import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A shortcut's row, on the page of what it opens. It works from any app; click it to type another,
/// as in Keyboard Shortcuts settings.
struct ShortcutRow: View {
    let action: Shortcuts.Action
    @ObservedObject private var shortcuts = Shortcuts.shared

    var body: some View {
        LabeledContent {
            ShortcutRecorder(action: action)
        } label: {
            Text(action.title)
            if shortcuts.taken.contains(action) { Text("Another app is using this shortcut.") }
        }
    }
}

/// A shortcut, as System Settings' Keyboard Shortcuts shows one: its keys, and, clicked, ready for
/// a new one to be typed. Escape, a click anywhere else, or leaving the page or the window leaves it
/// as it was; a shortcut without Command, Option or Control, or one another of Glance's shortcuts
/// has, is refused with the alert sound. Its menu puts back the one Glance came with.
struct ShortcutRecorder: View {
    let action: Shortcuts.Action
    @ObservedObject private var shortcuts = Shortcuts.shared
    @Environment(\.shownPage) private var shownPage
    @State private var recording = false
    @State private var monitor: Any?
    /// Where it is in its window, to tell a click on it from a click elsewhere.
    @State private var anchor = ViewAnchor()

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            Text(recording ? "Type Shortcut" : shortcuts.combos[action]?.symbols ?? "")
                .frame(minWidth: 96)
        }
        .buttonStyle(.bordered)
        .tint(recording ? .accentColor : nil)
        .background(ViewFinder(anchor: anchor))
        .contextMenu {
            Button("Restore Default") { shortcuts.set(action.standard, for: action) }
                .disabled(shortcuts.combos[action] == action.standard)
        }
        .accessibilityLabel(action.title)
        .accessibilityValue(shortcuts.combos[action]?.symbols ?? "")
        // Settings keeps its pages once built, so going to another page doesn't take this away:
        // it stops on its own, rather than taking every key typed there, with Glance's shortcuts
        // off all the while.
        .onChange(of: shownPage?.page) { stop() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { note in
            if (note.object as? NSWindow) === anchor.view?.window { stop() }
        }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        shortcuts.pause()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { event in
            // Whether the event goes on: a click does, a key typed here doesn't.
            let passes = MainActor.assumeIsolated { () -> Bool in
                guard event.type == .keyDown else {
                    // A click on it is its own to handle; one anywhere else ends the recording and
                    // goes on to do what it does.
                    if !anchor.contains(event) { stop() }
                    return true
                }
                let combo = KeyCombo(event: event)
                if Int(event.keyCode) == kVK_Escape, combo.modifiers == 0 {
                    stop()
                } else if combo.isValid, !shortcuts.combos.contains(where: { $0.key != action && $0.value == combo }) {
                    shortcuts.set(combo, for: action)
                    stop()
                } else {
                    NSSound.beep()
                }
                return false
            }
            return passes ? event : nil
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

/// The AppKit view behind a SwiftUI view, found once it's in a window.
@MainActor
private final class ViewAnchor {
    weak var view: NSView?

    /// Whether a click lands on the view.
    func contains(_ event: NSEvent) -> Bool {
        guard let view, event.window === view.window else { return false }
        return view.bounds.contains(view.convert(event.locationInWindow, from: nil))
    }
}

private struct ViewFinder: NSViewRepresentable {
    let anchor: ViewAnchor

    func makeNSView(context: Context) -> NSView {
        let view = ClickThrough()
        anchor.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        anchor.view = view
    }

    /// Only marks the place: clicks go to the button over it.
    private final class ClickThrough: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
