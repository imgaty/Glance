//
//  SettingsPreview.swift
//  Glance
//
//  Created by Gaty on 07/10/2026.
//

import AppKit
import Combine
import SwiftUI

/// The notch above the Appearance, Music and Opening pages: live, in the look of the display chosen
/// in Appearance. One for the window, so it carries on between pages, open; on the Opening page it
/// works as the real one does, to try opening and closing it.
@MainActor
final class SettingsPreview: ObservableObject {
    /// The display's own notch, as it is at rest there: made again when the display shown changes,
    /// or the display changes between a notch and a Dynamic Island.
    @Published private(set) var model: NotchModel
    let scrollClock = ScrollClock()
    @Published var display: String {
        didSet { followDisplay() }
    }

    /// Whether it has opened since the window did.
    var revealed = false
    private var revealTask: Task<Void, Never>?

    /// The display with a notch, if there's one; otherwise the main display.
    static var defaultDisplay: String {
        (NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main)?.notchID ?? ""
    }

    init() {
        let display = Self.defaultDisplay
        self.display = display
        model = .picture(of: ScreenTop(NSScreen.with(id: display) ?? NSScreen.main), state: .closed)
    }

    /// The notch is the display's: as large.
    private func followDisplay() {
        let top = self.top
        guard model.closedSize != top.notch else { return }
        model = .picture(of: top, state: model.state)
    }

    /// The top of the display shown, as the pictures of it draw it.
    var top: ScreenTop { ScreenTop(NSScreen.with(id: display) ?? NSScreen.main) }

    /// The first time it shows, the notch opens as it does when the pointer reaches it, on the
    /// notch's own spring; from then on it stays open.
    func reveal() {
        guard !revealed, !interactive else { return }
        revealed = true
        revealTask?.cancel()
        revealTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.3))
            guard let self, !Task.isCancelled, !self.interactive else { return }
            self.model.open()
        }
    }

    // MARK: Working it, as the real notch works (see NotchController)

    private(set) var interactive = false
    /// Opened by the tour's pointer, showing how, it gives no tap.
    var feelsOpening = true
    /// The tour's pointer is showing a click: resting on the notch doesn't open it first.
    var holdsHoverOpening = false
    private var openTask: Task<Void, Never>?
    private var closeTask: Task<Void, Never>?
    private var pressBeganClosed = false

    /// On the Opening page it closes, to be opened; leaving, it opens again and stays open.
    func setInteractive(_ on: Bool, animated: Bool) {
        guard on != interactive else { return }
        interactive = on
        openTask?.cancel()
        closeTask?.cancel()
        closeTask = nil
        var transaction = Transaction(animation: animated ? .spring(response: on ? 0.36 : 0.42, dampingFraction: on ? 0.88 : 1) : nil)
        transaction.disablesAnimations = !animated
        if on {
            revealTask?.cancel()
            withTransaction(transaction) {
                model.state = .closed
                model.pressed = false
            }
        } else {
            revealed = true
            withTransaction(transaction) {
                model.state = .open
                model.pressed = false
                model.proximity = 0
            }
        }
    }

    /// Where the notch is in the preview, for each of its states.
    struct Geometry {
        let rect: (NotchState) -> CGRect
        /// Preview points per screen point.
        let scale: CGFloat
    }

    /// Where the pointer counts as on the notch: a little past the closed notch, or the notch as
    /// it peeks or stands open.
    private func zone(_ g: Geometry) -> CGRect {
        let resting = g.rect(.closed).insetBy(dx: -4 * g.scale, dy: -4 * g.scale)
        return switch model.state {
        case .closed: resting
        case .peek: resting.union(g.rect(.peek))
        case .open: g.rect(.open)
        }
    }

    /// nil when the pointer has left the preview. Over it, the notch answers the pointer as the real
    /// one does; once it leaves, the notch goes back to how it rests here.
    func pointer(at p: CGPoint?, _ g: Geometry) {
        guard let p else { return goHome(g) }
        homeTask?.cancel()
        homeTask = nil
        switch model.state {
        case .closed, .peek:
            if zone(g).contains(p) {
                if model.state == .closed { peek() }
            } else if model.state == .peek {
                settle()
            } else {
                model.approach(1 - g.rect(.closed).distance(to: p) / (60 * g.scale))
            }
        case .open:
            if g.rect(.open).insetBy(dx: -8 * g.scale, dy: -8 * g.scale).contains(p) {
                closeTask?.cancel()
                closeTask = nil
            } else if closeTask == nil {
                // A short grace, so grazing the edge doesn't snap it shut.
                closeTask = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(280))
                    guard !Task.isCancelled else { return }
                    self?.close()
                }
            }
        }
    }

    /// Interactive, it rests closed, to be opened; otherwise open. The pointer gone, a closed notch
    /// settles at once, as on screen; one that rests open opens again a moment later.
    private func goHome(_ g: Geometry) {
        openTask?.cancel()
        switch model.state {
        case .closed, .peek:
            if model.state == .peek { settle() } else { model.approach(0) }
            guard !interactive, homeTask == nil else { return }
            homeTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(0.5))
                guard let self, !Task.isCancelled else { return }
                homeTask = nil
                model.open()
            }
        case .open:
            guard interactive else {
                // It rests open: it stays.
                closeTask?.cancel()
                closeTask = nil
                return
            }
            guard closeTask == nil else { return }
            closeTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(280))
                guard !Task.isCancelled else { return }
                self?.close()
            }
        }
    }

    private var homeTask: Task<Void, Never>?

    /// Pressing the closed notch squeezes it, and letting go opens it (or holding, with a hold time).
    func press(at p: CGPoint, _ g: Geometry) {
        pressBeganClosed = model.state != .open && zone(g).contains(p)
        guard pressBeganClosed else { return }
        model.press(true)
        let opening = Opening.current
        if opening.onClick, opening.clickDelay > 0 { scheduleOpen(after: opening.clickDelay) }
    }

    func release(at p: CGPoint, _ g: Geometry) {
        guard pressBeganClosed else { return }
        pressBeganClosed = false
        model.press(false)
        let opening = Opening.current
        if opening.clickDelay > 0 {
            if model.state != .open { openTask?.cancel() }
        } else if opening.onClick, zone(g).contains(p) {
            open()
        }
    }

    private func peek() {
        model.peek()
        let opening = Opening.current
        if opening.onHover, !holdsHoverOpening { scheduleOpen(after: opening.hoverDelay) }
    }

    /// A press that won't be let go, as the tour's pointer gives way: the notch springs back, and
    /// doesn't open.
    func cancelPress() {
        guard pressBeganClosed else { return }
        pressBeganClosed = false
        openTask?.cancel()
        model.press(false)
    }

    private func settle() {
        openTask?.cancel()
        model.settle(closeness: 0)
    }

    private func scheduleOpen(after delay: Double) {
        openTask?.cancel()
        openTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.open()
        }
    }

    private func open() {
        guard model.state != .open else { return }
        openTask?.cancel()
        closeTask?.cancel()
        closeTask = nil
        model.open()
        if feelsOpening { Opening.tap() }
    }

    private func close() {
        openTask?.cancel()
        closeTask = nil
        model.close()
    }
}

extension NotchModel {
    /// A notch for Settings' pictures: the display's own at rest, playing, and open unless said.
    static func picture(of top: ScreenTop, layout: PlayerLayout = .current, state: NotchState = .open) -> NotchModel {
        let model = NotchModel(closedSize: top.notch, layout: layout, hasCamera: false)
        model.activity = true
        model.state = state
        return model
    }
}

/// Which page of Settings shows. The notches pictured on the others hold still.
@MainActor
@Observable
final class ShownPage {
    var page = SettingsPane.general
}

extension EnvironmentValues {
    @Entry var shownPage: ShownPage? = nil
    /// The page a view is on.
    @Entry var settingsPage: SettingsPane? = nil
}

/// Time for the preview's page to scroll by, that can be paused and carries on where it stopped.
@MainActor
final class ScrollClock {
    private var start = Date.now
    private var pausedAt: Date?

    func time(at date: Date) -> Double { (pausedAt ?? date).timeIntervalSince(start) }

    func pause() {
        if pausedAt == nil { pausedAt = .now }
    }

    func resume() {
        guard let pausedAt else { return }
        start += Date.now.timeIntervalSince(pausedAt)
        self.pausedAt = nil
    }
}

/// The live notch, pinned above the page while the page scrolls, as a group of its own: as wide as
/// the page's groups, as far in from the window's edges, and rounded as they are, on the same
/// background (the page's forms draw none of their own).
struct PreviewHeader: View {
    /// As wide as the page's groups, which the welcome tour's pictures are drawn to the scale of.
    static let width = SettingsWindowController.width - SettingsWindowController.sidebarWidth - 40

    let pane: SettingsPane
    @EnvironmentObject private var preview: SettingsPreview
    @AppStorage(Preferences.sameLook) private var sameLook = false
    @AppStorage(Preferences.musicLayout) private var layout = PlayerLayout.top

    var body: some View {
        ZStack {
            // A new display's look, or the shared one, is drawn afresh: the old one fades out, and
            // the new one in once it has settled.
            NotchPreview(
                model: preview.model, display: preview.display, top: preview.top,
                interactive: pane == .opening, still: !pane.showsPreview
            )
            .environment(\.notchPaused, !pane.showsPreview)
            .id(identity)
            .transition(
                .asymmetric(
                    insertion: .opacity.animation(.easeInOut(duration: 0.3).delay(0.15)),
                    removal: .opacity.animation(.easeInOut(duration: 0.3))))
        }
        .animation(.easeInOut(duration: 0.3), value: identity)
        .frame(height: 200)
        // As the page's groups are rounded.
        .clipShape(RoundedRectangle(cornerRadius: GroupMetrics.radius, style: .continuous))
        .padding([.horizontal, .top], 20)
        // A new layout reshapes the open notch in place, as the real one does; on a page without
        // it, it simply takes it, rather than animating what can't be seen.
        .onChange(of: layout) {
            withAnimation(pane.showsPreview ? .spring(response: 0.5, dampingFraction: 1) : nil) { preview.model.use(layout) }
        }
        // From a page that shows the notch, it closes (or opens) before your eyes; from one without
        // it, it's simply there, as the page wants it. The Tray page shows it open on the tray.
        .onChange(of: pane, initial: true) { old, new in
            let animated = old != new && old.showsPreview && new.showsPreview
            preview.setInteractive(new == .opening, animated: animated)
            let page: NotchPage = new == .tray ? .tray : .player
            withAnimation(animated ? .spring(response: 0.4, dampingFraction: 1) : nil) { preview.model.page = page }
        }
        // Opened the first time it shows.
        .onChange(of: pane.showsPreview, initial: true) { if pane.showsPreview { preview.reveal() } }
    }

    /// What the preview shows: another display, the shared look, or the display's notch made anew.
    private var identity: String {
        "\(sameLook)-\(preview.display)-\(ObjectIdentifier(preview.model).hashValue)"
    }
}
