import Carbon.HIToolbox
import Testing

@testable import Glance

@MainActor
@Suite("Call control availability")
struct CallControlsTests {
    @Test("A third-party source precedes its available call actions")
    func thirdParty() {
        let call = CallShown(name: "Alex", over: "Conference", app: "fixture.conference", phase: .connected(since: .now), canEnd: true)
        #expect(ExpandedCallView.controls(for: call, microphoneAvailable: true, sourceAvailable: true) == [.activityThird, .activityFirst, .activityFourth])
        #expect(ExpandedCallView.controls(for: call, microphoneAvailable: true, sourceAvailable: false) == [.activityFirst, .activityFourth])
    }

    @Test("An Apple call keeps one source action and only supported microphone and end actions")
    func apple() {
        let call = CallShown(name: "Alex", over: "Phone", app: CallAudio.phone, phase: .connected(since: .now), canEnd: true)
        #expect(ExpandedCallView.controls(for: call, microphoneAvailable: true, sourceAvailable: true) == [.activityFirst, .activitySecond, .activityThird, .activityFourth])
        #expect(ExpandedCallView.controls(for: call, microphoneAvailable: false, sourceAvailable: false) == [.activityFirst, .activityFourth])
    }

    @Test("An incoming call can open its source without exposing an unsupported decline")
    func ringing() {
        var call = CallShown(name: "Alex", over: "Conference", app: "fixture.conference", phase: .ringing, canDecline: false)
        #expect(ExpandedCallView.controls(for: call, microphoneAvailable: false, sourceAvailable: true) == [.activityThird, .activitySecond])
        call.canDecline = true
        #expect(ExpandedCallView.controls(for: call, microphoneAvailable: false, sourceAvailable: true) == [.activityThird, .activityFirst, .activitySecond])
    }

    @Test("A calling page remains useful through its source even when ending is unavailable")
    func outgoing() {
        var call = CallShown(name: "Alex", over: "Conference", app: "fixture.conference", phase: .calling)
        #expect(ExpandedCallView.controls(for: call, microphoneAvailable: false, sourceAvailable: true) == [.activityThird])
        #expect(ExpandedCallView.controls(for: call, microphoneAvailable: false, sourceAvailable: false).isEmpty)
        call.canEnd = true
        #expect(ExpandedCallView.controls(for: call, microphoneAvailable: false, sourceAvailable: true) == [.activityThird, .activityFirst])
    }

    @Test("A lost source cannot receive a stale Return press")
    func lostSource() {
        let call = CallShown(name: "Alex", over: "Conference", app: "fixture.conference", phase: .connected(since: .now))
        let keys = PlayerKeys()
        keys.focus(on: .activityThird)
        let controls = ExpandedCallView.controls(for: call, microphoneAvailable: false, sourceAvailable: false)
        #expect(keys.typed(key: kVK_Return, shift: false, hasMedia: true, activity: controls) == .none)
        #expect(keys.focus == nil)
        #expect(keys.presses == 0)
        #expect(keys.typed(key: kVK_Tab, shift: false, hasMedia: true, activity: controls) == .moved)
        #expect(keys.focus == .activityFirst)
    }

    @Test("Missing or unknown apps do not become a FaceTime source link")
    func unavailableSource() {
        let unnamed = CallShown(name: "Alex", over: "Conference", phase: .calling)
        let missing = CallShown(name: "Alex", over: "Conference", app: "invalid.glance.fixture.missing-call-source", phase: .calling)
        #expect(unnamed.sourceURL == nil)
        #expect(missing.sourceURL == nil)
    }
}
