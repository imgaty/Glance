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

    @Test("Screenshot's existing authorization is untouched when Glance doesn't own it", arguments: [false, true])
    func preserveScreenshot(hiding: Bool) {
        let policy = MenuBarLiveActivities.SwitchPolicy(hiding: hiding, hidden: [], screenshot: "Screenshot", eligible: ["Now Playing"])
        // Nil means no AX read or press is requested for either an enabled or disabled switch.
        #expect(policy.target(for: "Screenshot") == nil)
        #expect(policy.target(for: "Now Playing") == (hiding ? false : nil))
        #expect(policy.isComplete(.init(hidden: [])))
    }

    @Test("An owned Screenshot change is restored while other activities remain hidden", arguments: [false, true])
    func migrateScreenshot(alreadyEnabled: Bool) {
        let policy = MenuBarLiveActivities.SwitchPolicy(hiding: true, hidden: ["Screenshot"], screenshot: "Screenshot", eligible: ["Now Playing"])
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
        let next = MenuBarLiveActivities.SwitchPolicy(hiding: true, hidden: result.hidden, screenshot: "Screenshot", eligible: ["Now Playing"])
        #expect(next.target(for: "Screenshot") == nil)
    }

    @Test("Missing or unconfirmed Screenshot restoration remains pending")
    func retryScreenshotMigration() {
        let policy = MenuBarLiveActivities.SwitchPolicy(hiding: true, hidden: ["Screenshot", "Now Playing"], screenshot: "Screenshot", eligible: ["Now Playing"])
        var missing = MenuBarLiveActivities.SwitchResult(hidden: policy.hidden)
        missing.record(name: "Now Playing", off: true, changed: false, confirmed: true)
        #expect(!policy.isComplete(missing))
        #expect(missing.hidden.contains("Screenshot"))

        var failed = MenuBarLiveActivities.SwitchResult(hidden: policy.hidden)
        failed.record(name: "Screenshot", off: false, changed: true, confirmed: false)
        #expect(!policy.isComplete(failed))
        #expect(failed.hidden.contains("Screenshot"))
    }

    @Test("Turning hiding off restores only owned changes")
    func restoreOwnedSwitches() {
        let policy = MenuBarLiveActivities.SwitchPolicy(hiding: false, hidden: ["Now Playing"], screenshot: "Screenshot", eligible: ["Now Playing"])
        #expect(policy.target(for: "Now Playing") == true)
        #expect(policy.target(for: "Screenshot") == nil)
        #expect(policy.target(for: "Other app") == nil)
        #expect(!policy.isComplete(.init(hidden: ["Now Playing"])))
        #expect(policy.isComplete(.init(hidden: [])))
    }

    @Test("Screenshot protection uses the localized Settings row name")
    func localizedScreenshot() {
        let name = "Captura de pantalla"
        let unowned = MenuBarLiveActivities.SwitchPolicy(hiding: true, hidden: [], screenshot: name)
        #expect(unowned.target(for: name) == nil)
        let owned = MenuBarLiveActivities.SwitchPolicy(hiding: true, hidden: [name], screenshot: name)
        #expect(owned.target(for: name) == true)
        #expect(!owned.isComplete(.init(hidden: [name])))
    }
    @Test("Unsupported and different-session activities stay native, restoring only owned changes")
    func preserveUnsupported() {
        let policy = MenuBarLiveActivities.SwitchPolicy(hiding: true, hidden: ["Clock", "Shortcuts"], screenshot: "Screenshot", eligible: ["Now Playing"])
        #expect(policy.target(for: "Clock") == true)
        #expect(policy.target(for: "Shortcuts") == true)
        #expect(policy.target(for: "Journal") == nil)
        #expect(policy.target(for: "Music Recognition") == nil)
        #expect(!policy.isComplete(.init(hidden: ["Clock"])))
        #expect(policy.isComplete(.init(hidden: ["Now Playing"])))
        let absent = MenuBarLiveActivities.SwitchPolicy(hiding: true, hidden: ["Now Playing"], screenshot: "Screenshot")
        #expect(absent.target(for: "Now Playing") == true)
        #expect(!absent.isComplete(.init(hidden: ["Now Playing"])))
    }

    @Test("A newly absent replacement restores during another switch's failure backoff")
    @MainActor func restoreBeforeBackoff() async {
        let settings = FakeActivitySettings()
        settings.owned = ["Clock"]
        settings.values["Clock"] = false
        settings.failures = ["Clock"]
        let manager = settings.manager()
        await manager.reconcile()
        #expect(settings.owned == ["Clock", "Now Playing"])
        #expect(settings.opens == 1)

        settings.now += 1
        settings.visible = []
        await manager.reconcile()
        #expect(settings.values["Now Playing"] == true)
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
        settings.beforeAuthorization = { settings.visible = [] }
        await settings.manager().reconcile()
        #expect(settings.skipped == 1)
        #expect(settings.writes.isEmpty)
        #expect(settings.owned.isEmpty)
    }

    @Test("A visibility change during an in-flight hide gets an immediate corrective pass")
    @MainActor func changedDuringPress() async {
        let settings = FakeActivitySettings()
        settings.afterSubmission = { _, target in if !target { settings.visible = [] } }
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
        settings.visible = []
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
    }

    @Test("An acknowledged hide with missing readback remains owned for restoration")
    @MainActor func uncertainSubmissionRemainsOwned() async {
        let settings = FakeActivitySettings()
        settings.unconfirmed = ["Now Playing"]
        let manager = settings.manager()
        await manager.reconcile()
        #expect(settings.owned == ["Now Playing"])
        settings.visible = []
        settings.unconfirmed = []
        await manager.reconcile()
        #expect(settings.owned.isEmpty)
        #expect(settings.values["Now Playing"] == true)
    }

    @Test("An already disabled unowned switch is never enabled by reconciliation")
    @MainActor func preserveUserDisabledSetting() async {
        let settings = FakeActivitySettings()
        settings.values["Now Playing"] = false
        settings.values["Journal"] = false
        let manager = settings.manager()
        await manager.reconcile()
        settings.visible = []
        await manager.reconcile()
        #expect(settings.writes.isEmpty)
        #expect(settings.owned.isEmpty)
        #expect(settings.values["Now Playing"] == false)
        #expect(settings.values["Journal"] == false)
    }

    @Test("Repeated changes during native writes cannot create an unbounded corrective loop")
    @MainActor func correctivePassIsBounded() async {
        let settings = FakeActivitySettings()
        settings.afterSubmission = { _, target in settings.visible = target ? ["Now Playing"] : [] }
        await settings.manager().reconcile()
        #expect(settings.opens == 2)
        #expect(settings.writes.count == 2)
        #expect(settings.closes == 2)
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
    var owned: [String] = []
    var visible: Set<String> = ["Now Playing"]
    var values = ["Now Playing": true, "Clock": true, "Journal": true]
    var failures = Set<String>()
    var unconfirmed = Set<String>()
    var unavailable = false
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
                saveOwned: { self.owned = $0 }, isTrusted: { true }, pillShowing: { false },
                openSettings: { await self.open() }))
        manager.replacements = { self.visible }
        return manager
    }

    private func open() async -> MenuBarLiveActivities.SettingsSession? {
        opens += 1
        await Task.yield()
        let hook = onOpen
        onOpen = nil
        hook?()
        guard !unavailable else { return nil }
        let rows = ["Clock", "Now Playing", "Journal"].map { name in
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
