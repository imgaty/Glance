import AppKit
import Testing

@testable import Glance

@Suite("Sound menu placement")
@MainActor
struct SoundPanelTests {
    @Test("The menu starts below its control and fits horizontally on each monitor")
    func displays() {
        let size = CGSize(width: 308, height: 240)
        for screen in [CGRect(x: 0, y: 0, width: 1512, height: 950), CGRect(x: -1920, y: 100, width: 1920, height: 1050), CGRect(x: 800, y: -1200, width: 1920, height: 1050)] {
            let anchor = CGRect(x: screen.midX, y: screen.maxY - 180, width: 0, height: 0)
            let top = SoundMenuPlacement.location(for: size, anchor: anchor, visible: screen)
            #expect(top.y == anchor.minY - 6)
            #expect(screen.contains(CGRect(x: top.x, y: top.y - size.height, width: size.width, height: size.height)))
            let edge = CGRect(x: screen.maxX - 8, y: anchor.minY, width: 0, height: 0)
            #expect(SoundMenuPlacement.location(for: size, anchor: edge, visible: screen).x + size.width == screen.maxX)
            let leftEdge = CGRect(x: screen.minX, y: anchor.minY, width: 40, height: 40)
            #expect(SoundMenuPlacement.location(for: size, anchor: leftEdge, visible: screen).x == screen.minX)
        }
    }
}
