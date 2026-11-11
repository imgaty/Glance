import Testing

@testable import Glance

@Suite("Bluetooth listening modes")
struct ListeningModeTests {
    @Test("Only supported modes are offered, in the native order")
    func available() {
        #expect(ListeningMode.Snapshot(current: 3, support: 7, writable: true).available == [.transparency, .adaptive, .noiseCancellation])
        #expect(ListeningMode.Snapshot(current: 2, support: 3, writable: true).available == [.transparency, .noiseCancellation])
        #expect(ListeningMode.Snapshot(current: 99, support: 8, writable: true).available.isEmpty)
        #expect(ListeningMode.Snapshot(current: 3, support: 7, writable: true).available.contains(.off) == false)
    }

    @Test("Unsupported, unavailable and read-only devices receive no write")
    func rejected() async {
        for state in [nil, ListeningMode.Snapshot(current: 3, support: 3, writable: true), ListeningMode.Snapshot(current: 3, support: 7, writable: false)] {
            var writes = 0
            let success = await ListeningMode.change(
                to: .adaptive, read: { state },
                write: { _ in
                    writes += 1
                    return true
                }, wait: {})
            #expect(!success)
            #expect(writes == 0)
        }
    }

    @Test("An accepted write is not success without confirmation from the device")
    func unconfirmed() async {
        let state = ListeningMode.Snapshot(current: 3, support: 7, writable: true)
        var waits = 0
        let success = await ListeningMode.change(to: .noiseCancellation, read: { state }, write: { _ in true }, wait: { waits += 1 })
        #expect(!success)
        #expect(waits == 12)
    }

    @Test("The current mode is kept until the device confirms the change")
    func confirmed() async {
        var current: UInt32 = 3
        var waits = 0
        let success = await ListeningMode.change(
            to: .adaptive, read: { .init(current: current, support: 7, writable: true) }, write: { _ in true },
            wait: {
                waits += 1
                if waits == 2 { current = 4 }
            })
        #expect(success)
        #expect(waits == 2)
    }

    @Test("Selecting the current mode does not send a device command")
    func unchanged() async {
        var writes = 0
        let success = await ListeningMode.change(
            to: .transparency, read: { .init(current: 3, support: 7, writable: true) },
            write: { _ in
                writes += 1
                return true
            }, wait: {})
        #expect(success)
        #expect(writes == 0)
    }
}
