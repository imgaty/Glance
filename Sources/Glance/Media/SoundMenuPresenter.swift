import AppKit
import SwiftUI

/// Opens Sound beneath its button, with the same gap for pointer and keyboard activation.
struct SoundMenuPresenter: NSViewRepresentable {
    @Binding var isPresented: Bool
    var alignTrailing = true
    let makeMenu: () -> SoundOutputMenu

    final class Anchor: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    @MainActor
    final class Coordinator {
        private var pending: Task<Void, Never>?
        private var menu: SoundOutputMenu?
        private var dismissed: () -> Void = {}

        func update(shown: Bool, anchor: NSView, alignTrailing: Bool, makeMenu: @escaping () -> SoundOutputMenu, dismissed: @escaping () -> Void) {
            self.dismissed = dismissed
            guard shown else { return cancel() }
            guard menu == nil, pending == nil else { return }
            pending = Task { @MainActor [weak self, weak anchor] in
                await Task.yield()
                guard !Task.isCancelled, let self else { return }
                self.pending = nil
                guard let anchor, let window = anchor.window, window.isVisible, let screen = window.screen else {
                    self.dismissed()
                    return
                }
                let menu = makeMenu()
                self.menu = menu
                let frame = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
                menu.present(below: frame, on: screen, appearance: anchor.effectiveAppearance, alignTrailing: alignTrailing) { [weak self] in
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
        context.coordinator.update(shown: isPresented, anchor: view, alignTrailing: alignTrailing, makeMenu: makeMenu) { isPresented = false }
    }
    static func dismantleNSView(_ view: Anchor, coordinator: Coordinator) { coordinator.cancel() }
}

/// A single glass outline, with no native-menu window imposing a second corner curve.
@MainActor
final class SoundMenuPanel: NSPanel {
    private weak var soundMenu: SoundOutputMenu?
    private let anchor: CGRect
    private let visibleFrame: CGRect
    private let alignTrailing: Bool
    private let glass = NSGlassEffectView()
    private let surface = NSView()
    private let scroll = NSScrollView()
    private let stack = SoundMenuStack()
    private var holders: [NSView] = []
    private var monitors: [Any] = []
    private weak var previousKey: NSWindow?
    var onDismiss: (() -> Void)?
    private var dismissing = false

    override var canBecomeKey: Bool { !dismissing }
    override var canBecomeMain: Bool { false }

    init(menu: SoundOutputMenu, anchor: CGRect, visible: CGRect, appearance: NSAppearance, alignTrailing: Bool = true) {
        self.soundMenu = menu
        self.anchor = anchor
        self.visibleFrame = visible
        self.alignTrailing = alignTrailing
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        // Glass supplies its own shadow; a window shadow also traces its clear surround.
        hasShadow = false
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        animationBehavior = .none
        isMovable = false
        self.appearance = appearance
        glass.cornerRadius = SoundLook.radius
        glass.style = .regular
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.autohidesScrollers = true
        scroll.documentView = stack
        glass.contentView = scroll
        surface.addSubview(glass)
        contentView = surface
        setAccessibilityLabel(String(localized: "Sound"))
        reload()
    }

    /// Every item has its own holder because NSMenuItem keeps its view's origin at zero.
    /// Existing holders survive device updates, so a live slider drag keeps the same control.
    func reload() {
        guard let menu = soundMenu else { return }
        let views = menu.items.compactMap(\.view)
        if holders.map({ $0.subviews.first }) != views.map(Optional.some) {
            holders.forEach { $0.removeFromSuperview() }
            holders = views.map { view in
                let holder = NSView(frame: NSRect(x: 0, y: 0, width: SoundLook.width, height: view.frame.height))
                holder.addSubview(view)
                stack.addSubview(holder)
                return holder
            }
        }
        var top = SoundLook.edge
        for (view, holder) in zip(views, holders) {
            let height = view.frame.height
            holder.frame = NSRect(x: 0, y: top, width: SoundLook.width, height: height)
            view.setFrameOrigin(.zero)
            top += height
        }
        let height = top + SoundLook.edge
        let size = CGSize(width: SoundLook.width, height: min(height, visibleFrame.height))
        let origin = SoundMenuPlacement.location(for: size, anchor: anchor, visible: visibleFrame, alignTrailing: alignTrailing)
        let room: CGFloat = 20
        setFrame(SoundMenuPlacement.frame(for: size, at: origin).insetBy(dx: -room, dy: -room), display: isVisible)
        surface.frame = NSRect(origin: .zero, size: frame.size)
        glass.frame = NSRect(x: room, y: room, width: size.width, height: size.height)
        scroll.frame = glass.bounds
        scroll.hasVerticalScroller = height > size.height
        stack.frame = NSRect(x: 0, y: 0, width: SoundLook.width, height: height)
        invalidateShadow()
    }

    func show() {
        previousKey = NSApp.keyWindow
        alphaValue = 0
        makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.12
            animator().alphaValue = 1
        }
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(
            matching: clicks,
            handler: { [weak self] _ in
                MainActor.assumeIsolated { self?.dismiss() }
            })
        {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(
            matching: clicks,
            handler: { [weak self] event in
                guard let self, event.window !== self else { return event }
                let point = event.window?.convertPoint(toScreen: event.locationInWindow)
                self.dismiss()
                // Pressing the same button closes Sound instead of immediately opening it again.
                return point.map(self.anchor.contains) == true ? nil : event
            })
        {
            monitors.append(local)
        }
    }

    func dismiss() {
        guard !dismissing else { return }
        dismissing = true
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        ignoresMouseEvents = true
        orderOut(nil)
        if let previousKey, previousKey.isVisible { previousKey.makeKey() }
        let callback = onDismiss
        onDismiss = nil
        callback?()
    }

    override func cancelOperation(_ sender: Any?) { dismiss() }
    // Placement already uses the triggering display's visible frame, including negative origins.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    override func resignKey() {
        super.resignKey()
        if isVisible { dismiss() }
    }
    override func sendEvent(_ event: NSEvent) {
        if [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type), !glass.frame.contains(event.locationInWindow) {
            dismiss()
            return
        }
        if event.type == .keyDown, soundMenu?.handleKey(event) == true { return }
        super.sendEvent(event)
    }

    // Match the app's other nonactivating glass panels, including behind-wallpaper renders.
    @objc func _hasActiveAppearance() -> Bool { true }
    @objc func _hasActiveAppearanceIgnoringKeyFocus() -> Bool { true }
}

private final class SoundMenuStack: NSView {
    override var isFlipped: Bool { true }
}

enum SoundMenuPlacement {
    static let gap: CGFloat = 6

    /// Aligned with the triggering button, confined to that display's usable area. The pointer
    /// is deliberately not an anchor: moving within a button must not move the panel.
    static func location(for size: CGSize, anchor: CGRect, visible: CGRect, alignTrailing: Bool = true) -> CGPoint {
        let preferredLeft = alignTrailing ? anchor.maxX - size.width : anchor.minX
        let left = min(max(preferredLeft, visible.minX), max(visible.minX, visible.maxX - size.width))
        let top = max(min(anchor.minY - gap, visible.maxY), min(visible.maxY, visible.minY + size.height))
        return CGPoint(x: left, y: top)
    }

    static func frame(for size: CGSize, at location: CGPoint) -> CGRect {
        CGRect(x: location.x, y: location.y - size.height, width: size.width, height: size.height)
    }
}
