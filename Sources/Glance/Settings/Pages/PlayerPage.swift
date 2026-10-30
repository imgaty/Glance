//
//  MusicPage.swift
//  Glance
//
//  Created by Gaty on 07/10/2026.
//

import AppKit
import SwiftUI

struct MusicPage: View {
    @EnvironmentObject private var preview: SettingsPreview
    @State private var customizing = false
    @AppStorage(Preferences.lyrics) private var lyrics = true
    @AppStorage(Preferences.musicHiddenApps) private var hiddenApps = ""
    @AppStorage(Preferences.musicSeenApps) private var seenApps = ""
    @AppStorage(Preferences.musicShowsNewApps) private var showsNewApps = true
    @AppStorage(Preferences.musicLayout) private var layout = PlayerLayout.top
    @AppStorage(Preferences.musicAccentTimeline) private var accentTimeline = true
    @AppStorage(Preferences.musicAppBadge) private var appBadge = false
    @AppStorage(Preferences.musicAnimatedArtwork) private var animatedArtwork = true
    @AppStorage(Preferences.liveActivity) private var liveActivity = true
    @AppStorage(Preferences.musicTrackPop) private var trackPop = true

    var body: some View {
        Form {
            Section {
                CenteredRow(alignment: .top) {
                    // Level with the tops of the pictures, inside their rings.
                    Text("Layout")
                        .padding(.top, 3)
                } trailing: {
                    ThumbnailPicker(selection: $layout, options: PlayerLayout.allCases.map { ($0, $0.title) }, columns: 2) { layout in
                        NotchThumbnail(layout: layout, display: preview.display)
                    }
                }
                CenteredRow {
                    Text("Controls")
                    Text("Choose the buttons beside the playback controls.")
                } trailing: {
                    Button("Customize Controls") { customizing = true }
                }
                Toggle(isOn: $lyrics) {
                    Text("Lyrics")
                    Text("Click the waveform to see the words, lit line by line.")
                }
                Toggle("Tint progress bar", isOn: $accentTimeline)
            }
            Section {
                Toggle(isOn: $animatedArtwork) {
                    Text("Animated art")
                    Text("Plays the album cover's animated version, if it has one.")
                }
                Toggle("Show app icon on artwork", isOn: $appBadge)
            }
            Section {
                Toggle(isOn: $liveActivity) {
                    Text("Cover and waveform")
                    Text("Shows what's playing beside the camera while the notch is closed.")
                }
                Toggle(isOn: $trackPop) {
                    Text("Announce new audio")
                    Text("Briefly shows what starts playing.")
                }
                .disabled(!liveActivity)
            }
            Section {
                // Follows the stored list, so an app that has just played appears at once.
                ForEach(MusicApps.listed(seen: seenApps.split(separator: ",").map(String.init)), id: \.self) { app in
                    Toggle(
                        isOn: Binding(
                            get: { !hiddenApps.split(separator: ",").contains(Substring(app)) },
                            set: { MusicApps.set(app, shown: $0) })
                    ) {
                        Label {
                            Text(MusicApps.name(of: app))
                        } icon: {
                            AppIcon(bundleID: app)
                        }
                    }
                    .contextMenu {
                        if MusicApps.removable(app) {
                            Button("Remove from List") { MusicApps.forget(app) }
                        }
                    }
                }
                CenteredRow {
                    Text("Other apps")
                    Text("Add apps to show or hide them.")
                } trailing: {
                    Button("Add App…") {
                        InstalledApps.choose(message: "Choose apps to show in the notch.") { $0.forEach(MusicApps.add) }
                    }
                }
                Toggle(isOn: $showsNewApps) {
                    Text("Show new apps")
                    Text("Apps that start playing are added turned on.")
                }
            } header: {
                SectionTitle("Apps")
            }
        }
        .sheet(isPresented: $customizing) {
            ControlsSheet(display: preview.display, top: preview.top)
        }
    }
}
