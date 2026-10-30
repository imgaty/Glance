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
    /// Glance Tray is on in the Share menu, as last looked.
    @State private var shareOn = true

    var body: some View {
        Form {
            Section {
                PageIntro(.tray, "Keeps files you drop on the notch, what you copy, and your screenshots. Drag anything back out when you need it.") {
                    Toggle("Tray", isOn: $trayOn)
                        .toggleStyle(.switch)
                        .labelsHidden()
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
                    Button("Add App…") {
                        InstalledApps.choose(message: "Choose apps whose copies the tray never keeps.") { $0.forEach(TrayApps.add) }
                    }
                }
                // Follows the stored list, so an app added shows at once; by name, as Music's list is.
                ForEach(ignored, id: \.self) { app in
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
            if !shareOn {
                Section {
                    CenteredRow {
                        Text("Add from the Share menu")
                        Text("Turn on Glance Tray, under Extensions in Sharing, to share pictures, links and files to the tray.")
                    } trailing: {
                        Button("Open Login Items & Extensions") { NSWorkspace.shared.open(TrayService.extensionsSettings) }
                    }
                }
                .disabled(!trayOn)
            }
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
        // Looked at again on coming back from System Settings.
        .task { shareOn = await TrayService.shareIsOn() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { shareOn = await TrayService.shareIsOn() }
        }
        .confirmationDialog("Clear the tray?", isPresented: $confirmingClear) {
            Button("Clear Tray", role: .destructive) { tray.clear() }
        } message: {
            Text("Everything in the tray is removed.")
        }
    }

    private var ignored: [String] {
        ignoredApps.split(separator: ",").map(String.init)
            .sorted { MusicApps.name(of: $0).localizedStandardCompare(MusicApps.name(of: $1)) == .orderedAscending }
    }
}
