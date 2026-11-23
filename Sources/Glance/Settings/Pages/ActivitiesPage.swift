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
    @AppStorage(Preferences.activityAlarms) private var alarms = true
    @AppStorage(Preferences.activityRecognition) private var recognition = true
    @AppStorage(Preferences.activityShortcuts) private var shortcuts = true
    @AppStorage(Preferences.activityClockTimers) private var timers = true
    @AppStorage(Preferences.activityStopwatch) private var stopwatch = true
    @AppStorage(Preferences.activityScreenRecording) private var screenRecording = true
    @AppStorage(Preferences.activityVoiceMemos) private var voiceMemos = true
    @AppStorage(Preferences.clockTimerHidesMenuBar) private var hidesMenuBar = false
    @AppStorage(Preferences.hideMenuBarLiveActivities) private var hidesSystemActivities = true
    @AppStorage(Preferences.liveActivityPlace) private var place = LiveActivityPlace.notch
    /// Taking macOS's timer out of the menu bar takes Accessibility.
    @State private var accessibilityAllowed = AXIsProcessTrusted()
    private let hasBattery = BatteryWatch.hasBattery

    /// The page's switches in visible order, including each activity within a group.
    static let previews: [(key: String, shows: PreviewActivity?)] = [
        (Preferences.musicTrackPop, .announcement), (Preferences.activityCharging, .charging), (Preferences.activityLowBattery, .lowBattery),
        (Preferences.activityDevices, .device),
        (Preferences.activityCalls, .call), (Preferences.activityAirDrop, .airDrop),
        (Preferences.activityScreenRecording, .screenRecording), (Preferences.activityVoiceMemos, .voiceMemo),
        (Preferences.activityClockTimers, .timer), (Preferences.activityStopwatch, .stopwatch),
        (Preferences.activityAlarms, .alarm), (Preferences.activityFocus, .focus), (Preferences.activityRecognition, .recognition),
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

    /// With Menu Bar chosen, what macOS shows there itself isn't in the notch.
    private var inMenuBar: Bool { place == .menuBar }

    /// The switch of something macOS shows in the menu bar itself: with Menu Bar chosen, off and
    /// grayed out, its own value kept as it was underneath, for when Notch is chosen again.
    private func placed(_ binding: Binding<Bool>) -> Binding<Bool> { Self.placed(binding) { place } }

    static func placed(_ binding: Binding<Bool>, place: @escaping () -> LiveActivityPlace) -> Binding<Bool> {
        Binding(
            get: { LiveActivityPlace.shown(binding.wrappedValue, place: place()) },
            set: { if place() == .notch { binding.wrappedValue = $0 } })
    }

    /// What each place includes, one after the other, under the choice.
    static var placesFootnote: AttributedString {
        let text = LiveActivityPlace.allCases.map(\.includes).joined(separator: "\n")
        return (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }

    /// Each switch, on or off, in that order; read on every change of one of them, as each is kept
    /// here.
    private var switches: [Bool] { Self.previews.map { UserDefaults.standard.object(forKey: $0.key) as? Bool ?? true } }

    var body: some View {
        Form {
            Section {
                PageIntro(.activities, String(localized: "Shows what's going on beside the camera while the notch is closed."))
            }
            // Where they show, and under it what each place includes, as a section's footnote.
            Section {
                Picker("Show in", selection: $place.animation(.easeInOut(duration: 0.25))) {
                    ForEach(LiveActivityPlace.allCases) { Text($0.title).tag($0) }
                }
            } footer: {
                Text(Self.placesFootnote)
            }
            // In the menu bar, macOS's own stay as they are: there's nothing to hide, so it shows off
            // and grayed out, as the switches of what's there do.
            Section {
                Toggle(isOn: placed($hidesSystemActivities)) {
                    Text("Hide native Live Activities")
                    Text(
                        "Hides every native Live Activity in the menu bar, other apps' too, while the notch shows Live Activities. macOS's own Music Recognition stays hidden. Clock stays, as its alarms show nowhere else."
                    )
                }
                .disabled(inMenuBar)
                .grayedOut(inMenuBar)
                // Said only when it's in the way.
                if !inMenuBar, hidesSystemActivities, !accessibilityAllowed {
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
                Toggle(isOn: placed(kind($liveActivity, $trackPop))) {
                    Text("Now Playing")
                    Text("Shows the cover and a waveform beside the camera, and briefly shows what starts playing.")
                }
                .disabled(inMenuBar)
                .grayedOut(inMenuBar)
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
                    Text("Shows AirPods and Beats as they connect.")
                }
            }
            Section {
                Toggle(isOn: $calls) {
                    Text("Calls")
                    Text("Shows calls coming in and the call you're on, in place of macOS's popup.")
                }
            }
            Section {
                Toggle(isOn: placed($airDrop)) {
                    Text("AirDrop")
                    Text("Shows files coming in and going out over AirDrop, as they go.")
                }
                .disabled(inMenuBar)
                .grayedOut(inMenuBar)
            }
            Section {
                Toggle(isOn: placed(kind($screenRecording, $voiceMemos))) {
                    Text("Recordings")
                    Text("Shows the screen or a voice memo being recorded, with a button to stop it.")
                }
                .disabled(inMenuBar)
                .grayedOut(inMenuBar)
            }
            Section {
                Toggle(isOn: placed(kind($timers, $stopwatch))) {
                    Text("Clock")
                    Text("Counts Clock's timers down and its stopwatch up beside the camera, and says when a timer is done.")
                }
                .disabled(inMenuBar)
                .grayedOut(inMenuBar)
                Toggle(isOn: placed($hidesMenuBar)) {
                    Text("Hide in menu bar")
                    Text("Takes macOS's timer out of the menu bar while the notch shows it.")
                }
                .disabled(!timers || inMenuBar)
                .grayedOut(inMenuBar)
                // Said only when it's in the way, as the Tray page says Glance can't see copies.
                if !inMenuBar, timers, hidesMenuBar, !accessibilityAllowed {
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
                Toggle(isOn: placed($alarms)) {
                    Text("Alarms")
                    Text("Shows Clock's alarms as they ring, with Snooze and Stop. Needs Accessibility.")
                }
                .disabled(inMenuBar)
                .grayedOut(inMenuBar)
            }
            Section {
                Toggle(isOn: $focus) {
                    Text("Focus")
                    Text("Briefly shows a Focus turning on or off. Needs Accessibility.")
                }
            }
            Section {
                Toggle(isOn: $recognition) {
                    Text("Music Recognition")
                    Text("Recognizes the song playing near you when you choose Recognize Music in the notch's menu. Glance listens only then.")
                }
            }
            Section {
                Toggle(isOn: $shortcuts) {
                    Text("Shortcuts")
                    Text("Shows shortcuts as they run, wherever you start them, with a button to stop each.")
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

extension View {
    /// Grayed out as well as disabled, words and all, as System Settings grays a row that can't be
    /// changed: SwiftUI's form leaves a disabled switch's words as they were.
    @ViewBuilder func grayedOut(_ grayed: Bool) -> some View {
        if grayed { foregroundStyle(.tertiary) } else { self }
    }
}
