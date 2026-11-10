//
//  PowerModeSettings.swift
//  Glance
//
//  Created by Gaty on 10/11/2026.
//

import AppKit
import ApplicationServices
import os

/// The Mac's own Low Power Mode policy. The native pop-up combines the battery and adapter
/// choices; changing the source in use keeps the other source's choice intact.
@MainActor
enum PowerModeSettings {
    nonisolated private static let log = Logger(subsystem: "dev.vibe.Glance", category: "power")

    /// The four entries in macOS's `low_power_mode` control, in its native order. Titles and the
    /// selected entry are read from Accessibility, so no translated names need to be guessed.
    enum Policy: Int, CaseIterable {
        case never, always, battery, adapter

        var onBattery: Bool { self == .always || self == .battery }
        var onAdapter: Bool { self == .always || self == .adapter }

        func setting(_ on: Bool, onBattery: Bool) -> Policy {
            let battery = onBattery ? on : self.onBattery
            let adapter = onBattery ? self.onAdapter : on
            switch (battery, adapter) {
            case (false, false): return .never
            case (true, true): return .always
            case (true, false): return .battery
            case (false, true): return .adapter
            }
        }
    }

    /// System Settings performs the entitled change, in a separate hidden instance. Its own
    /// window and menus stay hidden, and the user's Settings instance is left as it was.
    static func set(_ on: Bool) async -> Bool {
        guard AXIsProcessTrusted(), let settings = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") else { return false }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.hides = true
        config.createsNewApplicationInstance = true
        guard let instance = try? await NSWorkspace.shared.open([LowPowerMode.settings], withApplicationAt: settings, configuration: config) else { return false }
        instance.hide()
        defer { instance.terminate() }
        let pid = instance.processIdentifier
        guard
            let popup = await Task.detached(operation: { () -> AXUIElement? in
                let end = Date.now.addingTimeInterval(15)
                while Date.now < end {
                    if let popup = findPopup(in: pid) { return popup }
                    try? await Task.sleep(for: .milliseconds(200))
                }
                return nil
            }).value, let reading = BatteryWatch.read()
        else { return false }
        let onBattery = !reading.onPower
        let result = await Task.detached { () -> (Bool, String) in
            let previous = SystemNotices.value(popup, kAXValueAttribute) as? String
            guard AXUIElementPerformAction(popup, kAXPressAction as CFString) == .success else { return (false, "Could not open the policy control") }
            var items: [AXUIElement] = []
            for _ in 0..<20 {
                items = menuItems(in: popup)
                if items.count == Policy.allCases.count { break }
                try? await Task.sleep(for: .milliseconds(50))
            }
            guard items.count == Policy.allCases.count else { return (false, "Policy entries unavailable") }
            let titles = items.map { SystemNotices.value($0, kAXTitleAttribute) as? String ?? "" }
            guard
                let selected = items.firstIndex(where: { !(SystemNotices.value($0, "AXMenuItemMarkChar") as? String ?? "").isEmpty })
                    ?? titles.firstIndex(where: { $0 == previous }), let policy = Policy(rawValue: selected)
            else { return (false, "Selected policy unavailable") }
            let target = policy.setting(on, onBattery: onBattery)
            guard AXUIElementPerformAction(items[target.rawValue], kAXPressAction as CFString) == .success else { return (false, "Policy press failed") }
            for _ in 0..<20 {
                if SystemNotices.value(popup, kAXValueAttribute) as? String == titles[target.rawValue] {
                    return (true, "Policy \(policy.rawValue) to \(target.rawValue); visible Settings windows: \(visibleWindows(pid))")
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
            return (false, "Policy readback failed")
        }.value
        log.notice("Low Power Mode: \(result.1, privacy: .public)")
        guard result.0 else { return false }
        // Keep the instance alive until macOS itself has changed, rather than trusting only
        // Settings' selected item or ending its write by quitting too soon.
        for _ in 0..<30 {
            if ProcessInfo.processInfo.isLowPowerModeEnabled == on {
                try? await Task.sleep(for: .milliseconds(200))
                return true
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        log.notice("Low Power Mode did not change after the policy was selected")
        return false
    }

    nonisolated private static func menuItems(in popup: AXUIElement) -> [AXUIElement] {
        var todo = [popup], items: [AXUIElement] = []
        var at = 0
        let deadline = Date.now.addingTimeInterval(2)
        while at < todo.count, at < 80, Date.now < deadline {
            let item = todo[at]
            at += 1
            if SystemNotices.value(item, kAXRoleAttribute) as? String == kAXMenuItemRole { items.append(item) }
            todo += SystemNotices.value(item, kAXChildrenAttribute) as? [AXUIElement] ?? []
        }
        return items
    }

    nonisolated private static func findPopup(in pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        var todo = (SystemNotices.value(app, kAXWindowsAttribute) as? [AXUIElement] ?? []).map { ($0, 0) }
        var at = 0
        let deadline = Date.now.addingTimeInterval(1)
        while at < todo.count, at < 2500, Date.now < deadline {
            let (element, depth) = todo[at]
            at += 1
            if SystemNotices.value(element, kAXIdentifierAttribute) as? String == "low_power_mode" { return element }
            if depth < 30 { todo += (SystemNotices.value(element, kAXChildrenAttribute) as? [AXUIElement] ?? []).map { ($0, depth + 1) } }
        }
        return nil
    }

    nonisolated private static func visibleWindows(_ pid: pid_t) -> Int {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.filter { ($0[kCGWindowOwnerPID as String] as? Int) == Int(pid) }.count
    }

}
