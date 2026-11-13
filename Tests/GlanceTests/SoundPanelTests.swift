import AppKit
import SwiftUI
import Testing

@testable import Glance

@Suite("Sound popover placement")
struct SoundPanelTests {
    private let visible = CGRect(x: -1512, y: -144, width: 1512, height: 950)
    private let button = CGRect(x: -640, y: 680, width: 40, height: 40)
    private let size = CGSize(width: 308, height: 224.5)

    @Test("The arrow is centered beneath the button without overlapping it")
    func buttonAnchor() {
        let layout = SoundMenuPlacement.layout(content: size, anchor: button, visible: visible)
        #expect(layout.below)
        #expect(layout.frame.minX + layout.arrowX == button.midX)
        #expect(layout.frame.maxY == button.minY - SoundMenuPlacement.gap)
        #expect(!layout.frame.intersects(button))
        #expect(visible.contains(layout.frame))
    }

    @Test("The body stays on its display at either horizontal edge")
    func edges() {
        for x in [visible.minX, visible.maxX - button.width] {
            let edgeButton = CGRect(x: x, y: button.minY, width: button.width, height: button.height)
            let layout = SoundMenuPlacement.layout(content: size, anchor: edgeButton, visible: visible)
            #expect(visible.contains(layout.frame))
            #expect(layout.arrowX >= SoundLook.radius + 20)
            #expect(layout.arrowX <= size.width - SoundLook.radius - 20)
        }
    }

    @Test("The popover opens above a button close to the screen bottom")
    func above() {
        let anchor = CGRect(x: button.minX, y: visible.minY + 20, width: 40, height: 40)
        let layout = SoundMenuPlacement.layout(content: size, anchor: anchor, visible: visible)
        #expect(!layout.below)
        #expect(layout.frame.minY == anchor.maxY + SoundMenuPlacement.gap)
        #expect(visible.contains(layout.frame))
    }

    @Test("All four body corners have the same outline, with the arrow on either edge")
    func corners() {
        let height = size.height + SoundMenuPlacement.arrowHeight
        for below in [true, false] {
            let path = SoundPopoverShape(arrowX: 154, below: below).path(in: CGRect(x: 0, y: 0, width: size.width, height: height))
            let top: CGFloat = below ? SoundMenuPlacement.arrowHeight : 0
            let bottom = top + size.height
            for x in stride(from: 0.25, through: 16, by: 0.5) {
                for y in stride(from: 0.25, through: 16, by: 0.5) {
                    let corner = path.contains(CGPoint(x: x, y: top + y))
                    #expect(path.contains(CGPoint(x: size.width - x, y: top + y)) == corner)
                    #expect(path.contains(CGPoint(x: x, y: bottom - y)) == corner)
                    #expect(path.contains(CGPoint(x: size.width - x, y: bottom - y)) == corner)
                }
            }
        }
    }
}
