import AppKit
import CoreImage
import SwiftUI

/// An independent glass dropdown opened from the Sound button.
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
            let pointer = NSApp.currentEvent.flatMap { event -> CGPoint? in
                guard [.leftMouseDown, .leftMouseUp].contains(event.type), event.window === anchor.window else { return nil }
                return event.window?.convertPoint(toScreen: event.locationInWindow)
            }
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
        context.coordinator.update(shown: isPresented, anchor: view, makeMenu: makeMenu) { isPresented = false }
    }
    static func dismantleNSView(_ view: Anchor, coordinator: Coordinator) { coordinator.cancel() }
}

/// AppKit renders the glass and window transitions; Glance owns placement and the corner radius.
@MainActor
final class SoundPopover: NSObject {
    private weak var soundMenu: SoundOutputMenu?
    let panel = SoundPopoverPanel()
    let contentView = SoundPopoverContent()
    private let scroll = NSScrollView()
    private let stack = SoundMenuStack()
    private let maximumHeight: CGFloat
    private var holders: [ObjectIdentifier: SoundRowHolder] = [:]
    private(set) var contentSize = CGSize.zero
    private var position: SoundMenuPlacement.Position?
    private var anchor = CGRect.zero
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    private var workspaceObserver: NSObjectProtocol?
    private var previousApp: NSRunningApplication?
    private weak var previousKey: NSWindow?
    private var dismissing = false
    var onDismiss: (() -> Void)?

    init(menu: SoundOutputMenu, maximumHeight: CGFloat) {
        soundMenu = menu
        self.maximumHeight = maximumHeight
        super.init()
        panel.contentView = contentView
        panel.onDismiss = { [weak self] in self?.dismiss() }
        panel.handleKey = { [weak self] in self?.soundMenu?.handleKey($0) == true }
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.autohidesScrollers = true
        scroll.autoresizingMask = [.width, .height]
        scroll.documentView = stack
        contentView.contentView = scroll
        contentView.setAccessibilityLabel(String(localized: "Sound"))
        panel.setAccessibilityLabel(String(localized: "Sound"))
        reload()
    }

    /// Preserve rows by identity, moving existing rows while new ones reveal in the space opening.
    /// A hidden content window can exercise this transition without presenting the dropdown.
    func reload(animated: Bool? = nil) {
        guard let menu = soundMenu, !dismissing else { return }
        let animate = (animated ?? panel.isVisible) && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let views = menu.items.compactMap(\.view)
        let rowsHeight = views.reduce(CGFloat.zero) { $0 + $1.frame.height }
        let height = ceil(rowsHeight + SoundLook.edge * 2)
        var next: [ObjectIdentifier: SoundRowHolder] = [:]
        var inserted: [SoundRowHolder] = []
        var moves: [(SoundRowHolder, CGRect)] = []
        // Put any half-point window rounding above the rows, preserving the footer's exact inset.
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
        let resized = contentSize != size
        contentSize = size
        for holder in inserted { holder.reveal(animated: animate) }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animate ? SoundRowHolder.duration : 0
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            if resized {
                if let position {
                    let frame = position.frame(for: size)
                    if animate { panel.animator().setFrame(frame, display: true) } else { panel.setFrame(frame, display: panel.isVisible) }
                } else {
                    contentView.setFrameSize(size)
                    scroll.frame = contentView.bounds
                }
            }
            for (holder, frame) in moves {
                if animate { holder.animator().frame = frame } else { holder.frame = frame }
            }
            for holder in removed {
                holder.isRemoving = true
                if animate { holder.animator().alphaValue = 0 } else { holder.alphaValue = 0 }
            }
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                removed.forEach { $0.removeFromSuperview() }
                self?.panel.invalidateShadow()
            }
        }
    }

    func show(from view: NSView, pointer: CGPoint?) {
        guard !dismissing, let parent = view.window, parent.isVisible,
            let screen = SoundMenuPlacement.screen(for: pointer, fallback: parent.screen)
        else { return dismiss() }
        anchor = parent.convertToScreen(view.convert(view.bounds, to: nil))
        panel.appearance = view.effectiveAppearance
        place(
            at: SoundMenuPlacement.position(
                content: contentSize, anchor: anchor, visible: screen.visibleFrame, pointer: pointer,
                mirrored: NSApp.userInterfaceLayoutDirection == .rightToLeft))
        previousKey = NSApp.keyWindow
        if !NSApp.isActive {
            previousApp = NSWorkspace.shared.frontmostApplication
            NSApp.activate()
        }
        panel.animationBehavior = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? .none : .utilityWindow
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(contentView)
        watchDismissal(parent: parent)
    }

    func place(at position: SoundMenuPlacement.Position) {
        self.position = position
        panel.setFrame(position.frame(for: contentSize), display: false)
        contentView.layoutSubtreeIfNeeded()
    }

    private func watchDismissal(parent: NSWindow) {
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let monitor = NSEvent.addGlobalMonitorForEvents(
            matching: clicks,
            handler: { [weak self] _ in
                MainActor.assumeIsolated { self?.dismiss() }
            })
        {
            monitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(
            matching: clicks,
            handler: { [weak self] event in
                guard let self, event.window !== self.panel else { return event }
                let point = event.window?.convertPoint(toScreen: event.locationInWindow)
                self.dismiss()
                // A second click on Sound closes it without reopening it from the same event.
                return point.map(self.anchor.contains) == true ? nil : event
            })
        {
            monitors.append(monitor)
        }
        for (name, object) in [
            (NSWindow.willCloseNotification, parent as AnyObject), (NSApplication.didResignActiveNotification, NSApp as AnyObject),
            (NSApplication.didChangeScreenParametersNotification, NSApp as AnyObject),
        ] {
            observers.append(
                NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.dismiss() }
                })
        }
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }
    }

    func dismiss() {
        guard !dismissing else { return }
        dismissing = true
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        if let workspaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver) }
        workspaceObserver = nil
        let restoreFocus = panel.isKeyWindow
        panel.onDismiss = nil
        panel.handleKey = nil
        panel.ignoresMouseEvents = true
        panel.animationBehavior = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? .none : .utilityWindow
        panel.orderOut(nil)
        if restoreFocus, let previousKey, previousKey.isVisible, previousKey.canBecomeKey { previousKey.makeKey() }
        if NSApp.isActive, let previousApp, !previousApp.isTerminated { previousApp.activate(options: []) }
        previousApp = nil
        let callback = onDismiss
        onDismiss = nil
        callback?()
    }
}

final class SoundPopoverContent: NSGlassEffectView {
    override var acceptsFirstResponder: Bool { true }

    override init(frame: CGRect) {
        super.init(frame: frame)
        style = .regular
        cornerRadius = SoundLook.outerRadius
    }
    required init?(coder: NSCoder) { nil }
}

final class SoundPopoverPanel: NSPanel {
    var onDismiss: (() -> Void)?
    var handleKey: ((NSEvent) -> Bool)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isMovable = false
    }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    override func cancelOperation(_ sender: Any?) { onDismiss?() }
    override func resignKey() {
        super.resignKey()
        if isVisible { onDismiss?() }
    }
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, handleKey?(event) == true { return }
        super.sendEvent(event)
    }
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
    static let gap: CGFloat = 6

    struct Position {
        let x: CGFloat
        let edgeY: CGFloat
        let below: Bool
        let visible: CGRect

        /// Keep the opening edge fixed as devices arrive; constrain only at a display edge.
        func frame(for content: CGSize) -> CGRect {
            let size = CGSize(width: min(content.width, visible.width), height: min(content.height, visible.height))
            let y = below ? edgeY - size.height : edgeY
            return CGRect(
                x: min(max(x, visible.minX), visible.maxX - size.width),
                y: min(max(y, visible.minY), visible.maxY - size.height), width: size.width, height: size.height)
        }
    }

    static func position(content: CGSize, anchor: CGRect, visible: CGRect, pointer: CGPoint?, mirrored: Bool = false) -> Position {
        let lower = (pointer?.y ?? anchor.minY) - gap
        let upper = (pointer?.y ?? anchor.maxY) + gap
        let belowRoom = lower - visible.minY
        let aboveRoom = visible.maxY - upper
        let below = belowRoom >= content.height || belowRoom >= aboveRoom
        let x = pointer.map { $0.x - (mirrored ? content.width : 0) } ?? (anchor.midX - content.width / 2)
        return Position(x: x, edgeY: below ? lower : upper, below: below, visible: visible)
    }

    @MainActor static func screen(for pointer: CGPoint?, fallback: NSScreen?) -> NSScreen? {
        pointer.flatMap { point in NSScreen.screens.first { $0.frame.contains(point) } } ?? fallback
    }
}
