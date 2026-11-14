import AppKit
import SwiftUI

/// A system popover opened from the Sound button.
struct SoundMenuPresenter: NSViewRepresentable {
    @Binding var isPresented: Bool
    let makeMenu: () -> SoundOutputMenu
    /// Calls keep the dropdown under its button for every input method.
    var followsPointer = true

    final class Anchor: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    @MainActor
    final class Coordinator {
        private var pending: Task<Void, Never>?
        private var menu: SoundOutputMenu?
        private var dismissed: () -> Void = {}

        func update(shown: Bool, anchor: NSView, makeMenu: @escaping () -> SoundOutputMenu, followsPointer: Bool = true, dismissed: @escaping () -> Void) {
            self.dismissed = dismissed
            guard shown else { return cancel() }
            guard menu == nil, pending == nil else { return }
            let pointer: CGPoint? =
                followsPointer
                ? NSApp.currentEvent.flatMap { event -> CGPoint? in
                    guard [.leftMouseDown, .leftMouseUp].contains(event.type), event.window === anchor.window else { return nil }
                    return event.window?.convertPoint(toScreen: event.locationInWindow)
                } : nil
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
                menu.present(from: anchor, pointer: pointer) { [weak self] in
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
        context.coordinator.update(shown: isPresented, anchor: view, makeMenu: makeMenu, followsPointer: followsPointer) { isPresented = false }
    }
    static func dismantleNSView(_ view: Anchor, coordinator: Coordinator) { coordinator.cancel() }
}

/// AppKit supplies the popover's glass, arrow, corners, placement and window animations.
@MainActor
final class SoundPopover: NSObject, NSPopoverDelegate {
    private weak var soundMenu: SoundOutputMenu?
    let popover = NSPopover()
    let contentView = SoundPopoverContent()
    private let scroll = NSScrollView()
    private let stack = SoundMenuStack()
    private let maximumHeight: CGFloat
    private var holders: [ObjectIdentifier: SoundRowHolder] = [:]
    private(set) var contentSize = CGSize.zero
    private var keys: Any?
    private var observers: [NSObjectProtocol] = []
    private var workspaceObserver: NSObjectProtocol?
    private var previousApp: NSRunningApplication?
    private weak var previousKey: NSWindow?
    private var dismissing = false
    private var didFinish = false
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
        contentView.onCancel = { [weak self] in self?.dismiss() }
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.autohidesScrollers = true
        scroll.autoresizingMask = [.width, .height]
        scroll.documentView = stack
        contentView.addSubview(scroll)
        contentView.setAccessibilityLabel(String(localized: "Sound"))
        reload()
    }

    /// Preserve row identity, including a volume edit, while AppKit resizes the popover.
    func reload(animated: Bool? = nil) {
        guard let menu = soundMenu, !dismissing else { return }
        let animate = (animated ?? popover.isShown) && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let views = menu.items.compactMap(\.view)
        let rowsHeight = views.reduce(CGFloat.zero) { $0 + $1.frame.height }
        let height = ceil(rowsHeight + SoundLook.edge * 2)
        var next: [ObjectIdentifier: SoundRowHolder] = [:]
        var inserted: [SoundRowHolder] = []
        var moves: [(SoundRowHolder, CGRect)] = []
        // Put any half-point rounding above the rows, preserving the footer's exact inset.
        var top = height - SoundLook.edge - rowsHeight
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
        let size = CGSize(width: SoundLook.width, height: ceil(min(height, maximumHeight)))
        scroll.hasVerticalScroller = height > size.height
        stack.setFrameSize(CGSize(width: SoundLook.width, height: height))
        if contentSize != size {
            contentSize = size
            popover.animates = animate
            // The system owns the shown window's frame, including during live device changes.
            if !popover.isShown {
                contentView.setFrameSize(size)
                scroll.frame = contentView.bounds
            }
            popover.contentSize = size
        }
        NSAnimationContext.runAnimationGroup { context in
            if !animate { context.duration = 0 }
            for holder in inserted {
                if animate { holder.animator().alphaValue = 1 } else { holder.alphaValue = 1 }
            }
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
        guard !dismissing, let parent = anchor.window, parent.isVisible else { return finishDismissal() }
        popover.appearance = anchor.effectiveAppearance
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        previousKey = NSApp.keyWindow
        // A system popover needs the active app for immediate keyboard and slider focus.
        if !NSApp.isActive {
            previousApp = NSWorkspace.shared.frontmostApplication
            NSApp.activate()
        }
        popover.show(
            relativeTo: SoundMenuPlacement.anchorRect(in: anchor, pointer: pointer), of: anchor,
            preferredEdge: SoundMenuPlacement.below(anchor))
        guard popover.isShown else { return finishDismissal() }
        takeFocus()
        keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, !self.dismissing, event.window === self.contentView.window else { return event }
            return self.soundMenu?.handleKey(event) == true ? nil : event
        }
        // Outside clicks and the positioning window's lifetime belong to NSPopover.
        // Explicitly dismiss on desktop changes so it cannot follow a hidden activity.
        observers.append(
            NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: NSApp, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.dismiss() }
            })
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }
    }

    private func takeFocus() {
        guard !dismissing else { return }
        contentView.window?.makeKey()
        contentView.window?.makeFirstResponder(contentView)
    }

    func dismiss() {
        guard !dismissing else { return }
        dismissing = true
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if popover.isShown { popover.close() } else { finishDismissal() }
    }

    func popoverDidShow(_ notification: Notification) { takeFocus() }
    func popoverShouldDetach(_ popover: NSPopover) -> Bool { false }
    func popoverWillClose(_ notification: Notification) { dismissing = true }
    func popoverDidClose(_ notification: Notification) { finishDismissal() }

    private func finishDismissal() {
        guard !didFinish else { return }
        didFinish = true
        dismissing = true
        if let keys { NSEvent.removeMonitor(keys) }
        keys = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        if let workspaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver) }
        workspaceObserver = nil
        contentView.onCancel = nil
        if NSApp.isActive {
            if NSApp.keyWindow == nil, let previousKey, previousKey.isVisible, previousKey.canBecomeKey { previousKey.makeKey() }
            // A deliberate click in another Glance window keeps that window in front.
            if NSApp.keyWindow == nil || NSApp.keyWindow === previousKey,
                let previousApp, !previousApp.isTerminated
            {
                previousApp.activate(options: [])
            }
        }
        previousKey = nil
        previousApp = nil
        let callback = onDismiss
        onDismiss = nil
        callback?()
    }
}

final class SoundPopoverContent: NSView {
    var onCancel: (() -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

final class SoundRowHolder: NSView {
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
}

private final class SoundMenuStack: NSView {
    override var isFlipped: Bool { true }
}

enum SoundMenuPlacement {
    /// Button-based entry points use their whole bounds, so different click locations cannot
    /// move the popover. Only the legacy window-level entry point needs a click-sized anchor.
    @MainActor static func anchorRect(in view: NSView, pointer: CGPoint?) -> CGRect {
        guard !(view is SoundMenuPresenter.Anchor), let pointer, let window = view.window else { return view.bounds }
        let local = view.convert(window.convertPoint(fromScreen: pointer), from: nil)
        return CGRect(x: local.x - 0.5, y: local.y - 0.5, width: 1, height: 1)
    }

    @MainActor static func below(_ view: NSView) -> NSRectEdge { view.isFlipped ? .maxY : .minY }

    @MainActor static func screen(for pointer: CGPoint?, fallback: NSScreen?) -> NSScreen? {
        pointer.flatMap { point in NSScreen.screens.first { $0.frame.contains(point) } } ?? fallback
    }
}
