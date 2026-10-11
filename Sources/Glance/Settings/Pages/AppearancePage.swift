//
//  AppearancePage.swift
//  Glance
//
//  Created by Gaty on 07/10/2026.
//

import AppKit
import Combine
import SwiftUI

/// How the notch looks: Liquid Glass from clear to black, how much it blurs what's behind it, the
/// accent color, and the background while music plays. With more than one display, each keeps its
/// own look unless they share one; the preview above shows the display being edited.
struct AppearancePage: View {
    @EnvironmentObject private var preview: SettingsPreview
    @AppStorage(Preferences.sameLook) private var sameLook = false
    @State private var screens = NSScreen.screens

    var body: some View {
        Form {
            if screens.count > 1 {
                Section {
                    Toggle("Use the same appearance on all displays", isOn: Binding(get: { sameLook }, set: setSameLook))
                    if !sameLook {
                        Picker("Display", selection: $preview.display) {
                            ForEach(screens, id: \.notchID) { Text($0.localizedName).tag($0.notchID) }
                        }
                    }
                }
            }
            LookEditor(display: preview.display, shared: sameLook)
                .id(sameLook ? "shared" : preview.display)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            screens = NSScreen.screens
            if !screens.contains(where: { $0.notchID == preview.display }), let first = screens.first {
                preview.display = first.notchID
            }
        }
    }

    /// Going to one look, the display being edited sets it; going back to one each, every display
    /// starts from that shared look. The app rebuilds its notches when this changes.
    private func setSameLook(_ on: Bool) {
        let defaults = UserDefaults.standard
        for key in Preferences.perDisplay {
            if on {
                if let value = defaults.object(forKey: Preferences.key(key, for: preview.display)) { defaults.set(value, forKey: key) }
            } else if let shared = defaults.object(forKey: key) {
                for screen in NSScreen.screens { defaults.set(shared, forKey: Preferences.key(key, for: screen.notchID)) }
            }
        }
        sameLook = on
    }
}

/// The look's settings for one display, or the shared one.
private struct LookEditor: View {
    let display: String
    @ObservedObject private var accessibility = SystemAccessibility.shared
    @AppStorage private var followsSystem: Bool
    @AppStorage private var darkness: Double
    @AppStorage private var blur: Double
    @AppStorage private var background: MusicBackground
    @AppStorage(Preferences.musicLayout) private var layout = PlayerLayout.top
    @AppStorage(Preferences.musicAccentSource) private var accentSource = AccentSource.artwork

    init(display: String, shared: Bool) {
        if !shared { Preferences.seed(display) }
        func key(_ name: String) -> String { shared ? name : Preferences.key(name, for: display) }
        self.display = display
        _followsSystem = AppStorage(wrappedValue: false, key(Preferences.glassFollowsSystem))
        _darkness = AppStorage(wrappedValue: 0, key(Preferences.glassDarkness))
        _blur = AppStorage(wrappedValue: 0, key(Preferences.glassBlur))
        _background = AppStorage(wrappedValue: .replaceGlass, key(Preferences.musicBackground))
    }

    var body: some View {
        Section {
            Toggle(isOn: $followsSystem.animation(.easeInOut(duration: 0.25))) {
                Text("Match system Liquid Glass")
                Text("Uses the style set in Appearance settings.")
            }
            if !followsSystem {
                LabeledContent("Liquid Glass") {
                    slider($darkness, from: "capsule.on.rectangle.liquid.glass", "Clear", to: "capsule.on.rectangle.fill", "Black")
                }
                LabeledContent("Blur") {
                    slider($blur, from: "circle", "None", to: "circle.dotted", "Full")
                }
            }
        } footer: {
            if accessibility.reducesTransparency {
                Text("The notch is opaque while Reduce transparency is on in Accessibility settings.")
            }
        }
        .disabled(accessibility.reducesTransparency)
        Section {
            // One choice, as Apple would make it: the cover's colors, or the Mac's own accent.
            Toggle(isOn: Binding(get: { accentSource == .artwork }, set: { accentSource = $0 ? .artwork : .system })) {
                Text("Use artwork colors")
                Text("Tints the notch with the cover's colors, instead of your Mac's accent color.")
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Background")
                ThumbnailPicker(selection: $background, options: MusicBackground.allCases.map { ($0, $0.title) }) { background in
                    NotchThumbnail(layout: layout, display: display, background: background)
                        // Drawn afresh for a new layout.
                        .id(layout)
                }
            }
        }
    }

    /// As System Settings shows its Liquid Glass slider: a symbol at each end. The symbols get the
    /// same room on every slider, so the sliders are as long as each other and line up.
    private func slider(
        _ value: Binding<Double>, from low: String, _ lowName: String,
        to high: String, _ highName: String
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: low)
                .frame(width: 24)
                .accessibilityLabel(lowName)
            Slider(value: value, in: 0...1)
                .labelsHidden()
                .accessibilityValue(
                    value.wrappedValue < 0.05
                        ? lowName
                        : value.wrappedValue > 0.95
                            ? highName
                            : "\(Int(value.wrappedValue * 100))%")
            Image(systemName: high)
                .frame(width: 24)
                .accessibilityLabel(highName)
        }
        .foregroundStyle(.secondary)
        .frame(width: 260)
    }
}
