import AppKit
import Testing

@testable import Glance

@Suite("Native Sound popover anchors")
@MainActor
struct SoundPanelTests {
    @Test("Player clicks and keyboard activation use the whole button")
    func buttonAnchor() {
        let view = SoundMenuPresenter.Anchor(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
        #expect(SoundMenuPlacement.anchorRect(in: view, pointer: nil) == view.bounds)
        #expect(SoundMenuPlacement.anchorRect(in: view, pointer: CGPoint(x: -620, y: 700)) == view.bounds)
        #expect(SoundMenuPlacement.below(view) == .minY)
    }

    @Test("Call anchors convert screen coordinates on a display with a negative origin")
    func screenPoint() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: CGRect(x: -1100, y: 300, width: 500, height: 300), styleMask: [.borderless], backing: .buffered, defer: false)
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) - 1)
        window.ignoresMouseEvents = true
        let view = NSView(frame: CGRect(x: 200, y: 100, width: 40, height: 40))
        window.contentView?.addSubview(view)
        let clicked = CGPoint(x: 12, y: 24)
        let screen = window.convertPoint(toScreen: view.convert(clicked, to: nil))
        let rect = SoundMenuPlacement.anchorRect(in: view, pointer: screen)
        #expect(rect.midX == clicked.x)
        #expect(rect.midY == clicked.y)
        #expect(rect.size == CGSize(width: 1, height: 1))
    }

    @Test("A flipped call view still opens downward")
    func flipped() {
        class Flipped: NSView { override var isFlipped: Bool { true } }
        #expect(SoundMenuPlacement.below(Flipped()) == .maxY)
    }
}
