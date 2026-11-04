//
//  SettingsLastPageTests.swift
//  GlanceTests
//
//  Created by Gaty on 04/11/2026.
//

import Foundation
import Testing

@testable import Glance

/// The page Settings opens on.
@Suite("Settings' last page", .serialized)
struct SettingsLastPageTests {
    @Test("The window opens on General the first time, then on the page last shown")
    func lastPage() {
        preservingDefaults([Preferences.settingsPane]) {
            UserDefaults.standard.removeObject(forKey: Preferences.settingsPane)
            #expect(SettingsPane.last == .general)
            SettingsPane.last = .tray
            #expect(SettingsPane.last == .tray)
        }
    }

    @Test("A page that no longer exists falls back to General")
    func unknownPage() {
        preservingDefaults([Preferences.settingsPane]) {
            UserDefaults.standard.set("gone", forKey: Preferences.settingsPane)
            #expect(SettingsPane.last == .general)
        }
    }

    @Test("The key stays the same, as it's kept in people's defaults")
    func key() {
        #expect(Preferences.settingsPane == "settingsPane")
    }
}
