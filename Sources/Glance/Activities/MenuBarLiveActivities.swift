//
//  MenuBarLiveActivities.swift
//  Glance
//
//  Created by Gaty on 07/11/2026.
//

import AppKit
import ApplicationServices

/// macOS's own Live Activities in the menu bar, from macOS 27.3, which say what the notch says: Now
/// Playing, a screen recording and the like. The only switches macOS honors for them are System
/// Settings' own, under Menu Bar > Live Activities, one for each app (the private call behind them
/// takes Apple's entitlement, and a pill takes no Accessibility action but Press). So while Hide
/// macOS's Live Activities is on, Glance turns those switches off as soon as a pill shows, pressing
/// them through Accessibility in System Settings, opened in the background and closed after. Turned
/// back off, it turns on again the ones it turned off.
@MainActor
final class MenuBarLiveActivities {
    static let shared = MenuBarLiveActivities()

    private static let pane = URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension")!
    private static let settingsApp = "com.apple.systempreferences"
    /// The switches Glance turned off, by the names System Settings shows them by.
    static let turnedOffKey = "menuBarLiveActivitiesTurnedOff"

    private var timer: Timer?
    private var working = false
    private var settingObserver: NSObjectProtocol?
    private var wasOn = UserDefaults.standard.bool(forKey: Preferences.hideMenuBarLiveActivities)

    func start() {
        guard ActivityBench.scene == nil, timer == nil else { return }
        // A pill can show at any moment; looking for one is a handful of Accessibility calls.
        let timer = Timer(timeInterval: 3, repeats: true) { _ in
            MainActor.assumeIsolated { MenuBarLiveActivities.shared.check() }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        settingObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                let on = UserDefaults.standard.bool(forKey: Preferences.hideMenuBarLiveActivities)
                guard on != MenuBarLiveActivities.shared.wasOn else { return }
                MenuBarLiveActivities.shared.wasOn = on
                MenuBarLiveActivities.shared.check()
            }
        }
        check()
    }

    /// Hides any that show, or, turned off, shows again what Glance hid.
    private func check() {
        guard !working, AXIsProcessTrusted() else { return }
        let on = UserDefaults.standard.bool(forKey: Preferences.hideMenuBarLiveActivities)
        let hidden = UserDefaults.standard.stringArray(forKey: Self.turnedOffKey) ?? []
        if on, Self.pillShowing() {
            working = true
            Task {
                await switchApps(off: true)
                working = false
            }
        } else if !on, !hidden.isEmpty {
            working = true
            Task {
                await switchApps(off: false)
                working = false
            }
        }
    }

    /// A Live Activity's pill in the menu bar, any app's.
    static func pillShowing() -> Bool {
        guard let agent = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.MenuBarAgent").first else { return false }
        let app = AXUIElementCreateApplication(agent.processIdentifier)
        // Never kept waiting by the menu bar.
        AXUIElementSetMessagingTimeout(app, 0.2)
        func find(_ element: AXUIElement, _ depth: Int) -> Bool {
            if (SystemNotices.value(element, kAXIdentifierAttribute) as? String)?.hasPrefix(pillPrefix) == true { return true }
            guard depth < 10 else { return false }
            return (SystemNotices.value(element, kAXChildrenAttribute) as? [AXUIElement] ?? []).contains { find($0, depth + 1) }
        }
        return (SystemNotices.value(app, kAXWindowsAttribute) as? [AXUIElement] ?? []).contains { find($0, 0) }
    }

    /// What MenuBarAgent names a Live Activity's pill by, before the app's bundle ID.
    nonisolated static let pillPrefix = "live-activity-pill-"

    /// The section's heading, in the Mac's language, as System Settings words it.
    private static var sectionName: String {
        let bundle = Bundle(path: "/System/Library/ExtensionKit/Extensions/ControlCenterSettings.appex")
        return bundle?.localizedString(forKey: "Live Activities", value: "Live Activities", table: "Localizable") ?? "Live Activities"
    }

    /// Opens Menu Bar settings in the background, turns each app's switch off, or back on those Glance
    /// turned off, and closes System Settings again if it wasn't open.
    private func switchApps(off: Bool) async {
        let wasOpen = !NSRunningApplication.runningApplications(withBundleIdentifier: Self.settingsApp).isEmpty
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        _ = try? await NSWorkspace.shared.open(Self.pane, configuration: configuration)
        var rows: [(name: String, box: AXUIElement)] = []
        for _ in 0..<40 {
            try? await Task.sleep(for: .milliseconds(150))
            rows = Self.rows()
            if !rows.isEmpty { break }
        }
        var hidden = UserDefaults.standard.stringArray(forKey: Self.turnedOffKey) ?? []
        for row in rows {
            let isOn = SystemNotices.value(row.box, kAXValueAttribute) as? Int == 1
            if off, isOn {
                AXUIElementPerformAction(row.box, kAXPressAction as CFString)
                if !hidden.contains(row.name) { hidden.append(row.name) }
            } else if !off, !isOn, hidden.contains(row.name) {
                AXUIElementPerformAction(row.box, kAXPressAction as CFString)
            }
        }
        UserDefaults.standard.set(off ? hidden : [], forKey: Self.turnedOffKey)
        if !wasOpen {
            try? await Task.sleep(for: .milliseconds(300))
            NSRunningApplication.runningApplications(withBundleIdentifier: Self.settingsApp).first?.terminate()
        }
    }

    /// Each app's name and switch in Menu Bar settings' Live Activities section: the checkboxes after
    /// its heading, each after its name, until its buttons.
    private static func rows() -> [(name: String, box: AXUIElement)] {
        guard let settings = NSRunningApplication.runningApplications(withBundleIdentifier: settingsApp).first else { return [] }
        let app = AXUIElementCreateApplication(settings.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 1)
        var flat: [AXUIElement] = []
        func walk(_ element: AXUIElement, _ depth: Int) {
            guard depth < 40, flat.count < 3000 else { return }
            flat.append(element)
            for child in SystemNotices.value(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] { walk(child, depth + 1) }
        }
        for window in SystemNotices.value(app, kAXWindowsAttribute) as? [AXUIElement] ?? [] { walk(window, 0) }
        let name = sectionName
        guard
            let heading = flat.firstIndex(where: { element in
                SystemNotices.value(element, kAXRoleAttribute) as? String == "AXHeading"
                    && [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute].contains { SystemNotices.value(element, $0) as? String == name }
            })
        else { return [] }
        var rows: [(name: String, box: AXUIElement)] = []
        var label: String?
        for element in flat[(heading + 1)...] {
            switch SystemNotices.value(element, kAXRoleAttribute) as? String {
            case "AXStaticText": label = SystemNotices.value(element, kAXValueAttribute) as? String
            case "AXCheckBox": if let label { rows.append((label, element)) }
            case "AXButton", "AXHeading": return rows
            default: break
            }
        }
        return rows
    }
}
