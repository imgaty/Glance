import AppKit
import SwiftUI

/// Opens Sound at its triggering click, or below the player button for keyboard access.
struct SoundMenuPresenter: NSViewRepresentable {
    @Binding var isPresented: Bool
    var pointer: CGPoint?
    let makeMenu: () -> NSMenu

    final class Anchor: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    @MainActor
    final class Coordinator {
        private var pending: Timer?
        private var menu: NSMenu?
        private var presenting = false
        private var dismissed: () -> Void = {}

        func update(shown: Bool, pointer: CGPoint?, anchor: NSView, makeMenu: @escaping () -> NSMenu, dismissed: @escaping () -> Void) {
            self.dismissed = dismissed
            guard shown else { return cancel() }
            guard !presenting else { return }
            presenting = true
            let work = Timer(timeInterval: 0, repeats: false) { [weak self, weak anchor] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.pending = nil
                    guard let anchor, let window = anchor.window, window.isVisible else {
                        self.finish()
                        return
                    }
                    let activated = !NSApp.isActive
                    NSApp.activate()
                    let menu = makeMenu()
                    menu.appearance = anchor.effectiveAppearance
                    self.menu = menu
                    let frame = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
                    let visible = window.screen?.visibleFrame ?? frame
                    let location = SoundMenuPlacement.location(for: menu.size, anchor: frame, visible: visible, pointer: pointer)
                    defer {
                        self.menu = nil
                        self.finish()
                        if activated, NSApp.isActive,
                            !NSApp.windows.contains(where: { $0.isVisible && !($0 is NSPanel) })
                        {
                            NSApp.deactivate()
                        }
                    }
                    let point = anchor.convert(window.convertPoint(fromScreen: location), from: nil)
                    menu.popUp(positioning: nil, at: point, in: anchor)
                }
            }
            pending = work
            // Menu tracking is synchronous. A run-loop timer leaves the main queue free for
            // device changes, volume read-backs and the rest of the app while the menu is open.
            RunLoop.main.add(work, forMode: .common)
        }

        func cancel() {
            pending?.invalidate()
            pending = nil
            if let menu { menu.cancelTracking() } else { presenting = false }
        }

        private func finish() {
            presenting = false
            dismissed()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> Anchor { Anchor() }
    func updateNSView(_ view: Anchor, context: Context) {
        context.coordinator.update(shown: isPresented, pointer: pointer, anchor: view, makeMenu: makeMenu) { isPresented = false }
    }
    static func dismantleNSView(_ view: Anchor, coordinator: Coordinator) { coordinator.cancel() }
}

enum SoundMenuPlacement {
    /// NSMenu positions its content's top corner at this point and handles screen-edge fitting.
    static func location(for size: CGSize, anchor: CGRect, visible: CGRect, pointer: CGPoint? = nil) -> CGPoint {
        // Let AppKit fit a pointer-opened menu to the screen, just as it does for other native menus.
        if let pointer { return pointer }
        let x = min(max(anchor.midX - size.width / 2, visible.minX), max(visible.minX, visible.maxX - size.width))
        return CGPoint(x: x, y: anchor.minY - 6)
    }

    static func pointer(for event: NSEvent?) -> CGPoint? {
        guard let event, [.leftMouseDown, .leftMouseUp].contains(event.type), let window = event.window else { return nil }
        return window.convertPoint(toScreen: event.locationInWindow)
    }
}
