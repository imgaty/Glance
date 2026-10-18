//
//  ActivitiesPage.swift
//  Glance
//
//  Created by Gaty on 16/10/2026.
//

import AppKit
import SwiftUI

/// What the Mac announces beside the camera, each turned on or off, as the iPhone's Dynamic Island
/// shows them; and the timer. The battery's choices show only on a Mac with one. Music's own, with
/// the rest of Music, are a click away.
struct ActivitiesPage: View {
    @AppStorage(Preferences.activityCharging) private var charging = true
    @AppStorage(Preferences.activityLowBattery) private var lowBattery = true
    @AppStorage(Preferences.activityDevices) private var devices = true
    @AppStorage(Preferences.activityConnectivity) private var connectivity = true
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
                Toggle(isOn: $connectivity) {
                    Text("Connectivity")
                    Text("Shows when the Mac goes offline, comes back, or joins a Personal Hotspot.")
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
                        Button("Stop") { timer.stop() }
                    } else {
                        Menu("Start Timer") {
                            ForEach(NotchTimer.presets, id: \.self) { minutes in
                                Button(NotchTimer.name(minutes: minutes)) { timer.start(seconds: TimeInterval(minutes * 60)) }
                            }
                        }
                        .fixedSize()
                    }
                }
            }
        }
    }
}
