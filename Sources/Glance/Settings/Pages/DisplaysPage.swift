//
//  DisplaysPage.swift
//  Glance
//
//  Created by Gaty on 07/10/2026.
//

import AppKit
import Combine
import SwiftUI

/// As System Settings' Displays: the display first, pictured with its own desktop and named under
/// it, or chosen across the top; then the settings for that display; then the one for them all.
struct DisplaysPage: View {
    @AppStorage(Preferences.showOnExternalDisplays) private var showOnExternalDisplays = true
    @State private var screens = NSScreen.screens
    /// The display shown, chosen across the top as in System Settings' Displays.
    @State private var chosen = (NSScreen.main ?? NSScreen.screens.first)?.notchID ?? ""

    var body: some View {
        let screen = screens.first { $0.notchID == chosen } ?? screens.first
        Form {
            Section {
                display(screen)
            }
            if let screen {
                DisplaySettings(screen: screen)
                    .id(screen.notchID)
            }
            // The app rebuilds its notches when this changes.
            Section {
                Toggle("Show on external displays", isOn: $showOnExternalDisplays)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            screens = NSScreen.screens
        }
    }

    private func display(_ screen: NSScreen?) -> some View {
        VStack(spacing: 12) {
            ZStack {
                if let screen {
                    DisplayMockup(screen: screen)
                        .id(screen.notchID)
                        .transition(.opacity)
                }
            }
            .frame(height: 84, alignment: .bottom)
            // A choice only when there is one to make; a single display is just named.
            if screens.count > 1 {
                Picker("Display", selection: $chosen) {
                    ForEach(screens, id: \.notchID) { Text($0.localizedName).tag($0.notchID) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            } else if let screen {
                Text(screen.localizedName)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: chosen)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

/// What each display has its own of. The Mac's own display always has the notch; another can go
/// without. The app rebuilds its notches when that changes, and hides or shows them with full
/// screen as it next looks.
private struct DisplaySettings: View {
    let screen: NSScreen
    @AppStorage private var hidesInFullScreen: Bool
    @AppStorage(Preferences.showOnExternalDisplays) private var showOnExternalDisplays = true
    @AppStorage(Preferences.notchHiddenDisplays) private var hiddenDisplays = ""

    init(screen: NSScreen) {
        self.screen = screen
        _hidesInFullScreen = AppStorage(
            wrappedValue: Preferences.hidesInFullScreen(screen.notchID), Preferences.key(Preferences.hideInFullScreen, for: screen.notchID))
    }

    var body: some View {
        Section {
            if !screen.isBuiltIn {
                Toggle("Show the notch", isOn: shown)
                    .disabled(!showOnExternalDisplays)
            }
            Toggle("Hide in full screen", isOn: $hidesInFullScreen)
        }
    }

    private var shown: Binding<Bool> {
        Binding(
            get: { !hiddenDisplays.split(separator: ",").contains(Substring(screen.notchID)) },
            set: { on in
                var hidden = hiddenDisplays.split(separator: ",").map(String.init).filter { $0 != screen.notchID }
                if !on { hidden.append(screen.notchID) }
                hiddenDisplays = hidden.joined(separator: ",")
            })
    }
}
