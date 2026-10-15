//
//  InstalledApps.swift
//  Glance
//
//  Created by Gaty on 15/10/2026.
//

import AppKit
import Synchronization

/// Apps' names as Finder shows them, without ".app": for the apps in Settings' lists, the app
/// something was copied from, and Open With.
enum InstalledApps {
    /// Looked up once for each app.
    private static let names = Mutex<[String: String?]>([:])

    /// An installed app's name, by its bundle identifier; none if it isn't installed.
    static func name(_ bundle: String) -> String? {
        if let name = names.withLock({ $0[bundle] }) { return name }
        let name = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle).map(name(at:))
        names.withLock { $0[bundle] = name }
        return name
    }

    /// The app at a place.
    static func name(at app: URL) -> String {
        let name = FileManager.default.displayName(atPath: app.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    /// Chosen as apps are in System Settings' lists: from the Applications folder, any number at
    /// once, never Glance itself. Gives their bundle identifiers.
    @MainActor
    static func choose(message: String, then add: @escaping ([String]) -> Void) {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.prompt = "Add"
        panel.message = message
        let chosen: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK else { return }
            add(panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }.filter { $0 != Bundle.main.bundleIdentifier })
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: chosen)
        } else {
            chosen(panel.runModal())
        }
    }
}
