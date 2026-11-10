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
