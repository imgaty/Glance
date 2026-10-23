//
//  ActivitiesPage.swift
//  Glance
//
//  Created by Gaty on 16/10/2026.
//

import AppKit
import SwiftUI

/// What the Mac announces beside the camera, each turned on or off, as the iPhone's Dynamic Island
/// shows them; and the timer, with macOS's own. The battery's choices show only on a Mac with one.
/// Music's own, with the rest of Music, are a click away.
struct ActivitiesPage: View {
    @AppStorage(Preferences.activityCharging) private var charging = true
    @AppStorage(Preferences.activityLowBattery) private var lowBattery = true
    @AppStorage(Preferences.activityDevices) private var devices = true
    @AppStorage(Preferences.activityClockTimers) private var clockTimers = true
    @AppStorage(Preferences.clockTimerHidesMenuBar) private var hidesMenuBar = true
    @ObservedObject private var timer = NotchTimer.shared
    @Environment(\.showPane) private var showPane
    private let hasBattery = BatteryWatch.hasBattery

    var body: some View {
        Form {
            Section {
                CenteredRow {
                    Text("Music")
                    Text("The cover and waveform beside the camera, and new songs as they start, are in Music settings.")
                } trailing: {
                    Button("Music Settings") { showPane.action(.music) }
                }
            }
            if hasBattery {
                Section {
                    Toggle(isOn: $charging) {
                        Text("Charging")
                        Text("Shows the battery's level when you plug in.")
                    }
                    Toggle(isOn: $lowBattery) {
                        Text("Low battery")
                        Text("Warns at 20% and again at 10%.")
                    }
                }
            }
            Section {
                Toggle(isOn: $devices) {
                    Text("Devices")
                    Text("Shows headphones, keyboards, mice and trackpads as they connect, and sound going to AirPlay.")
                }
            }
            Section {
                CenteredRow {
                    Text("Timer")
                    Text("Counts down beside the camera. You can also start one from Glance in the menu bar.")
                } trailing: {
                    if let state = timer.state {
                        HStack {
                            Button(state.isRunning ? "Pause" : "Resume") { state.isRunning ? timer.pause() : timer.resume() }
                            Button("Cancel") { timer.cancel() }
                        }
                    } else if timer.ringing {
                        HStack {
                            Button("Repeat") { timer.repeatLast() }
                            Button("Stop") { timer.stop() }
                        }
                    } else {
                        Menu("Start Timer") {
                            ForEach(NotchTimer.presets, id: \.self) { minutes in
                                Button(NotchTimer.name(minutes: minutes)) { timer.start(seconds: TimeInterval(minutes * 60)) }
                            }
                        }
                        .fixedSize()
                    }
                }
                Toggle(isOn: $clockTimers) {
                    Text("Clock timers")
                    Text("Shows timers started in the Clock app, in Control Center or with Siri.")
                }
                Toggle(isOn: $hidesMenuBar) {
                    Text("Hide in menu bar")
                    Text("Takes macOS's timer out of the menu bar while the notch shows it. Needs Accessibility.")
                }
                .disabled(!clockTimers)
                CenteredRow {
                    Text("Menu bar timer")
                    Text("Once taken out, macOS's timer comes back with Show When Active for Timer in Menu Bar settings.")
                } trailing: {
                    Button("Menu Bar Settings…") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension")!)
                    }
                }
            }
        }
    }
}
