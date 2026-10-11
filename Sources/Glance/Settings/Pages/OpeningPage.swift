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

    var body: some View {
        Form {
            Section {
                Picker("Open with", selection: $openTrigger.animation(.easeInOut(duration: 0.25))) {
                    ForEach(OpenTrigger.allCases) { Text($0.title).tag($0) }
                }
                if openTrigger != .click {
                    delaySlider($hoverDelay, "Hover delay")
                }
                if openTrigger != .hover {
                    delaySlider($clickDelay, "Click and hold")
                }
                Toggle("Haptic feedback", isOn: $haptics)
            }
            // As Trackpad settings lists its gestures: what each does, and under it, how it's done.
            Section {
                Toggle(isOn: $swipeToOpen) {
                    Text("Open and close")
                    Text("Swipe down with two fingers to open, and up to close.")
                }
                Toggle(isOn: $swipeToSkip) {
                    Text("Change songs")
                    Text("Swipe left or right with two fingers.")
                }
            }
        }
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
                case 0.95...: return SliderTick(tick) { Text("Slow") }
                default: return SliderTick(tick)
                }
            }
            .labelsHidden()
            .frame(width: 260)
        }
    }
}
