import CoreAudio
import Foundation
import Testing

@testable import Glance

@MainActor
@Suite("Call audio", .serialized)
struct CallAudioTests {
    /// As measured on a real Discord call: its renderer plays and records, a helper does neither, and
    /// Glance's own taps count as recording.
    let processes = [
        CallAudio.Process(pid: 10, bundle: "com.hnc.Discord.helper.Renderer", input: true, output: true, microphones: [77]),
        CallAudio.Process(pid: 11, bundle: "com.hnc.Discord.helper", input: false, output: false),
        CallAudio.Process(pid: 12, bundle: "com.spotify.client", input: false, output: true),
        CallAudio.Process(pid: 13, bundle: "dev.vibe.Glance", input: true, output: true, microphones: [90]),
        CallAudio.Process(pid: 14, bundle: "us.zoom.xos", input: true, output: true, microphones: [80]),
    ]

    @Test("A call's processes are its app's, helpers included, and never Glance's own or another app's")
    func callProcesses() {
        #expect(CallAudio.ofCall(processes, in: "com.hnc.Discord.helper.Renderer").map(\.pid) == [10, 11])
        #expect(CallAudio.ofCall(processes, in: "com.hnc.Discord").map(\.pid) == [10, 11])
        // Not knowing the app, any calling app's.
        #expect(CallAudio.ofCall(processes, in: nil).map(\.pid) == [10, 11, 14])
        #expect(CallAudio.ofCall(processes, in: "com.spotify.client").map(\.pid) == [10, 11, 14])
    }

    @Test("Your voice is heard from the microphone the call records from, as Discord's MacBook microphone beside AirPods")
    func callsOwnMicrophone() {
        let macBook = CallAudio.Microphone(id: 77, listed: true, hasInput: true, ours: false)
        let recordedFrom = CallAudio.ofCall(processes, in: "com.hnc.Discord.helper.Renderer").flatMap(\.microphones)
        #expect(recordedFrom == [77])
        #expect(CallAudio.microphone(among: [macBook]) == 77)
    }

    @Test("With the call recording from no microphone, none is opened: there's no default to fall back on")
    func noMicrophone() {
        #expect(CallAudio.microphone(among: []) == nil)
        #expect(CallAudio.ofCall(processes, in: "com.hnc.Discord.helper").flatMap(\.microphones) == [77])
    }

    @Test("Glance's own devices, another app's private devices and devices without input are never opened")
    func onlyOpenableMicrophones() {
        let ours = CallAudio.Microphone(id: 200, listed: true, hasInput: true, ours: true)
        let privateAggregate = CallAudio.Microphone(id: 201, listed: false, hasInput: true, ours: false)
        let speakers = CallAudio.Microphone(id: 70, listed: true, hasInput: false, ours: false)
        let headset = CallAudio.Microphone(id: 90, listed: true, hasInput: true, ours: false)
        #expect(CallAudio.microphone(among: [ours, privateAggregate, speakers]) == nil)
        #expect(CallAudio.microphone(among: [ours, privateAggregate, speakers, headset]) == 90)
    }

    @Test("An app turned down that starts recording, as on a call, goes back to full and isn't turned down again")
    func recordingAppAtFull() {
        let volume = AppVolume.shared
        let app = "test.glance.call-app"
        defer { volume.follow(app: nil, pid: 0) }
        // No process to tap: only what the slider remembers changes.
        volume.follow(app: app, pid: 0)
        volume.set(0.4)
        #expect(abs(volume.level - 0.4) < 0.001)
        volume.recording(app)
        #expect(volume.level == 1)
        volume.follow(app: nil, pid: 0)
        volume.follow(app: app, pid: 0)
        #expect(volume.level == 1)
    }
}
