import Testing

@testable import Glance

@Suite("AirDrop send completion")
struct AirDropCompletionTests {
    @Test("Reaching or reading beyond EOF never claims delivery or removes an available Stop", arguments: [Int64(990), 999, 1000, 1200])
    func unconfirmedEnd(offset: Int64) {
        let file = AirDropSendWatch.OpenFile(descriptor: 7, path: "/fixture/movie.mov", offset: offset, size: 1000)
        let shown = AirDropShown(id: "fixture", sender: "", fraction: AirDropSendWatch.displayedFraction(of: file), sending: true, canStop: true)
        #expect(shown.fraction <= 0.99)
        #expect(!shown.done)
        #expect(shown.offersStop)
    }

    @Test("Ordinary file-read progress remains useful without inventing progress for an empty file")
    func intermediateProgress() {
        let half = AirDropSendWatch.OpenFile(descriptor: 7, path: "/fixture/movie.mov", offset: 500, size: 1000)
        let empty = AirDropSendWatch.OpenFile(descriptor: 8, path: "/fixture/empty.txt", offset: 0, size: 0)
        #expect(AirDropSendWatch.displayedFraction(of: half) == 0.5)
        #expect(AirDropSendWatch.displayedFraction(of: empty) == 0)
    }
}
