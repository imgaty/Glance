//
//  AlarmActivity.swift
//  Glance
//
//  Created by Gaty on 14/11/2026.
//

import AppKit
import ApplicationServices

struct AlarmShown: Equatable {
    var alarm: AlarmActivity.Alarm
    var sourceAvailable = true
    var pending: AlarmActivity.Action?
    var failure: String?

    func canPerform(_ action: AlarmActivity.Action) -> Bool {
        sourceAvailable && pending == nil && alarm.actions.contains(action)
    }

    var spoken: String {
        sourceAvailable ? String(localized: "Alarm, \(alarm.title)") : String(localized: "Alarm status unavailable, \(alarm.title)")
    }
}

/// Clock's currently displayed alarm alerts. Native notifications remain visible and own their
/// sound and lifetime; an acknowledged button press never invents a snoozed countdown.
@MainActor
final class AlarmActivity: ObservableObject {
    static let shared = AlarmActivity(isEnabled: {
        (UserDefaults.standard.object(forKey: Preferences.activityAlarms) as? Bool ?? true)
            && (UserDefaults.standard.object(forKey: Preferences.notchEnabled) as? Bool ?? true)
    })

    enum Action: String, Hashable, Sendable {
        case snooze, stop

        var title: String {
            switch self {
            case .snooze: String(localized: "Snooze")
            case .stop: String(localized: "Stop")
            }
        }

        var progress: String {
            switch self {
            case .snooze: String(localized: "Snoozing…")
            case .stop: String(localized: "Stopping…")
            }
        }
    }

    struct Alarm: Identifiable, Equatable, Sendable {
        let id: String
        let title: String
        let actions: Set<Action>
    }

    enum Reading: Equatable, Sendable {
        case available([Alarm], observedIDs: Set<String>? = nil)
        case unavailable
    }

    /// An injected source must supply its own commands too, so preview controls cannot reach Clock.
    @MainActor
    struct Backend {
        var read: @MainActor () async -> Reading
        var perform: @MainActor (Action, Alarm) async -> Bool
        var openClock: () -> Void

        static var native: Backend {
            let source = Native()
            return Backend(
                read: { await source.read() }, perform: { await source.perform($0, target: $1) },
                openClock: {
                    NSWorkspace.shared.open(Native.clock)
                })
        }
    }

    @Published private(set) var alarms: [Alarm] = [] { didSet { updateShown() } }
    @Published private(set) var isAvailable = false { didSet { updateShown() } }
    @Published private(set) var pending: Action? { didSet { updateShown() } }
    @Published private(set) var failure: String? { didSet { updateShown() } }
    @Published private(set) var shown: AlarmShown?

    var current: Alarm? { alarms.first }

    private let backend: Backend
    private let isEnabled: @MainActor () -> Bool
    private let live: Bool
    private var benched = false
    private var settingsObserver: NSObjectProtocol?
    private var poll: Timer?
    private var reading: Task<Void, Never>?
    private var readingID: UUID?
    private var command: Task<Void, Never>?
    private var commandID: UUID?
    private var request: UUID?
    private var generation = UUID()

    var isRefreshing: Bool { reading != nil }

    init(backend: Backend? = nil, isEnabled: @escaping @MainActor () -> Bool = { true }) {
        self.backend = backend ?? .native
        self.live = backend == nil
        self.isEnabled = isEnabled
    }

    func start() {
        guard settingsObserver == nil else { return }
        settingsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.settingsChanged() }
        }
        settingsChanged()
    }

    func settingsChanged() {
        guard !benched else { return }
        guard isEnabled(), !live || ActivityBench.scene == nil else { return suspendObservation() }
        guard poll == nil else { return }
        refresh()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        poll = timer
    }

    /// Stops observing, without dismissing or changing any Clock alarm.
    func stop() {
        if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) }
        settingsObserver = nil
        suspendObservation()
    }

    private func suspendObservation() {
        poll?.invalidate()
        poll = nil
        generation = UUID()
        reading?.cancel()
        command?.cancel()
        request = nil
        pending = nil
        failure = nil
        alarms = []
        isAvailable = false
    }

    func refresh() {
        guard !benched else { return }
        guard isEnabled(), !live || ActivityBench.scene == nil else { return suspendObservation() }
        // One poll at a time, including a cancelled native read that has not returned yet. Native
        // AX messages cannot be interrupted mid-call; their timeout bounds how long this waits.
        guard reading == nil, command == nil else { return }
        let token = UUID()
        let currentGeneration = generation
        readingID = token
        reading = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if readingID == token {
                    readingID = nil
                    reading = nil
                }
            }
            guard !Task.isCancelled else { return }
            let next = await backend.read()
            guard !Task.isCancelled, generation == currentGeneration else { return }
            guard isEnabled() else { return suspendObservation() }
            apply(next)
        }
    }

    private func apply(_ reading: Reading) {
        switch reading {
        case .unavailable:
            // Keep a known alert clearly unavailable while its source cannot be read. Losing
            // Accessibility or an AX timeout is not proof that the alarm stopped.
            isAvailable = false
        case .available(let found, let observedIDs):
            isAvailable = true
            var next = found
            // A button disappearing or becoming unreadable is not evidence that its alert ended.
            // Keep the known source without actions until a complete snapshot says it disappeared.
            if let current, observedIDs?.contains(current.id) == true, !next.contains(where: { $0.id == current.id }) {
                next.insert(Alarm(id: current.id, title: current.title, actions: []), at: 0)
            }
            let previous = current?.id
            if let previous, let index = next.firstIndex(where: { $0.id == previous }) {
                alarms = [next[index]] + next.enumerated().filter { $0.offset != index }.map(\.element)
            } else {
                alarms = next
            }
            if previous != current?.id { failure = nil }
        }
    }

    func canPerform(_ action: Action) -> Bool {
        isAvailable && pending == nil && current?.actions.contains(action) == true
    }

    func perform(_ action: Action, expectedID: String? = nil) {
        guard canPerform(action), command == nil, let target = current else { return }
        guard expectedID == nil || expectedID == target.id else { return }
        if benched {
            alarms = []
            ActivityBench.shared.stopped(.alarm)
            return
        }
        guard isEnabled(), !live || ActivityBench.scene == nil else { return }
        let token = UUID()
        request = token
        commandID = token
        pending = action
        failure = nil
        let previousRead = reading
        previousRead?.cancel()
        command = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if commandID == token {
                    commandID = nil
                    command = nil
                }
            }
            // Do not overlap reads even for an injected asynchronous backend. The native actor
            // also serializes the complete source-revalidation/action operation off the main actor.
            await previousRead?.value
            guard !Task.isCancelled, request == token else { return }
            let ready = await backend.read()
            guard !Task.isCancelled, request == token else { return }
            guard isEnabled() else { return suspendObservation() }
            apply(ready)
            guard case .available(let alarms, _) = ready else {
                failure = String(localized: "Clock is unavailable. Open Clock to manage this alarm.")
                finish(token)
                return
            }
            guard alarms.contains(target), target.actions.contains(action) else {
                finish(token)
                return
            }
            // Source read-back is authoritative even when AX accepts a stale action or reports an
            // error after delivering it. The command is delivered at most once per activation.
            _ = await backend.perform(action, target)
            let confirmationDeadline = ProcessInfo.processInfo.systemUptime + 3
            for attempt in 0..<20 {
                guard !Task.isCancelled, request == token else { return }
                if ProcessInfo.processInfo.systemUptime >= confirmationDeadline { break }
                let next = await backend.read()
                guard !Task.isCancelled, request == token else { return }
                apply(next)
                if case .available(let alarms, let observedIDs) = next,
                    !(observedIDs ?? Set(alarms.map(\.id))).contains(target.id)
                {
                    finish(token)
                    return
                }
                if attempt < 19 { try? await Task.sleep(for: .milliseconds(100)) }
            }
            guard !Task.isCancelled, request == token else { return }
            if current?.id == target.id {
                failure =
                    current?.actions.contains(action) == true
                    ? String(localized: "Clock hasn’t confirmed the change. Try again or open Clock.")
                    : String(localized: "Clock hasn’t confirmed the change. Open Clock to check this alarm.")
            }
            finish(token)
        }
    }

    private func finish(_ token: UUID) {
        guard request == token else { return }
        request = nil
        pending = nil
    }

    func openClock() {
        guard !benched, !live || ActivityBench.scene == nil else { return }
        backend.openClock()
    }

    private func updateShown() {
        shown = current.map { AlarmShown(alarm: $0, sourceAvailable: isAvailable, pending: pending, failure: failure) }
    }

    /// A source-build scene never reaches a native AX source or launches Clock.
    func bench(_ value: AlarmShown?) {
        stop()
        benched = true
        isAvailable = value?.sourceAvailable ?? false
        pending = value?.pending
        failure = value?.failure
        alarms = value.map { [$0.alarm] } ?? []
    }

    /// Classification uses advertised actions, never an action's position. A timer named Alarm
    /// still offers Repeat, and is explicitly excluded. Unrecognized alerts stay in macOS.
    nonisolated static func identifiedAlarm(
        id: String, description: String, appName: String, actionNames: [String],
        snoozeNames: Set<String>, stopNames: Set<String>, repeatNames: Set<String>, alarmNames: Set<String>
    ) -> Alarm? {
        let prefix = appName + ","
        guard description.hasPrefix(prefix), !id.isEmpty else { return nil }
        let labels = Set(actionNames.compactMap(actionLabel))
        guard labels.isDisjoint(with: repeatNames), !labels.isDisjoint(with: stopNames) else { return nil }
        let body = String(description.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = body.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let canSnooze = !labels.isDisjoint(with: snoozeNames)
        guard canSnooze || parts.contains(where: alarmNames.contains) else { return nil }
        let content = parts.first.map(alarmNames.contains) == true ? parts.dropFirst().joined(separator: ", ") : body
        let title = content.isEmpty ? String(localized: "Alarm") : content
        return Alarm(id: id, title: title, actions: canSnooze ? [.snooze, .stop] : [.stop])
    }

    nonisolated static func actionLabel(_ name: String) -> String? {
        guard name.hasPrefix("Name:") else { return nil }
        return String(name.dropFirst(5).prefix { $0 != "," && $0 != "\n" })
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// All AX references stay inside this serial actor. Only Sendable value snapshots cross back
    /// to the main actor; neither drawing the notch nor clicking a button waits synchronously on AX.
    private actor Native {
        static let clock = URL(fileURLWithPath: "/System/Applications/Clock.app")
        static let angel = URL(fileURLWithPath: "/System/Library/CoreServices/ClockAngel.app")

        private lazy var appName = FileManager.default.displayName(atPath: Self.clock.path).replacingOccurrences(of: ".app", with: "")
        private lazy var snoozeNames = names(["Snooze", "snooze"])
        private lazy var stopNames = names(["Stop", "stop", "stop.button"])
        private lazy var repeatNames = names(["Repeat", "repeat"])
        private lazy var alarmNames = names(["Alarm", "alarm.image"])

        private enum Unavailable: Error { case cancelled, timeout, limit, attribute }

        private struct Budget {
            let deadline = ProcessInfo.processInfo.systemUptime + 0.75

            func check() throws {
                guard !Task.isCancelled else { throw Unavailable.cancelled }
                guard ProcessInfo.processInfo.systemUptime < deadline else { throw Unavailable.timeout }
            }

            func prepare(_ element: AXUIElement) throws {
                try check()
                let remaining = deadline - ProcessInfo.processInfo.systemUptime
                guard remaining > 0,
                    AXUIElementSetMessagingTimeout(element, Float(min(0.1, remaining))) == .success
                else { throw Unavailable.timeout }
            }
        }

        struct Handle {
            var alarm: Alarm
            var element: AXUIElement
            var actions: [String]
        }

        struct Readback {
            var reading: Reading
            var handles: [Handle] = []
        }

        private func names(_ keys: [String]) -> Set<String> {
            let bundle = Bundle(url: Self.angel)
            return Set(keys.map { bundle?.localizedString(forKey: $0, value: $0, table: "Localizable") ?? $0 })
        }

        func read() -> Reading { snapshot().reading }

        private func snapshot() -> Readback {
            do { return try collect() } catch { return Readback(reading: .unavailable) }
        }

        private func value(_ element: AXUIElement, _ attribute: String, budget: Budget) throws -> CFTypeRef? {
            try budget.prepare(element)
            var value: CFTypeRef?
            switch AXUIElementCopyAttributeValue(element, attribute as CFString, &value) {
            case .success:
                try budget.check()
                return value
            case .noValue, .attributeUnsupported:
                return nil
            default:
                throw Unavailable.attribute
            }
        }

        private func collect() throws -> Readback {
            let budget = Budget()
            try budget.check()
            guard AXIsProcessTrusted(),
                let center = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").first
            else { return Readback(reading: .unavailable) }
            let app = AXUIElementCreateApplication(center.processIdentifier)
            guard let windows = try value(app, kAXWindowsAttribute, budget: budget) as? [AXUIElement] else { throw Unavailable.attribute }
            guard windows.count <= 32 else { throw Unavailable.limit }
            var waiting = windows.reversed().map { (element: $0, depth: 0) }
            var seen = Set<AXUIElement>()
            var handles: [Handle] = []
            var observedIDs = Set<String>()
            while let (element, depth) = waiting.popLast() {
                try budget.check()
                guard seen.insert(element).inserted else { continue }
                guard seen.count <= 512 else { throw Unavailable.limit }
                // Foreign trees can lead back into Glance. Reading its own AX UI from this worker
                // would execute AppKit off the main thread, so skip those entire subtrees.
                var owner: pid_t = 0
                guard AXUIElementGetPid(element, &owner) == .success else { throw Unavailable.attribute }
                if owner == getpid() { continue }
                let roleValue = try value(element, kAXSubroleAttribute, budget: budget)
                guard roleValue == nil || roleValue is String else { throw Unavailable.attribute }
                let role = roleValue as? String
                if role == "AXNotificationCenterAlert" || role == "AXNotificationCenterBanner" {
                    guard let words = try value(element, kAXDescriptionAttribute, budget: budget) as? String else { throw Unavailable.attribute }
                    if words.hasPrefix(appName + ",") {
                        let identifier = "\(center.processIdentifier):\(CFHash(element))"
                        observedIDs.insert(identifier)
                        try budget.prepare(element)
                        var actionsValue: CFArray?
                        guard AXUIElementCopyActionNames(element, &actionsValue) == .success,
                            let actions = actionsValue as? [String]
                        else { throw Unavailable.attribute }
                        if let alarm = identifiedAlarm(
                            id: identifier, description: words, appName: appName, actionNames: actions,
                            snoozeNames: snoozeNames, stopNames: stopNames, repeatNames: repeatNames, alarmNames: alarmNames)
                        {
                            handles.append(Handle(alarm: alarm, element: element, actions: actions))
                        }
                    }
                    // The alert itself advertises its actions. Its descendants add no capabilities
                    // and can contain rich content or an entire other app's Accessibility tree.
                    continue
                }
                let childrenValue = try value(element, kAXChildrenAttribute, budget: budget)
                guard childrenValue == nil || childrenValue is [AXUIElement] else { throw Unavailable.attribute }
                let children = childrenValue as? [AXUIElement] ?? []
                let unseen = children.filter { !seen.contains($0) }
                guard unseen.isEmpty || depth < 24, seen.count + waiting.count + unseen.count <= 1024 else { throw Unavailable.limit }
                waiting.append(contentsOf: unseen.reversed().map { ($0, depth + 1) })
            }
            try budget.check()
            return Readback(reading: .available(handles.map(\.alarm), observedIDs: observedIDs), handles: handles)
        }

        func perform(_ action: Action, target: Alarm) -> Bool {
            // No suspension between fresh source validation and dispatch: another AX operation
            // cannot interleave on this actor. Cancellation is rechecked immediately before press.
            guard !Task.isCancelled else { return false }
            let fresh = snapshot()
            guard !Task.isCancelled, case .available = fresh.reading,
                let handle = fresh.handles.first(where: { $0.alarm == target }),
                handle.alarm.actions.contains(action)
            else { return false }
            let labels = action == .snooze ? snoozeNames : stopNames
            guard let name = handle.actions.first(where: { actionLabel($0).map(labels.contains) == true }),
                AXUIElementSetMessagingTimeout(handle.element, 0.1) == .success,
                !Task.isCancelled
            else { return false }
            return AXUIElementPerformAction(handle.element, name as CFString) == .success
        }
    }
}
