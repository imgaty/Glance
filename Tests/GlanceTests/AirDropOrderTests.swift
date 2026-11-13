import Testing

@testable import Glance

@Suite("AirDrop session order")
struct AirDropOrderTests {
    @Test("Progress updates do not reorder simultaneous incoming transfers")
    func updatesPreserveArrival() {
        var order = AirDropTransferOrder()
        order.received("first")
        order.received("second")
        order.received("first")
        order.received("third")
        order.received("second")
        #expect(order.first(in: ["third", "second", "first"], keeping: nil) == "first")
        order.removed("first")
        #expect(order.first(in: ["third", "second"], keeping: "first") == "second")
    }

    @Test("An older request becoming accepted does not replace the visible transfer")
    func newlyAcceptedWaitsItsTurn() {
        var order = AirDropTransferOrder()
        order.received("waiting")
        order.received("receiving")
        let current = order.first(in: ["receiving"], keeping: nil)
        #expect(current == "receiving")
        #expect(order.first(in: ["waiting", "receiving"], keeping: current) == "receiving")
        // The completed transfer is still eligible during its brief full-ring hold.
        #expect(order.first(in: ["waiting", "receiving"], keeping: current) == "receiving")
        order.removed("receiving")
        #expect(order.first(in: ["waiting"], keeping: current) == "waiting")
    }

    @Test("Cancelled, absent and returning sessions cannot keep stale priority")
    func removalAndReappearance() {
        var order = AirDropTransferOrder()
        order.received("one")
        order.received("two")
        order.received("three")
        #expect(order.first(in: ["two", "three"], keeping: "one") == "two")
        order.removed("one")
        order.received("one")
        #expect(order.first(in: ["one", "two", "three"], keeping: nil) == "two")
        order.removed("two")
        order.removed("three")
        #expect(order.first(in: ["one"], keeping: nil) == "one")
        #expect(order.first(in: [], keeping: "one") == nil)
    }
}
