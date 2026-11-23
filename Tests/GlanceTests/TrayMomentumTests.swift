import AppKit
import CoreGraphics
import Testing

@testable import Glance

@Suite("Trackpad momentum on the notch")
@MainActor
struct TrayMomentumTests {
    /// A scroll made up in the test process and handed to one window, never posted to the system.
    private func scroll(phase: Int64, momentum: Int64, dx: Int32) throws -> NSEvent {
        let event = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 0, wheel2: dx, wheel3: 0))
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
        return try #require(NSEvent(cgEvent: event))
    }

    @Test("The glide after the fingers lift reaches the notch, which AppKit's own dispatch drops")
    func momentumReachesTheNotch() throws {
        _ = NSApplication.shared
        let panel = NotchPanel(frame: CGRect(x: 0, y: 0, width: 300, height: 120))
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) - 1)
        var phases: [NSEvent.Phase] = []
        var momentum: [NSEvent.Phase] = []
        panel.onScroll = { event in
            if event.momentumPhase.isEmpty { phases.append(event.phase) } else { momentum.append(event.momentumPhase) }
        }
        // CGScrollPhase began 1, changed 2, ended 4; CGMomentumScrollPhase begin 1, continue 2, end 3.
        for (phase, glide, dx) in [(1, 0, -4), (2, 0, -12), (4, 0, 0), (0, 1, -10), (0, 2, -8), (0, 3, 0)] as [(Int64, Int64, Int32)] {
            panel.sendEvent(try scroll(phase: phase, momentum: glide, dx: dx))
        }
        #expect(phases == [.began, .changed, .ended])
        #expect(momentum == [.began, .changed, .ended])
    }
}
