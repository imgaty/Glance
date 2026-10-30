//
//  GeneralPage.swift
//  Glance
//
//  Created by Gaty on 07/10/2026.
//

import AppKit
import SwiftUI

struct GeneralPage: View {
    @Environment(\.showPermissions) private var showPermissions
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        Form {
            Section {
                PageIntro(.general)
            }
            Section {
                LaunchAtLoginToggle()
                CenteredRow {
                    Text("Permissions")
                    Text("Allow access to audio and media apps.")
                } trailing: {
                    Button("Review…", action: showPermissions.action)
                }
            }
            Section {
                CenteredRow {
                    Text("Version \(BuildInfo.version)")
                    Text("New versions come from Glance's releases on GitHub.")
                } trailing: {
                    Button("Check for Updates…", action: updater.checkForUpdates)
                        .disabled(!updater.canCheck)
                }
                Toggle(
                    "Update automatically",
                    isOn: Binding(get: { updater.updatesAutomatically }, set: { updater.updatesAutomatically = $0 })
                )
                .disabled(!updater.isAvailable)
            }
            // Builds made from source say when and from where, for Rebuild.
            if let source = BuildInfo.sourceDirectory {
                Section {
                    LabeledContent("Built", value: BuildInfo.date ?? "")
                    LabeledContent("Source") {
                        Text(source.path(percentEncoded: false))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }
}
