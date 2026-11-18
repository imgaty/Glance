import SwiftUI
import Testing

@testable import Glance

@MainActor
@Suite("AirPods listening mode")
struct ListeningModeTests {
    private let words: [ListeningMode: String] = [.noiseCancellation: "Noise Cancellation", .transparency: "Transparency", .adaptive: "Adaptive", .off: "Off"]

    @Test("The mode is read from the banner's symbol, or failing that its words, and only from a listening mode banner")
    func read() {
        let bySymbol = FocusBannerSnapshot(
            identifier: ListeningMode.banner, texts: ["Listening Mode", "Transparency"], images: [.init(symbol: "person.open.fill", description: nil)])
        #expect(ListeningMode.read(bySymbol, words: words) == ListeningModeChange(mode: .transparency, word: "Transparency"))
        let byWord = FocusBannerSnapshot(identifier: ListeningMode.banner, texts: ["Listening Mode", "Off"], images: [])
        #expect(ListeningMode.read(byWord, words: words)?.mode == .off)
        let focus = FocusBannerSnapshot(identifier: FocusBannerSnapshot.identifier, texts: ["Do Not Disturb", "Off"], images: [])
        #expect(ListeningMode.read(focus, words: words) == nil)
        let unknown = FocusBannerSnapshot(identifier: ListeningMode.banner, texts: ["Something else"], images: [])
        #expect(ListeningMode.read(unknown, words: words) == nil)
    }

    @Test("Announced as macOS 27's island shows it: the AirPods on the left, the mode's symbol on the right, said by name")
    func alert() {
        let alert = ListeningModeChange(mode: .noiseCancellation, word: "Noise Cancellation").alert
        #expect(alert.kind == .listeningMode)
        #expect(alert.content == .symbols(leading: "airpods.pro", trailing: "person.closed.fill"))
        #expect(alert.spoken == "Noise Cancellation")
        #expect(!alert.tall)
        // Both sides as wide as a symbol needs beside the camera.
        let wing = SystemActivityView.wing(for: alert, restingHeight: 32, closedWidth: 185)
        #expect(isClose(wing, LiveActivityView.inset + SystemActivityView.side(32) + LiveActivityView.cameraGap))
        // Every mode's symbol draws, private ones included.
        for mode in ListeningMode.allCases { #expect(SystemSymbol.exists(mode.symbol)) }
    }

    @Test("The AirPods' own numbers for each mode, over Bluetooth")
    func bluetoothValues() {
        #expect(ListeningMode(bluetooth: 1) == .off)
        #expect(ListeningMode(bluetooth: 2) == .noiseCancellation)
        #expect(ListeningMode(bluetooth: 3) == .transparency)
        #expect(ListeningMode(bluetooth: 4) == .adaptive)
        #expect(ListeningMode(bluetooth: 0) == nil)
    }
}
