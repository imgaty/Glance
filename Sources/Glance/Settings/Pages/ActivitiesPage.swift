//
//  ActivitiesPage.swift
//  Glance
//
//  Created by Gaty on 16/10/2026.
//

import AppKit
import SwiftUI

/// What shows beside the camera, each turned on or off, as the iPhone's Dynamic Island shows them:
/// what's playing, what the Mac announces, and Clock's timer and stopwatch. The battery's choices
/// show only on a Mac with one.
struct ActivitiesPage: View {
    @EnvironmentObject private var preview: SettingsPreview
    @Environment(\.shownPage) private var shownPage
    @AppStorage(Preferences.liveActivity) private var liveActivity = true
    @AppStorage(Preferences.musicTrackPop) private var trackPop = true
    @AppStorage(Preferences.activityCharging) private var charging = true
    @AppStorage(Preferences.activityLowBattery) private var lowBattery = true
    @AppStorage(Preferences.activityDevices) private var devices = true
    @AppStorage(Preferences.activityCalls) private var calls = true
    @AppStorage(Preferences.activityAirDrop) private var airDrop = true
    @AppStorage(Preferences.activityClockTimers) private var timers = true
    @AppStorage(Preferences.activityStopwatch) private var stopwatch = true
    @AppStorage(Preferences.activityScreenRecording) private var screenRecording = true
    @AppStorage(Preferences.activityVoiceMemos) private var voiceMemos = true
    @AppStorage(Preferences.clockTimerHidesMenuBar) private var hidesMenuBar = false
    @AppStorage(Preferences.hideMenuBarLiveActivities) private var hidesSystemActivities = true
    /// Taking macOS's timer out of the menu bar takes Accessibility.
    @State private var accessibilityAllowed = AXIsProcessTrusted()
    private let hasBattery = BatteryWatch.hasBattery

    /// The page's switches, in order, and what the picture shows as each is turned on: nothing for
    /// calls, which it doesn't make up.
    static let previews: [(key: String, shows: PreviewActivity?)] = [
        (Preferences.musicTrackPop, .announcement), (Preferences.activityCharging, .charging), (Preferences.activityLowBattery, .lowBattery),
        (Preferences.activityDevices, .device), (Preferences.activityCalls, nil), (Preferences.activityAirDrop, .airDrop),
        (Preferences.activityClockTimers, .timer), (Preferences.activityStopwatch, .stopwatch),
        (Preferences.activityScreenRecording, .screenRecording), (Preferences.activityVoiceMemos, .voiceMemo),
    ]

    /// Each switch, on or off, in that order; read on every change of one of them, as each is kept
    /// here.
    private var switches: [Bool] { Self.previews.map { UserDefaults.standard.object(forKey: $0.key) as? Bool ?? true } }

    var body: some View {
        Form {
            Section {
                PageIntro(.activities, String(localized: "Shows what's going on beside the camera while the notch is closed."))
            }
            Section {
                Toggle(isOn: $hidesSystemActivities) {
                    Text("Hide native Live Activities")
                    Text("Turns them off in Menu Bar settings as they show, so they show only in the notch.")
                }
                // Said only when it's in the way.
                if hidesSystemActivities, !accessibilityAllowed {
                    CenteredRow {
                        Text("Glance can't turn them off")
                        Text("Allow it in Privacy & Security, under Accessibility.")
                    } trailing: {
                        Button("Open Privacy & Security…") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                    }
                }
            }
            Section {
                Toggle(isOn: $liveActivity) {
                    Text("Cover and waveform")
                    Text("Shows the cover on one side of the camera and a waveform on the other.")
                }
                Toggle(isOn: $trackPop) {
                    Text("Announce new audio")
                    Text("Briefly shows what starts playing.")
                }
                .disabled(!liveActivity)
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
                    Text("Shows AirPods and Beats as they connect, and sound going to AirPlay.")
                }
                Toggle(isOn: $calls) {
                    Text("Calls")
                    Text("Shows calls coming in and the call you're on, in place of macOS's popup.")
                }
                Toggle(isOn: $airDrop) {
                    Text("AirDrop")
                    Text("Shows files coming in and going out over AirDrop, as they go.")
                }
            }
            Section {
                Toggle(isOn: $screenRecording) {
                    Text("Screen recording")
                    Text("Shows the screen being recorded, from its countdown until it's saved, with a button to stop it.")
                }
                Toggle(isOn: $voiceMemos) {
                    Text("Voice Memos")
                    Text("Shows a voice memo being recorded, with its sound as it comes in, and a button to stop it.")
                }
            }
            Section {
                CenteredRow {
                    Text("Clock")
                    Text("Timers and the stopwatch are Clock's, started there, in Control Center or with Siri.")
                } trailing: {
                    Button("Open Clock…") {
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
                    Text("Takes macOS's timer out of the menu bar while the notch shows it.")
                }
                .disabled(!timers)
                // Said only when it's in the way, as the Tray page says Glance can't see copies.
                if timers, hidesMenuBar, !accessibilityAllowed {
                    CenteredRow {
                        Text("Glance can't take macOS's timer out")
                        Text("Allow it in Privacy & Security, under Accessibility.")
                    } trailing: {
                        Button("Open Privacy & Security…") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                    }
                }
            } footer: {
                // Before it's turned on, so it's chosen knowing: macOS keeps it, and Glance can't undo it.
                Text(
                    String(
                        localized:
                            "macOS keeps its timer out of the menu bar, even after this is turned off. To bring it back, choose Show When Active for Timer in [Menu Bar settings](x-apple.systempreferences:com.apple.ControlCenter-Settings.extension)."
                    )
                )
            }
        }
        // Turned on, the picture shows what it does.
        .onChange(of: switches) { old, new in
            guard shownPage?.page == .activities, let turned = zip(old, new).enumerated().first(where: { !$0.element.0 && $0.element.1 }),
                let shown = Self.previews[turned.offset].shows
            else { return }
            preview.show(shown)
        }
        // Looked at again on coming back from System Settings.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            accessibilityAllowed = AXIsProcessTrusted()
        }
    }
}
