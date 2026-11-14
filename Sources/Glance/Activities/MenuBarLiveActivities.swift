//
//  MenuBarLiveActivities.swift
//  Glance
//
//  Created by Gaty on 07/11/2026.
//

import AppKit
import ApplicationServices

/// Hide a native activity only while its verified replacement is visible in Glance.
/// App-wide switches cannot distinguish individual Clock alarms, Shortcuts runs or recording
/// sessions, so those remain native. Previously owned changes are restored and verified.
@MainActor
final class MenuBarLiveActivities {
    static let shared = MenuBarLiveActivities()
    var replacements: () -> Set<String> = { [] }
    private let dependencies: Dependencies
    private var intent: Intent?
    private var generation: UInt64 = 0
    private var retries = RetrySchedule()

    init(dependencies: Dependencies? = nil) {
        self.dependencies = dependencies ?? .system
    }

    static var nowPlayingName: String {
        let bundle = Bundle(path: "/System/Library/ExtensionKit/Extensions/ControlCenterSettings.appex")
        return bundle?.localizedString(forKey: "Now Playing", value: "Now Playing", table: "Localizable") ?? "Now Playing"
    }

    private static let pane = URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension")!
    private static let settingsApp = "com.apple.systempreferences"
    /// The switches Glance turned off, by the names System Settings shows them by.
    static let turnedOffKey = "menuBarLiveActivitiesTurnedOff"

    private var timer: Timer?
    private var working = false
    private var settingObserver: NSObjectProtocol?
    private var spaceObserver: NSObjectProtocol?
    /// How long System Settings' switches are waited for.
    private nonisolated static let patience: Duration = .seconds(20)

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
                guard on != MenuBarLiveActivities.shared.intent?.hiding else { return }
                MenuBarLiveActivities.shared.check()
            }
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
        // Refresh even during an in-flight Settings request, invalidating its queued writes.
        refreshIntent()
        guard !working else { return }
        Task { await reconcile() }
    }

    @discardableResult
    private func refreshIntent() -> Intent {
        let latest = Intent(hiding: dependencies.hiding(), eligible: replacements().subtracting([Self.screenshotName]))
        if latest != intent {
            retries.changed(from: intent, to: latest)
            intent = latest
            generation &+= 1
        }
        retries.retainRestorations(for: latest, owned: dependencies.owned())
        return latest
    }

    /// The same bounded reconciliation is used by production and fake Settings dependencies.
    /// A change during a write gets one immediate corrective pass, then the ordinary timer.
    func reconcile() async {
        refreshIntent()
        guard !working, dependencies.isTrusted() else { return }
        working = true
        defer { working = false }
        for _ in 0..<2 {
            var latest = refreshIntent()
            let showing =
                latest.hiding && !latest.eligible.isEmpty && dependencies.now() >= retries.hideAfter
                ? await dependencies.pillShowing() : false
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
            return
        }
    }

    private func reconcileRows(_ rows: [SettingsRow], plan: RetrySchedule.Plan, generation started: UInt64) async -> SwitchResult {
        var result = SwitchResult(hidden: dependencies.owned())
        var seen = Set<String>()
        for row in rows {
            let latest = refreshIntent()
            let policy = SwitchPolicy(hiding: latest.hiding, hidden: result.hidden, screenshot: Self.screenshotName, eligible: latest.eligible)
            guard let target = policy.target(for: row.name) else { continue }
            if target {
                guard retries.canRestore(row.name, now: dependencies.now()) else { continue }
            } else {
                // A newer intent gets its own pass; this session may only restore it.
                guard plan.hiding.contains(row.name), generation == started else { continue }
            }
            seen.insert(row.name)
            let authorizedGeneration = generation
            let authorization = WriteAuthorization { [weak self] in
                guard let self else { return false }
                let current = self.refreshIntent()
                let currentPolicy = SwitchPolicy(hiding: current.hiding, hidden: self.dependencies.owned(), screenshot: Self.screenshotName, eligible: current.eligible)
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
        let current = refreshIntent()
        let policy = SwitchPolicy(hiding: current.hiding, hidden: result.hidden, screenshot: Self.screenshotName, eligible: current.eligible)
        if !policy.isComplete(result) || !plan.hiding.isSubset(of: seen) { result.failed = true }
        return result
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

    /// Opens a separate hidden Settings instance, leaving the user's own window alone.
    private static func openSettings() async -> SettingsSession? {
        guard let settings = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.settingsApp) else { return nil }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.hides = true
        // Beside any the user has open, which may be on another Space, and left as it is.
        configuration.createsNewApplicationInstance = true
        guard let instance = try? await NSWorkspace.shared.open([Self.pane], withApplicationAt: settings, configuration: configuration) else { return nil }
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
            instance.terminate()
            return nil
        }
        return SettingsSession(
            rows: rows.map { settingRow(name: $0.name, box: $0.box) },
            close: {
                try? await Task.sleep(for: .milliseconds(300))
                instance.terminate()
            })
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
        var hiding: Bool
        var eligible: Set<String>
        var hiddenNames: Set<String> { hiding ? eligible : [] }
    }

    /// A failed Clock migration must never postpone restoring a newly absent music replacement.
    struct RetrySchedule {
        struct Plan {
            let hiding: Set<String>
            let restoring: Set<String>
        }

        var hideAfter = Date.distantPast
        private var restoreAfter: [String: Date] = [:]
        private var allPending = true
        private static let delay: TimeInterval = 60

        mutating func changed(from previous: Intent?, to current: Intent) {
            allPending = true
            hideAfter = .distantPast
            if previous?.hiding != current.hiding { restoreAfter.removeAll() }
        }

        mutating func retainRestorations(for intent: Intent, owned: [String]) {
            let needed = Set(owned).subtracting(intent.hiddenNames)
            restoreAfter = restoreAfter.filter { needed.contains($0.key) }
        }

        func canRestore(_ name: String, now: Date) -> Bool { now >= (restoreAfter[name] ?? .distantPast) }

        func plan(intent: Intent, owned: [String], showing: Bool, now: Date) -> Plan? {
            let restoring = Set(owned).subtracting(intent.hiddenNames).filter { canRestore($0, now: now) }
            let hiding = now >= hideAfter && (allPending || showing) ? intent.hiddenNames : []
            guard !restoring.isEmpty || !hiding.isEmpty else { return nil }
            return Plan(hiding: hiding, restoring: restoring)
        }

        mutating func finished(_ plan: Plan, remaining: [String], failed: Bool, now: Date) {
            for name in plan.restoring {
                restoreAfter[name] = remaining.contains(name) ? now + Self.delay : nil
            }
            if !plan.hiding.isEmpty {
                allPending = failed
                hideAfter = failed ? now + Self.delay : .distantPast
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
        var pillShowing: @MainActor () async -> Bool
        var openSettings: @MainActor () async -> SettingsSession?

        @MainActor static var system: Self {
            Self(
                now: { .now },
                hiding: { UserDefaults.standard.bool(forKey: Preferences.hideMenuBarLiveActivities) },
                owned: { UserDefaults.standard.stringArray(forKey: MenuBarLiveActivities.turnedOffKey) ?? [] },
                saveOwned: { UserDefaults.standard.set($0, forKey: MenuBarLiveActivities.turnedOffKey) },
                isTrusted: { AXIsProcessTrusted() },
                pillShowing: { await Task.detached { MenuBarLiveActivities.pillShowing(ignoring: [MenuBarLiveActivities.capture]) }.value },
                openSettings: { await MenuBarLiveActivities.openSettings() })
        }
    }

    /// Pure policy shared by migration and ordinary reconciliation, without changing settings.
    struct SwitchPolicy {
        let hiding: Bool
        let hidden: [String]
        let screenshot: String
        var eligible: Set<String> = []

        /// Nil leaves the user's current setting untouched, including a disabled Screenshot.
        func target(for name: String) -> Bool? {
            if name == screenshot { return hidden.contains(name) ? true : nil }
            if hiding, eligible.contains(name) { return false }
            return hidden.contains(name) ? true : nil
        }

        func isComplete(_ result: SwitchResult) -> Bool {
            !result.failed && (hiding ? result.hidden.allSatisfy { $0 != screenshot && eligible.contains($0) } : result.hidden.isEmpty)
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
