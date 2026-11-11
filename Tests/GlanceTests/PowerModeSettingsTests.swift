//
//  PowerModeSettingsTests.swift
//  GlanceTests
//
//  Created by Gaty on 10/11/2026.
//

import PowerControlInterface
import Testing

@Suite("Power helper command boundary")
struct PowerModeSettingsTests {
    @Test("The helper changes only Low Power Mode on the selected power source")
    func scopedCommands() {
        #expect(PowerControlCommand.arguments(enabled: true, source: .battery) == ["-b", "lowpowermode", "1"])
        #expect(PowerControlCommand.arguments(enabled: false, source: .battery) == ["-b", "lowpowermode", "0"])
        #expect(PowerControlCommand.arguments(enabled: true, source: .adapter) == ["-c", "lowpowermode", "1"])
        #expect(PowerControlCommand.arguments(enabled: false, source: .adapter) == ["-c", "lowpowermode", "0"])
    }

    @Test("The signing requirement cannot target an arbitrary executable")
    func identity() {
        #expect(PowerControlIdentity.requirement(for: "untrusted.app") == nil)
        #expect(PowerControlIdentity.requirement(for: "\" or true") == nil)
    }
}
