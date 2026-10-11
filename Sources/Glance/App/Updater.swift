//
//  Updater.swift
//  Glance
//
//  Created by Gaty on 11/10/2026.
//

import AppKit
import Sparkle

/// Check for Updates…, through Sparkle: it reads the appcast (`updater/appcast.xml`) uploaded with
/// Glance's latest GitHub release, and downloads a newer release's disk image, installing it once its
/// signature matches the key in Info.plist. By default it looks once a day, downloads on its own,
/// and installs when Glance quits. release.sh makes the releases.
@MainActor
final class Updater: NSObject, ObservableObject {
    static let shared = Updater()

    /// False in builds without an update key, which can't check.
    @Published private(set) var isAvailable = false
    /// False while a check is underway, and when the updater isn't available.
    @Published private(set) var canCheck = false

    /// Looking every day, downloading and installing, all without asking.
    var updatesAutomatically: Bool {
        get { controller?.updater.automaticallyDownloadsUpdates ?? false }
        set {
            objectWillChange.send()
            controller?.updater.automaticallyChecksForUpdates = newValue
            controller?.updater.automaticallyDownloadsUpdates = newValue
        }
    }

    private var controller: SPUStandardUpdaterController?
    private var canCheckWatch: NSKeyValueObservation?

    /// Builds made before the update key existed have none to check signatures against, and Sparkle
    /// would greet them with an error, so they leave it off.
    func start() {
        guard controller == nil, Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") != nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
        self.controller = controller
        isAvailable = true
        canCheckWatch = controller.updater.observe(\.canCheckForUpdates, options: [.initial]) { [weak self] updater, _ in
            let can = updater.canCheckForUpdates
            Task { @MainActor in self?.canCheck = can }
        }
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}

extension Updater: SPUStandardUserDriverDelegate {
    /// Glance lives in the menu bar, so a found update waits quietly rather than taking the focus
    /// from whatever app is in front.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }
}
