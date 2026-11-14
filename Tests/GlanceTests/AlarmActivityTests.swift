import Foundation
import Testing

@testable import Glance

@MainActor
@Suite("Clock alarm source and actions")
struct AlarmActivityTests {
    private let alarm = AlarmActivity.Alarm(id: "first", title: "Morning", actions: [.snooze, .stop])

    private func identified(_ description: String, actions: [String], app: String = "Clock") -> AlarmActivity.Alarm? {
        AlarmActivity.identifiedAlarm(
            id: "notice", description: description, appName: app, actionNames: actions,
            snoozeNames: ["Snooze", "Adiar"], stopNames: ["Stop", "Parar"],
            repeatNames: ["Repeat", "Repetir"], alarmNames: ["Alarm", "Alarme"])
    }

    @Test("Alarm capabilities come from exact advertised actions, not button order")
    func identification() throws {
        let found = try #require(identified("Clock, Alarm, Morning", actions: ["Name:Close", "Name:Snooze, Target:0", "Name:Stop"]))
        #expect(found.title == "Morning")
        #expect(found.actions == [.snooze, .stop])
        let localized = try #require(identified("Relógio, Alarme, Trabalho", actions: ["Name:Parar", "Name:Adiar"], app: "Relógio"))
        #expect(localized.title == "Trabalho")
        #expect(localized.actions == [.snooze, .stop])
        let noSnooze = try #require(identified("Clock, Alarm", actions: ["Name:Stop"]))
        #expect(noSnooze.actions == [.stop])
    }

    @Test("Other apps, timers named Alarm and ambiguous stop-only alerts are not alarms")
    func unrelatedNotifications() {
        #expect(identified("Other, Alarm", actions: ["Name:Snooze", "Name:Stop"]) == nil)
        #expect(identified("Clock, Alarm", actions: ["Name:Repeat", "Name:Stop"]) == nil)
        #expect(identified("Clock, Unknown", actions: ["Name:Stop"]) == nil)
        #expect(identified("Clock, Alarm", actions: ["Name:Stopwatch"]) == nil)
        #expect(identified("Clock, Alarm", actions: ["AXPress", "AXCancel"]) == nil)
    }

    @Test("Only the observed ClockAngel alarm pill is a read-only alarm source")
    func menuPillContract() {
        var snapshot = AlarmPillSnapshot(identifier: AlarmPillSnapshot.identifier, symbols: ["alarm.fill"], texts: ["16:05"])
        #expect(snapshot.title == "16:05")
        snapshot.identifier = "live-activity-pill-com.example.Clock"
        #expect(snapshot.title == nil)
        snapshot.identifier = AlarmPillSnapshot.identifier
        snapshot.symbols = ["timer"]
        #expect(snapshot.title == nil)
        snapshot.symbols = ["stopwatch.fill"]
        #expect(snapshot.title == nil)
        snapshot.symbols = ["alarm.fill", "zzz"]
        #expect(snapshot.title == nil)
        snapshot.symbols = ["alarm.fill"]
        snapshot.texts = [" "]
        #expect(snapshot.title == nil)
        snapshot.texts = ["16:05", "Unverified extra state"]
        #expect(snapshot.title == nil)
    }

    @Test("Pill identity survives a failed read but not disappearance or changed native content")
    func menuPillIdentity() throws {
        var ledger = AlarmPillLedger<String>()
        let snapshot = AlarmPillSnapshot(identifier: AlarmPillSnapshot.identifier, symbols: ["alarm.fill"], texts: ["16:05"])
        func first(_ reading: AlarmActivity.Reading) throws -> AlarmActivity.Alarm {
            guard case .available(let alarms, _) = reading else { throw WaitError.timeout }
            return try #require(alarms.first)
        }
        let initial = try first(ledger.read([("pid:element", snapshot)]))
        #expect(initial.actions.isEmpty)
        #expect(try first(ledger.read([("pid:element", snapshot)])) == initial)
        #expect(ledger.read(nil) == .unavailable)
        #expect(try first(ledger.read([("pid:element", snapshot)])) == initial)
        var changed = snapshot
        changed.texts = ["16:15"]
        #expect(try first(ledger.read([("pid:element", changed)])).id != initial.id)
        #expect(ledger.read([]) == .available([], observedIDs: []))
        let returned = try first(ledger.read([("pid:element", snapshot)]))
        #expect(returned.id != initial.id)
        #expect(try first(ledger.read([("different-pid:element", snapshot)])).id != returned.id)
    }

    @Test("An observed menu alarm displays and recovers without inventing Stop or Snooze")
    func readOnlyMenuAlarmRecovery() async throws {
        var ledger = AlarmPillLedger<String>()
        let snapshot = AlarmPillSnapshot(identifier: AlarmPillSnapshot.identifier, symbols: ["alarm.fill"], texts: ["16:05"])
        guard case .available(let alarms, _) = ledger.read([("pid:element", snapshot)]) else { throw WaitError.timeout }
        let source = Source(alarms)
        let activity = AlarmActivity(backend: source.backend)
        activity.refresh()
        try await settle { !activity.isRefreshing }
        let shown = try #require(activity.shown)
        #expect(shown.alarm.title == "16:05")
        #expect(AlarmActivityView.controls(for: shown) == [.activityThird])
        activity.perform(.stop, expectedID: shown.alarm.id)
        activity.perform(.snooze, expectedID: shown.alarm.id)
        #expect(source.commands.isEmpty)
        source.available = false
        activity.refresh()
        try await settle { !activity.isRefreshing }
        #expect(activity.shown?.sourceAvailable == false)
        #expect(activity.shown?.alarm.id == shown.alarm.id)
        source.available = true
        activity.refresh()
        try await settle { !activity.isRefreshing }
        #expect(activity.shown?.sourceAvailable == true)
        #expect(!activity.canPerform(.stop) && !activity.canPerform(.snooze))
        activity.openClock()
        #expect(source.openCount == 1)
        source.alarms = []
        activity.refresh()
        try await settle { !activity.isRefreshing }
        #expect(activity.shown == nil)
        activity.stop()
    }

    @Test("A changed or replaced alert is revalidated before sending its command")
    func staleTarget() async throws {
        let source = Source([alarm])
        let activity = AlarmActivity(backend: source.backend)
        activity.refresh()
        try await settle { !activity.isRefreshing }
        source.alarms = [.init(id: "second", title: "Morning", actions: [.stop])]
        activity.perform(.snooze)
        try await settle { activity.pending == nil }
        #expect(source.commands.isEmpty)
        #expect(activity.current?.id == "second")
        #expect(!activity.canPerform(.snooze))

        activity.perform(.stop)
        // The async command has not run yet. A replacement here must not inherit the old click.
        source.alarms = [.init(id: "third", title: "Morning", actions: [.stop])]
        try await settle { activity.pending == nil }
        #expect(source.commands.isEmpty)
        #expect(activity.current?.id == "third")
        activity.stop()
    }

    @Test("A command is sent once and a disappearing source confirms its completion")
    func sourceConfirmation() async throws {
        let source = Source([alarm])
        source.removeOnCommand = true
        source.acknowledge = false
        let activity = AlarmActivity(backend: source.backend)
        activity.refresh()
        try await settle { !activity.isRefreshing }
        activity.perform(.snooze)
        activity.perform(.snooze)
        try await settle { activity.pending == nil }
        #expect(source.commands == [.snooze])
        #expect(activity.current == nil)
        #expect(activity.failure == nil)
        // No locally invented snoozed state or duration is introduced.
        #expect(activity.alarms.isEmpty)
        activity.stop()
    }

    @Test("An accepted but ineffective command retains the real alarm and offers retry")
    func ineffectiveCommand() async throws {
        let source = Source([alarm])
        let activity = AlarmActivity(backend: source.backend)
        activity.refresh()
        try await settle { !activity.isRefreshing }
        activity.perform(.stop)
        try await settle { activity.pending == nil }
        #expect(activity.current == alarm)
        #expect(activity.failure != nil)
        #expect(activity.canPerform(.stop))
        source.removeOnCommand = true
        activity.perform(.stop)
        try await settle { activity.pending == nil }
        #expect(source.commands == [.stop, .stop])
        #expect(activity.current == nil)
        activity.stop()
    }

    @Test("Losing the source never reports that the alarm stopped")
    func unavailableSource() async throws {
        let source = Source([alarm])
        source.unavailableOnCommand = true
        let activity = AlarmActivity(backend: source.backend)
        activity.refresh()
        try await settle { !activity.isRefreshing }
        activity.perform(.stop)
        try await settle { activity.pending == nil }
        #expect(activity.current == alarm)
        #expect(!activity.isAvailable)
        #expect(activity.failure != nil)
        #expect(!activity.canPerform(.stop))
        activity.openClock()
        #expect(source.openCount == 1)
        activity.stop()
    }

    @Test("Stopping observation cancels deferred work without commanding the actual alarm")
    func stopObservation() async throws {
        let source = Source([alarm])
        let activity = AlarmActivity(backend: source.backend)
        activity.refresh()
        try await settle { !activity.isRefreshing }
        activity.perform(.stop)
        activity.stop()
        try await Task.sleep(for: .milliseconds(20))
        #expect(source.commands.isEmpty)
        #expect(activity.current == nil)
        #expect(activity.pending == nil)
    }

    @Test("Concurrent refresh requests coalesce and a stopped snapshot cannot republish")
    func coalescedReads() async throws {
        let source = Source([alarm])
        source.holdReads = true
        let activity = AlarmActivity(backend: source.backend)
        activity.refresh()
        try await settle { !source.readReplies.isEmpty }
        for _ in 0..<10 { activity.refresh() }
        #expect(source.readCount == 1)
        #expect(source.maximumConcurrentReads == 1)
        activity.stop()
        // Even a refresh immediately after stop cannot overlap the cancelled AX message.
        activity.refresh()
        #expect(source.readCount == 1)
        source.releaseReads()
        try await settle { !activity.isRefreshing }
        #expect(activity.current == nil)
        #expect(!activity.isAvailable)
        activity.refresh()
        try await settle { !activity.isRefreshing }
        #expect(activity.current == alarm)
        #expect(source.readCount == 2)
        #expect(source.maximumConcurrentReads == 1)
        activity.stop()
    }

    @Test("Actions wait for an in-flight snapshot and then revalidate the target")
    func actionWaitsForRead() async throws {
        let source = Source([alarm])
        let activity = AlarmActivity(backend: source.backend)
        activity.refresh()
        try await settle { !activity.isRefreshing }
        source.holdReads = true
        activity.refresh()
        try await settle { !source.readReplies.isEmpty }
        activity.perform(.snooze)
        await Task.yield()
        #expect(source.readCount == 2)
        #expect(source.commands.isEmpty)
        source.alarms = [.init(id: "replacement", title: "Morning", actions: [.stop])]
        source.releaseReads()
        try await settle { activity.pending == nil }
        #expect(source.commands.isEmpty)
        #expect(activity.current?.id == "replacement")
        #expect(source.maximumConcurrentReads == 1)
        activity.stop()
    }

    @Test("Losing advertised buttons does not confirm that the exact alert disappeared")
    func sourceIdentityMustDisappear() async throws {
        let source = Source([alarm])
        source.hideActionsOnCommand = true
        let activity = AlarmActivity(backend: source.backend)
        activity.refresh()
        try await settle { !activity.isRefreshing }
        activity.perform(.stop)
        try await settle { activity.pending == nil }
        #expect(source.commands == [.stop])
        #expect(activity.current?.id == alarm.id)
        #expect(activity.current?.actions.isEmpty == true)
        #expect(activity.failure != nil)
        #expect(!activity.canPerform(.stop))
        source.observedIDs = []
        activity.refresh()
        try await settle { !activity.isRefreshing }
        #expect(activity.current == nil)
        activity.stop()
    }

    private enum WaitError: Error { case timeout }

    @Test("A rendered action cannot target a different alarm ID")
    func renderedIdentity() async throws {
        let source = Source([alarm])
        let activity = AlarmActivity(backend: source.backend)
        activity.refresh()
        try await settle { !activity.isRefreshing }
        activity.perform(.stop, expectedID: "an-earlier-alarm")
        #expect(activity.pending == nil)
        #expect(source.commands.isEmpty)
        activity.stop()
    }

    @Test("Disabling observation clears Glance without changing Clock and enabling resumes it")
    func settingLifecycle() async throws {
        let source = Source([alarm])
        var enabled = true
        let activity = AlarmActivity(backend: source.backend, isEnabled: { enabled })
        activity.start()
        try await settle { !activity.isRefreshing }
        #expect(activity.shown?.alarm == alarm)
        enabled = false
        activity.settingsChanged()
        #expect(activity.shown == nil)
        #expect(source.alarms == [alarm])
        #expect(source.commands.isEmpty)
        enabled = true
        activity.settingsChanged()
        try await settle { !activity.isRefreshing }
        #expect(activity.shown?.alarm == alarm)
        activity.stop()
    }

    @Test("Bench actions, refresh and Open Clock cannot reach their source backend")
    func isolatedBench() {
        let source = Source([alarm])
        let activity = AlarmActivity(backend: source.backend)
        activity.bench(AlarmShown(alarm: alarm))
        activity.refresh()
        activity.openClock()
        activity.perform(.snooze, expectedID: alarm.id)
        #expect(source.readCount == 0)
        #expect(source.openCount == 0)
        #expect(source.commands.isEmpty)
        #expect(source.alarms == [alarm])
        #expect(activity.shown == nil)
        activity.stop()
    }

    @Test("Keyboard traversal follows advertised actions and keeps Open Clock reachable")
    func keyboardCapabilities() {
        var shown = AlarmShown(alarm: alarm)
        #expect(AlarmActivityView.controls(for: shown) == [.activityFirst, .activitySecond, .activityThird])
        shown.pending = .stop
        #expect(AlarmActivityView.controls(for: shown) == [.activityThird])
        shown.pending = nil
        shown.sourceAvailable = false
        #expect(AlarmActivityView.controls(for: shown) == [.activityThird])
        shown.sourceAvailable = true
        shown.alarm = .init(id: alarm.id, title: alarm.title, actions: [.stop])
        #expect(AlarmActivityView.controls(for: shown) == [.activitySecond, .activityThird])
        #expect(!NotchController.stepsAway(.alarm))
    }

    @Test("Alarm height adds only the space needed for pending or wrapped error content")
    func contentHeight() {
        let normal = AlarmShown(alarm: alarm)
        let height = AlarmActivityView.height(restingHeight: 32, camera: 185, shown: normal)
        #expect(height < 32 + LiveActivityView.cameraGap + 200)
        var pending = normal
        pending.pending = .snooze
        #expect(AlarmActivityView.height(restingHeight: 32, camera: 185, shown: pending) > height)
        var failed = normal
        failed.failure = String(repeating: "Clock hasn’t confirmed the change. Open Clock to check this alarm. ", count: 4)
        let narrow = AlarmActivityView.height(restingHeight: 32, camera: 185, shown: failed)
        let wide = AlarmActivityView.height(restingHeight: 32, camera: 520, shown: failed)
        #expect(narrow > wide)
        #expect(wide > height)
        let model = NotchModel(closedSize: CGSize(width: 185, height: 32), layout: .top, hasCamera: true)
        model.alarm = failed
        model.expanded = .alarm
        model.state = .open
        #expect(model.metrics.height == AlarmActivityView.height(restingHeight: 32, camera: model.camera, shown: failed))
    }

    @Test("Updating one alarm’s controls preserves its expanded presentation")
    func presentationUpdates() {
        let model = NotchModel(closedSize: CGSize(width: 185, height: 32), layout: .top, hasCamera: true)
        model.alarm = AlarmShown(alarm: alarm)
        model.expanded = .alarm
        model.state = .open
        let transition = model.activityTransitionID
        model.changeActivityPresentation { model.alarm?.pending = .snooze }
        #expect(model.activityTransitionID == transition)
        #expect(!model.activityFolded)
        #expect(model.expanded == .alarm)
        #expect(model.openableActivities == [.alarm])
        model.dismissed.insert(.alarm)
        model.alarm?.pending = nil
        #expect(model.activities.isEmpty)
        model.cancelActivityTransition()
    }

    private func settle(_ condition: () -> Bool) async throws {
        for _ in 0..<300 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw WaitError.timeout
    }

    @MainActor
    private final class Source {
        var alarms: [AlarmActivity.Alarm]
        var available = true
        var commands: [AlarmActivity.Action] = []
        var removeOnCommand = false
        var unavailableOnCommand = false
        var acknowledge = true
        var openCount = 0
        var observedIDs: Set<String>?
        var hideActionsOnCommand = false
        var holdReads = false
        var readReplies: [CheckedContinuation<Void, Never>] = []
        var readCount = 0
        var activeReads = 0
        var maximumConcurrentReads = 0

        init(_ alarms: [AlarmActivity.Alarm]) { self.alarms = alarms }

        var backend: AlarmActivity.Backend {
            .init(
                read: {
                    self.readCount += 1
                    self.activeReads += 1
                    self.maximumConcurrentReads = max(self.maximumConcurrentReads, self.activeReads)
                    defer { self.activeReads -= 1 }
                    let next: AlarmActivity.Reading = self.available ? .available(self.alarms, observedIDs: self.observedIDs) : .unavailable
                    if self.holdReads { await withCheckedContinuation { self.readReplies.append($0) } }
                    return next
                },
                perform: { action, alarm in
                    guard self.alarms.contains(alarm), alarm.actions.contains(action) else { return false }
                    self.commands.append(action)
                    if self.removeOnCommand { self.alarms.removeAll { $0.id == alarm.id } }
                    if self.unavailableOnCommand { self.available = false }
                    if self.hideActionsOnCommand {
                        self.observedIDs = [alarm.id]
                        self.alarms = []
                    }
                    return self.acknowledge
                }, openClock: { self.openCount += 1 })
        }

        func releaseReads() {
            holdReads = false
            let replies = readReplies
            readReplies = []
            for reply in replies { reply.resume() }
        }
    }
}
