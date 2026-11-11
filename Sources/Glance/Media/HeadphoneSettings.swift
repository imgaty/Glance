//
//  HeadphoneSettings.swift
//  Glance
//
//  Created by Gaty on 11/11/2026.
//

import AppKit
import ApplicationServices

/// Connected headphones have a dynamic sidebar entry, not a fixed Settings URL. Open Bluetooth
/// first, then select the exact device's entry using Glance's existing Accessibility access.
enum HeadphoneSettings {
    @MainActor static func open(named name: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") else { return }
        NSWorkspace.shared.open(url)
        guard AXIsProcessTrusted() else { return }
        Task.detached {
            let deadline = Date.now.addingTimeInterval(4)
            // Let the URL select Bluetooth before selecting the dynamic headphone entry.
            try? await Task.sleep(for: .milliseconds(300))
            var confirmed = 0
            while Date.now < deadline, !Task.isCancelled {
                if let process = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").first {
                    let app = AXUIElementCreateApplication(process.processIdentifier)
                    AXUIElementSetMessagingTimeout(app, 0.15)
                    if let sidebar = find(
                        in: app, deadline: deadline,
                        matching: {
                            SystemNotices.value($0, kAXIdentifierAttribute) as? String == "com.apple.settings.sidebar.collectionView"
                        })
                    {
                        let rows = SystemNotices.value(sidebar, kAXChildrenAttribute) as? [AXUIElement] ?? []
                        let matches = rows.filter { row in
                            find(in: row, deadline: deadline) { element in
                                [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute].contains {
                                    SystemNotices.value(element, $0) as? String == name
                                }
                            } != nil
                        }
                        if matches.count == 1 {
                            if (SystemNotices.value(matches[0], kAXSelectedAttribute) as? NSNumber)?.boolValue == true {
                                confirmed += 1
                                if confirmed >= 3 { return }
                            } else {
                                confirmed = 0
                                guard AXUIElementSetAttributeValue(matches[0], kAXSelectedAttribute as CFString, kCFBooleanTrue) == .success else { return }
                            }
                        }
                    }
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    private static func find(in root: AXUIElement, deadline: Date, matching: (AXUIElement) -> Bool) -> AXUIElement? {
        var pending = [(root, 0)], seen = Set<AXUIElement>()
        while let (element, depth) = pending.popLast(), seen.count < 250, Date.now < deadline {
            guard seen.insert(element).inserted else { continue }
            if matching(element) { return element }
            if depth < 7 {
                pending += (SystemNotices.value(element, kAXChildrenAttribute) as? [AXUIElement] ?? []).map { ($0, depth + 1) }
            }
        }
        return nil
    }
}
