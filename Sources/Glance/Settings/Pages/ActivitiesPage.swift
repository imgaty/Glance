//
//  ActivitiesPage.swift
//  Glance
//
//  Created by Gaty on 16/10/2026.
//

import AppKit
import SwiftUI

/// What shows beside the camera, each kind turned on or off, as the iPhone's Dynamic Island shows
/// them: what's playing, what the Mac announces, recordings, and Clock's timers and stopwatch. The
/// battery's switch shows only on a Mac with one.
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
    @AppStorage(Preferences.activityFocus) private var focus = true
    @AppStorage(Preferences.activityPrint) private var printing = true
    @AppStorage(Preferences.activityAlarms) private var alarms = true
    @AppStorage(Preferences.activityRecognition) private var recognition = true
    @AppStorage(Preferences.activityShortcuts) private var shortcuts = true
    @AppStorage(Preferences.activityClockTimers) private var timers = true
    @AppStorage(Preferences.activityStopwatch) private var stopwatch = true
    @AppStorage(Preferences.activityScreenRecording) private var screenRecording = true
    @AppStorage(Preferences.activityVoiceMemos) private var voiceMemos = true
    @AppStorage(Preferences.clockTimerHidesMenuBar) private var hidesMenuBar = false
    @AppStorage(Preferences.hideMenuBarLiveActivities) private var hidesSystemActivities = true
    /// Taking macOS's timer out of the menu bar takes Accessibility.
    @State private var accessibilityAllowed = AXIsProcessTrusted()
    private let hasBattery = BatteryWatch.hasBattery

    /// The page's switches in visible order, including each activity within a group.
    static let previews: [(key: String, shows: PreviewActivity?)] = [
        (Preferences.musicTrackPop, .announcement), (Preferences.activityCharging, .charging), (Preferences.activityLowBattery, .lowBattery),
        (Preferences.activityDevices, .device), (Preferences.activityDevices, .airplay),
        (Preferences.activityCalls, .call), (Preferences.activityAirDrop, .airDrop),
        (Preferences.activityScreenRecording, .screenRecording), (Preferences.activityVoiceMemos, .voiceMemo),
        (Preferences.activityClockTimers, .timer), (Preferences.activityStopwatch, .stopwatch),
        (Preferences.activityAlarms, .alarm), (Preferences.activityPrint, .printing), (Preferences.activityFocus, .focus), (Preferences.activityRecognition, .recognition),
        (Preferences.activityShortcuts, .shortcut),
    ]

    /// One switch for a kind of activity: on while any of its own is, turning them all on or off.
    private func kind(_ first: Binding<Bool>, _ second: Binding<Bool>) -> Binding<Bool> {
        Binding(
            get: { first.wrappedValue || second.wrappedValue },
            set: {
                first.wrappedValue = $0
                second.wrappedValue = $0
            })
    }

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
                    Text("Hides native Now Playing while its replacement is visible in Glance. Other activities keep their native controls.")
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
            // One switch for each kind, as Menu Bar settings lists its Live Activities, each turning
            // on or off everything of that kind.
            Section {
                Toggle(isOn: kind($liveActivity, $trackPop)) {
                    Text("Now Playing")
                    Text("Shows the cover and a waveform beside the camera, and briefly shows what starts playing.")
                }
            }
            if hasBattery {
                Section {
                    Toggle(isOn: kind($charging, $lowBattery)) {
                        Text("Battery")
                        Text("Shows the battery's level when you plug in, and warns at 20% and again at 10%.")
                    }
                }
            }
            Section {
                Toggle(isOn: $devices) {
                    Text("Devices")
                    Text("Shows AirPods and Beats as they connect, and sound going to AirPlay.")
                }
            }
            Section {
                Toggle(isOn: $calls) {
                    Text("Calls")
                    Text("Shows calls coming in and the call you're on, in place of macOS's popup.")
                }
            }
            Section {
                Toggle(isOn: $airDrop) {
                    Text("AirDrop")
                    Text("Shows files coming in and going out over AirDrop, as they go.")
                }
            }
            Section {
                Toggle(isOn: kind($screenRecording, $voiceMemos)) {
                    Text("Recordings")
                    Text("Shows the screen or a voice memo being recorded, with a button to stop it.")
                }
            }
            Section {
                Toggle(isOn: kind($timers, $stopwatch)) {
                    Text("Clock")
                    Text("Counts Clock's timers down and its stopwatch up beside the camera, and says when a timer is done.")
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
                // Read as Markdown, so its link is one.
                Text(
                    (try? AttributedString(
                        markdown: String(
                            localized:
                                "macOS keeps its timer out of the menu bar, even after this is turned off. To bring it back, choose Show When Active for Timer in [Menu Bar settings](x-apple.systempreferences:com.apple.ControlCenter-Settings.extension)."
                        ))) ?? ""
                )
            }
            Section {
                Toggle(isOn: $alarms) {
                    Text("Alarms")
                    Text("Shows Clock’s firing alarms with their available Snooze and Stop controls. Requires Accessibility; Clock’s alert remains available.")
                }
            }
            Section {
                Toggle(isOn: $printing) {
                    Text("Printing")
                    Text("Shows your active print jobs, with controls to cancel a job or open Print Center.")
                }
            }
            Section {
                Toggle(isOn: $focus) {
                    Text("Focus Changes")
                    Text("Briefly shows the Focus name and state when macOS announces a change. Requires Accessibility.")
                }
            }
            Section {
                Toggle(isOn: $recognition) {
                    Text("Music Recognition")
                    Text("Choose Recognize Music in Glance’s menu to identify a song with your microphone. Enabling this does not start listening.")
                }
            }
            Section {
                Toggle(isOn: $shortcuts) {
                    Text("Shortcuts")
                    Text("Shows shortcuts you run from Glance’s menu, with a control to stop each run.")
                }
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
