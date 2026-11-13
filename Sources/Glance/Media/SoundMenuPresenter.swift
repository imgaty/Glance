import AppKit
import SwiftUI

/// A glass popover with a stable anchor beneath its button.
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

/// One glass shape owns the body and arrow, so the four outer corners share one radius.
/// A nonactivating panel gives the controls focus without bringing the app to the front.
@MainActor
final class SoundPopover: NSObject {
    private weak var soundMenu: SoundOutputMenu?
    private let panel = SoundPopoverPanel()
    let contentView = NSView()
    private let surface = NSView()
    private let glass = NSHostingView(rootView: SoundPopoverGlass())
    private let scroll = NSScrollView()
    private let stack = SoundMenuStack()
    private let maximumHeight: CGFloat
    private var holders: [NSView] = []
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private weak var previousKey: NSWindow?
    private var anchor = CGRect.zero
    private var positioning = CGRect.zero
    private var visibleFrame = CGRect.zero
    private var dismissing = false
    var onDismiss: (() -> Void)?

    init(menu: SoundOutputMenu, maximumHeight: CGFloat) {
        soundMenu = menu
        self.maximumHeight = maximumHeight
        super.init()
        panel.contentView = surface
        panel.onDismiss = { [weak self] in self?.dismiss() }
        panel.handleKey = { [weak self] in self?.soundMenu?.handleKey($0) == true }
        surface.addSubview(glass)
        surface.addSubview(contentView)
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.autohidesScrollers = true
        scroll.autoresizingMask = [.width, .height]
        scroll.documentView = stack
        contentView.addSubview(scroll)
        contentView.setAccessibilityLabel(String(localized: "Sound"))
        panel.setAccessibilityLabel(String(localized: "Sound"))
        reload()
    }

    /// Holders preserve item origins; retaining them keeps the native slider alive during updates.
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
        contentView.setFrameSize(CGSize(width: SoundLook.width, height: min(height, maximumHeight)))
        scroll.frame = contentView.bounds
        scroll.hasVerticalScroller = height > contentView.frame.height
        stack.frame = NSRect(x: 0, y: 0, width: SoundLook.width, height: height)
        if !visibleFrame.isEmpty { place() }
    }

    func show(from view: NSView, pointer: CGPoint?) {
        guard let window = view.window, let screen = window.screen else { return dismiss() }
        anchor = window.convertToScreen(view.convert(view.bounds, to: nil))
        // Player buttons reserve their whole height, keeping the arrow below the hit area.
        // Calls supply a screen point because their output button has no AppKit anchor view.
        positioning =
            view is SoundMenuPresenter.Anchor
            ? anchor
            : pointer.map { CGRect(x: $0.x - 0.5, y: $0.y - 0.5, width: 1, height: 1) } ?? anchor
        visibleFrame = screen.visibleFrame
        panel.appearance = view.effectiveAppearance
        place()
        surface.layoutSubtreeIfNeeded()
        previousKey = NSApp.keyWindow
        panel.animationBehavior = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? .none : .utilityWindow
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(nil)
        watchDismissal(parent: window)
    }

    private func place() {
        let layout = SoundMenuPlacement.layout(content: contentView.frame.size, anchor: positioning, visible: visibleFrame)
        let room = SoundMenuPlacement.shadowRoom
        panel.setFrame(layout.frame.insetBy(dx: -room, dy: -room), display: panel.isVisible)
        surface.frame = CGRect(origin: .zero, size: panel.frame.size)
        glass.frame = CGRect(origin: CGPoint(x: room, y: room), size: layout.frame.size)
        glass.rootView = SoundPopoverGlass(arrowX: layout.arrowX, below: layout.below)
        contentView.setFrameOrigin(CGPoint(x: room, y: room + (layout.below ? 0 : SoundMenuPlacement.arrowHeight)))
        panel.bodyFrame = contentView.frame
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
                // A second click on Sound closes it, without reopening it from the same event.
                return point.map(self.anchor.contains) == true ? nil : event
            })
        {
            monitors.append(monitor)
        }
        observers.append(
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: parent, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.dismiss() }
            })
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            workspaceObservers.append(
                NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.dismiss() }
                })
        }
    }

    func dismiss() {
        guard !dismissing else { return }
        dismissing = true
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        workspaceObservers = []
        let restoreFocus = panel.isKeyWindow
        panel.onDismiss = nil
        panel.handleKey = nil
        panel.ignoresMouseEvents = true
        panel.animationBehavior = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? .none : .utilityWindow
        panel.orderOut(nil)
        if restoreFocus, let previousKey, previousKey.isVisible, previousKey.canBecomeKey { previousKey.makeKey() }
        let callback = onDismiss
        onDismiss = nil
        callback?()
    }
}

private final class SoundPopoverPanel: NSPanel {
    var onDismiss: (() -> Void)?
    var handleKey: ((NSEvent) -> Bool)?
    var bodyFrame = CGRect.zero
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false  // The glass shape supplies its own shadow.
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
        if [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type), !bodyFrame.contains(event.locationInWindow) {
            onDismiss?()
            return
        }
        if event.type == .keyDown, handleKey?(event) == true { return }
        super.sendEvent(event)
    }
}

private struct SoundPopoverGlass: View {
    var arrowX: CGFloat = SoundLook.width / 2
    var below = true
    var body: some View {
        Color.clear
            .glassEffect(.regular, in: SoundPopoverShape(arrowX: arrowX, below: below))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The arrow joins the body before glass is applied: no overlapping bubbles or second outline.
struct SoundPopoverShape: Shape {
    var arrowX: CGFloat
    var below: Bool

    func path(in rect: CGRect) -> Path {
        let height = SoundMenuPlacement.arrowHeight
        let body = CGRect(x: rect.minX, y: rect.minY + height, width: rect.width, height: rect.height - height)
        let x = rect.minX + arrowX
        let y = rect.minY + height
        var arrow = Path()
        arrow.move(to: CGPoint(x: x - 20, y: y + 1))
        arrow.addLine(to: CGPoint(x: x - 20, y: y))
        arrow.addCurve(to: CGPoint(x: x - 8.75, y: y - 3), control1: CGPoint(x: x - 13, y: y), control2: CGPoint(x: x - 11, y: y))
        arrow.addLine(to: CGPoint(x: x - 5, y: rect.minY + 3))
        arrow.addCurve(to: CGPoint(x: x + 5, y: rect.minY + 3), control1: CGPoint(x: x - 2, y: rect.minY - 1), control2: CGPoint(x: x + 2, y: rect.minY - 1))
        arrow.addLine(to: CGPoint(x: x + 8.75, y: y - 3))
        arrow.addCurve(to: CGPoint(x: x + 20, y: y), control1: CGPoint(x: x + 11, y: y), control2: CGPoint(x: x + 13, y: y))
        arrow.addLine(to: CGPoint(x: x + 20, y: y + 1))
        arrow.closeSubpath()
        let path = RoundedRectangle(cornerRadius: SoundLook.radius, style: .continuous).path(in: body).union(arrow)
        return below ? path : path.applying(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: rect.minY + rect.maxY))
    }
}

private final class SoundMenuStack: NSView {
    override var isFlipped: Bool { true }
}

enum SoundMenuPlacement {
    static let gap: CGFloat = 4
    static let arrowHeight: CGFloat = 11
    static let shadowRoom: CGFloat = 20

    struct Layout {
        let frame: CGRect
        let arrowX: CGFloat
        let below: Bool
    }

    /// Keep the arrow below the button and the entire body on the triggering display.
    static func layout(content: CGSize, anchor: CGRect, visible: CGRect) -> Layout {
        let size = CGSize(width: content.width, height: content.height + arrowHeight)
        let belowRoom = anchor.minY - gap - visible.minY
        let aboveRoom = visible.maxY - anchor.maxY - gap
        let below = belowRoom >= size.height || belowRoom >= aboveRoom
        let x = min(max(anchor.midX - size.width / 2, visible.minX), visible.maxX - size.width)
        let preferredY = below ? anchor.minY - gap - size.height : anchor.maxY + gap
        let y = min(max(preferredY, visible.minY), visible.maxY - size.height)
        let shoulder = SoundLook.radius + 20
        return Layout(
            frame: CGRect(origin: CGPoint(x: x, y: y), size: size),
            arrowX: min(max(anchor.midX - x, shoulder), size.width - shoulder), below: below)
    }
}
