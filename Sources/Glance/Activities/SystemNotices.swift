//
//  SystemNotices.swift
//  Glance
//
//  Created by Gaty on 24/10/2026.
//

import AppKit
import ApplicationServices

/// macOS's own notifications for what the notch says, found in Notification Center through
/// Accessibility, to be answered or taken away as they show, so nothing is said twice: Clock's
/// alert for a timer that's done, Control Center's Low Battery, and AirPods' own when they run low;
/// and Bluetooth's banner at the top of the screen for a device connecting or running low, hidden.
/// macOS's settings for them stay as they are; without Accessibility, they show as before.
@MainActor
enum SystemNotices {
    /// The alerts and banners showing from an app, by the name it goes by in the system's language,
    /// newest first.
    static func showing(from app: String) -> [AXUIElement] {
        guard AXIsProcessTrusted(),
            let center = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").first
        else { return [] }
        let element = AXUIElementCreateApplication(center.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.5)
        let subroles: Set<String> = ["AXNotificationCenterAlert", "AXNotificationCenterBanner"]
        return (value(element, kAXWindowsAttribute) as? [AXUIElement] ?? []).flatMap {
            findAll(in: $0) { subroles.contains(value($0, kAXSubroleAttribute) as? String ?? "") }
        }
        .filter { words(of: $0).hasPrefix(app + ",") }
    }

    /// What it says, as VoiceOver reads it: "Clock, Timer", or the app, its title and its text.
    static func words(of notification: AXUIElement) -> String {
        value(notification, kAXDescriptionAttribute) as? String ?? ""
    }

    /// Presses one of its buttons, by its English name, or in another language by its place among
    /// them, counted from the end. Whether it was there.
    @discardableResult
    static func press(_ english: String, fromEnd place: Int, on notification: AXUIElement) -> Bool {
        var names: CFArray?
        AXUIElementCopyActionNames(notification, &names)
        let named = (names as? [String] ?? []).filter { $0.hasPrefix("Name:") }
        let action = named.first { $0.hasPrefix("Name:" + english) } ?? (named.count >= place ? named[named.count - place] : nil)
        guard let action else { return false }
        return AXUIElementPerformAction(notification, action as CFString) == .success
    }

    /// Takes away an app's notification saying any of these words, as its Close does, if it shows
    /// within a few seconds; looked for every tenth of a second, as it shows a moment after what it
    /// tells of.
    static func close(from app: String, saying words: [String], within seconds: Double = 10) {
        guard AXIsProcessTrusted() else { return }
        Task { @MainActor in
            let until = Date.now + seconds
            while Date.now < until {
                let found = showing(from: app).first { notification in
                    words.contains { Self.words(of: notification).localizedCaseInsensitiveContains($0) }
                }
                if let found {
                    press("Close", fromEnd: 1, on: found)
                    return
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    /// Bluetooth's banners for devices, at the top of the screen: an app of their own, started for
    /// each while it shows.
    static let bluetoothBanners = "com.apple.BluetoothUIService"

    /// Bluetooth's banner, as it shows within a few seconds, hidden while the notch says the same;
    /// shown again after, for any banner that comes later.
    static func hideBluetoothBanner(within seconds: Double = 4) {
        guard UserDefaults.standard.bool(forKey: Preferences.notchEnabled) else { return }
        Task { @MainActor in
            let until = Date.now + seconds
            while Date.now < until {
                if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bluetoothBanners).first {
                    if !app.isHidden, !app.hide(), AXIsProcessTrusted() {
                        AXUIElementSetAttributeValue(AXUIElementCreateApplication(app.processIdentifier), kAXHiddenAttribute as CFString, kCFBooleanTrue)
                    }
                    try? await Task.sleep(for: .seconds(6))
                    if !app.isTerminated, app.isHidden { app.unhide() }
                    return
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    /// AirPods' own notification that they need charging, in Notification Center, taken away.
    static func closeAirPodsReminder() {
        let bundle = URL(fileURLWithPath: "/System/Library/UserNotifications/Bundles/com.apple.AudioAccessoryUserNotifications.bundle")
        let app = Bundle(url: bundle)?.localizedInfoDictionary?["CFBundleDisplayName"] as? String ?? "AirPods"
        close(from: app, saying: [words("CHARGING_REMINDER_TITLE", table: "Localizable", of: bundle)], within: 30)
    }

    /// The name an app goes by in the system's language, as Notification Center names it.
    static func name(of app: URL) -> String {
        FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: "")
    }

    /// Words an app of macOS's says, in the system's language, from its own tables.
    static func words(_ key: String, table: String, of app: URL) -> String {
        Bundle(url: app)?.localizedString(forKey: key, value: key, table: table) ?? key
    }

    static func value(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    static func findAll(in element: AXUIElement, where match: (AXUIElement) -> Bool) -> [AXUIElement] {
        (match(element) ? [element] : []) + (value(element, kAXChildrenAttribute) as? [AXUIElement] ?? []).flatMap { findAll(in: $0, where: match) }
    }
}
