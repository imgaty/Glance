//
//  OpeningPage.swift
//  Glance
//
//  Created by Gaty on 07/10/2026.
//

import AppKit
import SwiftUI

struct OpeningPage: View {
    @AppStorage(Preferences.openTrigger) private var openTrigger = OpenTrigger.both
    @AppStorage(Preferences.hoverDelay) private var hoverDelay = 0.2
    @AppStorage(Preferences.clickDelay) private var clickDelay = 0.0
    @AppStorage(Preferences.haptics) private var haptics = false
    @AppStorage(Preferences.swipeToOpen) private var swipeToOpen = true
    @AppStorage(Preferences.swipeToSkip) private var swipeToSkip = true
    @AppStorage(Preferences.swipeToSwitch) private var swipeToSwitch = true
    @AppStorage(Preferences.tray) private var trayOn = true

    var body: some View {
        Form {
            Section {
                Picker("Open with", selection: $openTrigger.animation(.easeInOut(duration: 0.25))) {
                    ForEach(OpenTrigger.allCases) { Text($0.title).tag($0) }
                }
                if openTrigger != .click {
                    delaySlider($hoverDelay, String(localized: "Hover delay"))
                }
                if openTrigger != .hover {
                    delaySlider($clickDelay, String(localized: "Click and hold"))
                }
                Toggle("Haptic feedback", isOn: $haptics)
            }
            // One switch for every swipe, on the trackpad and on a display with Touch, and under it
            // what each does, as Trackpad settings says how its gestures are done.
            Section {
                Toggle(isOn: gestures) {
                    Text("Gestures")
                    Text(
                        trayOn
                            ? String(localized: "Swipe down with two fingers to open the notch, up to close it or swipe a live activity away, and left or right to change songs.")
                                + " " + String(localized: "Swipe with three fingers on the open notch, or scroll holding Shift, to go between tools.")
                            : String(localized: "Swipe down with two fingers to open the notch, up to close it or swipe a live activity away, and left or right to change songs.")
                    )
                }
            }
            Section {
                ShortcutRow(action: .music)
                ShortcutRow(action: .tray)
                    .disabled(!trayOn)
            }
        }
    }

    /// On while any swipe is, turning them all on or off.
    private var gestures: Binding<Bool> {
        Binding(
            get: { swipeToOpen || swipeToSkip || swipeToSwitch },
            set: {
                swipeToOpen = $0
                swipeToSkip = $0
                swipeToSwitch = $0
            })
    }

    /// As System Settings' notched sliders, like Key Repeat: no wait to a second, with a notch every
    /// tenth of a second so the steps show, but only the ends and the middle named.
    private func delaySlider(_ value: Binding<Double>, _ title: String) -> some View {
        LabeledContent(title) {
            Slider(value: value, in: 0...1, step: 0.1) {
                Text(title)
            } tick: { tick in
                switch tick {
                case ..<0.05: return SliderTick(tick) { Text("None") }
                case 0.45..<0.55: return SliderTick(tick) { Text(0.5.formatted(.number.precision(.fractionLength(1))) + " s") }
                case 0.95...: return SliderTick(tick) { Text(1.formatted() + " s") }
                default: return SliderTick(tick)
                }
            }
            .labelsHidden()
            .frame(width: 260)
        }
    }
}
