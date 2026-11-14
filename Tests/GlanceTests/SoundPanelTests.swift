import AppKit
import Testing

@testable import Glance

@Suite("Native Sound popover anchors")
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
}
