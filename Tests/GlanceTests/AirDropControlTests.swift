import Testing

@testable import Glance

@MainActor
@Suite("AirDrop controls")
struct AirDropControlTests {
    @Test("Only an unfinished transfer with cancellation available offers Stop")
    func availability() {
        var transfer = AirDropShown(id: "fixture", sender: "Phone", fraction: 0.4, canStop: false)
        #expect(!transfer.offersStop)
        transfer.canStop = true
        #expect(transfer.offersStop)
        transfer.fraction = 1
        #expect(!transfer.offersStop)
    }

    @Test("Hidden, unavailable and completed AirDrop views never invoke cancellation")
    func unavailableActions() {
        var actions = 0
        for (revealed, available, fraction) in [(false, true, 0.4), (true, false, 0.4), (true, true, 1.0)] {
            let transfer = AirDropShown(id: "fixture", sender: "Phone", fraction: fraction, canStop: available)
            let view = ExpandedAirDropView(shown: transfer, restingHeight: 32, width: 400, revealed: revealed, stop: { actions += 1 })
            view.performStop()
        }
        #expect(actions == 0)
    }

    @Test("Visible receiving and sending controls invoke their isolated action once")
    func availableActions() {
        var actions = 0
        for sending in [false, true] {
            let transfer = AirDropShown(id: "fixture", sender: "Phone", fraction: 0.4, sending: sending, canStop: true)
            let view = ExpandedAirDropView(shown: transfer, restingHeight: 32, width: 400, stop: { actions += 1 })
            view.performStop()
        }
        #expect(actions == 2)
    }
}
