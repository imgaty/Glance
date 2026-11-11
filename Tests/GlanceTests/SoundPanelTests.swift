import AppKit
import Testing

@testable import Glance

@Suite("Sound panel placement")
@MainActor
struct SoundPanelTests {
    @Test("The panel stays below its control on each monitor")
    func displays() {
        let size = CGSize(width: 308, height: 240)
        for screen in [CGRect(x: 0, y: 0, width: 1512, height: 950), CGRect(x: -1920, y: 100, width: 1920, height: 1050), CGRect(x: 800, y: -1200, width: 1920, height: 1050)] {
            let anchor = CGRect(x: screen.midX, y: screen.maxY - 180, width: 0, height: 0)
            let origin = StatusPanel.origin(for: size, anchor: anchor, visible: screen)
            #expect(origin.y + size.height == anchor.minY - 6)
            #expect(screen.contains(CGRect(origin: origin, size: size)))
            let edge = CGRect(x: screen.maxX - 8, y: anchor.minY, width: 0, height: 0)
            #expect(StatusPanel.origin(for: size, anchor: edge, visible: screen).x + size.width == edge.maxX)
        }
    }
}
