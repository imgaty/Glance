//
//  MenuBarLiveActivitiesTests.swift
//  GlanceTests
//
//  Created by Gaty on 11/11/2026.
//

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

}
