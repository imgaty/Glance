import AppKit
import SwiftUI

/// Opens the AppKit Sound menu below the actual player button, on that button's display.
struct SoundMenuPresenter: NSViewRepresentable {
    @Binding var isPresented: Bool
    let makeMenu: () -> NSMenu

    final class Anchor: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    @MainActor
    final class Coordinator {
        private var pending: DispatchWorkItem?
        private var menu: NSMenu?
        private var presenting = false
        private var dismissed: () -> Void = {}

        func update(shown: Bool, anchor: NSView, makeMenu: @escaping () -> NSMenu, dismissed: @escaping () -> Void) {
            self.dismissed = dismissed
            guard shown else { return cancel() }
            guard !presenting else { return }
            presenting = true
            let work = DispatchWorkItem { [weak self, weak anchor] in
                guard let self, let anchor, let window = anchor.window, window.isVisible else {
                    self?.finish()
                    return
                }
                self.pending = nil
                let activated = !NSApp.isActive
                NSApp.activate()
                let menu = makeMenu()
                menu.appearance = anchor.effectiveAppearance
                self.menu = menu
                let frame = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
                let visible = window.screen?.visibleFrame ?? frame
                let location = SoundMenuPlacement.location(for: menu.size, anchor: frame, visible: visible)
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
            pending = work
            DispatchQueue.main.async(execute: work)
        }

        func cancel() {
            pending?.cancel()
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
        context.coordinator.update(shown: isPresented, anchor: view, makeMenu: makeMenu) { isPresented = false }
    }
    static func dismantleNSView(_ view: Anchor, coordinator: Coordinator) { coordinator.cancel() }
}

enum SoundMenuPlacement {
    /// NSMenu positions its content's top corner at this point and handles screen-edge fitting.
    static func location(for size: CGSize, anchor: CGRect, visible: CGRect) -> CGPoint {
        let x = min(max(anchor.midX - size.width / 2, visible.minX), max(visible.minX, visible.maxX - size.width))
        return CGPoint(x: x, y: anchor.minY - 6)
    }
}
