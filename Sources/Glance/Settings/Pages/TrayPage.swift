//
//  TrayPage.swift
//  Glance
//
//  Created by Gaty on 12/10/2026.
//

import AppKit
import SwiftUI

/// The tray's settings, as Spotlight's for its clipboard history: whether copies and screenshots are
/// kept, for how long, apps whose copies never are, and a way to clear it all.
struct TrayPage: View {
    @AppStorage(Preferences.tray) private var trayOn = true
    @AppStorage(Preferences.trayClipboard) private var keepsCopies = true
    @AppStorage(Preferences.trayClipboardKeep) private var keep = ClipboardKeep.eightHours
    @AppStorage(Preferences.trayScreenshots) private var keepsScreenshots = true
    @AppStorage(Preferences.trayIgnoredApps) private var ignoredApps = ""
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
                    Text("Never keep copies from")
                    Text("What you copy in these apps doesn't join the tray.")
                } trailing: {
                    Button("Add App…", action: addApps)
                }
                // Follows the stored list, so an app added shows at once.
                ForEach(ignoredApps.split(separator: ",").map(String.init), id: \.self) { app in
                    CenteredRow {
                        Label {
                            Text(MusicApps.name(of: app))
                        } icon: {
                            AppIcon(bundleID: app)
                        }
                    } trailing: {
                        Button("Remove") { TrayApps.remove(app) }
                            .accessibilityLabel("Remove \(MusicApps.name(of: app))")
                    }
                }
            } header: {
                SectionTitle("Apps")
            }
            .disabled(!trayOn || !keepsCopies)
            Section {
                CenteredRow {
                    Text("Clear tray")
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

    /// Chosen as apps are in System Settings' lists: from the Applications folder, any number at once.
    private func addApps() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.prompt = "Add"
        panel.message = "Choose apps whose copies the tray never keeps."
        let add: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK else { return }
            for url in panel.urls {
                if let app = Bundle(url: url)?.bundleIdentifier, app != Bundle.main.bundleIdentifier { TrayApps.add(app) }
            }
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: add)
        } else {
            add(panel.runModal())
        }
    }
}
