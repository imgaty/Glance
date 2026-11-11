//
//  GeneralPage.swift
//  Glance
//
//  Created by Gaty on 07/10/2026.
//

import AppKit
import SwiftUI

struct GeneralPage: View {
    @ObservedObject private var updater = Updater.shared
    @State private var reviewing = false

    var body: some View {
        Form {
            Section {
                LaunchAtLoginToggle()
                CenteredRow {
                    Text("Permissions")
                    Text("Review access for Glance's features.")
                } trailing: {
                    Button("Review…") { reviewing = true }
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
                    String(localized: "Update automatically"),
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
        .sheet(isPresented: $reviewing) { PermissionsSheet() }
    }
}
