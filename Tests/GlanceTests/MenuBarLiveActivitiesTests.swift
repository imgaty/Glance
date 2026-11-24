//
//  MenuBarLiveActivitiesTests.swift
//  GlanceTests
//
//  Created by Gaty on 11/11/2026.
//

import Foundation
import Testing

@testable import Glance

@Suite("Native Live Activities settings")
struct MenuBarLiveActivitiesTests {
    @Test("Labeled native switches stay in section order and ignore surrounding controls")
    func switches() {
        var reader = MenuBarLiveActivities.SectionReader(heading: "Live Activities")
        #expect(reader.read(role: "AXSwitch", labels: ["Unrelated"], value: nil) == nil)
        #expect(reader.read(role: "AXHeading", labels: ["Live Activities"], value: nil) == nil)
        #expect(reader.read(role: "AXStaticText", labels: [], value: "Follow ongoing activity") == nil)
        #expect(reader.read(role: "AXSwitch", labels: ["Now Playing"], value: nil) == "Now Playing")
        #expect(reader.read(role: "AXCheckBox", labels: ["", "Screenshot"], value: nil) == "Screenshot")
        #expect(reader.read(role: "AXButton", labels: ["Menu Bar Controls"], value: nil) == nil)
        #expect(reader.read(role: "AXSwitch", labels: ["Other setting"], value: nil) == nil)
        #expect(reader.finished)
    }

    @Test("Legacy checkboxes use their preceding labels and stop at the next heading")
    func checkboxes() {
        var reader = MenuBarLiveActivities.SectionReader(heading: "Actividades en directo")
        #expect(reader.read(role: "AXHeading", labels: [], value: "Actividades en directo") == nil)
        #expect(reader.read(role: "AXStaticText", labels: [], value: "Reproducción") == nil)
        #expect(reader.read(role: "AXCheckBox", labels: [], value: nil) == "Reproducción")
        #expect(reader.read(role: "AXCheckBox", labels: [], value: nil) == nil)
        #expect(reader.read(role: "AXHeading", labels: ["Next section"], value: nil) == nil)
        #expect(reader.finished)
    }

    @Test("A failed or missing restore remains saved while successful restores are removed")
    func restore() {
        var result = MenuBarLiveActivities.SwitchResult(hidden: ["Now Playing", "Screenshot", "Missing app"])
        result.record(name: "Now Playing", off: false, changed: true, confirmed: false)
        #expect(result.failed)
        #expect(result.hidden == ["Now Playing", "Screenshot", "Missing app"])
        result.record(name: "Screenshot", off: false, changed: false, confirmed: true)
        #expect(result.hidden == ["Now Playing", "Missing app"])
        result.record(name: "Now Playing", off: false, changed: true, confirmed: true)
        #expect(result.hidden == ["Missing app"])
    }

    @Test("Only switches actually disabled by Glance are remembered")
    func hide() {
        var result = MenuBarLiveActivities.SwitchResult(hidden: [])
        result.record(name: "Already off", off: true, changed: false, confirmed: true)
        result.record(name: "Failed", off: true, changed: true, confirmed: false)
        result.record(name: "Now Playing", off: true, changed: true, confirmed: true)
        result.record(name: "Now Playing", off: true, changed: true, confirmed: true)
        #expect(result.hidden == ["Now Playing"])
        #expect(result.failed)
    }

    private static let kept: Set<String> = ["Clock", "Screenshot"]

    @Test("Hiding turns every switch off, apps' own included, except those Glance reads its activities from")
    func hidesAll() {
        let policy = MenuBarLiveActivities.SwitchPolicy(intent: .init(hiding: true, active: true, kept: Self.kept), hidden: [])
        for name in ["Now Playing", "Music Recognition", "Shortcuts", "Journal"] {
            #expect(policy.target(for: name) == false)
        }
        // Nil means no AX read or press is requested for either an enabled or disabled switch.
        #expect(policy.target(for: "Screenshot") == nil)
        #expect(policy.target(for: "Clock") == nil)
        #expect(policy.isComplete(.init(hidden: ["Now Playing", "Journal"])))
        #expect(!policy.isComplete(.init(hidden: ["Now Playing", "Clock"])))
    }

    @Test("A kept switch Glance turned off earlier is turned back on while the others stay off", arguments: [false, true])
    func migrateKept(alreadyEnabled: Bool) {
        let intent = MenuBarLiveActivities.Intent(hiding: true, active: true, kept: Self.kept)
        let policy = MenuBarLiveActivities.SwitchPolicy(intent: intent, hidden: ["Screenshot"])
        var switches = ["Screenshot": alreadyEnabled, "Now Playing": true, "Already off": false]
        var result = MenuBarLiveActivities.SwitchResult(hidden: policy.hidden)
        for name in ["Screenshot", "Now Playing", "Already off"] {
            guard let target = policy.target(for: name) else { continue }
            let changed = switches[name] != target
            switches[name] = target
            result.record(name: name, off: !target, changed: changed, confirmed: switches[name] == target)
        }
        #expect(switches == ["Screenshot": true, "Now Playing": false, "Already off": false])
        #expect(result.hidden == ["Now Playing"])
        #expect(policy.isComplete(result))
        #expect(MenuBarLiveActivities.SwitchPolicy(intent: intent, hidden: result.hidden).target(for: "Screenshot") == nil)
    }

    @Test("Missing or unconfirmed restoration of a kept switch remains pending")
    func retryKeptMigration() {
        let policy = MenuBarLiveActivities.SwitchPolicy(
            intent: .init(hiding: true, active: true, kept: Self.kept), hidden: ["Screenshot", "Now Playing"])
        var missing = MenuBarLiveActivities.SwitchResult(hidden: policy.hidden)
        missing.record(name: "Now Playing", off: true, changed: false, confirmed: true)
        #expect(!policy.isComplete(missing))
        #expect(missing.hidden.contains("Screenshot"))

        var failed = MenuBarLiveActivities.SwitchResult(hidden: policy.hidden)
        failed.record(name: "Screenshot", off: false, changed: true, confirmed: false)
        #expect(!policy.isComplete(failed))
        #expect(failed.hidden.contains("Screenshot"))
    }

    @Test(
        "Turning hiding off, or the notch no longer showing Live Activities, restores only owned changes",
        arguments: [(false, true), (true, false)])
    func restoreOwnedSwitches(hiding: Bool, active: Bool) {
        let policy = MenuBarLiveActivities.SwitchPolicy(
            intent: .init(hiding: hiding, active: active, kept: Self.kept), hidden: ["Now Playing", "Shortcuts"])
        #expect(policy.target(for: "Now Playing") == true)
        #expect(policy.target(for: "Shortcuts") == true)
        #expect(policy.target(for: "Screenshot") == nil)
        #expect(policy.target(for: "Other app") == nil)
        #expect(!policy.isComplete(.init(hidden: ["Now Playing"])))
        #expect(policy.isComplete(.init(hidden: [])))
    }

    @Test("Kept switches go by the names System Settings shows in the Mac's language")
    func localizedKept() {
        let name = "Captura de pantalla"
        let intent = MenuBarLiveActivities.Intent(hiding: true, active: true, kept: [name])
        #expect(MenuBarLiveActivities.SwitchPolicy(intent: intent, hidden: []).target(for: name) == nil)
        let owned = MenuBarLiveActivities.SwitchPolicy(intent: intent, hidden: [name])
        #expect(owned.target(for: name) == true)
        #expect(!owned.isComplete(.init(hidden: [name])))
        #expect(MenuBarLiveActivities.SwitchPolicy(intent: intent, hidden: []).target(for: "Screenshot") == false)
    }

    @Test("Clock always stays; Now Playing and Screenshot stay only while Glance's own switch for them is off")
    func kept() {
        let suite = "dev.vibe.Glance.tests.kept-live-activities"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let clock = MenuBarLiveActivities.clockName, nowPlaying = MenuBarLiveActivities.nowPlayingName
        let screenshot = MenuBarLiveActivities.screenshotName
        for (music, recordings) in [(true, true), (false, true), (true, false), (false, false)] {
            defaults.set(music, forKey: Preferences.liveActivity)
            defaults.set(recordings, forKey: Preferences.activityScreenRecording)
            var expected: Set<String> = [clock]
            if !music { expected.insert(nowPlaying) }
            if !recordings { expected.insert(screenshot) }
            #expect(MenuBarLiveActivities.kept(in: defaults) == expected, "music \(music), recordings \(recordings)")
        }
        // Music Recognition and Shortcuts are never kept.
        #expect(!MenuBarLiveActivities.kept(in: defaults).contains("Music Recognition"))
        #expect(AlarmPillSnapshot.identifier == MenuBarLiveActivities.pillPrefix + MenuBarLiveActivities.clockPill)
        #expect(MenuBarLiveActivities.known.map(\.pill) == [MenuBarLiveActivities.nowPlayingPill, MenuBarLiveActivities.capture, MenuBarLiveActivities.clockPill])
    }

    @Test("Every row System Settings lists turns off, and back on with the switch, or with Menu Bar chosen", arguments: [false, true])
    @MainActor func hidesEveryRow(byPlace: Bool) async {
        let settings = FakeActivitySettings()
        settings.rows = ["Clock", "Music Recognition", "Now Playing", "Screenshot", "Shortcuts", "Journal"]
        settings.kept = ["Clock", "Screenshot"]
        for name in settings.rows { settings.values[name] = true }
        let manager = settings.manager()
        await manager.reconcile()
        #expect(settings.owned == ["Music Recognition", "Now Playing", "Shortcuts", "Journal"])
        #expect(settings.rows.filter { settings.values[$0] == true } == ["Clock", "Screenshot"])
        #expect(settings.opens == 1)
        if byPlace { settings.active = false } else { settings.hiding = false }
        await manager.reconcile()
        #expect(settings.owned.isEmpty)
        #expect(settings.rows.allSatisfy { settings.values[$0] == true })
        #expect(settings.opens == 2)
    }

    @Test("A pill that stays once every switch is off never has System Settings opened again for it")
    @MainActor func settledPill() async {
        let settings = FakeActivitySettings()
        settings.pills = ["com.example.unswitchable"]
        let manager = settings.manager()
        await manager.reconcile()
        #expect(settings.opens == 1)
        for _ in 0..<3 { await manager.reconcile() }
        #expect(settings.opens == 1)
        // Gone and back, it's looked at once more: it may be a new app's.
        settings.pills = []
        await manager.reconcile()
        settings.pills = ["com.example.unswitchable"]
        await manager.reconcile()
        await manager.reconcile()
        #expect(settings.opens == 2)
    }

    @Test("A newly absent replacement restores during another switch's failure backoff")
    @MainActor func restoreBeforeBackoff() async {
        let settings = FakeActivitySettings()
        settings.owned = ["Clock"]
        settings.values["Clock"] = false
        settings.failures = ["Clock"]
        let manager = settings.manager()
        await manager.reconcile()
        #expect(settings.owned == ["Clock", "Now Playing", "Journal"])
        #expect(settings.opens == 1)

        settings.now += 1
        settings.active = false
        await manager.reconcile()
        #expect(settings.values["Now Playing"] == true)
        #expect(settings.values["Journal"] == true)
        #expect(settings.owned == ["Clock"])
        #expect(settings.opens == 2)
        #expect(settings.attempts.filter { $0.name == "Clock" }.count == 1)

        await manager.reconcile()
        #expect(settings.opens == 2)
        settings.now += 60
        await manager.reconcile()
        #expect(settings.opens == 3)
        #expect(settings.attempts.filter { $0.name == "Clock" }.count == 2)
    }

    @Test("Turning hiding off during Settings discovery never issues the stale hide")
    @MainActor func changedDuringDiscovery() async {
        let settings = FakeActivitySettings()
        settings.onOpen = { settings.hiding = false }
        await settings.manager().reconcile()
        #expect(settings.writes.isEmpty)
        #expect(settings.values["Now Playing"] == true)
        #expect(settings.owned.isEmpty)
        #expect(settings.closes == settings.opens)
    }

    @Test("A queued row reauthorizes after its read and skips an absent replacement")
    @MainActor func changedBeforePress() async {
        let settings = FakeActivitySettings()
        settings.beforeAuthorization = { settings.active = false }
        await settings.manager().reconcile()
        #expect(settings.skipped == 1)
        #expect(settings.writes.isEmpty)
        #expect(settings.owned.isEmpty)
    }

    @Test("A visibility change during an in-flight hide gets an immediate corrective pass")
    @MainActor func changedDuringPress() async {
        let settings = FakeActivitySettings()
        settings.afterSubmission = { _, target in if !target { settings.active = false } }
        await settings.manager().reconcile()
        #expect(settings.writes == [.init(name: "Now Playing", target: false), .init(name: "Now Playing", target: true)])
        #expect(settings.owned.isEmpty)
        #expect(settings.opens == 2)
        #expect(settings.closes == 2)
    }

    @Test("Failed discovery keeps ownership and bounds retries while restoration is unavailable")
    @MainActor func failedDiscoveryIsBounded() async {
        let settings = FakeActivitySettings()
        settings.owned = ["Now Playing"]
        settings.values["Now Playing"] = false
        settings.active = false
        settings.unavailable = true
        let manager = settings.manager()
        await manager.reconcile()
        for _ in 0..<5 { await manager.reconcile() }
        #expect(settings.opens == 1)
        #expect(settings.owned == ["Now Playing"])
        settings.now += 60
        await manager.reconcile()
        #expect(settings.opens == 2)
        #expect(settings.writes.isEmpty)
        // Failing again, it waits twice as long before the next.
        settings.now += 60
        await manager.reconcile()
        #expect(settings.opens == 2)
        settings.now += 60
        await manager.reconcile()
        #expect(settings.opens == 3)
    }

    @Test("An acknowledged hide with missing readback remains owned for restoration")
    @MainActor func uncertainSubmissionRemainsOwned() async {
        let settings = FakeActivitySettings()
        settings.unconfirmed = ["Now Playing"]
        let manager = settings.manager()
        await manager.reconcile()
        #expect(settings.owned == ["Now Playing", "Journal"])
        settings.active = false
        settings.unconfirmed = []
        await manager.reconcile()
        #expect(settings.owned.isEmpty)
        #expect(settings.values["Now Playing"] == true)
        #expect(settings.values["Journal"] == true)
    }

    @Test("An already disabled unowned switch is never enabled by reconciliation")
    @MainActor func preserveUserDisabledSetting() async {
        let settings = FakeActivitySettings()
        settings.values["Now Playing"] = false
        settings.values["Journal"] = false
        let manager = settings.manager()
        await manager.reconcile()
        settings.active = false
        await manager.reconcile()
        #expect(settings.writes.isEmpty)
        #expect(settings.owned.isEmpty)
        #expect(settings.values["Now Playing"] == false)
        #expect(settings.values["Journal"] == false)
    }

    @Test("Repeated changes during native writes cannot create an unbounded corrective loop")
    @MainActor func correctivePassIsBounded() async {
        let settings = FakeActivitySettings()
        settings.afterSubmission = { _, target in settings.active = target }
        await settings.manager().reconcile()
        #expect(settings.opens == 2)
        #expect(settings.writes.count == 2)
        #expect(settings.closes == 2)
    }

    @Test("Quitting turns back on what Glance turned off, and closes the System Settings that took")
    @MainActor func quitRestores() async {
        let settings = FakeActivitySettings()
        settings.owned = ["Now Playing"]
        settings.values["Now Playing"] = false
        let manager = settings.manager()
        // The notch has closed away.
        settings.active = false
        await manager.finish(within: .seconds(3))
        #expect(settings.writes == [.init(name: "Now Playing", target: true)])
        #expect(settings.owned.isEmpty)
        #expect(settings.opens == 1)
        #expect(settings.closes == 1)
    }

    @Test("Quitting waits for a System Settings still opening, so none is left behind")
    @MainActor func quitWaitsForOpening() async {
        let settings = FakeActivitySettings()
        settings.openDelay = .milliseconds(300)
        let manager = settings.manager()
        let pass = Task { await manager.reconcile() }
        #expect(await eventually { settings.opens == 1 })
        settings.active = false
        await manager.finish(within: .seconds(3))
        #expect(settings.closes == settings.opens)
        #expect(settings.writes.isEmpty)
        #expect(settings.owned.isEmpty)
        await pass.value
    }

    @Test("Quitting gives up on a System Settings that takes too long, rather than holding Glance open")
    @MainActor func quitGivesUp() async {
        let settings = FakeActivitySettings()
        settings.owned = ["Now Playing"]
        settings.values["Now Playing"] = false
        settings.active = false
        settings.openDelay = .seconds(2)
        let manager = settings.manager()
        let clock = ContinuousClock()
        let start = clock.now
        await manager.finish(within: .milliseconds(200), launchTime: .zero)
        #expect(clock.now - start < .milliseconds(1500))
        #expect(settings.closes == 0)
        // The pass it left still ends on its own.
        #expect(await eventually { settings.closes == 1 })
    }
}

/// The async boundaries match discovery, the state read before a press, and its readback.
/// Nothing here opens System Settings or reads/writes the real user's preferences.
@MainActor
private final class FakeActivitySettings {
    struct Write: Equatable {
        let name: String
        let target: Bool
    }

    var now = Date(timeIntervalSince1970: 1000)
    var hiding = true
    var active = true
    var owned: [String] = []
    var rows = ["Clock", "Now Playing", "Journal"]
    var kept: Set<String> = ["Clock"]
    var pills: Set<String> = []
    var values = ["Now Playing": true, "Clock": true, "Journal": true]
    var failures = Set<String>()
    var unconfirmed = Set<String>()
    var unavailable = false
    /// How long System Settings takes to open, if at all.
    var openDelay: Duration?
    var opens = 0
    var closes = 0
    var skipped = 0
    var attempts: [Write] = []
    var writes: [Write] = []
    var onOpen: (() -> Void)?
    var beforeAuthorization: (() -> Void)?
    var afterSubmission: ((String, Bool) -> Void)?

    func manager() -> MenuBarLiveActivities {
        let manager = MenuBarLiveActivities(
            dependencies: .init(
                now: { self.now }, hiding: { self.hiding }, owned: { self.owned },
                saveOwned: { self.owned = $0 }, isTrusted: { true }, kept: { self.kept }, pills: { self.pills },
                openSettings: { await self.open() }))
        manager.active = { self.active }
        return manager
    }

    private func open() async -> MenuBarLiveActivities.SettingsSession? {
        opens += 1
        if let openDelay { try? await Task.sleep(for: openDelay) }
        await Task.yield()
        let hook = onOpen
        onOpen = nil
        hook?()
        guard !unavailable else { return nil }
        let rows = rows.map { name in
            MenuBarLiveActivities.SettingsRow(name: name) { target, authorization in
                await self.apply(name: name, target: target, authorization: authorization)
            }
        }
        return .init(rows: rows, close: { self.closes += 1 })
    }

    private func apply(name: String, target: Bool, authorization: MenuBarLiveActivities.WriteAuthorization) async -> MenuBarLiveActivities.WriteOutcome {
        attempts.append(.init(name: name, target: target))
        if values[name] == target { return .unchanged }
        let hook = beforeAuthorization
        beforeAuthorization = nil
        hook?()
        guard await authorization.isCurrent() else {
            skipped += 1
            return .stale
        }
        guard !failures.contains(name) else { return .failed }
        values[name] = target
        writes.append(.init(name: name, target: target))
        afterSubmission?(name, target)
        await Task.yield()
        return .submitted(confirmed: !unconfirmed.contains(name))
    }
}
