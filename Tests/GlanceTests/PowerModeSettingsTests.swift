//
//  PowerModeSettingsTests.swift
//  GlanceTests
//
//  Created by Gaty on 10/11/2026.
//

import Testing

@testable import Glance

@Suite("Low Power Mode policy")
struct PowerModeSettingsTests {
    typealias Policy = PowerModeSettings.Policy

    @Test("Changing the battery's mode keeps the adapter's choice")
    func battery() {
        #expect(Policy.battery.setting(false, onBattery: true) == .never)
        #expect(Policy.always.setting(false, onBattery: true) == .adapter)
        #expect(Policy.never.setting(true, onBattery: true) == .battery)
        #expect(Policy.adapter.setting(true, onBattery: true) == .always)
    }

    @Test("Changing the adapter's mode keeps the battery's choice")
    func adapter() {
        #expect(Policy.adapter.setting(false, onBattery: false) == .never)
        #expect(Policy.always.setting(false, onBattery: false) == .battery)
        #expect(Policy.never.setting(true, onBattery: false) == .adapter)
        #expect(Policy.battery.setting(true, onBattery: false) == .always)
    }
}

@Suite("Power mode authorization wait")
struct PowerModeAuthorizationTests {
    @Test("The native authorization sheet stays alive until the system confirms the change")
    func authorized() {
        var wait = PowerModeSettings.ChangeWait(start: 0)
        #expect(wait.advance(applied: false, authorization: false, now: 1) == .waiting)
        #expect(wait.advance(applied: false, authorization: true, now: 2) == .reveal)
        #expect(wait.advance(applied: false, authorization: true, now: 60) == .waiting)
        #expect(wait.advance(applied: false, authorization: false, now: 61) == .waiting)
        #expect(wait.advance(applied: true, authorization: false, now: 62) == .applied)
    }

    @Test("Cancellation and a missing state change end without opening another Settings window")
    func cancelled() {
        var wait = PowerModeSettings.ChangeWait(start: 0)
        #expect(wait.advance(applied: false, authorization: true, now: 1) == .reveal)
        #expect(wait.advance(applied: false, authorization: false, now: 3) == .waiting)
        #expect(wait.advance(applied: false, authorization: false, now: 7) == .failed)
        var missing = PowerModeSettings.ChangeWait(start: 10)
        #expect(missing.advance(applied: false, authorization: false, now: 12) == .reveal)
        #expect(missing.advance(applied: false, authorization: false, now: 60) == .waiting)
        #expect(missing.advance(applied: false, authorization: true, now: 61) == .waiting)
        #expect(missing.advance(applied: false, authorization: false, now: 62) == .waiting)
        #expect(missing.advance(applied: false, authorization: false, now: 66) == .failed)
    }
}
