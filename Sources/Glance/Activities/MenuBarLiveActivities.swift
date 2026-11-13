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
/// them through Accessibility in a System Settings of its own, opened in the background beside any
/// the user has open and quit after. Turned back off, it turns on again the ones it turned off.
/// Screenshot is always left alone: its authorization also supplies the recording indicator
/// Glance follows, and macOS doesn't reliably replace a denied Live Activity with a legacy stop
/// item. If an older Glance version turned Screenshot off, only that owned change is restored.
/// Behind a full-screen app, that System Settings' window opens on another Space, where
/// Accessibility can take many seconds to see it; if it never does, Glance waits for the Space to
/// change, or a minute, before trying again, rather than opening System Settings over and over.
/// macOS's microphone and camera indicator isn't one of these: it has no switch, and hiding it is
/// kept to Apple's own processes.
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
    private var spaceObserver: NSObjectProtocol?
    /// After System Settings' switches couldn't be reached, not before this, or the Space changing.
    private var retryAfter = Date.distantPast
    /// How long System Settings' switches are waited for, and how long before trying again without.
    private nonisolated static let patience: Duration = .seconds(20)
    private static let retryDelay: TimeInterval = 60
    private var wasOn = UserDefaults.standard.bool(forKey: Preferences.hideMenuBarLiveActivities)
    /// Every eligible switch is to be turned off, not only those whose pill shows.
    private var allPending = UserDefaults.standard.bool(forKey: Preferences.hideMenuBarLiveActivities)

    /// Screenshot's pill's app.
    nonisolated static let capture = "com.apple.screencaptureui"
    /// Screenshot's name, as System Settings lists it.
    nonisolated static var screenshotName: String {
        FileManager.default.displayName(atPath: "/System/Applications/Utilities/Screenshot.app").replacingOccurrences(of: ".app", with: "")
    }

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
                // Turned on, every eligible switch goes off at once.
                MenuBarLiveActivities.shared.allPending = on
                MenuBarLiveActivities.shared.retryAfter = .distantPast
                MenuBarLiveActivities.shared.check()
            }
        }
        // Off a full-screen app, System Settings' window opens where it can be seen.
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                MenuBarLiveActivities.shared.retryAfter = .distantPast
                MenuBarLiveActivities.shared.check()
            }
        }
        check()
    }

    /// Hides any that show, or, turned off, shows again what Glance hid. Nothing here waits on the
    /// thread that draws the notch.
    private func check() {
        guard !working, Date.now >= retryAfter, AXIsProcessTrusted() else { return }
        let on = UserDefaults.standard.bool(forKey: Preferences.hideMenuBarLiveActivities)
        let hidden = UserDefaults.standard.stringArray(forKey: Self.turnedOffKey) ?? []
        guard on || !hidden.isEmpty else { return }
        working = true
        Task {
            defer {
                working = false
                // A second toggle may arrive while the first Settings instance is still working.
                if UserDefaults.standard.bool(forKey: Preferences.hideMenuBarLiveActivities) != on {
                    retryAfter = .distantPast
                    allPending = !on
                    check()
                }
            }
            let showing = await Task.detached { Self.pillShowing(ignoring: [Self.capture]) }.value
            guard UserDefaults.standard.bool(forKey: Preferences.hideMenuBarLiveActivities) == on else { return }
            var reached = true
            // Also migrate an owned Screenshot change when no pill can appear because its
            // authorization was disabled. A user-disabled, unowned switch is never enabled.
            if on, showing || allPending || hidden.contains(Self.screenshotName) {
                reached = await switchApps(off: true)
                if reached { allPending = false }
            } else if !on {
                reached = await switchApps(off: false)
            }
            if !reached { retryAfter = .now + Self.retryDelay }
        }
    }

    /// Any pill except those being ignored, in either native menu bar tree.
    nonisolated static func pillShowing(ignoring: [String] = []) -> Bool {
        pills().contains { !ignoring.contains($0) }
    }

    nonisolated private static func pills() -> Set<String> {
        guard let agent = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.MenuBarAgent").first else { return [] }
        let app = AXUIElementCreateApplication(agent.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.2)
        var roots = SystemNotices.value(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
        if let bar = SystemNotices.value(app, kAXExtrasMenuBarAttribute), CFGetTypeID(bar) == AXUIElementGetTypeID() { roots.append(bar as! AXUIElement) }
        var pending = roots.map { ($0, 0) }, seen = Set<AXUIElement>(), found = Set<String>()
        let deadline = Date.now.addingTimeInterval(1)
        while let (element, depth) = pending.popLast(), seen.count < 1500, Date.now < deadline {
            guard seen.insert(element).inserted else { continue }
            if let identifier = SystemNotices.value(element, kAXIdentifierAttribute) as? String, identifier.hasPrefix(pillPrefix) {
                found.insert(String(identifier.dropFirst(pillPrefix.count)))
            }
            if depth < 12 { pending += (SystemNotices.value(element, kAXChildrenAttribute) as? [AXUIElement] ?? []).map { ($0, depth + 1) } }
        }
        return found
    }

    /// What MenuBarAgent names a Live Activity's pill by, before the app's bundle ID.
    nonisolated static let pillPrefix = "live-activity-pill-"

    /// The section's heading, in the Mac's language, as System Settings words it.
    nonisolated private static var sectionName: String {
        let bundle = Bundle(path: "/System/Library/ExtensionKit/Extensions/ControlCenterSettings.appex")
        return bundle?.localizedString(forKey: "Live Activities", value: "Live Activities", table: "Localizable") ?? "Live Activities"
    }

    /// Reconciles eligible switches in a background System Settings of Glance's own. Screenshot is
    /// only restored if Glance disabled it; other apps follow the hide preference and owned list.
    private func switchApps(off: Bool) async -> Bool {
        guard let settings = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.settingsApp) else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.hides = true
        // Beside any the user has open, which may be on another Space, and left as it is.
        configuration.createsNewApplicationInstance = true
        guard let instance = try? await NSWorkspace.shared.open([Self.pane], withApplicationAt: settings, configuration: configuration) else { return false }
        instance.hide()
        defer { instance.terminate() }
        let pid = instance.processIdentifier
        let rows = await Task.detached { () -> [(name: String, box: AXUIElement)] in
            let clock = ContinuousClock()
            let deadline = clock.now + Self.patience
            while clock.now < deadline {
                try? await Task.sleep(for: .milliseconds(250))
                let rows = Self.rows(in: pid)
                if !rows.isEmpty { return rows }
            }
            return []
        }.value
        guard !rows.isEmpty else { return false }
        let hidden = UserDefaults.standard.stringArray(forKey: Self.turnedOffKey) ?? []
        let policy = SwitchPolicy(hiding: off, hidden: hidden, screenshot: Self.screenshotName)
        let result = await Task.detached { () -> SwitchResult in
            var result = SwitchResult(hidden: hidden)
            for row in rows {
                guard let target = policy.target(for: row.name) else { continue }
                var state = SystemNotices.value(row.box, kAXValueAttribute) as? Int
                let changed = state == (target ? 0 : 1)
                if changed {
                    guard AXUIElementPerformAction(row.box, kAXPressAction as CFString) == .success else {
                        result.failed = true
                        continue
                    }
                    for _ in 0..<20 {
                        try? await Task.sleep(for: .milliseconds(75))
                        state = SystemNotices.value(row.box, kAXValueAttribute) as? Int
                        if state == (target ? 1 : 0) { break }
                    }
                }
                result.record(name: row.name, off: !target, changed: changed, confirmed: state == (target ? 1 : 0))
            }
            return result
        }.value
        UserDefaults.standard.set(result.hidden, forKey: Self.turnedOffKey)
        // Keep missing and failed restores for another attempt, including after a restart.
        let reached = policy.isComplete(result)
        try? await Task.sleep(for: .milliseconds(300))
        return reached
    }

    /// Pure policy shared by migration and ordinary reconciliation, without changing settings.
    struct SwitchPolicy {
        let hiding: Bool
        let hidden: [String]
        let screenshot: String

        /// Nil leaves the user's current setting untouched, including a disabled Screenshot.
        func target(for name: String) -> Bool? {
            if name == screenshot { return hidden.contains(name) ? true : nil }
            if hiding { return false }
            return hidden.contains(name) ? true : nil
        }

        func isComplete(_ result: SwitchResult) -> Bool {
            !result.failed && (hiding ? !result.hidden.contains(screenshot) : result.hidden.isEmpty)
        }
    }

    struct SwitchResult {
        var hidden: [String]
        var failed = false

        mutating func record(name: String, off: Bool, changed: Bool, confirmed: Bool) {
            guard confirmed else {
                failed = true
                return
            }
            if off, changed, !hidden.contains(name) { hidden.append(name) }
            if !off { hidden.removeAll { $0 == name } }
        }
    }

    /// Recent systems label the switch itself. Earlier systems place a text label before a
    /// checkbox. In either case, stop at the next heading or section button.
    struct SectionReader {
        let heading: String
        private(set) var inside = false
        private(set) var finished = false
        private var precedingLabel: String?

        mutating func read(role: String, labels: [String], value: String?) -> String? {
            guard !finished else { return nil }
            if !inside {
                inside = role == "AXHeading" && (labels + [value ?? ""]).contains(heading)
                return nil
            }
            switch role {
            case "AXButton", "AXHeading": finished = true
            case "AXStaticText": precedingLabel = value
            case "AXSwitch", "AXCheckBox":
                let name = labels.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? precedingLabel
                precedingLabel = nil
                return name
            default: break
            }
            return nil
        }
    }

    nonisolated private static func rows(in pid: pid_t) -> [(name: String, box: AXUIElement)] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        var pending = (SystemNotices.value(app, kAXWindowsAttribute) as? [AXUIElement] ?? []).reversed().map { ($0, 0) }
        var seen = Set<AXUIElement>(), rows: [(name: String, box: AXUIElement)] = []
        var section = SectionReader(heading: sectionName)
        let deadline = Date.now.addingTimeInterval(2)
        while let (element, depth) = pending.popLast(), seen.count < 3000, Date.now < deadline {
            guard seen.insert(element).inserted else { continue }
            let role = SystemNotices.value(element, kAXRoleAttribute) as? String ?? ""
            let relevant = section.inside || role == "AXHeading"
            let labels = relevant ? [kAXTitleAttribute, kAXDescriptionAttribute].compactMap { SystemNotices.value(element, $0) as? String } : []
            let value = relevant ? SystemNotices.value(element, kAXValueAttribute) as? String : nil
            if let name = section.read(role: role, labels: labels, value: value) { rows.append((name, element)) }
            if section.finished { return rows }
            if depth < 40 {
                pending += (SystemNotices.value(element, kAXChildrenAttribute) as? [AXUIElement] ?? []).reversed().map { ($0, depth + 1) }
            }
        }
        // A partial tree must not silently count as a complete restore or hide operation.
        return section.finished ? rows : []
    }
}
