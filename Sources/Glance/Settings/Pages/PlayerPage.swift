//
//  PlayerPage.swift
//  Glance
//
//  Created by Gaty on 07/10/2026.
//

import AppKit
import SwiftUI

struct PlayerPage: View {
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

    var body: some View {
        Form {
            Section {
                PageIntro(.player, "Open the notch to see what almost any app is playing, with its cover, its controls and the lyrics.")
            }
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
                    Button("Customize Controls…") { customizing = true }
                }
                Toggle(isOn: $lyrics) {
                    Text("Lyrics")
                    Text("Click the waveform to see the words, lit line by line.")
                }
                Toggle("Tint progress bar", isOn: $accentTimeline)
            }
            Section {
                Toggle(isOn: $animatedArtwork) {
                    Text("Animated cover")
                    Text("Plays the album cover's animated version, if it has one.")
                }
                Toggle("Show app icon on cover", isOn: $appBadge)
            }
            Section {
                // Follows the stored list, so an app that has just played appears at once.
                AppList(
                    title: "Show audio from", detail: "Turn an app off to keep it out of the notch.",
                    prompt: "Choose apps to show in the notch.",
                    apps: MusicApps.listed(seen: seenApps.split(separator: ",").map(String.init)),
                    add: MusicApps.add, remove: MusicApps.forget, removable: MusicApps.removable
                ) { app in
                    Toggle(
                        MusicApps.name(of: app),
                        isOn: Binding(
                            get: { !hiddenApps.split(separator: ",").contains(Substring(app)) },
                            set: { MusicApps.set(app, shown: $0) })
                    )
                    .toggleStyle(.switch)
                    .labelsHidden()
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
