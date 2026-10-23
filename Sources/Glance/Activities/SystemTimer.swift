//
//  SystemTimer.swift
//  Glance
//
//  Created by Gaty on 23/10/2026.
//

import AppKit
import ApplicationServices

/// A timer started with macOS's own Timer, from the Clock app, Control Center or Siri, so it counts
/// down beside the camera as Glance's own does. macOS shares its timers with no other app, but shows
/// the one running in the menu bar: what's left is read from there, through Accessibility, which
/// Glance already has for the trackpad's swipes, and whether it's counting from whether that changes;
/// how long it is, from what macOS keeps of the timer as it starts. Without Accessibility, or with
/// the timer taken out of the menu bar, it doesn't show.
@MainActor
final class SystemTimer: ObservableObject {
    static let shared = SystemTimer()

    @Published private(set) var state: NotchTimer.State?

    private var poll: Timer?
    /// The menu bar's timer, once found, and when to look for it again while there's none.
    private var item: AXUIElement?
    private var nextSearch = Date.distantPast
    /// What it last read, and when that changed: still for a while, it's paused.
    private var lastLeft: TimeInterval?
    private var lastChange = Date.distantPast
    /// How long this one is, once known, and when macOS has it end.
    private var total: TimeInterval?
    private var fire: Date?

    /// The menu bar's own name for its timer.
    static let menuExtra = "com.apple.menuextra.timer"
    /// Where macOS keeps its timers.
    private static let domain = "com.apple.mobiletimerd" as CFString

    func start() {
        guard poll == nil else { return }
        read()
    }

    /// While there's a timer, a few times a second, so it changes with the menu bar's; a look at one
    /// item costs little. Otherwise every two seconds, for one to start.
    private func schedule(_ interval: TimeInterval) {
        guard poll?.timeInterval != interval else { return }
        poll?.invalidate()
        let poll = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.read() }
        }
        poll.tolerance = interval / 5
        RunLoop.main.add(poll, forMode: .common)
        self.poll = poll
    }

    private func read() {
        defer { schedule(item == nil ? 2 : 0.25) }
        guard AXIsProcessTrusted() else { return end() }
        if item == nil { item = Self.findItem() }
        guard let item else { return end() }
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(item, kAXValueAttribute as CFString, &value) == .success,
            let text = value as? String
        else {
            // Gone from the menu bar: done, or cancelled.
            self.item = nil
            return end()
        }
        guard let left = Self.seconds(text), left > 0 else { return end() }
        let now = Date.now
        if left != lastLeft {
            // A new one, or it started again: longer than it was.
            if lastLeft.map({ left > $0 + 1 }) ?? true { (total, fire) = Self.length(endingIn: left) }
            lastLeft = left
            lastChange = now
        }
        let total = max(total ?? left, left)
        // Counting while it changes each second; still for longer than that, paused.
        let counting = now.timeIntervalSince(lastChange) < 1.3
        let next: NotchTimer.State
        if counting {
            // When macOS has it end, while that holds; otherwise as the menu bar shows it, in whole
            // seconds from its last change, give or take a look's interval. Kept unless that moves,
            // so nothing redraws for nothing.
            let until = fire.flatMap { abs($0.timeIntervalSince(lastChange + left)) < 2 ? $0 : nil } ?? lastChange + left
            if case .running(let current, let currentTotal) = state, abs(current.timeIntervalSince(until)) < 0.6, currentTotal == total {
                return
            }
            next = .running(until: until, total: total)
        } else {
            next = .paused(left: left, total: total)
        }
        if state != next { state = next }
    }

    private func end() {
        lastLeft = nil
        total = nil
        fire = nil
        if state != nil { state = nil }
    }

    /// The menu bar's timer, among macOS's own items in it.
    private static func findItem() -> AXUIElement? {
        guard let agent = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.MenuBarAgent").first else { return nil }
        let app = AXUIElementCreateApplication(agent.processIdentifier)
        // Never kept waiting by the menu bar.
        AXUIElementSetMessagingTimeout(app, 0.1)
        func children(_ element: AXUIElement) -> [AXUIElement] {
            var value: AnyObject?
            guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else { return [] }
            return value as? [AXUIElement] ?? []
        }
        var bar: AnyObject?
        guard AXUIElementCopyAttributeValue(app, kAXExtrasMenuBarAttribute as CFString, &bar) == .success, let bar else { return nil }
        for item in children(bar as! AXUIElement).flatMap({ [$0] + children($0) }) {
            var identifier: AnyObject?
            if AXUIElementCopyAttributeValue(item, kAXIdentifierAttribute as CFString, &identifier) == .success,
                identifier as? String == menuExtra
            {
                AXUIElementSetMessagingTimeout(item, 0.1)
                return item
            }
        }
        return nil
    }

    /// "5:25" or "1:05:25", as the menu bar shows what's left.
    static func seconds(_ text: String) -> TimeInterval? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard (2...3).contains(parts.count) else { return nil }
        let numbers = parts.compactMap { Int($0) }
        guard numbers.count == parts.count else { return nil }
        return TimeInterval(numbers.reduce(0) { $0 * 60 + $1 })
    }

    /// How long the timer just started is, and when it ends, from what macOS keeps of it: the
    /// running one ending about when this one does. Otherwise what's left now, so its ring starts
    /// full.
    static func length(endingIn left: TimeInterval, timers: [[String: Any]]? = nil) -> (TimeInterval, Date?) {
        let timers = timers ?? {
            CFPreferencesAppSynchronize(domain)
            return (CFPreferencesCopyAppValue("MTTimers" as CFString, domain) as? [String: Any])?["MTTimers"] as? [[String: Any]] ?? []
        }()
        for entry in timers {
            // Running (3), with the moment it ends and its length.
            guard let timer = entry["$MTTimer"] as? [String: Any], timer["MTTimerState"] as? Int == 3,
                let duration = timer["MTTimerDuration"] as? TimeInterval,
                let fire = ((timer["MTTimerFireTime"] as? [String: Any])?["$MTTimerDate"] as? [String: Any])?["MTTimerTimeDate"] as? Date,
                abs(fire.timeIntervalSinceNow - left) < 3, duration >= left
            else { continue }
            return (duration, fire)
        }
        return (left, nil)
    }
}
