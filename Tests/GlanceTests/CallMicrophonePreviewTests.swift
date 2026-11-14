import Foundation
import Testing

@testable import Glance

@MainActor
struct CallMicrophonePreviewTests {
    @Test("A fake unavailable microphone stays unavailable and has no call control")
    func unavailable() {
        let microphone = CallMicrophone(fakes: true, fakeAvailable: false)
        microphone.refresh()
        #expect(!microphone.available)
        let call = CallShown(name: "Alex", over: "Phone", app: CallAudio.phone, phase: .connected(since: .now), canEnd: true)
        let controls = ExpandedCallView.controls(for: call, microphoneAvailable: microphone.available, sourceAvailable: true)
        #expect(!controls.contains(.activitySecond))
        #expect(controls == [.activityFirst, .activityThird, .activityFourth])
    }

    @Test("The fake capability override cannot change live microphone availability")
    func liveIgnoresOverride() {
        let available = CallMicrophone.canMute
        let microphone = CallMicrophone(fakes: false, fakeAvailable: !available)
        #expect(microphone.available == available)
    }
}
