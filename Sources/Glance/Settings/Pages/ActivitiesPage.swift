//
//  ActivitiesPage.swift
//  Glance
//
//  Created by Gaty on 16/10/2026.
//

import AppKit
import SwiftUI

/// What the Mac announces beside the camera, each turned on or off, as the iPhone's Dynamic Island
/// shows them; and Clock's timer and stopwatch. The battery's choices show only on a Mac with one.
/// Music's own, with the rest of Music, are a click away.
struct ActivitiesPage: View {
    @AppStorage(Preferences.activityCharging) private var charging = true
    @AppStorage(Preferences.activityLowBattery) private var lowBattery = true
    @AppStorage(Preferences.activityDevices) private var devices = true
    @AppStorage(Preferences.activityAirDrop) private var airDrop = true
    @AppStorage(Preferences.activityClockTimers) private var timers = true
    @AppStorage(Preferences.activityStopwatch) private var stopwatch = true
    @AppStorage(Preferences.clockTimerHidesMenuBar) private var hidesMenuBar = true
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
                    Text("Shows headphones, keyboards, mice, trackpads and game controllers as they connect, and sound going to AirPlay.")
                }
                Toggle(isOn: $airDrop) {
                    Text("AirDrop")
                    Text("Shows files coming in over AirDrop, as they come.")
                }
            }
            Section {
                CenteredRow {
                    Text("Clock")
                    Text("Timers and the stopwatch are Clock's, started there, in Control Center or with Siri.")
                } trailing: {
                    Button("Open Clock") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Clock.app"))
                    }
                }
                Toggle(isOn: $timers) {
                    Text("Timers")
                    Text("Counts down beside the camera, and says when it's done.")
                }
                Toggle(isOn: $stopwatch) {
                    Text("Stopwatch")
                    Text("Counts up beside the camera.")
                }
                Toggle(isOn: $hidesMenuBar) {
                    Text("Hide in menu bar")
                    Text("Takes macOS's timer out of the menu bar while the notch shows it. Needs Accessibility.")
                }
                .disabled(!timers)
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
