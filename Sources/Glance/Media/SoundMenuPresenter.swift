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

/// The Sound menu's window: AppKit's own container for a menu that points at what opened it, as the
/// Dock's menus point at their icons, under the button that opened it: at once, following a held
/// press, fading as it closes. It takes the keys for its rows and slider without making Glance the
/// app in use, as the Dock's menus never make the Dock the app in use, so the app in front stays in
/// front and its window stays the key one: opening and closing it never makes that window blink
/// between looking in front and behind.
@MainActor
final class SoundPanel: NSObject {
    private weak var soundMenu: SoundOutputMenu?
    let window = SoundPanelWindow()
    let contentView = SoundPanelContent()
    /// The container, its arrow pointing up at the button.
    private let callout = SoundCalloutView()
    private let scroll = NSScrollView()
    private let stack = SoundMenuStack()
    private let maximumHeight: CGFloat
    private var holders: [ObjectIdentifier: SoundRowHolder] = [:]
    private(set) var contentSize = CGSize.zero
    /// The button's rect on the screen, and the screen's visible part, it hangs under.
    private var placement: (anchor: CGRect, visible: CGRect)?
    private var monitors: [Any] = []
    /// Follows the press that opened it, until it's let go.
    private var pressMonitor: Any?
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
        // Rows scrolled under the corners stay inside them, and follow the window as it grows.
        contentView.autoresizingMask = [.width, .height]
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = SoundLook.radius
        contentView.layer?.cornerCurve = .continuous
        contentView.layer?.masksToBounds = true
        callout.addSubview(contentView)
        window.contentView = callout
        window.onCancel = { [weak self] in self?.dismiss() }
        // A click beside the arrow, on the clear strip, is outside the menu.
        window.shows = { [weak self] point in self?.callout.shows(point) ?? true }
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
                let box = SoundMenuPlacement.frame(for: size, below: placement.anchor, in: placement.visible)
                window.setFrame(Self.windowFrame(around: box), display: true, animate: animate)
            } else {
                window.setContentSize(Self.windowFrame(around: CGRect(origin: .zero, size: size)).size)
            }
            callout.frame = CGRect(origin: .zero, size: window.frame.size)
            contentView.frame = CGRect(origin: .zero, size: size)
            scroll.frame = contentView.bounds
            pointArrow()
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
        let box = SoundMenuPlacement.frame(for: contentSize, below: onScreen, in: screen.visibleFrame)
        window.setFrame(Self.windowFrame(around: box), display: false)
        callout.frame = CGRect(origin: .zero, size: window.frame.size)
        pointArrow()
        return true
    }

    /// The window round a box: the box, and above it the arrow's strip.
    static func windowFrame(around box: CGRect) -> CGRect {
        CGRect(x: box.minX, y: box.minY, width: box.width, height: box.height + SoundCalloutView.margin)
    }

    /// The box on the screen, under the arrow's strip.
    private var boxOnScreen: CGRect {
        CGRect(x: window.frame.minX, y: window.frame.minY, width: window.frame.width, height: window.frame.height - SoundCalloutView.margin)
    }

    /// The arrow at the button's middle, wherever the box had to go.
    private func pointArrow() {
        guard let anchor = placement?.anchor else { return }
        callout.point(at: anchor.midX - window.frame.minX)
    }

    func show(from anchor: NSView, pointer: CGPoint?) {
        guard !dismissing, let parent = anchor.window, parent.isVisible, place(from: anchor, pointer: pointer) else { return finishDismissal() }
        previousKey = NSApp.keyWindow
        // All at once, as a menu shows.
        window.alphaValue = 1
        // Key without making Glance the app in use: the panel is non-activating.
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(contentView)
        // Opened by a press still held, it follows the drag, as a menu does.
        if NSEvent.pressedMouseButtons & 1 != 0 { trackPress() }
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
            context.timingFunction = SoundLook.fadeCurve
            window.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated {
                window.orderOut(nil)
                self.finishDismissal()
            }
        }
    }

    /// While the press that opened it is held: dragged onto a row, it lights the row; let go there,
    /// it chooses it. Let go on the button or anywhere in the panel, it stays open, as a menu does
    /// after a click; let go anywhere else once the pointer has moved, it closes.
    private func trackPress() {
        let start = NSEvent.mouseLocation
        var moved = false
        pressMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, !self.dismissing else { return }
                let point = NSEvent.mouseLocation
                if hypot(point.x - start.x, point.y - start.y) > SoundLook.dragSlop { moved = true }
                let row = self.row(at: point)
                if event.type == .leftMouseDragged {
                    if moved { self.soundMenu?.highlight(row?.item) }
                    return
                }
                self.endPress()
                if let item = row?.item {
                    self.soundMenu?.activate(item)
                } else if moved, !self.boxOnScreen.contains(point), self.placement?.anchor.contains(point) != true {
                    self.dismiss()
                }
            }
            return event
        }
    }

    private func endPress() {
        if let pressMonitor { NSEvent.removeMonitor(pressMonitor) }
        pressMonitor = nil
    }

    /// The row a press can choose at this point on the screen, if it's on one in sight.
    func row(at point: CGPoint) -> SoundMenuContentRow? {
        guard window.isVisible, window.frame.contains(point) else { return nil }
        for case let row as SoundMenuContentRow in soundMenu?.items.compactMap(\.view) ?? [] {
            guard row.window === window, !row.isHiddenOrHasHiddenAncestor, let item = row.item, item.isEnabled, item.action != nil else { continue }
            let shown = row.bounds.intersection(row.visibleRect)
            if window.convertToScreen(row.convert(shown, to: nil)).contains(point) { return row }
        }
        return nil
    }

    private func finishDismissal() {
        guard !didFinish else { return }
        didFinish = true
        dismissing = true
        endPress()
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
    /// Whether a point in the window is on what it draws: a click anywhere else closes it.
    var shows: ((CGPoint) -> Bool)?

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
        if [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type), let shows, !shows(event.locationInWindow) {
            onCancel?()
            return
        }
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

/// AppKit's container for a menu that points at what opened it, the Dock's menus' own, drawn by its
/// frame for such menus: glass with an arrow, its corners and arrow AppKit's. The window holds the box
/// and, above it, the strip the arrow stands in; the frame's other margins fall outside it. Cut to the
/// frame's own outline, as a menu's window is, so the strip stays clear beside the arrow and the
/// window's shadow follows the outline. Where AppKit has no such frame, plain glass with the same
/// corners and no arrow.
@MainActor
final class SoundCalloutView: NSView {
    /// The strip above the box the arrow stands in, the room AppKit's frame keeps on each side of its
    /// box: measured, 13 points.
    nonisolated static let margin: CGFloat = 13
    private static let frameClass = NSClassFromString("_NSPopupMenuWindowPopoverFrame") as? NSView.Type
    private static let outlineSelector = NSSelectorFromString("_copyFrameMaskPathInRect:")
    /// Whether AppKit's own container, with its arrow, is in use.
    static var pointsWithArrow: Bool { frameClass?.instancesRespond(to: outlineSelector) == true }

    /// AppKit's frame, or the glass standing in for it.
    let background: NSView
    private let outline = CAShapeLayer()
    private var arrowX: CGFloat = 0

    init() {
        if Self.pointsWithArrow, let frameClass = Self.frameClass {
            background = frameClass.init(frame: .zero)
            // The arrow on the top edge, pointing up at the button.
            background.setValue(NSRectEdge.maxY.rawValue, forKey: "anchorEdge")
        } else {
            let glass = NSGlassEffectView()
            glass.cornerRadius = SoundLook.radius
            background = glass
        }
        super.init(frame: .zero)
        wantsLayer = true
        addSubview(background)
    }
    required init?(coder: NSCoder) { nil }

    /// The box, under the arrow's strip.
    var box: CGRect { CGRect(x: 0, y: 0, width: bounds.width, height: max(0, bounds.height - Self.margin)) }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        reshape()
    }

    override func layout() {
        super.layout()
        reshape()
    }

    /// Points the arrow at this x, in the container's own coordinates.
    func point(at x: CGFloat) {
        arrowX = x
        reshape()
    }

    /// Whether a point, in the container's coordinates, is on what it draws.
    func shows(_ point: CGPoint) -> Bool {
        guard Self.pointsWithArrow, let path = outline.path else { return box.contains(point) }
        return path.contains(point)
    }

    private func reshape() {
        guard Self.pointsWithArrow else {
            background.frame = box
            return
        }
        // The frame keeps its margins on every side; only the top one, the arrow's, is the window's.
        let margin = Self.margin
        background.frame = CGRect(x: -margin, y: -margin, width: bounds.width + margin * 2, height: bounds.height + margin)
        background.setValue(NSValue(point: CGPoint(x: arrowX + margin, y: background.bounds.maxY)), forKey: "anchorPoint")
        typealias Outline = @convention(c) (AnyObject, Selector, CGRect) -> Unmanaged<CGPath>?
        let copy = unsafeBitCast(background.method(for: Self.outlineSelector), to: Outline.self)
        guard let framePath = copy(background, Self.outlineSelector, background.bounds)?.takeRetainedValue() else { return }
        var shift = CGAffineTransform(translationX: -margin, y: -margin)
        let path = framePath.copy(using: &shift) ?? framePath
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        outline.path = path
        outline.frame = bounds
        layer?.mask = outline
        CATransaction.commit()
        background.needsDisplay = true
        window?.invalidateShadow()
    }
}

enum SoundMenuPlacement {
    /// The box's frame, the container's 13 points round it: under the button, as the Dock places its
    /// menus by their icons, the arrow's tip at the button's edge, and centered on the button, so the
    /// arrow is in the box's middle; moved in only to stay on the screen, the arrow still at the button.
    static func frame(for size: CGSize, below anchor: CGRect, in visible: CGRect) -> CGRect {
        // The arrow's strip above the box ends at the button's edge.
        let x = min(max(anchor.midX - size.width / 2, visible.minX), max(visible.minX, visible.maxX - size.width))
        let y = max(visible.minY, anchor.minY - SoundCalloutView.margin - size.height)
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
