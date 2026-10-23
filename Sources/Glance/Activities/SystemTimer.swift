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
/// They're read from there every second. While one shows, the menu bar's own is taken out, through
/// Accessibility, so it isn't shown twice.
@MainActor
final class SystemTimer: ObservableObject {
    static let shared = SystemTimer()

    @Published private(set) var state: NotchTimer.State?

    private var poll: Timer?
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
        CFPreferencesAppSynchronize(Self.domain)
        let kept = (CFPreferencesCopyAppValue("MTTimers" as CFString, Self.domain) as? [String: Any])?["MTTimers"] as? [[String: Any]] ?? []
        let next = Self.current(in: kept)
        if next != state { state = next }
        if next != nil, Date.now >= nextHide {
            nextHide = .now + 3
            Self.hideMenuBarTimer()
        }
    }

    /// The timer to show of those macOS keeps: the running one ending first; otherwise the one
    /// paused last. One that has ended waits to be dismissed, ringing, which macOS shows itself.
    static func current(in kept: [[String: Any]], at now: Date = .now) -> NotchTimer.State? {
        var running: (until: Date, total: TimeInterval)?
        var paused: (left: TimeInterval, total: TimeInterval, changed: Date)?
        for entry in kept {
            guard let timer = entry["$MTTimer"] as? [String: Any], let total = timer["MTTimerDuration"] as? TimeInterval else { continue }
            let fire = timer["MTTimerFireTime"] as? [String: Any]
            switch timer["MTTimerState"] as? Int {
            // Running: when it ends.
            case 3:
                guard let until = (fire?["$MTTimerDate"] as? [String: Any])?["MTTimerTimeDate"] as? Date, until > now else { continue }
                if running.map({ until < $0.until }) ?? true { running = (until, total) }
            // Paused: what's left.
            case 2:
                guard let left = (fire?["$MTTimerTimeInterval"] as? [String: Any])?["MTTimerTimeInterval"] as? TimeInterval, left > 0 else {
                    continue
                }
                let changed = timer["MTTimerLastModifiedDate"] as? Date ?? .distantPast
                if paused.map({ changed > $0.changed }) ?? true { paused = (left, total, changed) }
            default: continue
            }
        }
        if let running { return .running(until: running.until, total: max(running.total, running.until.timeIntervalSince(now))) }
        if let paused { return .paused(left: paused.left, total: max(paused.total, paused.left)) }
        return nil
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
