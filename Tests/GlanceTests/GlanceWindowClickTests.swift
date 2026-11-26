//
//  GlanceWindowClickTests.swift
//  GlanceTests
//
//  Created by Gaty on 26/11/2026.
//

import AppKit
import Testing

@testable import Glance

/// Clicks in Glance's own windows, which the watch on other apps' clicks never hears: off the
/// notch, they close it as a click in another app does.
@Suite("Clicks in Glance's own windows")
@MainActor
struct GlanceWindowClickTests {
    private let notch = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 400, height: 200), styleMask: .borderless, backing: .buffered, defer: true)
    private let touch = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 200, height: 40), styleMask: .borderless, backing: .buffered, defer: true)
    private let settings = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: true)

    private func outside(_ window: NSWindow?, menuUp: Bool = false, sharing: Bool = false, quickLook: NSWindow? = nil) -> Bool {
        NotchController.clickIsOutside(in: window, own: [notch, touch], menuUp: menuUp, sharing: sharing, quickLook: quickLook)
    }

    @Test("A click in Settings, or in any other window of Glance's, is outside the notch")
    func settingsIsOutside() {
        #expect(outside(settings))
        // Another display's notch is another notch's window, not this one's.
        let otherNotch = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 400, height: 200), styleMask: .borderless, backing: .buffered, defer: true)
        #expect(outside(otherNotch))
        // A click no window takes, as on the menu bar, isn't on the notch either.
        #expect(outside(nil))
    }

    @Test("Its own window and touch target take their clicks themselves")
    func ownWindows() {
        #expect(!outside(notch))
        #expect(!outside(touch))
        // However the notch is held open, a click on it is still its own.
        #expect(!outside(notch, menuUp: true, sharing: true))
    }

    @Test("A menu opened from it, or Share's picker over the tray, takes its own clicks")
    func keptOpen() {
        #expect(!outside(settings, menuUp: true))
        #expect(!outside(settings, sharing: true))
        #expect(!outside(nil, menuUp: true))
    }

    @Test("Quick Look showing the tray's items keeps it open; once Quick Look is gone, Settings doesn't")
    func quickLook() {
        let look = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 500, height: 500), styleMask: [.titled], backing: .buffered, defer: true)
        #expect(!outside(look, quickLook: look))
        #expect(outside(settings, quickLook: look))
        #expect(outside(look, quickLook: nil))
    }
}
