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
/// and Bluetooth's banner at the top of the screen for a device connecting or running low, hidden,
/// as is the banner under the menu bar for AirPods doing the same. macOS's settings for them stay as
/// they are; without Accessibility, they show as before.
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
    nonisolated static let bluetoothBanners = "com.apple.BluetoothUIService"

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

    // MARK: Banners under the menu bar

    /// The menu bar's own app, which shows Control Center's banners in windows of its own.
    private nonisolated static let menuBarAgent = "com.apple.MenuBarAgent"
    /// The one for AirPods, by the name Accessibility knows it by: connecting, running low, or
    /// offering the sound back from another device.
    private nonisolated static let airPodsBanner = "smart-routing-system-banner"

    private static var bannerWatch: (app: AXUIElement, pid: pid_t, observer: AXObserver)?
    private static var bannerShown: () -> Void = {}
    /// The last one seen: each is told of more than once as it's made.
    private static var lastBanner: AXUIElement?

    /// Follows the menu bar, for AirPods' banner, each as it's made: told at once, unlike the banners
    /// looked for above, so it's gone before it shows. `shown` is called for each.
    static func watchBanners(shown: @escaping () -> Void) {
        bannerShown = shown
        followMenuBar()
    }

    /// With Accessibility allowed since, or the menu bar started again, it's followed anew.
    static func followMenuBar() {
        guard AXIsProcessTrusted(),
            let agent = NSRunningApplication.runningApplications(withBundleIdentifier: menuBarAgent).first?.processIdentifier,
            agent != bannerWatch?.pid
        else { return }
        var made: AXObserver?
        let told: AXObserverCallback = { _, _, _, _ in MainActor.assumeIsolated { SystemNotices.menuBarChanged() } }
        guard AXObserverCreate(agent, told, &made) == .success, let observer = made else { return }
        let app = AXUIElementCreateApplication(agent)
        AXUIElementSetMessagingTimeout(app, 0.3)
        AXObserverAddNotification(observer, app, kAXCreatedNotification as CFString, nil)
        AXObserverAddNotification(observer, app, kAXWindowCreatedNotification as CFString, nil)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        bannerWatch = (app, agent, observer)
    }

    /// Its banner is taken off the screen as it's made, before there's anything to read in it, and
    /// put back unless it turns out to be one the notch says too. What's reconnected as the Mac
    /// wakes isn't announced, so it stays.
    private static func menuBarChanged() {
        guard let app = bannerWatch?.app,
            let banner = (value(app, kAXWindowsAttribute) as? [AXUIElement] ?? []).first(where: { value($0, "AXIdentifier") as? String == airPodsBanner }),
            lastBanner.map({ !CFEqual($0, banner) }) ?? true
        else { return }
        lastBanner = banner
        defer { bannerShown() }
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: Preferences.notchEnabled), defaults.bool(forKey: Preferences.activityDevices), !Activities.shared.settling,
            let place = position(of: banner)
        else { return }
        // Past every display.
        let away = CGPoint(x: (NSScreen.screens.map(\.frame.minX).min() ?? 0) - 4000, y: -4000)
        guard move(banner, to: away) else { return }
        Task {
            for _ in 0..<25 {
                if showsBattery(findAll(in: banner) { value($0, kAXRoleAttribute) as? String == kAXStaticTextRole }.compactMap { value($0, kAXValueAttribute) as? String }) {
                    return
                }
                try? await Task.sleep(for: .milliseconds(20))
            }
            move(banner, to: place)
        }
    }

    /// AirPods connecting or running low show their level, which is what the notch says; offering
    /// the sound back, they have nothing to tell and something to press.
    nonisolated static func showsBattery(_ words: [String]) -> Bool {
        words.contains { word in !word.isEmpty && word.allSatisfy { $0.isNumber || $0 == "%" } }
    }

    private static func position(of element: AXUIElement) -> CGPoint? {
        guard let found = value(element, kAXPositionAttribute), CFGetTypeID(found) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(found as! AXValue, .cgPoint, &point) ? point : nil
    }

    @discardableResult private static func move(_ element: AXUIElement, to point: CGPoint) -> Bool {
        var point = point
        guard let place = AXValueCreate(.cgPoint, &point) else { return false }
        return AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, place) == .success
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
