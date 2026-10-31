//
//  MenuBarBanners.swift
//  Glance
//
//  Created by Gaty on 30/10/2026.
//

import AppKit
import ApplicationServices

/// macOS's banner under the menu bar for AirPods, which Control Center shows in a window of the menu
/// bar's own app and no setting turns off. It's taken off the screen the moment it's made, where the
/// notch says the same, through Accessibility; without it, it shows as before. The menu bar tells of
/// the window as it's made, on a thread of its own here: its first frames are a matter of
/// milliseconds, and the main thread may be drawing.
final class MenuBarBanners: @unchecked Sendable {
    static let shared = MenuBarBanners()

    /// The menu bar's own app.
    private static let menuBarAgent = "com.apple.MenuBarAgent"
    /// The banner, by the name Accessibility knows it by: AirPods connecting, running low, or
    /// offering the sound back from another device.
    private static let airPodsBanner = "smart-routing-system-banner"
    /// Past any arrangement of displays.
    private static let away = CGPoint(x: -20000, y: -20000)

    private let lock = NSLock()
    private var wokeAt = Date.distantPast
    private var shown: (@MainActor @Sendable () -> Void)?

    // The thread's own, from here on.
    private var app: AXUIElement?
    private var agent: pid_t = 0
    private var observer: AXObserver?
    /// The last one seen: each is told of more than once as it's made.
    private var last: AXUIElement?

    private lazy var runLoop: CFRunLoop = {
        let ready = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var loop: CFRunLoop?
        let thread = Thread {
            loop = CFRunLoopGetCurrent()
            // Something to wait for, or it ends at once.
            RunLoop.current.add(Port(), forMode: .default)
            ready.signal()
            RunLoop.current.run()
        }
        thread.name = "Menu bar banners"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        return loop!
    }()

    /// Starts following the menu bar. `shown` is called for each banner, shown or not.
    func watch(shown: @escaping @MainActor @Sendable () -> Void) {
        lock.withLock { self.shown = shown }
        follow()
    }

    /// With Accessibility allowed since, or the menu bar started again, it's followed anew.
    func follow() {
        guard AXIsProcessTrusted(),
            let agent = NSRunningApplication.runningApplications(withBundleIdentifier: Self.menuBarAgent).first?.processIdentifier
        else { return }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) { [self] in attach(to: agent) }
        CFRunLoopWakeUp(runLoop)
    }

    /// What's reconnected as the Mac wakes isn't announced, so for a moment its banner stays.
    func woke() {
        lock.withLock { wokeAt = .now }
    }

    private func attach(to agent: pid_t) {
        guard agent != self.agent else { return }
        var made: AXObserver?
        let told: AXObserverCallback = { _, _, _, _ in MenuBarBanners.shared.changed() }
        guard AXObserverCreate(agent, told, &made) == .success, let made else { return }
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode) }
        let app = AXUIElementCreateApplication(agent)
        AXUIElementSetMessagingTimeout(app, 0.25)
        AXObserverAddNotification(made, app, kAXCreatedNotification as CFString, nil)
        AXObserverAddNotification(made, app, kAXWindowCreatedNotification as CFString, nil)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(made), .defaultMode)
        self.agent = agent
        self.app = app
        observer = made
    }

    /// As few trips to the menu bar's app as can be, as each waits its turn while it's busy making
    /// the banner: its windows, then what one is called and where it is, in one go, and it's moved.
    private func changed() {
        guard let app else { return }
        for window in SystemNotices.value(app, kAXWindowsAttribute) as? [AXUIElement] ?? [] {
            if let last, CFEqual(last, window) { continue }
            var found: CFArray?
            let names = ["AXIdentifier", kAXPositionAttribute] as CFArray
            guard AXUIElementCopyMultipleAttributeValues(window, names, [], &found) == .success,
                let values = found as? [AnyObject], values.count == 2, values[0] as? String == Self.airPodsBanner
            else { continue }
            last = window
            if hides { take(window, backTo: values[1]) }
            let shown = lock.withLock { self.shown }
            DispatchQueue.main.async { MainActor.assumeIsolated { shown?() } }
        }
    }

    private var hides: Bool {
        let defaults = UserDefaults.standard
        return defaults.bool(forKey: Preferences.notchEnabled) && defaults.bool(forKey: Preferences.activityDevices)
            && lock.withLock { Date.now.timeIntervalSince(wokeAt) >= 10 }
    }

    /// Taken away before there's anything to read in it, and put back unless it turns out to be one
    /// the notch says too.
    private func take(_ banner: AXUIElement, backTo place: AnyObject) {
        var point = Self.away
        guard let away = AXValueCreate(.cgPoint, &point),
            AXUIElementSetAttributeValue(banner, kAXPositionAttribute as CFString, away) == .success
        else { return }
        for _ in 0..<25 {
            let words = SystemNotices.findAll(in: banner) { SystemNotices.value($0, kAXRoleAttribute) as? String == kAXStaticTextRole }
            if Self.showsBattery(words.compactMap { SystemNotices.value($0, kAXValueAttribute) as? String }) { return }
            usleep(20_000)
        }
        AXUIElementSetAttributeValue(banner, kAXPositionAttribute as CFString, place)
    }

    /// AirPods connecting or running low show their level, which is what the notch says; offering
    /// the sound back, they have nothing to tell and something to press.
    static func showsBattery(_ words: [String]) -> Bool {
        words.contains { word in !word.isEmpty && word.allSatisfy { $0.isNumber || $0 == "%" } }
    }
}
