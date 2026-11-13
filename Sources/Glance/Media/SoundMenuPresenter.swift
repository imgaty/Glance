import AppKit
import CoreImage
import SwiftUI

/// The system popover, anchored to the whole Sound button.
struct SoundMenuPresenter: NSViewRepresentable {
    @Binding var isPresented: Bool
    let makeMenu: () -> SoundOutputMenu

    final class Anchor: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    @MainActor
    final class Coordinator {
        private var pending: Task<Void, Never>?
        private var menu: SoundOutputMenu?
        private var dismissed: () -> Void = {}

        func update(shown: Bool, anchor: NSView, makeMenu: @escaping () -> SoundOutputMenu, dismissed: @escaping () -> Void) {
            self.dismissed = dismissed
            guard shown else { return cancel() }
            guard menu == nil, pending == nil else { return }
            pending = Task { @MainActor [weak self, weak anchor] in
                await Task.yield()
                guard !Task.isCancelled, let self else { return }
                self.pending = nil
                guard let anchor, anchor.window?.isVisible == true else {
                    self.dismissed()
                    return
                }
                let menu = makeMenu()
                self.menu = menu
                menu.present(from: anchor, pointer: nil) { [weak self] in
                    self?.menu = nil
                    self?.dismissed()
                }
            }
        }

        func cancel() {
            pending?.cancel()
            pending = nil
            menu?.dismiss()
            menu = nil
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> Anchor { Anchor() }
    func updateNSView(_ view: Anchor, context: Context) {
        context.coordinator.update(shown: isPresented, anchor: view, makeMenu: makeMenu) { isPresented = false }
    }
    static func dismantleNSView(_ view: Anchor, coordinator: Coordinator) { coordinator.cancel() }
}

/// AppKit supplies the complete popover: glass, arrow, corners, shadow and window animations.
@MainActor
final class SoundPopover: NSObject, NSPopoverDelegate {
    private weak var soundMenu: SoundOutputMenu?
    let popover = NSPopover()
    let contentView = SoundPopoverContent()
    private let scroll = NSScrollView()
    private let stack = SoundMenuStack()
    private let maximumHeight: CGFloat
    private var holders: [ObjectIdentifier: SoundRowHolder] = [:]
    private var targetSize = CGSize.zero
    private var keys: Any?
    private var previousApp: NSRunningApplication?
    var onDismiss: (() -> Void)?

    init(menu: SoundOutputMenu, maximumHeight: CGFloat) {
        soundMenu = menu
        self.maximumHeight = maximumHeight
        super.init()
        popover.behavior = .transient
        popover.delegate = self
        let controller = NSViewController()
        controller.title = String(localized: "Sound")
        controller.view = contentView
        popover.contentViewController = controller
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.autohidesScrollers = true
        scroll.autoresizingMask = [.width, .height]
        scroll.documentView = stack
        contentView.addSubview(scroll)
        contentView.setAccessibilityLabel(String(localized: "Sound"))
        reload()
    }

    /// Preserve rows by identity, moving existing rows while new ones reveal in the space opening.
    /// A hidden content window can exercise this transition without presenting a popover.
    func reload(animated: Bool? = nil) {
        guard let menu = soundMenu else { return }
        let animate = (animated ?? popover.isShown) && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let views = menu.items.compactMap(\.view)
        var next: [ObjectIdentifier: SoundRowHolder] = [:]
        var inserted: [SoundRowHolder] = []
        var moves: [(SoundRowHolder, CGRect)] = []
        var top = SoundLook.edge
        for view in views {
            let id = ObjectIdentifier(view)
            let frame = CGRect(x: 0, y: top, width: SoundLook.width, height: view.frame.height)
            let holder: SoundRowHolder
            if let existing = holders[id] {
                holder = existing
            } else {
                holder = SoundRowHolder(row: view, frame: frame)
                holder.alphaValue = animate ? 0 : 1
                stack.addSubview(holder)
                inserted.append(holder)
            }
            if holder.targetFrame != frame { moves.append((holder, frame)) }
            holder.targetFrame = frame
            next[id] = holder
            top += frame.height
        }
        let removed = holders.filter { next[$0.key] == nil }.map(\.value)
        holders = next
        let height = top + SoundLook.edge
        let size = CGSize(width: SoundLook.width, height: min(height, maximumHeight))
        scroll.hasVerticalScroller = height > size.height
        stack.setFrameSize(CGSize(width: SoundLook.width, height: height))
        if targetSize != size {
            targetSize = size
            popover.animates = animate
            // Setting the root view's frame while shown bypasses NSPopover's resize animation.
            // Only contentSize changes while shown; AppKit resizes the content view itself.
            if !popover.isShown {
                contentView.setFrameSize(size)
                scroll.frame = contentView.bounds
            }
            popover.contentSize = size
        }
        for holder in inserted { holder.reveal(animated: animate) }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animate ? SoundRowHolder.duration : 0
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            for (holder, frame) in moves {
                if animate { holder.animator().frame = frame } else { holder.frame = frame }
            }
            for holder in removed {
                holder.isRemoving = true
                if animate { holder.animator().alphaValue = 0 } else { holder.alphaValue = 0 }
            }
        } completionHandler: {
            MainActor.assumeIsolated { removed.forEach { $0.removeFromSuperview() } }
        }
    }

    func show(from anchor: NSView, pointer: CGPoint?) {
        guard anchor.window?.isVisible == true else { return didClose() }
        popover.appearance = anchor.effectiveAppearance
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        // A real popover needs an active app for keyboard focus, unlike the notch's panel.
        if !NSApp.isActive {
            previousApp = NSWorkspace.shared.frontmostApplication
            NSApp.activate()
        }
        popover.show(relativeTo: SoundMenuPlacement.anchorRect(in: anchor, pointer: pointer), of: anchor, preferredEdge: SoundMenuPlacement.below(anchor))
        guard popover.isShown else { return didClose() }
        takeFocus()
        keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.contentView.window else { return event }
            return self.soundMenu?.handleKey(event) == true ? nil : event
        }
    }

    private func takeFocus() {
        contentView.window?.makeKey()
        contentView.window?.makeFirstResponder(contentView)
    }

    func dismiss() {
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if popover.isShown { popover.performClose(nil) } else { didClose() }
    }

    func popoverDidShow(_ notification: Notification) {
        takeFocus()
    }

    func popoverShouldDetach(_ popover: NSPopover) -> Bool { false }
    func popoverDidClose(_ notification: Notification) { didClose() }

    private func didClose() {
        if let keys { NSEvent.removeMonitor(keys) }
        keys = nil
        if NSApp.isActive, let previousApp, !previousApp.isTerminated {
            previousApp.activate(options: [])
        }
        previousApp = nil
        let callback = onDismiss
        onDismiss = nil
        callback?()
    }
}

final class SoundPopoverContent: NSView {
    override var acceptsFirstResponder: Bool { true }
}

/// The blur affects only an inserted row, never the popover glass or the live volume slider.
final class SoundRowHolder: NSView {
    static let duration: TimeInterval = 0.35
    var targetFrame: CGRect
    var isRemoving = false

    init(row: NSView, frame: CGRect) {
        targetFrame = frame
        super.init(frame: frame)
        wantsLayer = true
        addSubview(row)
        row.setFrameOrigin(.zero)
    }
    required init?(coder: NSCoder) { nil }
    override func hitTest(_ point: NSPoint) -> NSView? { isRemoving ? nil : super.hitTest(point) }

    func reveal(animated: Bool) {
        guard animated, let layer else {
            alphaValue = 1
            return
        }
        alphaValue = 0
        let blur = CIFilter(name: "CIGaussianBlur")!
        blur.name = "soundReveal"
        blur.setValue(0, forKey: kCIInputRadiusKey)
        layer.filters = [blur]
        let animation = CABasicAnimation(keyPath: "filters.soundReveal.inputRadius")
        animation.fromValue = 6
        animation.toValue = 0
        animation.duration = Self.duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(animation, forKey: "soundReveal")
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().alphaValue = 1
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.layer?.filters = nil }
        }
    }
}

private final class SoundMenuStack: NSView {
    override var isFlipped: Bool { true }
}

enum SoundMenuPlacement {
    /// The player's full button bounds keep the arrow in one place. Calls supply a screen point.
    @MainActor static func anchorRect(in view: NSView, pointer: CGPoint?) -> CGRect {
        guard !(view is SoundMenuPresenter.Anchor), let pointer, let window = view.window else { return view.bounds }
        let local = view.convert(window.convertPoint(fromScreen: pointer), from: nil)
        return CGRect(x: local.x - 0.5, y: local.y - 0.5, width: 1, height: 1)
    }

    @MainActor static func below(_ view: NSView) -> NSRectEdge { view.isFlipped ? .maxY : .minY }
}
