import Foundation
import Testing

@testable import Glance

@Suite("Closed alert button presses")
struct AlertPressTests {
    @Test("Dragging away cancels feedback and release, returning restores only the original control")
    func dragCancellation() {
        let alert = UUID()
        var press = AlertPress()
        press.begin(on: .again, alert: alert)
        #expect(press.highlight(over: .again, alert: alert) == .again)
        #expect(press.highlight(over: nil, alert: alert) == nil)
        #expect(press.highlight(over: .stop, alert: alert) == nil)
        #expect(press.highlight(over: .again, alert: alert) == .again)
        #expect(press.end(over: .stop, alert: alert) == nil)
        #expect(!press.isActive)
    }

    @Test("A replacement alert cannot inherit a previous press")
    func changedAlert() {
        var press = AlertPress()
        press.begin(on: .accept, alert: UUID())
        let replacement = UUID()
        #expect(press.highlight(over: .accept, alert: replacement) == nil)
        #expect(press.end(over: .accept, alert: replacement) == nil)
        #expect(!press.isActive)
    }

    @Test("An unchanged control activates once and a missing alert cannot start a press")
    func activation() {
        var press = AlertPress()
        let alert = UUID()
        press.begin(on: .lowPower, alert: alert)
        #expect(press.end(over: .lowPower, alert: alert) == .lowPower)
        #expect(press.end(over: .lowPower, alert: alert) == nil)
        press.begin(on: .lowPower, alert: nil)
        #expect(!press.isActive)
    }
}
