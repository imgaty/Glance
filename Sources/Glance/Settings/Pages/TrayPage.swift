//
//  TrayPage.swift
//  Glance
//
//  Created by Gaty on 12/10/2026.
//

import AppKit
import SwiftUI

/// The tray's settings, as Spotlight's for its clipboard history: whether copies and screenshots are
/// kept, for how long, and a way to clear it all.
struct TrayPage: View {
    @AppStorage(Preferences.tray) private var trayOn = true
    @AppStorage(Preferences.trayClipboard) private var keepsCopies = true
    @AppStorage(Preferences.trayClipboardKeep) private var keep = ClipboardKeep.eightHours
    @AppStorage(Preferences.trayScreenshots) private var keepsScreenshots = true
    @ObservedObject private var tray = Tray.shared
    @State private var confirmingClear = false

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $trayOn) {
                    Text("Tray")
                    Text("Keeps files you drop on the notch, what you copy, and your screenshots.")
                }
            }
            Section {
                Toggle(isOn: $keepsCopies) {
                    Text("Keep what you copy")
                    Text("Passwords and other private items are never kept.")
                }
                Toggle(isOn: $keepsScreenshots) {
                    Text("Keep screenshots")
                    Text("Each screenshot joins the tray as soon as it's saved.")
                }
                Picker("Keep copies and screenshots for", selection: $keep) {
                    ForEach(ClipboardKeep.allCases) { Text($0.title).tag($0) }
                }
                .disabled(!keepsCopies && !keepsScreenshots)
                if keepsCopies, tray.pasteBlocked {
                    CenteredRow {
                        Text("Glance can't see what you copy")
                        Text("Allow it in Privacy & Security, under Paste from Other Apps.")
                    } trailing: {
                        Button("Open Privacy & Security") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Pasteboard")!)
                        }
                    }
                }
            }
            .disabled(!trayOn)
            Section {
                CenteredRow {
                    Text("Clear Tray")
                    Text("Removes everything in it. Files stay where they are.")
                } trailing: {
                    Button("Clear…") { confirmingClear = true }
                        .disabled(tray.items.isEmpty)
                }
            }
        }
        .confirmationDialog("Clear the tray?", isPresented: $confirmingClear) {
            Button("Clear Tray", role: .destructive) { tray.clear() }
        } message: {
            Text("Everything in the tray is removed. Files stay where they are.")
        }
    }
}
