import AppKit
import Testing

@testable import Glance

@Suite("Sound panel placement")
@MainActor
struct SoundPanelTests {
    @Test("Every click and keyboard activation uses the complete Sound button")
    func buttonAnchor() {
        let anchor = SoundMenuPresenter.Anchor(frame: CGRect(x: 25, y: 60, width: 40, height: 32))
        for pointer: CGPoint? in [nil, CGPoint(x: -750, y: 660), CGPoint(x: 1200, y: 500)] {
            #expect(SoundMenuPlacement.anchorRect(in: anchor, pointer: pointer) == anchor.bounds)
        }
        #expect(SoundMenuPlacement.below(anchor) == .minY)
    }

    @Test("Legacy window click points convert through the actual window and view")
    func windowAnchor() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: CGRect(x: -1000, y: 100, width: 500, height: 250), styleMask: [.borderless], backing: .buffered, defer: false)
        let view = NSView(frame: CGRect(x: 50, y: 30, width: 200, height: 100))
        window.contentView?.addSubview(view)
        let local = CGPoint(x: 35, y: 25)
        let screen = window.convertPoint(toScreen: view.convert(local, to: nil))
        let rect = SoundMenuPlacement.anchorRect(in: view, pointer: screen)
        #expect(rect.midX == local.x)
        #expect(rect.midY == local.y)
        #expect(SoundMenuPlacement.anchorRect(in: view, pointer: nil) == view.bounds)
    }

    @Test("The panel hangs under the button, centered on it, and stays on the screen")
    func frameUnderButton() {
        let visible = CGRect(x: 0, y: 0, width: 1512, height: 950)
        let size = CGSize(width: SoundLook.width, height: 227)
        let button = CGRect(x: 900, y: 800, width: 40, height: 40)
        let frame = SoundMenuPlacement.frame(for: size, below: button, in: visible)
        #expect(frame.midX == button.midX)
        #expect(frame.maxY == button.minY - SoundLook.below)
        // Near the screen's right edge, it's moved in rather than cut off.
        let edge = SoundMenuPlacement.frame(for: size, below: CGRect(x: 1490, y: 800, width: 20, height: 20), in: visible)
        #expect(edge.maxX == visible.maxX)
        // Too low for its height, it stops at the bottom.
        let low = SoundMenuPlacement.frame(for: size, below: CGRect(x: 600, y: 100, width: 40, height: 40), in: visible)
        #expect(low.minY == visible.minY)
    }

    @Test("Opening it never makes Glance the app in use")
    func nonactivating() {
        _ = NSApplication.shared
        let panel = SoundPanelWindow()
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
        #expect(!panel.hidesOnDeactivate)
    }
}
