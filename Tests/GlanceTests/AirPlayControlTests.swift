import CoreAudio
import Testing

@testable import Glance

@MainActor
@Suite("AirPlay controls")
struct AirPlayControlTests {
    private static let speakers = AudioOutput.Device(id: 1, name: "Mac Speakers", symbol: "laptopcomputer", transport: kAudioDeviceTransportTypeBuiltIn)
    private static let headphones = AudioOutput.Device(id: 2, name: "Headphones", symbol: "headphones", transport: kAudioDeviceTransportTypeBluetooth)
    private static let remote = AudioOutput.Device(id: 3, name: "Living Room", symbol: "homepod", transport: kAudioDeviceTransportTypeAirPlay)
    private static let otherRemote = AudioOutput.Device(id: 4, name: "Kitchen", symbol: "homepodmini", transport: kAudioDeviceTransportTypeAirPlay)

    /// Every reader and writer is isolated from Core Audio, including device-model lookup.
    @MainActor
    private final class Fixture {
        var available = [headphones, remote, speakers, otherRemote]
        var current: AudioDeviceID = remote.id
        var enabled = true
        var status: OSStatus = noErr
        var writes: [AudioDeviceID] = []
        lazy var watch = AirPlayWatch(
            outputs: { [unowned self] in available },
            currentOutput: { [unowned self] in current },
            setOutput: { [unowned self] id in
                writes.append(id)
                if status == noErr { current = id }
                return status
            },
            routeSymbol: { $0.symbol },
            isEnabled: { [unowned self] in enabled }
        )
    }

    @Test("Stop restores the previous local route and follows the actual output afterward")
    func restoresPreviousOutput() {
        let fixture = Fixture()
        fixture.current = Self.headphones.id
        fixture.watch.refresh()
        #expect(fixture.watch.route == nil)
        fixture.current = Self.remote.id
        fixture.watch.refresh()
        #expect(fixture.watch.route?.outputID == Self.remote.id)
        #expect(fixture.watch.route?.canStop == true)
        #expect(fixture.watch.stop(expectedOutput: Self.remote.id))
        #expect(fixture.writes == [Self.headphones.id])
        #expect(fixture.watch.route == nil)
    }

    @Test("A missing previous route falls back to built-in, then another available local output")
    func fallbackOrder() {
        let all = [Self.headphones, Self.remote, Self.speakers]
        #expect(AirPlayWatch.returnOutput(in: all, previous: Self.headphones.id)?.id == Self.headphones.id)
        #expect(AirPlayWatch.returnOutput(in: all, previous: 99)?.id == Self.speakers.id)
        #expect(AirPlayWatch.returnOutput(in: all, previous: Self.remote.id)?.id == Self.speakers.id)
        #expect(AirPlayWatch.returnOutput(in: [Self.remote, Self.headphones], previous: nil)?.id == Self.headphones.id)
        #expect(AirPlayWatch.returnOutput(in: [Self.remote], previous: nil) == nil)

        let fixture = Fixture()
        fixture.watch.refresh()
        #expect(fixture.watch.stop())
        #expect(fixture.writes == [Self.speakers.id])
    }

    @Test("A disappearing previous output never receives a stale write")
    func disconnectedPreviousOutput() {
        let fixture = Fixture()
        fixture.current = Self.headphones.id
        fixture.watch.refresh()
        fixture.current = Self.remote.id
        fixture.watch.refresh()
        fixture.available.removeAll { $0.id == Self.headphones.id }
        #expect(fixture.watch.stop())
        #expect(fixture.writes == [Self.speakers.id])
    }

    @Test("Stale route actions cannot replace a new local or AirPlay destination", arguments: [AudioDeviceID(1), 4, 99])
    func staleRoute(current: AudioDeviceID) {
        let fixture = Fixture()
        fixture.watch.refresh()
        fixture.current = current
        #expect(!fixture.watch.stop(expectedOutput: Self.remote.id))
        #expect(fixture.writes.isEmpty)
        #expect(fixture.current == current)
        if current == Self.otherRemote.id {
            #expect(fixture.watch.route?.outputID == current)
        } else {
            #expect(fixture.watch.route == nil)
        }
    }

    @Test("Losing all return targets retracts Stop without changing the current route")
    func noReturnTarget() {
        let fixture = Fixture()
        fixture.watch.refresh()
        fixture.available = [Self.remote]
        #expect(!fixture.watch.stop())
        #expect(fixture.writes.isEmpty)
        #expect(fixture.watch.route?.outputID == Self.remote.id)
        #expect(fixture.watch.route?.canStop == false)
        #expect(!fixture.watch.stop())
        #expect(fixture.writes.isEmpty)
    }

    @Test("A failed output change does not pretend AirPlay stopped")
    func writeFailure() {
        let fixture = Fixture()
        fixture.status = kAudioHardwareUnspecifiedError
        fixture.watch.refresh()
        #expect(!fixture.watch.stop())
        #expect(fixture.writes == [Self.speakers.id])
        #expect(fixture.watch.route?.outputID == Self.remote.id)
    }

    @Test("Disabling the activity clears its route and leaves audio untouched")
    func disabledActivity() {
        let fixture = Fixture()
        fixture.watch.refresh()
        fixture.enabled = false
        fixture.watch.refresh()
        #expect(fixture.watch.route == nil)
        #expect(!fixture.watch.stop(expectedOutput: Self.remote.id))
        #expect(fixture.writes.isEmpty)
    }

    @Test("Hidden and unavailable views reject actions; the active view sends its exact route ID")
    func viewEligibility() {
        var actions: [AudioDeviceID?] = []
        for (revealed, canStop) in [(false, true), (true, false), (true, true)] {
            let route = AirPlayRoute(name: "Living Room", symbol: "homepod", outputID: Self.remote.id, canStop: canStop)
            let view = ExpandedAirPlayView(route: route, restingHeight: 32, width: 400, revealed: revealed, stop: { actions.append($0) })
            view.performStop()
        }
        #expect(actions == [Self.remote.id])
    }
}
