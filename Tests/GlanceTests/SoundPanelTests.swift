import AppKit
import Testing

@testable import Glance

@Suite("Sound dropdown placement")
@MainActor
struct SoundPanelTests {
    private let visible = CGRect(x: -1512, y: -144, width: 1512, height: 950)
    private let anchor = CGRect(x: -780, y: 650, width: 40, height: 40)
    private let size = CGSize(width: 308, height: 200)

    @Test("Clicks open at the pointer on the built-in display with a small gap")
    func pointerPlacement() {
        let point = CGPoint(x: -750, y: 660)
        let place = SoundMenuPlacement.position(content: size, anchor: anchor, visible: visible, pointer: point)
        let frame = place.frame(for: size)
        #expect(frame.minX == point.x)
        #expect(frame.maxY == point.y - 6)
        #expect(visible.contains(frame))
    }

    @Test("Keyboard activation centers the dropdown below the entire button")
    func keyboardPlacement() {
        let frame = SoundMenuPlacement.position(content: size, anchor: anchor, visible: visible, pointer: nil).frame(for: size)
        #expect(frame.midX == anchor.midX)
        #expect(frame.maxY == anchor.minY - 6)
    }

    @Test("Device insertion keeps the opening edge fixed instead of changing sides")
    func stableGrowth() {
        let place = SoundMenuPlacement.position(content: size, anchor: anchor, visible: visible, pointer: nil)
        let before = place.frame(for: size)
        let after = place.frame(for: CGSize(width: size.width, height: size.height + 64))
        #expect(after.minX == before.minX)
        #expect(after.maxY == before.maxY)
        #expect(after.height == before.height + 64)
    }

    @Test("Near the bottom edge it opens upward and keeps its bottom edge during growth")
    func upwardGrowth() {
        let place = SoundMenuPlacement.position(content: size, anchor: anchor, visible: visible, pointer: CGPoint(x: -400, y: -100))
        #expect(!place.below)
        let before = place.frame(for: size)
        let after = place.frame(for: CGSize(width: size.width, height: 400))
        #expect(after.minY == before.minY)
        #expect(visible.contains(after))
    }

    @Test("Screen confinement and right-to-left alignment work with a negative display origin")
    func displayEdges() {
        for point in [CGPoint(x: -1510, y: 800), CGPoint(x: -2, y: 800), CGPoint(x: -2, y: -140)] {
            let place = SoundMenuPlacement.position(content: size, anchor: anchor, visible: visible, pointer: point)
            #expect(visible.contains(place.frame(for: size)))
            #expect(visible.contains(place.frame(for: CGSize(width: 308, height: 2000))))
        }
        let point = CGPoint(x: -700, y: 660)
        let frame = SoundMenuPlacement.position(content: size, anchor: anchor, visible: visible, pointer: point, mirrored: true).frame(for: size)
        #expect(frame.maxX == point.x)
    }
}
