import AppKit
import Testing

@testable import Glance

@Suite("Sound panel placement")
struct SoundPanelTests {
    @Test("Sound aligns to either button edge with a gap on both displays")
    func displays() {
        let size = CGSize(width: 308, height: 224)
        // Actual external and built-in usable frames, including the laptop's negative origin.
        for screen in [CGRect(x: 0, y: 0, width: 2304, height: 1266), CGRect(x: -1512, y: -54, width: 1512, height: 860)] {
            let anchor = CGRect(x: screen.midX - 20, y: screen.maxY - 170, width: 40, height: 40)
            let top = SoundMenuPlacement.location(for: size, anchor: anchor, visible: screen)
            let frame = SoundMenuPlacement.frame(for: size, at: top)
            #expect(frame.maxY == anchor.minY - 6)
            #expect(frame.maxX == anchor.maxX)
            let left = SoundMenuPlacement.location(for: size, anchor: anchor, visible: screen, alignTrailing: false)
            #expect(left.x == anchor.minX)
            #expect(screen.contains(frame))
            #expect(!frame.intersects(anchor))
        }
    }

    @Test("Panels near each display edge stay in that display")
    func edges() {
        let visible = CGRect(x: -1512, y: -54, width: 1512, height: 860)
        let size = CGSize(width: 308, height: 224)
        for anchor in [CGRect(x: -1512, y: 700, width: 40, height: 40), CGRect(x: -40, y: 700, width: 40, height: 40), CGRect(x: -700, y: -54, width: 40, height: 40)] {
            let point = SoundMenuPlacement.location(for: size, anchor: anchor, visible: visible)
            #expect(visible.contains(SoundMenuPlacement.frame(for: size, at: point)))
        }
    }
}
