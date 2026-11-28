import Foundation
import Testing

@testable import Glance

/// What Do Not Disturb's service logged on macOS 27.3 as Do Not Disturb was turned on and then off
/// from Control Center's panel (2026-11-28), whose banner Control Center dropped: each line cut short
/// at the length the log keeps.
@Suite("Focus changes read from Do Not Disturb's log")
struct FocusLogTests {
    static let turnedOn = """
        Delivering state update: pid=720, stateUpdate=<DNDStateUpdate: 0x7abe852c10; reason: user action; source: local; options: <none>; state: <DNDState: 0x7abee1b980; suppressionState: while UI locked; startDate: 2026-11-28 13:35:00 +0000; userVisibleTransitionDate: 2026-11-30 17:00:00 +0000; userVisibleTransitionLifetimeType: schedule; activeModeConfiguration: <DNDMutableModeConfiguration: 0x7abeeb9480; mode: <DNDMode: 0x7abe8267b0; name: Do Not Disturb; modeIdentifier: com.apple.donotdisturb.mode.default; symbolImageName: moon.fill; tintColorName: systemIndigoColor; symbolDescriptor: (null); semanticType: 0; visibility: 0; identifier: 49017CE2-2DA8-44B0-838C-D727BD363A08; isPlaceHolder: NO>; impactsAvailability: disabled; dimsLockScreen: default>; activeModeIdentifier: com.apple.donotdisturb.mode.default>; previousState: <DNDState: 0x7abee1b100; suppressionState: inactive; startDate: 2026-11-28 12:53:35 +0000; userVisibleTransitionDate: 2026-11-30 09:00:00 +0000; userVisibleTransitionLifetimeType: schedule; activeModeConfiguration: (null); ac, connection=<decode: missing data>
        """
    static let turnedOff = """
        Delivering state update: pid=720, stateUpdate=<DNDStateUpdate: 0x7abe853bd0; reason: user action; source: local; options: <none>; state: <DNDState: 0x7abee1ad40; suppressionState: inactive; startDate: 2026-11-28 13:35:02 +0000; userVisibleTransitionDate: 2026-11-30 09:00:00 +0000; userVisibleTransitionLifetimeType: schedule; activeModeConfiguration: (null); activeModeIdentifier: (null)>; previousState: <DNDState: 0x7abee1ad00; suppressionState: while UI locked; startDate: 2026-11-28 13:35:00 +0000; userVisibleTransitionDate: 2026-11-30 17:00:00 +0000; userVisibleTransitionLifetimeType: schedule; activeModeConfiguration: <DNDMutableModeConfiguration: 0x7abeeb8600; mode: <DNDMode: 0x7abe826d50; name: Do Not Disturb; modeIdentifier: com.apple.donotdisturb.mode.default; symbolImageName: moon.fill; tintColorName: systemIndigoColor; symbolDescriptor: (null); semanticType: 0; visibility: 0; identifier: 49017CE2-2DA8-44B0-838C-D727BD363A08; isPlaceHolder: NO>; impactsAvailability: disabled; dimsLockScreen: default>; activeModeIdentifier: com.apple, connection=<decode: missing data>
        """
    static let doNotDisturb = FocusStateLine.Mode(identifier: "com.apple.donotdisturb.mode.default", name: "Do Not Disturb", symbol: "moon.fill")

    @Test("A line says which Focus is on now and which was before, cut short as it is")
    func reads() throws {
        let on = try #require(FocusStateLine.read(Self.turnedOn))
        #expect(on.active == Self.doNotDisturb)
        #expect(on.previousRead && on.previous == nil)
        let off = try #require(FocusStateLine.read(Self.turnedOff))
        #expect(off.active == nil)
        #expect(off.previousRead && off.previous == Self.doNotDisturb)
        // Another of the service's lines, or one cut before what's on now, isn't read.
        #expect(FocusStateLine.read("Delivering active mode update: pid=655, activeModeIdentifier=(null)") == nil)
        #expect(FocusStateLine.read(String(Self.turnedOn.prefix(400))) == nil)
    }

    @Test("Only a different Focus is news: on, then off, each once though every client's line repeats it")
    func follows() throws {
        let on = try #require(FocusStateLine.read(Self.turnedOn))
        let off = try #require(FocusStateLine.read(Self.turnedOff))
        var follower = FocusModeFollower()
        let turnedOn = follower.take(on)
        let first = try #require(turnedOn)
        #expect(first.mode == Self.doNotDisturb && first.on)
        // The same state, delivered to the next client.
        let again = follower.take(on)
        #expect(again == nil)
        let turnedOff = follower.take(off)
        let second = try #require(turnedOff)
        #expect(second.mode == Self.doNotDisturb && !second.on)
        let offAgain = follower.take(off)
        #expect(offAgain == nil)
    }

    @Test("Before anything's known, a line that doesn't say what was on before is only noted")
    func unknownBefore() throws {
        // Cut before the Focus before: the screen locking with Do Not Disturb already on reads so.
        let cut = Self.turnedOn.components(separatedBy: "; previousState: ")[0] + "; previousState: <DNDState: 0x1; suppressionState: inactive"
        let line = try #require(FocusStateLine.read(cut))
        #expect(!line.previousRead)
        var follower = FocusModeFollower()
        let noted = follower.take(line)
        #expect(noted == nil)
        // Known from then on: turning it off is news.
        let off = try #require(FocusStateLine.read(Self.turnedOff))
        let turnedOff = follower.take(off)
        #expect(turnedOff?.on == false)
    }

    @Test("Lines of newline-delimited JSON come whole, however the stream breaks them up")
    func lines() throws {
        let object = try JSONSerialization.data(withJSONObject: ["eventMessage": Self.turnedOn, "processImagePath": "/usr/sbin/donotdisturbd"])
        let data = object + Data([0x0A]) + object + Data([0x0A])
        let reader = LogLines()
        let split = data.count / 3
        #expect(reader.take(data.prefix(split)).isEmpty)
        let messages = reader.take(data.dropFirst(split))
        #expect(messages == [Self.turnedOn, Self.turnedOn])
    }
}

