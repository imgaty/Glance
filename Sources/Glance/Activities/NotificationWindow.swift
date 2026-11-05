//
//  NotificationWindow.swift
//  Glance
//
//  Created by Gaty on 05/11/2026.
//

import AppKit
import ApplicationServices

/// Notification Center's window, which macOS keeps full-screen and draws every banner and alert in,
/// out of sight while the notch shows the same as what's in it: a call, a file coming in over AirDrop,
/// a timer that's rung. It's moved up until only its last row of points is on screen, which has
/// nothing in it, so what's in it can still be read and answered, as off the screen altogether it
/// can't be. Every other notification hides with it until it's let go. macOS puts it back by itself
/// now and then, so it's looked at again whenever Notification Center changes, and every second
/// while it's held. Without Accessibility, nothing moves.
@MainActor
final class NotificationWindow {
    static let shared = NotificationWindow()

    static let center = "com.apple.notificationcenterui"
    /// Where it belongs while it's moved, kept in case Glance doesn't get to put it back.
    private static let homeKey = "callPopupWindowHome"

    /// What's holding it out of sight.
    enum Hold: Hashable {
        case call, airDrop, timer
    }

    private var holds: Set<Hold> = []
    private var home: CGPoint?
    private var window: AXUIElement?
    private var timer: Timer?
    private var started = false

    /// Where it's kept while it's held, from where it belongs and how tall it is: one point on screen.
    nonisolated static func away(from home: CGPoint, height: CGFloat) -> CGPoint {
        CGPoint(x: home.x, y: home.y - height + 1)
    }

    /// As Glance starts: left moved by a Glance that stopped, it goes back, or no notification would
    /// ever show. It's put back as Glance quits, too.
    func start() {
        guard !started, AXIsProcessTrusted() else { return }
        started = true
        if let left = UserDefaults.standard.string(forKey: Self.homeKey) {
            var place = NSPointFromString(left)
            for window in windows() {
                if let back = AXValueCreate(.cgPoint, &place) { AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, back) }
            }
            UserDefaults.standard.removeObject(forKey: Self.homeKey)
        }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { NotificationWindow.shared.bringBack() }
        }
    }

    func hold(_ reason: Hold) {
        holds.insert(reason)
        check()
        guard timer == nil else { return }
        let made = Timer(timeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { NotificationWindow.shared.check() }
        }
        made.tolerance = 0.2
        RunLoop.main.add(made, forMode: .common)
        timer = made
    }

    func letGo(_ reason: Hold) {
        holds.remove(reason)
        guard holds.isEmpty else { return }
        timer?.invalidate()
        timer = nil
        bringBack()
    }

    /// Back for now, as only what's on screen can be clicked. It's held again the next time it's looked at.
    func bringBack() {
        guard var place = home, let window, let back = AXValueCreate(.cgPoint, &place) else { return }
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, back)
        home = nil
        UserDefaults.standard.removeObject(forKey: Self.homeKey)
    }

    /// Out of sight, if it's held and isn't.
    func check() {
        guard !holds.isEmpty, AXIsProcessTrusted(), let window = windows().first else { return }
        self.window = window
        var frame = CGRect.zero
        guard let value = SystemNotices.value(window, "AXFrame"), AXValueGetValue(value as! AXValue, .cgRect, &frame) else { return }
        // Only as far as it's been moved: macOS puts it back without saying.
        if let home, frame.origin != home { return }
        let place = frame.origin
        var away = Self.away(from: place, height: frame.height)
        guard let moved = AXValueCreate(.cgPoint, &away),
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, moved) == .success
        else { return }
        home = place
        UserDefaults.standard.set(NSStringFromPoint(place), forKey: Self.homeKey)
    }

    private func windows() -> [AXUIElement] {
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: Self.center).first?.processIdentifier else { return [] }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        return SystemNotices.value(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
    }
}
