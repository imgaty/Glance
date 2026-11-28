import AppKit
import CoreAudio
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

    @Test("It hangs under the button as the Dock's menus hang by their icons, its arrow in the middle")
    func frameUnderButton() {
        let visible = CGRect(x: 0, y: 0, width: 1512, height: 950)
        let size = CGSize(width: SoundLook.width, height: 227)
        // The player's Sound button: the box centered on it, the arrow's tip at its edge, the
        // container's 13 points above the box.
        let button = CGRect(x: 877, y: 832, width: 40, height: 40)
        let frame = SoundMenuPlacement.frame(for: size, below: button, in: visible)
        #expect(frame.midX == button.midX)
        #expect(frame.maxY == button.minY - 13)
        #expect(SoundCalloutView.margin == 13)
        // Near the screen's edges, it's moved in rather than cut off.
        let edge = SoundMenuPlacement.frame(for: size, below: CGRect(x: 1490, y: 800, width: 20, height: 20), in: visible)
        #expect(edge.maxX == visible.maxX)
        let start = SoundMenuPlacement.frame(for: size, below: CGRect(x: 2, y: 800, width: 20, height: 20), in: visible)
        #expect(start.minX == visible.minX)
        // Too low for its height, it stops at the bottom.
        let low = SoundMenuPlacement.frame(for: size, below: CGRect(x: 600, y: 100, width: 40, height: 40), in: visible)
        #expect(low.minY == visible.minY)
    }

    @Test("The window holds the box and the arrow's strip; beside the arrow is outside it")
    func calloutOutline() {
        _ = NSApplication.shared
        let callout = SoundCalloutView()
        callout.frame = SoundPanel.windowFrame(around: CGRect(x: 0, y: 0, width: SoundLook.width, height: 161))
        callout.point(at: 154)
        #expect(callout.box == CGRect(x: 0, y: 0, width: SoundLook.width, height: 161))
        #expect(callout.shows(CGPoint(x: 154, y: 80)))
        if SoundCalloutView.pointsWithArrow {
            // The arrow, up to its rounded tip about ten points above the box.
            #expect(callout.shows(CGPoint(x: 154, y: 161 + 8)))
            // The clear strip beside it, and the box's cut corners.
            #expect(!callout.shows(CGPoint(x: 40, y: 161 + 6)))
            #expect(!callout.shows(CGPoint(x: 0.5, y: 160.5)))
            #expect(callout.layer?.mask is CAShapeLayer)
        }
    }

    @Test("A click acts once: on its press when seen going down, otherwise on its release")
    func pressedClick() throws {
        _ = NSApplication.shared
        func mouse(_ type: NSEvent.EventType, _ number: Int) throws -> NSEvent {
            try #require(
                NSEvent.mouseEvent(
                    with: type, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: number,
                    clickCount: 1, pressure: 1))
        }
        // Seen going down: the press acts, and that click's release doesn't again.
        #expect(PressedClick.takes(try mouse(.leftMouseDown, 41)))
        #expect(PressedClick.releasesHandled(try mouse(.leftMouseUp, 41)))
        // Only once, and never for another click's release.
        #expect(!PressedClick.releasesHandled(try mouse(.leftMouseUp, 41)))
        #expect(PressedClick.takes(try mouse(.leftMouseDown, 42)))
        #expect(!PressedClick.releasesHandled(try mouse(.leftMouseUp, 43)))
        // A press seen late, or by the keys, doesn't act: the button acts as it's let go.
        #expect(!PressedClick.takes(try mouse(.leftMouseDragged, 44)))
        #expect(!PressedClick.takes(nil))
        #expect(!PressedClick.releasesHandled(nil))
    }

    @Test("A held press chooses only a row it's let go on, in sight in the panel")
    func pressedRow() async throws {
        _ = NSApplication.shared
        let speakers = AudioOutput.Device(id: 10001, name: "MacBook Pro Speakers", symbol: "macbook.gen2", transport: kAudioDeviceTransportTypeBuiltIn)
        let menu = SoundOutputMenu(devices: [speakers], current: speakers.id, volume: nil, batteries: [:], choose: { _ in }, settings: {})
        let screen = try #require(NSScreen.screens.first)
        let panel = SoundPanel(menu: menu, maximumHeight: 700)
        // Behind the wallpaper and never key: shown only so its rows have a place on the screen.
        panel.window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) - 1)
        panel.window.ignoresMouseEvents = true
        panel.window.setFrame(
            SoundPanel.windowFrame(around: CGRect(origin: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.minY + 100), size: panel.contentSize)), display: true)
        panel.window.orderFrontRegardless()
        defer { panel.window.orderOut(nil) }
        #expect(!panel.window.isKeyWindow)
        // The rows follow the window as it grows, the arrow's strip kept above them.
        let grown = panel.window.frame.insetBy(dx: 0, dy: -20)
        panel.window.setFrame(grown, display: true)
        #expect(panel.contentView.frame.maxY == panel.window.frame.height - SoundCalloutView.margin)
        panel.window.setFrame(grown.insetBy(dx: 0, dy: 20), display: true)
        let item = try #require(menu.items.first { $0.tag == Int(speakers.id) })
        let row = try #require(item.view as? SoundMenuContentRow)
        let rect = panel.window.convertToScreen(row.convert(row.bounds, to: nil))
        #expect(panel.row(at: CGPoint(x: rect.midX, y: rect.midY)) === row)
        // The slider's row and anything outside the panel choose nothing.
        let slider = try #require(menu.items.first { $0.view is VolumeMenuSlider }?.view)
        let sliderRect = panel.window.convertToScreen(slider.convert(slider.bounds, to: nil))
        #expect(panel.row(at: CGPoint(x: sliderRect.midX, y: sliderRect.midY)) == nil)
        #expect(panel.row(at: CGPoint(x: panel.window.frame.minX - 10, y: rect.midY)) == nil)
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
