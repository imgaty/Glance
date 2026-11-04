//
//  AppList.swift
//  Glance
//
//  Created by Gaty on 04/11/2026.
//

import SwiftUI

/// A list of apps in a page's group, the same wherever it is: what the list is for and Add App… at
/// the top, then each app with its icon and name, its own control at the row's end, and Remove from
/// List in its menu, for an app that can be taken off.
struct AppList<Control: View>: View {
    let title: String
    let detail: String
    /// What the panel for choosing apps says.
    let prompt: String
    let apps: [String]
    let add: (String) -> Void
    let remove: (String) -> Void
    var removable: (String) -> Bool = { _ in true }
    @ViewBuilder let control: (String) -> Control

    var body: some View {
        CenteredRow {
            Text(title)
            Text(detail)
        } trailing: {
            Button("Add App…") {
                InstalledApps.choose(message: prompt) { $0.forEach(add) }
            }
        }
        ForEach(apps, id: \.self) { app in
            CenteredRow {
                Label {
                    Text(MusicApps.name(of: app))
                } icon: {
                    AppIcon(bundleID: app)
                }
            } trailing: {
                control(app)
            }
            .contextMenu {
                if removable(app) {
                    Button("Remove from List") { remove(app) }
                }
            }
            .accessibilityActions {
                if removable(app) {
                    Button("Remove from List") { remove(app) }
                }
            }
        }
    }
}
