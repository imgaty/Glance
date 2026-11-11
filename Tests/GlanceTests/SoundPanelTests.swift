import AppKit
import Testing

@testable import Glance

@Suite("Sound menu placement")
@MainActor
struct SoundPanelTests {
    @Test("A mouse event keeps its click position in screen coordinates")
    func mouseEvent() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: CGRect(x: 200, y: 300, width: 100, height: 100), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let point = CGPoint(x: 38, y: 61)
        let event = try #require(
            NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0))
        #expect(SoundMenuPlacement.pointer(for: event) == window.convertPoint(toScreen: point))
    }

    @Test("Pointer clicks supply the native menu's opening point on every display")
    func clicks() {
        let size = CGSize(width: 308, height: 240)
        for screen in [CGRect(x: 0, y: 0, width: 1512, height: 950), CGRect(x: -1920, y: 100, width: 1920, height: 1050), CGRect(x: 800, y: -1200, width: 1920, height: 1050)] {
            let anchor = CGRect(x: screen.maxX - 60, y: screen.maxY - 120, width: 32, height: 32)
            for click in [CGPoint(x: anchor.minX + 2, y: anchor.maxY - 3), CGPoint(x: anchor.maxX - 2, y: anchor.minY + 3)] {
                #expect(SoundMenuPlacement.location(for: size, anchor: anchor, visible: screen, pointer: click) == click)
            }
        }
    }

    @Test("Keyboard and accessibility activation do not reuse the pointer")
    func nonPointerActivation() {
        #expect(SoundMenuPlacement.pointer(for: nil) == nil)
        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49)
        #expect(SoundMenuPlacement.pointer(for: event) == nil)
    }

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
