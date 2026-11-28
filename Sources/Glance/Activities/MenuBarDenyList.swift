//
//  MenuBarDenyList.swift
//  Glance
//
//  Created by Gaty on 25/11/2026.
//

import Foundation

/// Keeps out of the menu bar macOS's own Live Activities that no switch in System Settings lists:
/// AirDrop's. MenuBarAgent leaves out the Live Activities of every app on a list it reads,
/// `MenuBarDeniedLiveActivityBundleIDs`, from its own preferences, which fall back on the global
/// domain, the one place another app can write it. Glance adds those apps to the list there while
/// they should be hidden, and later takes out only the ones it added, so a list the user keeps
/// stays as it was. What it added is remembered, so a Glance that didn't quit cleanly takes them
/// out at its next launch. No Accessibility is needed, and no System Settings opens.
///
/// Hidden this way, AirDrop's Live Activity is gone altogether, the request someone nearby sends
/// included, so it's hidden only while the notch shows AirDrop itself, and a request brings it
/// back until it's answered (see `AirDropRequests`).
@MainActor
struct MenuBarDenyList {
    /// MenuBarAgent's key, as its tuning keys are named: the group, then the setting.
    nonisolated static let key = "MenuBarDeniedLiveActivityBundleIDs"
    /// The apps Glance added to the list, in Glance's own preferences.
    nonisolated static let addedKey = "menuBarDeniedLiveActivities"

    /// The apps that are hidden this way: those no switch takes away.
    let apps: Set<String>
    let store: Store

    init(apps: Set<String> = MenuBarLiveActivities.unswitchable, store: Store = .system) {
        self.apps = apps
        self.store = store
    }

    struct Store {
        /// MenuBarAgent's list, nil when there's none.
        var list: () -> [String]?
        var setList: ([String]?) -> Void
        var added: () -> [String]
        var setAdded: ([String]) -> Void

        static var system: Self {
            let key = MenuBarDenyList.key as CFString
            return Self(
                list: {
                    CFPreferencesCopyValue(key, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [String]
                },
                setList: { list in
                    CFPreferencesSetValue(key, list as CFArray?, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
                    CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
                },
                added: { UserDefaults.standard.stringArray(forKey: MenuBarDenyList.addedKey) ?? [] },
                setAdded: { added in
                    if added.isEmpty {
                        UserDefaults.standard.removeObject(forKey: MenuBarDenyList.addedKey)
                    } else {
                        UserDefaults.standard.set(added, forKey: MenuBarDenyList.addedKey)
                    }
                })
        }
    }

    /// Whether AirDrop's is wanted hidden: while the hider hides, and Glance's own `AirDrop` switch
    /// is on, so what comes in over AirDrop still shows somewhere.
    nonisolated static func hides(_ hiding: Bool, in defaults: UserDefaults = .standard) -> Bool {
        hiding && defaults.bool(forKey: Preferences.activityAirDrop)
    }

    /// Whether it's hidden now: as wanted, but only while a request would be seen (see
    /// `AirDropRequests`), and never while one waits for an answer, as macOS's Live Activity is
    /// the only place it shows.
    nonisolated static func hides(wanted: Bool, requestsSeen: Bool, asking: Bool) -> Bool {
        wanted && requestsSeen && !asking
    }

    /// Puts the apps on the list, or takes off those Glance put there. Only writes when something
    /// changes, so it can run as often as the settings are looked at.
    func apply(hiding: Bool) {
        let list = store.list() ?? []
        let added = store.added()
        if hiding {
            let missing = apps.subtracting(list).sorted()
            guard !missing.isEmpty else { return }
            // Remembered first: should Glance stop between the two, it still takes them out later.
            store.setAdded(added + missing.filter { !added.contains($0) })
            store.setList(list + missing)
        } else {
            guard !added.isEmpty else { return }
            let kept = list.filter { !added.contains($0) }
            if kept != list { store.setList(kept.isEmpty ? nil : kept) }
            store.setAdded([])
        }
    }
}
