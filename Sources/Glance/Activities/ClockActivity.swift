//
//  ClockActivity.swift
//  Glance
//
//  Created by Gaty on 23/10/2026.
//

import AppKit
import ApplicationServices

/// macOS's own timer and stopwatch, from the Clock app, Control Center or Siri, which count beside
/// the camera as the iPhone's do in the Dynamic Island. macOS shares them with no other app, but
/// keeps them in its settings: each timer's length, and when it ends, what's left of it while paused,
/// or when it rang; and when the stopwatch started, and what was on it. They're read from there every
/// second while one shows, every three otherwise, unless they're turned off in Settings. A timer
/// that rings says so, as the iPhone's Timer does when it's done, in place of macOS's own alert:
/// while the notch is on, with Accessibility, that alert is stopped as it shows, and Glance rings
/// with the timer's chime instead (see `TimerChime`), until it's stopped or repeated in the notch.
/// Otherwise macOS's alert chimes beside it, and stopping or repeating it in the notch stops or
/// repeats macOS's alert, and the other way round.
///
/// While a timer shows, the menu bar's own is taken out, through Accessibility, so it isn't shown
/// twice, unless Hide in menu bar is off. They're paused, resumed, cancelled, started again and
/// reset with Clock's own buttons for them (see `control(_:)`).
@MainActor
final class ClockActivity: ObservableObject {
    static let shared = ClockActivity()

    @Published private(set) var timer: NotchTimer.State?
    /// Its label, as named in Clock; none if it wasn't given one.
    @Published private(set) var timerTitle: String?
    @Published private(set) var stopwatch: Stopwatch?
    /// The timer that rang last, while it says so, to start it again, and when it rang.
    @Published private(set) var rang: (length: TimeInterval, title: String?, date: Date)?
    /// Rung in place of macOS's alert, when it's taken away.
    private let chime = TimerChime()
    /// When the timer whose alert Glance stopped, to ring itself, rang: macOS notes it as answered.
    private var silenced: Date?
    /// Reads again the moment the timer showing ends, so its ring is caught as it starts.
    private var ringCheck: Task<Void, Never>?
    /// Whether Glance may press Clock's buttons, which macOS allows only with Accessibility.
    @Published private(set) var canControl = AXIsProcessTrusted()

    private let activities: Activities
    private var poll: Timer?
    private var lastRead = Date.distantPast
    /// What a press makes of the timer and the stopwatch, shown at once, until macOS's own says so,
    /// or for a few seconds, if Clock never does.
    private var expectedTimer: (state: NotchTimer.State?, until: Date)?
    private var expectedStopwatch: (state: Stopwatch?, until: Date)?
    /// When a timer last rang, so each rings once.
    private var lastRing: Date?
    /// Clock, opened hidden by Glance, kept open a while for the next press, and quit after.
    private var openedClock = false
    private var quitClock: Task<Void, Never>?
    /// The timer showing's id, which Clock knows it by.
    private var shownID: String?
    /// When to look for the menu bar's own timer again, to take it out.
    private var nextHide = Date.distantPast

    /// Where macOS keeps its timers and stopwatch.
    private static let domain = "com.apple.mobiletimerd" as CFString
    /// The menu bar's own name for its timer.
    static let menuExtra = "com.apple.menuextra.timer"

    init(activities: Activities? = nil) {
        self.activities = activities ?? .shared
    }

    func start() {
        guard poll == nil else { return }
        // Every second while one shows; every three otherwise, which is soon enough to notice one start.
        let poll = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.timer != nil || self.stopwatch != nil || Date.now.timeIntervalSince(self.lastRead) > 2.9 else { return }
                self.read()
            }
        }
        poll.tolerance = 0.2
        RunLoop.main.add(poll, forMode: .common)
        self.poll = poll
        read()
    }

    private func read() {
        lastRead = .now
        let defaults = UserDefaults.standard
        CFPreferencesAppSynchronize(Self.domain)
        func kept(_ key: String) -> [[String: Any]] {
            (CFPreferencesCopyAppValue(key as CFString, Self.domain) as? [String: Any])?[key] as? [[String: Any]] ?? []
        }
        let timers = defaults.bool(forKey: Preferences.activityClockTimers) ? kept("MTTimers") : []
        let current = Self.timer(in: timers)
        var nextTimer = current?.state
        shownID = current?.id
        if current?.title != timerTitle { timerTitle = current?.title }
        if let expected = expectedTimer {
            if Date.now < expected.until, !Self.alike(nextTimer, expected.state) {
                nextTimer = expected.state
            } else {
                expectedTimer = nil
            }
        }
        if nextTimer != timer { timer = nextTimer }
        noticeRing(in: timers)
        if case .running(let until, _) = nextTimer, until.timeIntervalSinceNow < 1.5, ringCheck == nil {
            ringCheck = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(max(until.timeIntervalSinceNow, 0) + 0.1))
                // macOS notes it rang a moment after it ends.
                for _ in 0..<5 where self?.rang == nil {
                    self?.read()
                    try? await Task.sleep(for: .milliseconds(150))
                }
                self?.ringCheck = nil
            }
        }

        var nextStopwatch = defaults.bool(forKey: Preferences.activityStopwatch) ? Stopwatch.current(in: kept("MTStopwatches")) : nil
        if let expected = expectedStopwatch {
            if Date.now < expected.until, !Stopwatch.alike(nextStopwatch, expected.state) {
                nextStopwatch = expected.state
            } else {
                expectedStopwatch = nil
            }
        }
        if nextStopwatch != stopwatch { stopwatch = nextStopwatch }

        let trusted = AXIsProcessTrusted()
        if trusted != canControl { canControl = trusted }
        if nextTimer != nil, defaults.bool(forKey: Preferences.clockTimerHidesMenuBar), Date.now >= nextHide {
            nextHide = .now + 3
            Self.hideMenuBarTimer()
        }
    }

    /// A timer macOS keeps: how it stands, the id Clock knows it by, and its label.
    typealias Found = (state: NotchTimer.State, id: String?, title: String?)

    /// The timer to show of those macOS keeps: the running one ending first; otherwise the one
    /// paused last. Its label is the one given it in Clock; Clock's placeholder for an unnamed one
    /// isn't.
    static func timer(in kept: [[String: Any]], at now: Date = .now) -> Found? {
        var running: (until: Date, total: TimeInterval, id: String?, title: String?)?
        var paused: (left: TimeInterval, total: TimeInterval, changed: Date, id: String?, title: String?)?
        for entry in kept {
            guard let timer = entry["$MTTimer"] as? [String: Any], let total = timer["MTTimerDuration"] as? TimeInterval else { continue }
            let fire = timer["MTTimerFireTime"] as? [String: Any]
            let id = timer["MTTimerID"] as? String
            let title = title(of: timer)
            switch timer["MTTimerState"] as? Int {
            // Running: when it ends.
            case 3:
                guard let until = (fire?["$MTTimerDate"] as? [String: Any])?["MTTimerTimeDate"] as? Date, until > now else { continue }
                if running.map({ until < $0.until }) ?? true { running = (until, total, id, title) }
            // Paused: what's left.
            case 2:
                guard let left = (fire?["$MTTimerTimeInterval"] as? [String: Any])?["MTTimerTimeInterval"] as? TimeInterval, left > 0 else {
                    continue
                }
                let changed = timer["MTTimerLastModifiedDate"] as? Date ?? .distantPast
                if paused.map({ changed > $0.changed }) ?? true { paused = (left, total, changed, id, title) }
            default: continue
            }
        }
        if let running {
            return (.running(until: running.until, total: max(running.total, running.until.timeIntervalSince(now))), running.id, running.title)
        }
        if let paused { return (.paused(left: paused.left, total: max(paused.total, paused.left)), paused.id, paused.title) }
        return nil
    }

    private static func title(of timer: [String: Any]) -> String? {
        (timer["MTTimerTitle"] as? String)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty || $0 == "CURRENT_TIMER" ? nil : $0 }
    }

    /// The timer that rang last of those macOS keeps, and when: the moment it ends, macOS stops it
    /// and notes when it rang.
    static func lastRung(in kept: [[String: Any]]) -> Rung? {
        kept.compactMap { entry -> Rung? in
            guard let timer = entry["$MTTimer"] as? [String: Any], let fired = timer["MTTimerFiredDate"] as? Date,
                let length = timer["MTTimerDuration"] as? TimeInterval
            else { return nil }
            // Once its alert is stopped or closed, macOS notes when.
            let dismissed = (timer["MTTimerDismissedDate"] as? Date).map { $0 >= fired } ?? false
            let tone = ((timer["MTTimerSound"] as? [String: Any])?["$MTSound"] as? [String: Any])?["MTSoundToneID"] as? String
            return Rung(date: fired, length: length, title: title(of: timer), dismissed: dismissed, tone: tone)
        }
        .max { $0.date < $1.date }
    }

    /// A timer that rang: when, its length and label, whether its alert has been answered, and the
    /// tone it rings with, as macOS names it ("system:Radial").
    struct Rung {
        var date: Date
        var length: TimeInterval
        var title: String?
        var dismissed: Bool
        var tone: String?
    }

    /// A timer that has just rung says so, as the iPhone's does: once, and only if it rang just now,
    /// not one that rang before Glance looked.
    private func noticeRing(in timers: [[String: Any]]) {
        guard let rung = Self.lastRung(in: timers) else { return }
        defer { lastRing = rung.date }
        // Stopped or repeated in macOS's own alert: no longer said here either; unless it was Glance
        // that stopped it, to ring in its place.
        if let rang, rung.date == rang.date, rung.dismissed, silenced != rung.date {
            self.rang = nil
            chime.stop()
            activities.dismiss(.timerDone)
            return
        }
        guard let lastRing, rung.date > lastRing, Date.now.timeIntervalSince(rung.date) < 30, !rung.dismissed else { return }
        rang = (rung.length, rung.title, rung.date)
        let name = rung.title ?? "Timer"
        activities.post(
            NotchAlert(kind: .timerDone, content: .timerDone(length: rung.length, name: name), spoken: "\(name) done", stays: true))
        ringInstead(of: rung)
    }

    /// While the notch is on, with Accessibility, macOS's alert for the timer that has just rung is
    /// stopped as it shows, which stops its chime, and the notch rings in its place, with the same
    /// tone. If it never shows, macOS's own rings as before.
    private func ringInstead(of rung: Rung) {
        guard AXIsProcessTrusted(), UserDefaults.standard.bool(forKey: Preferences.notchEnabled) else { return }
        silenced = rung.date
        Task { @MainActor in
            // It shows a moment after the timer ends.
            for _ in 0..<40 {
                // Answered in the notch meanwhile.
                guard rang?.date == rung.date else { return }
                if Self.answerAlert(.stop, title: rung.title) {
                    chime.play(tone: rung.tone)
                    return
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
            silenced = nil
        }
    }

    // MARK: Pressing Clock's buttons

    /// Pauses or resumes the timer showing, as its own button in Clock does: macOS lets no other app
    /// do it. It shows paused or running at once, as Clock will have it. Without Accessibility, macOS
    /// asks for it, in its own words, with a way to its settings.
    func toggleTimer() {
        guard let timer, allowed() else { return }
        switch timer {
        case .running(let until, let total): expect(timer: .paused(left: max(until.timeIntervalSinceNow, 0), total: total))
        case .paused(let left, let total): expect(timer: .running(until: .now + left, total: total))
        }
        control(.toggleTimer)
    }

    func cancelTimer() {
        guard timer != nil, allowed() else { return }
        expect(timer: nil)
        control(.cancelTimer)
    }

    /// The timer that rang, started again, as the Timer's Repeat does: with macOS's own alert's
    /// Repeat, which stops its chime too; once that's gone, the length Clock is set to starts again,
    /// with its label, if it's that one's; otherwise Clock comes forward on its timers.
    func repeatTimer() {
        guard let rang else { return }
        self.rang = nil
        chime.stop()
        activities.dismiss(.timerDone)
        guard allowed() else { return }
        expect(timer: .running(until: .now + rang.length, total: rang.length))
        if Self.answerAlert(.again, title: rang.title) { return }
        control(.repeatTimer(length: rang.length, title: rang.title))
    }

    /// The timer that rang, no longer said, and its chime stopped: macOS's own alert for it, or the
    /// notch's in its place.
    func dismissRing() {
        guard let rang else { return }
        self.rang = nil
        chime.stop()
        activities.dismiss(.timerDone)
        if AXIsProcessTrusted() { _ = Self.answerAlert(.stop, title: rang.title) }
    }

    /// Clock's alert for a timer that has rung, in Notification Center, answered as its own buttons
    /// do: Repeat, or Stop, which stops its chime. Named in the system's language; in another than
    /// English, found by their place, between Show Details and Close. Whether it was there.
    private static func answerAlert(_ button: AlertButton, title: String?) -> Bool {
        let alerts = SystemNotices.showing(from: SystemNotices.name(of: Self.clock))
        // The one for this timer, by its label, when it has one.
        let alert = alerts.first { alert in
            title.map { SystemNotices.words(of: alert).hasSuffix($0) } ?? true
        } ?? alerts.first
        guard let alert else { return false }
        // Show Details, Repeat, Stop and Close.
        return button == .again
            ? SystemNotices.press("Repeat", fromEnd: 3, on: alert) : SystemNotices.press("Stop", fromEnd: 2, on: alert)
    }

    /// Starts or stops the stopwatch, as its Start and Stop button does.
    func startStopStopwatch() {
        guard let stopwatch, allowed() else { return }
        let elapsed = stopwatch.elapsed()
        expect(stopwatch: stopwatch.isRunning ? .stopped(elapsed: elapsed) : .running(since: .now - elapsed))
        control(.stopwatch(identifiers: ["StartStopButton"]))
    }

    /// Back to 0:00, shown at once. While it runs, it starts over and keeps running: Clock's Lap
    /// would change nothing the notch shows, so it's stopped, reset and started again with Clock's
    /// own buttons. Stopped, it's reset, as its Reset button does.
    func resetStopwatch() {
        guard let stopwatch, allowed() else { return }
        guard stopwatch.isRunning else {
            expect(stopwatch: nil)
            return control(.stopwatch(identifiers: ["LapResetButton"]))
        }
        // At 0:00 for the moment Clock takes to press its three buttons, so it doesn't step back once
        // Clock's own start is read; expected long enough for Clock to be opened first.
        expect(stopwatch: .running(since: .now + 0.6), for: 8)
        control(.stopwatch(identifiers: ["StartStopButton", "LapResetButton", "StartStopButton"]))
    }

    private func allowed() -> Bool {
        let allowed = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
        if allowed != canControl { canControl = allowed }
        return allowed
    }

    private func expect(timer next: NotchTimer.State?) {
        expectedTimer = (next, .now + 4)
        timer = next
    }

    private func expect(stopwatch next: Stopwatch?, for seconds: TimeInterval = 4) {
        expectedStopwatch = (next, .now + seconds)
        stopwatch = next
    }

    /// Both running, both paused, or both gone.
    private static func alike(_ a: NotchTimer.State?, _ b: NotchTimer.State?) -> Bool {
        switch (a, b) {
        case (nil, nil), (.running?, .running?), (.paused?, .paused?): true
        default: false
        }
    }

    private enum Control {
        case toggleTimer, cancelTimer
        case repeatTimer(length: TimeInterval, title: String?)
        /// The stopwatch's buttons, one after another, by the names Clock gives them in any language.
        case stopwatch(identifiers: [String])
    }

    private static let clock = URL(fileURLWithPath: "/System/Applications/Clock.app")
    private static let clockID = "com.apple.clock"

    /// Clock is opened, hidden, if it isn't already, and shown for a moment, without coming forward,
    /// as its buttons answer only then; then hidden again. Its window comes and goes behind every
    /// other. If Glance opened it, it's kept open half a minute, so the next press is as quick, then
    /// quit.
    private func control(_ control: Control) {
        let id = shownID
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
                let pressed = await Self.press(control, timer: id, in: clock)
                // Set to another length, Clock is brought forward on its timers, to start it there.
                if !pressed, case .repeatTimer = control {
                    expectedTimer = nil
                    openedClock = false
                    clock.unhide()
                    clock.activate()
                }
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

    /// Presses the button in Clock, with Clock shown for the moment it takes. Whether it found it.
    private static func press(_ control: Control, timer id: String?, in clock: NSRunningApplication) async -> Bool {
        let app = AXUIElementCreateApplication(clock.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.5)
        // Its window, once it's open.
        var window: AXUIElement?
        for _ in 0..<30 {
            window = (value(app, kAXWindowsAttribute) as? [AXUIElement])?.first
            if window != nil { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard let window else { return false }
        let hidden = clock.isHidden
        if hidden {
            AXUIElementSetAttributeValue(app, kAXHiddenAttribute as CFString, kCFBooleanFalse)
            try? await Task.sleep(for: .milliseconds(150))
        }
        let pressed = await press(control, timer: id, in: window)
        try? await Task.sleep(for: .milliseconds(250))
        if hidden { AXUIElementSetAttributeValue(app, kAXHiddenAttribute as CFString, kCFBooleanTrue) }
        return pressed
    }

    private static func press(_ control: Control, timer id: String?, in window: AXUIElement) async -> Bool {
        func identified(_ identifier: String) -> (AXUIElement) -> Bool {
            { value($0, kAXIdentifierAttribute) as? String == identifier && value($0, kAXRoleAttribute) as? String != kAXGroupRole }
        }
        switch control {
        case .toggleTimer, .cancelTimer:
            let row = await onAnyPage(in: window) {
                value($0, kAXRoleAttribute) as? String == kAXGroupRole && id != nil && value($0, kAXIdentifierAttribute) as? String == id
            }
            guard let row else { return false }
            if case .toggleTimer = control {
                // The button on its row: Pause, or Resume.
                let button = (value(row, kAXChildrenAttribute) as? [AXUIElement] ?? []).first {
                    value($0, kAXRoleAttribute) as? String == kAXButtonRole
                }
                guard let button else { return false }
                AXUIElementPerformAction(button, kAXPressAction as CFString)
            } else {
                // Its row's own action, which takes the timer away.
                var actions: CFArray?
                AXUIElementCopyActionNames(row, &actions)
                guard let remove = (actions as? [String])?.first(where: { $0.hasPrefix("Name:") }) else { return false }
                AXUIElementPerformAction(row, remove as CFString)
            }
        case .repeatTimer(let length, let title):
            // Clock keeps the length last started; its Start beside it starts it again.
            guard let picker = await onAnyPage(in: window, find: identified("TimePicker")),
                (value(picker, kAXValueAttribute) as? String).flatMap(seconds) == length,
                let parent = value(picker, kAXParentAttribute)
            else { return false }
            let group = parent as! AXUIElement
            guard let start = find(in: group, where: identified("PauseResumeButton")) else { return false }
            if let label = find(in: group, where: { value($0, kAXRoleAttribute) as? String == kAXTextFieldRole }) {
                AXUIElementSetAttributeValue(label, kAXValueAttribute as CFString, (title ?? "") as CFString)
            }
            AXUIElementPerformAction(start, kAXPressAction as CFString)
        case .stopwatch(let identifiers):
            for (index, identifier) in identifiers.enumerated() {
                // Each found again once Clock has answered the last: it makes its buttons anew.
                if index > 0 { try? await Task.sleep(for: .milliseconds(150)) }
                guard let button = await onAnyPage(in: window, find: identified(identifier)) else { return false }
                AXUIElementPerformAction(button, kAXPressAction as CFString)
            }
        }
        return true
    }

    /// "00:05:00", as Clock's picker reads, in seconds.
    static func seconds(_ reading: String) -> TimeInterval? {
        let parts = reading.split(separator: ":").compactMap { Double($0) }
        guard parts.count == 3 else { return nil }
        return parts[0] * 3600 + parts[1] * 60 + parts[2]
    }

    /// What's looked for, on the page it's on, which Clock is turned to if it's on another.
    private static func onAnyPage(in window: AXUIElement, find match: @escaping (AXUIElement) -> Bool) async -> AXUIElement? {
        if let found = find(in: window, where: match) { return found }
        // Its pages are the toolbar's choices.
        let pages = findAll(in: window) { value($0, kAXRoleAttribute) as? String == kAXRadioButtonRole }
        for page in pages {
            AXUIElementPerformAction(page, kAXPressAction as CFString)
            try? await Task.sleep(for: .milliseconds(200))
            if let found = find(in: window, where: match) { return found }
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
