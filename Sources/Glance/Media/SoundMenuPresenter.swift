import AppKit
import SwiftUI

/// The Sound menu, opened from the Sound button (see `SoundPanel`).
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
                menu.present(from: anchor, pointer: pointer) { [weak self, weak menu] in
                    // One closed here and still fading out says nothing about a newer one open.
                    guard let self, let menu, self.menu === menu else { return }
                    self.menu = nil
                    self.dismissed()
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

/// The Sound menu's window: a glass panel under the button that opened it, as Control Center opens
/// its Sound menu from the menu bar. It takes the keys for its rows and slider without making Glance
/// the app in use, so the app in front stays in front and its window stays the key one: opening and
/// closing it never makes that window blink between looking in front and behind.
@MainActor
final class SoundPanel: NSObject {
    private weak var soundMenu: SoundOutputMenu?
    let window = SoundPanelWindow()
    let contentView = SoundPanelContent()
    private let glass = NSGlassEffectView()
    private let scroll = NSScrollView()
    private let stack = SoundMenuStack()
    private let maximumHeight: CGFloat
    private var holders: [ObjectIdentifier: SoundRowHolder] = [:]
    private(set) var contentSize = CGSize.zero
    /// The button's rect on the screen, and the screen's visible part, it hangs under.
    private var placement: (anchor: CGRect, visible: CGRect)?
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    /// Glance's own window that had the keys before (the notch, say), given them back.
    private weak var previousKey: NSWindow?
    private var dismissing = false
    private var didFinish = false
    var onDismiss: (() -> Void)?

    init(menu: SoundOutputMenu, maximumHeight: CGFloat) {
        soundMenu = menu
        self.maximumHeight = maximumHeight
        super.init()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.autohidesScrollers = true
        scroll.autoresizingMask = [.width, .height]
        scroll.documentView = stack
        contentView.addSubview(scroll)
        contentView.onCancel = { [weak self] in self?.dismiss() }
        contentView.setAccessibilityRole(.group)
        contentView.setAccessibilityLabel(String(localized: "Sound"))
        glass.cornerRadius = SoundLook.radius
        glass.contentView = contentView
        window.contentView = glass
        window.onCancel = { [weak self] in self?.dismiss() }
        window.onKey = { [weak self] event in
            guard let self, !self.dismissing else { return false }
            return self.soundMenu?.handleKey(event) == true
        }
        window.setAccessibilityTitle(String(localized: "Sound"))
        reload()
    }

    /// Preserve row identity, including a volume edit, while the panel grows or shrinks from its top.
    func reload(animated: Bool? = nil) {
        guard let menu = soundMenu, !dismissing else { return }
        let animate = (animated ?? window.isVisible) && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
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
            if let placement, window.isVisible {
                window.setFrame(SoundMenuPlacement.frame(for: size, below: placement.anchor, in: placement.visible), display: true, animate: animate)
            } else {
                window.setContentSize(size)
            }
            glass.frame = CGRect(origin: .zero, size: size)
            contentView.frame = glass.bounds
            scroll.frame = contentView.bounds
            window.invalidateShadow()
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

    /// Places the panel under the button, above the notch's own window, without showing it.
    func place(from anchor: NSView, pointer: CGPoint?) -> Bool {
        guard let parent = anchor.window, let screen = parent.screen ?? NSScreen.main else { return false }
        window.appearance = anchor.effectiveAppearance
        let rect = SoundMenuPlacement.anchorRect(in: anchor, pointer: pointer)
        let onScreen = parent.convertToScreen(anchor.convert(rect, to: nil))
        placement = (onScreen, screen.visibleFrame)
        window.level = NSWindow.Level(rawValue: max(parent.level.rawValue, NSWindow.Level.popUpMenu.rawValue) + 1)
        window.setFrame(SoundMenuPlacement.frame(for: contentSize, below: onScreen, in: screen.visibleFrame), display: false)
        return true
    }

    func show(from anchor: NSView, pointer: CGPoint?) {
        guard !dismissing, let parent = anchor.window, parent.isVisible, place(from: anchor, pointer: pointer) else { return finishDismissal() }
        previousKey = NSApp.keyWindow
        let fades = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        window.alphaValue = fades ? 0 : 1
        // Key without making Glance the app in use: the panel is non-activating.
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(contentView)
        if fades {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = SoundLook.fade
                window.animator().alphaValue = 1
            }
        }
        NSAccessibility.post(element: contentView, notification: .layoutChanged, userInfo: [.uiElements: [contentView]])
        let anchorRect = placement?.anchor
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        monitors = [
            // Anywhere outside Glance, as a menu closes.
            NSEvent.addGlobalMonitorForEvents(matching: clicks) { [weak self] _ in
                MainActor.assumeIsolated { self?.dismiss() }
            },
            // In Glance, anywhere but the panel and the button, which closes it itself.
            NSEvent.addLocalMonitorForEvents(matching: clicks) { [weak self, weak parent] event in
                MainActor.assumeIsolated {
                    guard let self, event.window !== self.window else { return }
                    if let anchorRect, event.window === parent, let window = event.window,
                        anchorRect.contains(window.convertPoint(toScreen: event.locationInWindow))
                    {
                        return
                    }
                    self.dismiss()
                }
                return event
            },
        ].compactMap { $0 }
        // It can't follow the notch onto another Space or display.
        observers.append(
            NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: NSApp, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.dismiss() }
            })
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            workspaceObservers.append(
                workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.dismiss() }
                })
        }
    }

    func dismiss() {
        guard !dismissing else { return }
        dismissing = true
        guard window.isVisible else { return finishDismissal() }
        // Fading, it lets clicks through to what's under it.
        window.ignoresMouseEvents = true
        let window = window
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : SoundLook.fade
            window.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated {
                window.orderOut(nil)
                self.finishDismissal()
            }
        }
    }

    private func finishDismissal() {
        guard !didFinish else { return }
        didFinish = true
        dismissing = true
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        workspaceObservers = []
        contentView.onCancel = nil
        window.onCancel = nil
        window.onKey = nil
        if window.isVisible { window.orderOut(nil) }
        // The keys go back to Glance's own window that had them; another app's never left it.
        if let previousKey, previousKey !== window, previousKey.isVisible, previousKey.canBecomeKey, NSApp.keyWindow == nil || NSApp.keyWindow === window {
            previousKey.makeKey()
        }
        previousKey = nil
        let callback = onDismiss
        onDismiss = nil
        callback?()
    }
}

/// Takes the keys without making Glance the app in use, and draws as a window in front, so the
/// slider and the playing output keep the accent color.
final class SoundPanelWindow: NSPanel {
    var onCancel: (() -> Void)?
    /// A key pressed, before anything in the menu sees it: whether the menu took it.
    var onKey: ((NSEvent) -> Bool)?

    init() {
        super.init(contentRect: CGRect(x: 0, y: 0, width: SoundLook.width, height: 100), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = false
        collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onCancel?() }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, onKey?(event) == true { return }
        super.sendEvent(event)
    }

    /// Private AppKit hooks, as the menu bar menu's: drawn as a window in front, so the slider has
    /// its color and the glass isn't the flat look of a window behind.
    @objc func _hasActiveAppearance() -> Bool { true }
    @objc func _hasActiveAppearanceIgnoringKeyFocus() -> Bool { true }
}

final class SoundPanelContent: NSView {
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
    /// The panel's frame: its top the gap under the button, centered on it, kept on the screen.
    static func frame(for size: CGSize, below anchor: CGRect, in visible: CGRect) -> CGRect {
        let x = min(max(anchor.midX - size.width / 2, visible.minX), max(visible.minX, visible.maxX - size.width))
        let y = max(visible.minY, anchor.minY - SoundLook.below - size.height)
        return CGRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height)
    }

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
