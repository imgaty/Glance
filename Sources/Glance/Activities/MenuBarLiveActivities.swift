//
//  MenuBarLiveActivities.swift
//  Glance
//
//  Created by Gaty on 07/11/2026.
//

import AppKit
import ApplicationServices

/// Hides macOS's own Live Activities in the menu bar while the notch shows Live Activities: every
/// switch System Settings lists under Menu Bar > Live Activities, read as it is, so apps' own are
/// included, but those that would leave something showing nowhere (see `kept`). What it turned off
/// is remembered, and only that is turned back on: when the switch goes off, Menu Bar is chosen or
/// the notch is turned off. AirDrop's, which no switch lists, goes on MenuBarAgent's own list of
/// apps it leaves out instead, at the same times (see `MenuBarDenyList`).
@MainActor
final class MenuBarLiveActivities {
    static let shared = MenuBarLiveActivities()
    /// Whether the notch is where Live Activities show: on, on a display with a notch, with Notch
    /// chosen in Show in.
    var active: () -> Bool = { false }
    private let dependencies: Dependencies
    private var intent: Intent?
    private var generation: UInt64 = 0
    private var retries = RetrySchedule()

    init(dependencies: Dependencies? = nil) {
        self.dependencies = dependencies ?? .system
    }

    private static let pane = URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension")!
    private static let settingsApp = "com.apple.systempreferences"
    /// The switches Glance turned off, by the names System Settings shows them by.
    static let turnedOffKey = "menuBarLiveActivitiesTurnedOff"

    private var timer: Timer?
    private var working = false
    /// The System Settings Glance has open, hidden, if any: quit with Glance if Glance quits first.
    private static var opened: NSRunningApplication?
    /// Openings of System Settings asked for that haven't come back yet: until one does, nothing
    /// can quit it.
    private static var launching = 0
    /// Set once Glance starts quitting: no pass starts on its own after that (see `finish`).
    private var stopping = false
    /// Calls of `reconcile` that have returned, to tell when one asked for is over.
    private var passes = 0
    private var settingObserver: NSObjectProtocol?
    private var spaceObserver: NSObjectProtocol?
    /// How long System Settings' switches are waited for.
    private nonisolated static let patience: Duration = .seconds(20)

    /// Screenshot's pill's app.
    nonisolated static let capture = "com.apple.screencaptureui"
    /// Screenshot's name, as System Settings lists it.
    nonisolated static var screenshotName: String { appName("/System/Applications/Utilities/Screenshot.app") }
    /// Clock's pill's app, and its name as System Settings lists it.
    nonisolated static let clockPill = "com.apple.ClockAngel"
    nonisolated static var clockName: String { appName("/System/Applications/Clock.app") }
    nonisolated private static func appName(_ path: String) -> String {
        FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: "")
    }

    /// Now Playing's name, as System Settings lists it, and its pill's app.
    nonisolated static var nowPlayingName: String {
        let bundle = Bundle(path: "/System/Library/ExtensionKit/Extensions/ControlCenterSettings.appex")
        return bundle?.localizedString(forKey: "Now Playing", value: "Now Playing", table: "Localizable") ?? "Now Playing"
    }
    nonisolated static let nowPlayingPill = "com.apple.MediaRemoteUIService"

    /// A switch System Settings lists for one of macOS's own, by its name, with its pill's app.
    struct Row: Equatable, Sendable {
        let name: String
        let pill: String
    }

    nonisolated static var known: [Row] {
        [Row(name: nowPlayingName, pill: nowPlayingPill), Row(name: screenshotName, pill: capture), Row(name: clockName, pill: clockPill)]
    }

    /// The switches left on. Clock's always: with it off, macOS shows a ringing alarm nowhere, not
    /// even as a notification (it skips one, seeing Live Activities turned on), and Glance reads
    /// alarms from its pill alone. Now Playing's and Screenshot's while Glance's own switch for
    /// what they show is off, so what's playing, or being recorded, still shows somewhere.
    nonisolated static func kept(in defaults: UserDefaults = .standard) -> Set<String> {
        var kept: Set<String> = [clockName]
        if !defaults.bool(forKey: Preferences.liveActivity) { kept.insert(nowPlayingName) }
        if !defaults.bool(forKey: Preferences.activityScreenRecording) { kept.insert(screenshotName) }
        return kept
    }

    /// Pills no switch takes away, so showing never calls for another pass: AirDrop's, which
    /// `MenuBarDenyList` hides instead.
    nonisolated static let unswitchable: Set<String> = ["com.apple.Sharing.AirDropUI"]

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
                let shared = MenuBarLiveActivities.shared
                let on = UserDefaults.standard.bool(forKey: Preferences.hideMenuBarLiveActivities)
                guard on != shared.intent?.hiding || shared.active() != shared.intent?.active else { return }
                shared.check()
            }
        }
        // A request someone sends over AirDrop brings macOS's AirDrop back at once, and its answer
        // hides it again.
        AirDropRequests.shared.changed = { MenuBarLiveActivities.shared.refreshIntent() }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { Self.opened?.forceTerminate() }
        }
        // Off a full-screen app, System Settings' window opens where it can be seen.
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                MenuBarLiveActivities.shared.retries = RetrySchedule()
                MenuBarLiveActivities.shared.check()
            }
        }
        check()
    }

    /// Hides any that show, or, turned off, shows again what Glance hid. Nothing here waits on the
    /// thread that draws the notch.
    private func check() {
        guard !stopping else { return }
        // Refresh even during an in-flight Settings request, invalidating its queued writes.
        refreshIntent()
        guard !working else { return }
        Task { await reconcile() }
    }

    @discardableResult
    private func refreshIntent() -> Intent {
        let latest = Intent(hiding: dependencies.hiding(), active: active(), kept: dependencies.kept())
        if latest != intent {
            retries.changed(from: intent, to: latest)
            intent = latest
            generation &+= 1
        }
        retries.retainRestorations(for: latest, owned: dependencies.owned())
        // Needs neither Accessibility nor System Settings, so it never waits on a pass. Once Glance
        // is quitting, a pass still under way can't put AirDrop back on the list.
        dependencies.denyList(latest.hidesAny && !stopping)
        return latest
    }

    /// The same bounded reconciliation is used by production and fake Settings dependencies.
    /// A change during a write gets one immediate corrective pass, then the ordinary timer.
    func reconcile() async {
        defer { passes &+= 1 }
        refreshIntent()
        guard !working, dependencies.isTrusted() else { return }
        working = true
        defer { working = false }
        for _ in 0..<2 {
            var latest = refreshIntent()
            // A pill showing calls for another pass, unless it stayed after the last one.
            var showing = false
            if latest.hidesAny, dependencies.now() >= retries.hideAfter {
                let pills = await dependencies.pills()
                retries.settled.formIntersection(pills)
                showing = !pills.subtracting(retries.settled).isEmpty
            }
            latest = refreshIntent()
            guard let plan = retries.plan(intent: latest, owned: dependencies.owned(), showing: showing, now: dependencies.now()) else { return }
            let started = generation
            guard let session = await dependencies.openSettings() else {
                refreshIntent()
                if generation != started { continue }
                retries.finished(plan, remaining: dependencies.owned(), failed: true, now: dependencies.now())
                return
            }
            let result = await reconcileRows(session.rows, plan: plan, generation: started)
            await session.close()
            refreshIntent()
            if generation != started { continue }
            retries.finished(plan, remaining: result.hidden, failed: result.failed, now: dependencies.now())
            // What still shows once everything is off isn't any switch's to take away.
            if plan.hiding, !result.failed { retries.settled = await dependencies.pills() }
            return
        }
    }

    /// Whether quitting has anything to wait for: switches Glance turned off, or a System Settings
    /// it's opening or has open.
    var unfinished: Bool {
        working || Self.launching > 0 || Self.opened != nil
            || (timer != nil && !dependencies.owned().isEmpty && dependencies.isTrusted())
    }

    /// Glance is quitting: no pass starts on its own any more, as one started now would open System
    /// Settings after Glance had gone, and leave it open, with nothing left to quit it.
    func stop() {
        guard !stopping else { return }
        stopping = true
        timer?.invalidate()
        timer = nil
        if let settingObserver { NotificationCenter.default.removeObserver(settingObserver) }
        if let spaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver) }
        settingObserver = nil
        spaceObserver = nil
        // Quitting doesn't wait out a failure's backoff.
        retries = RetrySchedule()
        // Instant, so macOS's AirDrop shows again even if Glance is made to quit at once.
        dependencies.denyList(false)
    }

    /// Glance is quitting, the notch gone: turns back on what Glance turned off, as with the notch
    /// turned off, so macOS's own show while Glance doesn't run, then makes sure the System
    /// Settings that took is gone. Gives up after `time`; past it, an opening already asked for
    /// still gets `launchTime` to come back, as only then can it be quit.
    func finish(within time: Duration = .seconds(3), launchTime: Duration = .seconds(2)) async {
        stop()
        let clock = ContinuousClock()
        let deadline = clock.now + time
        // Twice: a pass under way may already have used its corrective pass on something else.
        for _ in 0..<2 where clock.now < deadline {
            let before = passes
            Task { await reconcile() }
            while clock.now < deadline, passes == before || working {
                try? await Task.sleep(for: .milliseconds(20))
            }
            if dependencies.owned().isEmpty { break }
        }
        let last = clock.now + launchTime
        while clock.now < last, Self.launching > 0 {
            try? await Task.sleep(for: .milliseconds(20))
        }
        Self.opened?.forceTerminate()
    }

    private func reconcileRows(_ rows: [SettingsRow], plan: RetrySchedule.Plan, generation started: UInt64) async -> SwitchResult {
        var result = SwitchResult(hidden: dependencies.owned())
        for row in rows {
            let latest = refreshIntent()
            let policy = SwitchPolicy(intent: latest, hidden: result.hidden)
            guard let target = policy.target(for: row.name) else { continue }
            if target {
                guard retries.canRestore(row.name, now: dependencies.now()) else { continue }
            } else {
                // A newer intent gets its own pass; this session may only restore it.
                guard plan.hiding, generation == started else { continue }
            }
            let authorizedGeneration = generation
            let authorization = WriteAuthorization { [weak self] in
                guard let self else { return false }
                let currentPolicy = SwitchPolicy(intent: self.refreshIntent(), hidden: self.dependencies.owned())
                return self.generation == authorizedGeneration && currentPolicy.target(for: row.name) == target
            }
            let outcome = await row.apply(target, authorization)
            switch outcome {
            case .unchanged:
                result.record(name: row.name, off: !target, changed: false, confirmed: true)
            case .submitted(let confirmed):
                // A successful press with a failed readback still belongs to Glance. Keep
                // ownership so a late native update can be restored instead of lost.
                result.record(name: row.name, off: !target, changed: true, confirmed: confirmed, submitted: true)
            case .failed:
                result.failed = true
            case .stale:
                break
            }
            dependencies.saveOwned(result.hidden)
            refreshIntent()
            if generation != authorizedGeneration { break }
        }
        let policy = SwitchPolicy(intent: refreshIntent(), hidden: result.hidden)
        if !policy.isComplete(result) { result.failed = true }
        return result
    }

    /// The apps whose pills show, in either native menu bar tree.
    nonisolated static func pills() -> Set<String> {
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

    /// Opens a separate hidden Settings instance, leaving the user's own window alone.
    private static func openSettings() async -> SettingsSession? {
        guard let settings = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.settingsApp) else { return nil }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.hides = true
        // Beside any the user has open, which may be on another Space, and left as it is.
        configuration.createsNewApplicationInstance = true
        launching += 1
        let instance = try? await NSWorkspace.shared.open([Self.pane], withApplicationAt: settings, configuration: configuration)
        // Kept before it counts as back, so quitting finds one or the other.
        if let instance { opened = instance }
        launching -= 1
        guard let instance else { return nil }
        instance.hide()
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
        guard !rows.isEmpty else {
            await quit(instance)
            return nil
        }
        return SettingsSession(
            rows: rows.map { settingRow(name: $0.name, box: $0.box) },
            close: {
                try? await Task.sleep(for: .milliseconds(300))
                await quit(instance)
            })
    }

    /// Quits the System Settings Glance opened, and makes sure it's gone: one still loading can let
    /// the request to quit pass, and would stay open, hidden, for good.
    private static func quit(_ instance: NSRunningApplication) async {
        defer { if opened == instance { opened = nil } }
        instance.terminate()
        for _ in 0..<12 {
            if instance.isTerminated { return }
            try? await Task.sleep(for: .milliseconds(250))
            if !instance.isTerminated { instance.terminate() }
        }
        if !instance.isTerminated { instance.forceTerminate() }
    }

    private nonisolated static func settingRow(name: String, box: AXUIElement) -> SettingsRow {
        SettingsRow(name: name) { target, authorization in
            await Task.detached {
                let desired = target ? 1 : 0
                var state = SystemNotices.value(box, kAXValueAttribute) as? Int
                if state == desired { return WriteOutcome.unchanged }
                guard state == (target ? 0 : 1) else { return .failed }
                // Re-read the actual MainActor intent after the AX read and immediately before
                // the press. A request invalidated while discovery or this read waited is inert.
                guard await authorization.isCurrent() else { return .stale }
                guard AXUIElementPerformAction(box, kAXPressAction as CFString) == .success else { return .failed }
                for _ in 0..<20 {
                    try? await Task.sleep(for: .milliseconds(75))
                    state = SystemNotices.value(box, kAXValueAttribute) as? Int
                    if state == desired { break }
                }
                return .submitted(confirmed: state == desired)
            }.value
        }
    }

    struct Intent: Equatable, Sendable {
        /// The switch.
        var hiding: Bool
        /// Whether the notch shows Live Activities.
        var active: Bool
        /// Switches left on whatever the switch says (see `sources`).
        var kept: Set<String>
        var hidesAny: Bool { hiding && active }
        func hides(_ name: String) -> Bool { hidesAny && !kept.contains(name) }
    }

    /// A failed Clock migration must never postpone restoring a newly absent music replacement.
    struct RetrySchedule {
        struct Plan {
            /// Whether this pass turns off every switch that should be.
            let hiding: Bool
            let restoring: Set<String>
        }

        var hideAfter = Date.distantPast
        /// Pills still showing right after every switch was turned off: none of them is a switch's,
        /// so they never call for another pass while they show.
        var settled = Set<String>()
        private var restoreAfter: [String: Date] = [:]
        private var allPending = true
        /// Passes that failed in a row: each waits twice as long as the last before the next, from a
        /// minute up to half an hour, so System Settings isn't opened again and again for nothing.
        private var failures = 0
        private var delay: TimeInterval { min(60 * pow(2, Double(max(failures - 1, 0))), 30 * 60) }

        mutating func changed(from previous: Intent?, to current: Intent) {
            allPending = true
            hideAfter = .distantPast
            settled = []
            if previous?.hiding != current.hiding { restoreAfter.removeAll() }
        }

        mutating func retainRestorations(for intent: Intent, owned: [String]) {
            let needed = Set(owned.filter { !intent.hides($0) })
            restoreAfter = restoreAfter.filter { needed.contains($0.key) }
        }

        func canRestore(_ name: String, now: Date) -> Bool { now >= (restoreAfter[name] ?? .distantPast) }

        func plan(intent: Intent, owned: [String], showing: Bool, now: Date) -> Plan? {
            let restoring = Set(owned.filter { !intent.hides($0) && canRestore($0, now: now) })
            let hiding = intent.hidesAny && now >= hideAfter && (allPending || showing)
            guard !restoring.isEmpty || hiding else { return nil }
            return Plan(hiding: hiding, restoring: restoring)
        }

        mutating func finished(_ plan: Plan, remaining: [String], failed: Bool, now: Date) {
            let unrestored = plan.restoring.contains { remaining.contains($0) }
            failures = failed || unrestored ? failures + 1 : 0
            for name in plan.restoring {
                restoreAfter[name] = remaining.contains(name) ? now + delay : nil
            }
            if plan.hiding {
                allPending = failed
                hideAfter = failed ? now + delay : .distantPast
            }
        }
    }

    struct WriteAuthorization: Sendable {
        let validate: @MainActor @Sendable () -> Bool
        func isCurrent() async -> Bool { await validate() }
    }

    enum WriteOutcome: Sendable {
        case unchanged, submitted(confirmed: Bool), failed, stale
    }

    struct SettingsRow: Sendable {
        let name: String
        let apply: @Sendable (Bool, WriteAuthorization) async -> WriteOutcome
    }

    struct SettingsSession {
        let rows: [SettingsRow]
        let close: @MainActor () async -> Void
    }

    struct Dependencies {
        var now: @MainActor () -> Date
        var hiding: @MainActor () -> Bool
        var owned: @MainActor () -> [String]
        var saveOwned: @MainActor ([String]) -> Void
        var isTrusted: @MainActor () -> Bool
        var kept: @MainActor () -> Set<String>
        /// The apps whose pills show, other than those that are meant to.
        var pills: @MainActor () async -> Set<String>
        var openSettings: @MainActor () async -> SettingsSession?
        /// Puts the apps no switch hides on MenuBarAgent's list, or takes them off.
        var denyList: @MainActor (_ hiding: Bool) -> Void = { _ in }

        @MainActor static var system: Self {
            Self(
                now: { .now },
                hiding: { UserDefaults.standard.bool(forKey: Preferences.hideMenuBarLiveActivities) },
                owned: { UserDefaults.standard.stringArray(forKey: MenuBarLiveActivities.turnedOffKey) ?? [] },
                saveOwned: { UserDefaults.standard.set($0, forKey: MenuBarLiveActivities.turnedOffKey) },
                isTrusted: { AXIsProcessTrusted() },
                kept: { MenuBarLiveActivities.kept() },
                pills: {
                    // A kept switch's pill is meant to show, as AirDrop's always does.
                    let kept = MenuBarLiveActivities.kept()
                    let ignored = Set(MenuBarLiveActivities.known.filter { kept.contains($0.name) }.map(\.pill)).union(MenuBarLiveActivities.unswitchable)
                    return await Task.detached { MenuBarLiveActivities.pills().subtracting(ignored) }.value
                },
                openSettings: { await MenuBarLiveActivities.openSettings() },
                denyList: { hiding in
                    // Hidden only while a request would be seen, and none waits for an answer.
                    let wanted = MenuBarDenyList.hides(hiding), requests = AirDropRequests.shared
                    requests.follow(wanted)
                    MenuBarDenyList().apply(hiding: MenuBarDenyList.hides(wanted: wanted, requestsSeen: requests.ready, asking: requests.asking))
                })
        }
    }

    /// Pure policy shared by migration and ordinary reconciliation, without changing settings.
    struct SwitchPolicy {
        let intent: Intent
        let hidden: [String]

        /// Off for every switch that hides; back on for one Glance turned off that no longer does.
        /// Nil leaves the user's own setting untouched, a kept switch they turned off included.
        func target(for name: String) -> Bool? {
            if intent.hides(name) { return false }
            return hidden.contains(name) ? true : nil
        }

        func isComplete(_ result: SwitchResult) -> Bool {
            !result.failed && result.hidden.allSatisfy(intent.hides)
        }
    }

    struct SwitchResult {
        var hidden: [String]
        var failed = false

        mutating func record(name: String, off: Bool, changed: Bool, confirmed: Bool, submitted: Bool = false) {
            if off, submitted, !hidden.contains(name) { hidden.append(name) }
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
