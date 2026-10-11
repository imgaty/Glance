//
//  DisplaysPage.swift
//  Glance
//
//  Created by Gaty on 07/10/2026.
//

import AppKit
import Combine
import SwiftUI

struct DisplaysPage: View {
    @AppStorage(Preferences.showOnPlainDisplays) private var showOnPlainDisplays = true
    @AppStorage(Preferences.hideInFullScreen) private var hideInFullScreen = true
    @State private var screens = NSScreen.screens
    /// The display shown, chosen across the top as in System Settings' Displays.
    @State private var chosen = (NSScreen.main ?? NSScreen.screens.first)?.notchID ?? ""
    /// Re-read when a style is chosen.
    @State private var styles = NotchStyle.signature

    var body: some View {
        let screen = screens.first { $0.notchID == chosen } ?? screens.first
        Form {
            // These are for every display, so they come first, before the display is chosen, as in
            // Sound and Notifications settings. The app rebuilds its notches when either changes.
            Section {
                Toggle("Show on displays without a notch", isOn: $showOnPlainDisplays)
                Toggle("Hide in full screen", isOn: $hideInFullScreen)
            }
            // Then one display: pictured with its own desktop and named under it, as in System
            // Settings' Displays, with its own settings in the same group.
            Section {
                display(screen)
                if let screen {
                    style(screen)
                }
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

    @ViewBuilder private func style(_ screen: NSScreen) -> some View {
        let notch = screen.safeAreaInsets.top > 0
        let label = Label {
            Text("Style")
        } icon: {
            Image(systemName: notch ? "laptopcomputer" : "display")
        }
        if notch || !showOnPlainDisplays {
            LabeledContent {
                Text(notch ? "Notch" : "None")
                    .foregroundStyle(.secondary)
            } label: {
                label
            }
        } else {
            // A display without a notch shows the one chosen for it.
            Picker(selection: style(of: screen)) {
                ForEach(NotchStyle.allCases) { Text($0.title).tag($0) }
            } label: {
                label
            }
        }
    }

    private func style(of screen: NSScreen) -> Binding<NotchStyle> {
        Binding {
            _ = styles
            return NotchStyle.of(screen)
        } set: { style in
            UserDefaults.standard.set(style.rawValue, forKey: Preferences.key(Preferences.notchStyle, for: screen.notchID))
            styles = NotchStyle.signature
        }
    }
}
