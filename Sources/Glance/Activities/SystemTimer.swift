//
//  SystemTimer.swift
//  Glance
//
//  Created by Gaty on 23/10/2026.
//

import AppKit
import ApplicationServices

/// A timer started with macOS's own Timer, from the Clock app, Control Center or Siri, so it counts
/// down beside the camera as Glance's own does. macOS shares its timers with no other app, but keeps
/// them in its settings: each one's length, and when it ends, or what's left of it while paused.
/// They're read from there every second, unless Clock timers is off in Settings. While one shows, the
/// menu bar's own is taken out, through Accessibility, so it isn't shown twice, unless Hide in menu
/// bar is off; and it's paused, resumed or cancelled with Clock's own buttons for it (see `toggle()`).
@MainActor
final class SystemTimer: ObservableObject {
    static let shared = SystemTimer()

    @Published private(set) var state: NotchTimer.State?
    /// Whether Glance may press Clock's buttons, which macOS allows only with Accessibility.
    @Published private(set) var canControl = AXIsProcessTrusted()

    private var poll: Timer?
    /// What a press makes of the timer, shown at once, until macOS's own says so, or for a few
    /// seconds, if Clock never does.
    private var expected: (state: NotchTimer.State?, until: Date)?
    /// Clock, opened hidden by Glance, kept open a while for the next press, and quit after.
    private var openedClock = false
    private var quitClock: Task<Void, Never>?
    /// The one showing's id, which Clock knows it by.
    private var shownID: String?
    /// When to look for the menu bar's own timer again, to take it out.
    private var nextHide = Date.distantPast

    /// Where macOS keeps its timers.
    private static let domain = "com.apple.mobiletimerd" as CFString
    /// The menu bar's own name for its timer.
    static let menuExtra = "com.apple.menuextra.timer"

    func start() {
        guard poll == nil else { return }
        let poll = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.read() }
        }
        poll.tolerance = 0.2
        RunLoop.main.add(poll, forMode: .common)
        self.poll = poll
        read()
    }

    private func read() {
        let defaults = UserDefaults.standard
        var current: (state: NotchTimer.State, id: String?)?
        if defaults.bool(forKey: Preferences.activityClockTimers) {
            CFPreferencesAppSynchronize(Self.domain)
            let kept = (CFPreferencesCopyAppValue("MTTimers" as CFString, Self.domain) as? [String: Any])?["MTTimers"] as? [[String: Any]] ?? []
            current = Self.current(in: kept)
        }
        var next = current?.state
        shownID = current?.id
        if let expected {
            if Date.now < expected.until, !Self.alike(next, expected.state) {
                next = expected.state
            } else {
                self.expected = nil
            }
        }
        if next != state { state = next }
        let trusted = AXIsProcessTrusted()
        if trusted != canControl { canControl = trusted }
        if next != nil, defaults.bool(forKey: Preferences.clockTimerHidesMenuBar), Date.now >= nextHide {
            nextHide = .now + 3
            Self.hideMenuBarTimer()
        }
    }

    /// The timer to show of those macOS keeps: the running one ending first; otherwise the one
    /// paused last. One that has ended waits to be dismissed, ringing, which macOS shows itself.
    static func current(in kept: [[String: Any]], at now: Date = .now) -> (state: NotchTimer.State, id: String?)? {
        var running: (until: Date, total: TimeInterval, id: String?)?
        var paused: (left: TimeInterval, total: TimeInterval, changed: Date, id: String?)?
        for entry in kept {
            guard let timer = entry["$MTTimer"] as? [String: Any], let total = timer["MTTimerDuration"] as? TimeInterval else { continue }
            let fire = timer["MTTimerFireTime"] as? [String: Any]
            let id = timer["MTTimerID"] as? String
            switch timer["MTTimerState"] as? Int {
            // Running: when it ends.
            case 3:
                guard let until = (fire?["$MTTimerDate"] as? [String: Any])?["MTTimerTimeDate"] as? Date, until > now else { continue }
                if running.map({ until < $0.until }) ?? true { running = (until, total, id) }
            // Paused: what's left.
            case 2:
                guard let left = (fire?["$MTTimerTimeInterval"] as? [String: Any])?["MTTimerTimeInterval"] as? TimeInterval, left > 0 else {
                    continue
                }
                let changed = timer["MTTimerLastModifiedDate"] as? Date ?? .distantPast
                if paused.map({ changed > $0.changed }) ?? true { paused = (left, total, changed, id) }
            default: continue
            }
        }
        if let running { return (.running(until: running.until, total: max(running.total, running.until.timeIntervalSince(now))), running.id) }
        if let paused { return (.paused(left: paused.left, total: max(paused.total, paused.left)), paused.id) }
        return nil
    }

    /// Pauses or resumes the timer showing, or cancels it, as its own buttons in Clock do: macOS lets
    /// no other app do it. It shows paused, running or gone at once, as Clock will have it. Clock is
    /// opened, hidden, if it isn't already, and shown for a moment, without coming forward, as its
    /// buttons answer only then; then hidden again. Its window comes and goes behind every other. If
    /// Glance opened it, it's kept open half a minute, so the next press is as quick, then quit.
    /// Without Accessibility, macOS asks for it, in its own words, with a way to its settings.
    func toggle() {
        guard let state, allowed() else { return }
        switch state {
        case .running(let until, let total): expect(.paused(left: max(until.timeIntervalSinceNow, 0), total: total))
        case .paused(let left, let total): expect(.running(until: .now + left, total: total))
        }
        control(.toggle)
    }

    func cancel() {
        guard state != nil, allowed() else { return }
        expect(nil)
        control(.cancel)
    }

    private func allowed() -> Bool {
        let allowed = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
        if allowed != canControl { canControl = allowed }
        return allowed
    }

    private func expect(_ next: NotchTimer.State?) {
        expected = (next, .now + 4)
        state = next
    }

    /// Both running, both paused, or both gone.
    private static func alike(_ a: NotchTimer.State?, _ b: NotchTimer.State?) -> Bool {
        switch (a, b) {
        case (nil, nil), (.running?, .running?), (.paused?, .paused?): true
        default: false
        }
    }

    private enum Control {
        case toggle, cancel
    }

    private static let clock = URL(fileURLWithPath: "/System/Applications/Clock.app")
    private static let clockID = "com.apple.clock"

    private func control(_ control: Control) {
        guard let id = shownID else { return }
        quitClock?.cancel()
        Task { @MainActor in
            if NSRunningApplication.runningApplications(withBundleIdentifier: Self.clockID).isEmpty {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = false
                config.hides = true
                config.addsToRecentItems = false
                _ = try? await NSWorkspace.shared.openApplication(at: Self.clock, configuration: config)
                openedClock = true
            }
            if let clock = NSRunningApplication.runningApplications(withBundleIdentifier: Self.clockID).first {
                await Self.press(control, on: id, in: clock)
            }
            read()
            guard openedClock else { return }
            quitClock?.cancel()
            quitClock = Task { @MainActor in
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                openedClock = false
                // Unless it has been brought forward since, to be used.
                let clock = NSRunningApplication.runningApplications(withBundleIdentifier: Self.clockID).first
                if clock?.isHidden == true { clock?.terminate() }
            }
        }
    }

    /// Presses the timer's button in Clock, or its row's action to take it away, with Clock shown
    /// for the moment it takes.
    private static func press(_ control: Control, on id: String, in clock: NSRunningApplication) async {
        let app = AXUIElementCreateApplication(clock.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.5)
        // Its window, once it's open.
        var window: AXUIElement?
        for _ in 0..<30 {
            window = (value(app, kAXWindowsAttribute) as? [AXUIElement])?.first
            if window != nil { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard let window else { return }
        let hidden = clock.isHidden
        if hidden {
            AXUIElementSetAttributeValue(app, kAXHiddenAttribute as CFString, kCFBooleanFalse)
            try? await Task.sleep(for: .milliseconds(150))
        }
        if let row = await timerRow(id, in: window) {
            switch control {
            case .toggle:
                // The button on its row: Pause, or Resume.
                let button = (value(row, kAXChildrenAttribute) as? [AXUIElement] ?? []).first {
                    value($0, kAXRoleAttribute) as? String == kAXButtonRole
                }
                if let button { AXUIElementPerformAction(button, kAXPressAction as CFString) }
            case .cancel:
                // Its row's own action, which takes the timer away.
                var actions: CFArray?
                AXUIElementCopyActionNames(row, &actions)
                if let remove = (actions as? [String])?.first(where: { $0.hasPrefix("Name:") }) {
                    AXUIElementPerformAction(row, remove as CFString)
                }
            }
        }
        try? await Task.sleep(for: .milliseconds(250))
        if hidden { AXUIElementSetAttributeValue(app, kAXHiddenAttribute as CFString, kCFBooleanTrue) }
    }

    /// The timer's row in Clock's list of timers, on its Timers page, which it's turned to if it's
    /// on another.
    private static func timerRow(_ id: String, in window: AXUIElement) async -> AXUIElement? {
        func row() -> AXUIElement? {
            find(in: window) { value($0, kAXRoleAttribute) as? String == kAXGroupRole && value($0, kAXIdentifierAttribute) as? String == id }
        }
        if let row = row() { return row }
        // Its pages are the toolbar's choices.
        let pages = findAll(in: window) { value($0, kAXRoleAttribute) as? String == kAXRadioButtonRole }
        for page in pages {
            AXUIElementPerformAction(page, kAXPressAction as CFString)
            try? await Task.sleep(for: .milliseconds(200))
            if let row = row() { return row }
        }
        return nil
    }

    private static func value(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    private static func find(in element: AXUIElement, where match: (AXUIElement) -> Bool) -> AXUIElement? {
        if match(element) { return element }
        for child in value(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
            if let found = find(in: child, where: match) { return found }
        }
        return nil
    }

    private static func findAll(in element: AXUIElement, where match: (AXUIElement) -> Bool) -> [AXUIElement] {
        (match(element) ? [element] : []) + (value(element, kAXChildrenAttribute) as? [AXUIElement] ?? []).flatMap { findAll(in: $0, where: match) }
    }

    /// Takes the menu bar's own timer out, as its menu's Remove from Menu Bar does: the notch shows
    /// it. macOS keeps that choice; the timer comes back to the menu bar from its settings.
    private static func hideMenuBarTimer() {
        guard AXIsProcessTrusted(),
            let agent = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.MenuBarAgent").first
        else { return }
        let app = AXUIElementCreateApplication(agent.processIdentifier)
        // Never kept waiting by the menu bar.
        AXUIElementSetMessagingTimeout(app, 0.1)
        func value(_ element: AXUIElement, _ name: String) -> AnyObject? {
            var value: AnyObject?
            return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
        }
        guard let bar = value(app, kAXExtrasMenuBarAttribute) else { return }
        let groups = value(bar as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement] ?? []
        let items = groups.flatMap { [$0] + (value($0, kAXChildrenAttribute) as? [AXUIElement] ?? []) }
        guard let item = items.first(where: { value($0, kAXIdentifierAttribute) as? String == menuExtra }) else { return }
        var actions: CFArray?
        AXUIElementCopyActionNames(item, &actions)
        // Its own action, named in the system's language, beside Press and Show Menu.
        guard let remove = (actions as? [String])?.first(where: { $0.hasPrefix("Name:") }) else { return }
        AXUIElementPerformAction(item, remove as CFString)
    }
}
