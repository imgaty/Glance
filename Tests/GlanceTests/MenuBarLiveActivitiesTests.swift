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
}
