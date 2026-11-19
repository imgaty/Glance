//
//  AirDropAnswer.swift
//  Glance
//
//  Created by Gaty on 19/11/2026.
//

import AppKit
import ApplicationServices

/// Answers an AirDrop that asks to be accepted, as macOS's own Accept and Decline do. First through
/// the request itself: macOS's AirDrop observer hands each transfer over with the actions its own
/// request offers (`possibleActions`, and `cancelAction` to decline), each run by the handler macOS
/// gave it. Without one, by pressing macOS's own button, read by Accessibility: in AirDrop's Live
/// Activity in the menu bar (macOS 27.3's AirDropUI), or in its notification. Never by moving the
/// pointer. Built from what macOS's code and words show; an incoming request was never seen on this
/// Mac while it was written.
enum AirDropAnswer {
    enum Choice: Equatable, Sendable {
        case accept, decline
    }

    /// sharingd's action for saving what comes in to Downloads, which Accept does with files.
    static let saveToDownloads = "SDSaveToDownloadsActionIdentifier"
    /// sharingd's action that declines a request, or stops a transfer.
    static let cancel = "SDCancelActionIdentifier"

    /// Which of the request's offered actions is Accept, by their identifiers: saving to Downloads
    /// if it's offered, otherwise the first that isn't the one declining.
    static func acceptAction(among identifiers: [String], declining: String?) -> Int? {
        if let save = identifiers.firstIndex(of: saveToDownloads) { return save }
        return identifiers.firstIndex { $0 != declining && $0 != cancel }
    }

    /// Runs one of macOS's AirDrop actions, if macOS gave it a handler to run; without one, its
    /// `triggerAction` would crash. Whether it ran.
    @discardableResult
    static func trigger(_ action: NSObject) -> Bool {
        let selector = NSSelectorFromString("triggerAction")
        guard action.responds(to: selector), action.responds(to: NSSelectorFromString("actionHandler")),
            action.value(forKey: "actionHandler") != nil
        else { return false }
        action.perform(selector)
        return true
    }

    /// Answers the request: by its own action, or else by macOS's own button.
    @MainActor
    static func answer(_ choice: Choice, transfer: NSObject?) {
        if let transfer, let action = action(choice, in: transfer), trigger(action) { return }
        let titles = Self.titles(choice)
        Task.detached(priority: .userInitiated) { _ = pressButton(titles: titles) }
    }

    /// The request's own action for the choice, if it offers one.
    private static func action(_ choice: Choice, in transfer: NSObject) -> NSObject? {
        let declining = transfer.value(forKey: "cancelAction") as? NSObject
        switch choice {
        case .decline: return declining
        case .accept:
            let offered = (transfer.value(forKey: "possibleActions") as? [NSObject]) ?? []
            let identifiers = offered.map { $0.value(forKey: "actionIdentifier") as? String ?? "" }
            return acceptAction(among: identifiers, declining: declining?.value(forKey: "actionIdentifier") as? String).map { offered[$0] }
        }
    }

    // MARK: macOS's own buttons

    /// What macOS calls the button in the Mac's language, as AirDrop's Live Activity and its
    /// notification word it, and in English.
    static func titles(_ choice: Choice) -> Set<String> {
        let ui = Bundle(path: "/System/Library/CoreServices/AirDropUI.app")
        let sharing = Bundle(path: "/System/Library/PrivateFrameworks/Sharing.framework")
        let keys: [(Bundle?, String)] =
            switch choice {
            case .accept: [(ui, "Accept"), (ui, "AirDropUIAcceptButtonTitle"), (sharing, "ACCEPT_BUTTON_TITLE")]
            case .decline: [(ui, "Decline"), (sharing, "DECLINE_BUTTON_TITLE")]
            }
        var titles: Set<String> = [choice == .accept ? "Accept" : "Decline"]
        for (bundle, key) in keys {
            if let title = bundle?.localizedString(forKey: key, value: nil, table: "Localizable"), title != key { titles.insert(title) }
        }
        return titles
    }

    /// Whether a button, by its title and description, is the one named.
    static func isButton(labels: [String], named titles: Set<String>) -> Bool {
        labels.contains { titles.contains($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    /// Presses macOS's own button: in AirDrop's Live Activity under the menu bar, or else in its
    /// notification. Whether one was found and pressed.
    nonisolated static func pressButton(titles: Set<String>) -> Bool {
        if let button = liveActivityButton(titles: titles) {
            return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
        }
        return pressNotification(titles: titles)
    }

    /// The button inside AirDrop's Live Activity, opened under the menu bar, as Clock's alarm has
    /// its Snooze and Dismiss.
    nonisolated private static func liveActivityButton(titles: Set<String>) -> AXUIElement? {
        guard AXIsProcessTrusted(),
            let agent = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.MenuBarAgent").first
        else { return nil }
        let app = AXUIElementCreateApplication(agent.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.2)
        var roots = SystemNotices.value(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
        if let bar = SystemNotices.value(app, kAXExtrasMenuBarAttribute), CFGetTypeID(bar) == AXUIElementGetTypeID() { roots.append(bar as! AXUIElement) }
        // Each element, with whether it's inside a Live Activity.
        var pending = roots.map { ($0, 0, false) }, seen = Set<AXUIElement>()
        let deadline = Date.now.addingTimeInterval(1)
        while let (element, depth, inside) = pending.popLast(), seen.count < 1500, Date.now < deadline {
            guard seen.insert(element).inserted else { continue }
            let role = SystemNotices.value(element, kAXRoleAttribute) as? String
            let subrole = SystemNotices.value(element, kAXSubroleAttribute) as? String
            let within = inside || subrole == "AXLiveActivity"
            if within, role == kAXButtonRole {
                let labels = [kAXTitleAttribute, kAXDescriptionAttribute, kAXIdentifierAttribute].compactMap { SystemNotices.value(element, $0) as? String }
                if isButton(labels: labels, named: titles) { return element }
            }
            // Only the pills' and Live Activities' own subtrees can hold it.
            if depth < 12 {
                pending += (SystemNotices.value(element, kAXChildrenAttribute) as? [AXUIElement] ?? []).map { ($0, depth + 1, within) }
            }
        }
        return nil
    }

    /// AirDrop's notification, by its action named as the button is.
    nonisolated private static func pressNotification(titles: Set<String>) -> Bool {
        guard AXIsProcessTrusted(),
            let center = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").first
        else { return false }
        let app = AXUIElementCreateApplication(center.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.5)
        let subroles: Set<String> = ["AXNotificationCenterAlert", "AXNotificationCenterBanner"]
        let notifications = (SystemNotices.value(app, kAXWindowsAttribute) as? [AXUIElement] ?? []).flatMap {
            SystemNotices.findAll(in: $0) { subroles.contains(SystemNotices.value($0, kAXSubroleAttribute) as? String ?? "") }
        }
        for notification in notifications where (SystemNotices.value(notification, kAXDescriptionAttribute) as? String ?? "").hasPrefix("AirDrop") {
            var names: CFArray?
            AXUIElementCopyActionNames(notification, &names)
            let action = (names as? [String] ?? []).first { name in
                guard name.hasPrefix("Name:") else { return false }
                let label = name.dropFirst(5).split(separator: "\n").first.map(String.init) ?? ""
                return isButton(labels: [label], named: titles)
            }
            if let action { return AXUIElementPerformAction(notification, action as CFString) == .success }
        }
        return false
    }
}
