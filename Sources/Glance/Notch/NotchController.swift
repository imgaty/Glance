//
//  NotchController.swift
//  Glance
//
//  Created by Gaty on 07/10/2026.
//

import AppKit
import Combine
import SwiftUI

private enum Layout {
    static let virtualNotchWidth: CGFloat = 185
    /// An island's length, and its tallest, the iPhone's.
    static let islandWidth: CGFloat = 126
    static let islandMaxHeight: CGFloat = 32
    /// How far away (pt) the closed notch starts to notice the pointer.
    static let proximityRange: CGFloat = 60
    /// Room around the open notch for its glass edge and rubber-band stretch.
    static let windowPadding = CGSize(width: 60, height: 90)
    /// How far the window reaches past the top of the screen, with nothing drawn there: a window
    /// that ends right at the top edge misses a click with the pointer pushed against it.
    static let pastTop: CGFloat = 2
}

/// What a display without a notch shows: a notch, like the built-in display's, or a Dynamic Island,
/// floating just below the top of the screen.
enum NotchStyle: String, CaseIterable, Identifiable {
    case notch, island

    var id: Self { self }
    var title: String { self == .notch ? "Notch" : "Dynamic Island" }

    static func of(_ screen: NSScreen) -> NotchStyle {
        NotchStyle(rawValue: UserDefaults.standard.string(forKey: Preferences.key(Preferences.notchStyle, for: screen.notchID)) ?? "") ?? .notch
    }

    /// Every display's, so a change can be noticed.
    static var signature: String {
        NSScreen.screens.map { of($0).rawValue }.joined(separator: ",")
    }
}

/// How the notch opens, read fresh each time so changes in Settings apply at once.
struct Opening {
    let onHover: Bool
    let onClick: Bool
    /// How long the pointer rests on the notch before it opens.
    let hoverDelay: Double
    /// How long a click must be held to open it; zero opens on a plain click.
    let clickDelay: Double
    let haptics: Bool

    static var current: Opening {
        let defaults = UserDefaults.standard
        let trigger = OpenTrigger(rawValue: defaults.string(forKey: Preferences.openTrigger) ?? "") ?? .both
        return Opening(
            onHover: trigger != .click, onClick: trigger != .hover,
            hoverDelay: defaults.double(forKey: Preferences.hoverDelay),
            clickDelay: defaults.double(forKey: Preferences.clickDelay),
            haptics: defaults.bool(forKey: Preferences.haptics))
    }

    /// A tap on the trackpad, if haptic feedback is on.
    static func tap() {
        guard current.haptics else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
}

/// One notch on one display: owns its window and decides when to peek, open and close.
@MainActor
final class NotchController {
    var onContextMenu: ((NSEvent, NSView) -> Void)?

    private let screen: NSScreen
    private let model: NotchModel
    private let nowPlaying: NowPlaying
    private let panel: NotchPanel
    private let eventView = NotchEventView()
    private let centerX: CGFloat
    private let topY: CGFloat

    private var openTask: Task<Void, Never>?
    private var closeTask: Task<Void, Never>?
    private var pollTimer: Timer?
    /// After an explicit close, stay shut until the pointer leaves the notch.
    private var holdUntilExit = false
    private var pull: CGFloat = 0
    private var pullFired = false
    private var playingWatch: AnyCancellable?
    private var activityTask: Task<Void, Never>?
    private var titleWatch: AnyCancellable?
    private var settingsWatch: AnyCancellable?
    private var songWatch: AnyCancellable?
    private var popTask: Task<Void, Never>?
    /// Songs reported in the first moments are what was already playing, not new ones.
    private let createdAt = Date.now
    /// A trackpad gesture's direction, settled by its first movement.
    private var scrollAxis: Axis?
    private var swipe: CGFloat = 0
    /// Whether the current click began on a closed notch, so letting go opens rather than closes it.
    private var pressBeganClosed = false
    /// A menu opened from inside the open notch, like the sound output's, is up: the pointer is on
    /// the menu, outside the notch, but the notch stays open under it until it's gone.
    private var menuHold = false
    /// Opened from the keyboard: it stays open with the pointer elsewhere, until the shortcut comes
    /// again, a click lands outside it, or the pointer visits it and leaves.
    private var keyboardHold = false
    private var menuWatches: [AnyCancellable] = []
    private var pasteWatch: AnyCancellable?
    /// Something for the tray is being dragged in the top half of this display: the notch is open on
    /// the tray to take it, wherever the pointer is.
    private var dragHold = false
    /// A sideways swipe on the tray was let go and the row glides on.
    private var trayGliding = false
    private var glideCheck: Task<Void, Never>?

    /// A full-screen app covers this display and the user chose to hide the notch then. Like the
    /// menu bar there, it stays out of sight until the pointer reaches the top edge, slides down
    /// with it, and slides away again once the pointer leaves it and the menu bar.
    var fullScreen = false {
        didSet {
            guard fullScreen != oldValue else { return }
            if fullScreen { tuck() } else { untuck() }
        }
    }

    /// Slid up out of sight, while full screen.
    private var tucked = false
    private var revealTask: Task<Void, Never>?
    /// Where the panel sits when shown.
    private let restingOrigin: CGPoint

    var screenFrame: CGRect { screen.frame }

    /// The notch at rest on a display: the camera housing's own size where there is one; otherwise a
    /// notch as tall as the menu bar, or a Dynamic Island, as chosen for the display.
    struct Resting {
        let size: CGSize
        let centerX: CGFloat
        let island: Bool
        let camera: Bool
        /// The menu bar's height on that display.
        let menuBar: CGFloat
    }

    static func resting(on screen: NSScreen) -> Resting {
        let frame = screen.frame
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea, screen.safeAreaInsets.top > 0 {
            let size = CGSize(width: right.minX - left.maxX, height: screen.safeAreaInsets.top)
            return Resting(size: size, centerX: left.maxX + size.width / 2, island: false, camera: true, menuBar: size.height)
        }
        let menuBar = frame.maxY - screen.visibleFrame.maxY
        let barHeight = (20...44).contains(menuBar) ? menuBar : 24
        // A Dynamic Island, if chosen for this display: a pill as long as the iPhone's, inside the menu
        // bar, so it never hangs over the windows below it.
        let island = NotchStyle.of(screen) == .island
        let islandHeight = min(Layout.islandMaxHeight, barHeight - NotchModel.islandGap * 2)
        return Resting(
            size: island
                ? CGSize(width: Layout.islandWidth, height: islandHeight)
                : CGSize(width: Layout.virtualNotchWidth, height: barHeight),
            centerX: frame.midX, island: island, camera: false, menuBar: barHeight)
    }

    /// Returns nil for a display without a notch unless `allowVirtual` is set.
    init?(screen: NSScreen, allowVirtual: Bool, nowPlaying: NowPlaying) {
        let frame = screen.frame
        let resting = Self.resting(on: screen)
        guard resting.camera || allowVirtual else { return nil }
        let closedSize = resting.size
        centerX = resting.centerX
        self.screen = screen
        self.nowPlaying = nowPlaying
        topY = frame.maxY
        // Open, the player fills the notch; its artwork sits up beside the camera.
        model = NotchModel(closedSize: closedSize, layout: PlayerLayout.current, hasCamera: resting.camera, island: resting.island)

        // Room for the largest layout with the lyrics open, so switching layouts never resizes it.
        let largest = PlayerLayout.allCases.map { $0.size(closed: closedSize) }
        let size = CGSize(
            width: largest.map(\.width).max()! + model.lyricsWidth + Layout.windowPadding.width * 2,
            height: largest.map(\.height).max()! + Layout.windowPadding.height)
        panel = NotchPanel(
            frame: CGRect(
                x: centerX - size.width / 2, y: topY - size.height,
                width: size.width, height: size.height + Layout.pastTop))
        restingOrigin = panel.frame.origin

        let host = NotchHostingView(rootView: NotchView(model: model, display: screen.notchID).environmentObject(nowPlaying))
        host.sizingOptions = []
        eventView.frame = CGRect(origin: .zero, size: panel.frame.size)
        // The notch is drawn from the top of the screen; the window's strip above it is empty.
        host.frame = CGRect(x: 0, y: Layout.pastTop, width: size.width, height: size.height)
        host.autoresizingMask = [.width, .height]
        eventView.addSubview(host)
        panel.contentView = eventView

        eventView.onMouseDown = { [weak self] in self?.press() }
        eventView.onMouseUp = { [weak self] in self?.release() }
        eventView.onScroll = { [weak self] event in self?.scrolled(event) }
        eventView.onMouseMoved = { [weak self] in self?.pointerMoved(to: NSEvent.mouseLocation) }
        eventView.passesThrough = { [weak self] point in
            guard let model = self?.model, model.state == .open else { return false }
            // In the notch's own points, which start below the strip past the top.
            let inNotch = CGPoint(x: point.x, y: point.y - Layout.pastTop)
            return model.controlFrames.contains { $0.contains(inNotch) }
        }
        eventView.onRightMouseDown = { [weak self] event in
            guard let self else { return }
            onContextMenu?(event, eventView)
        }
        eventView.registerForDraggedTypes(
            [.fileURL, .URL, .string, .png, .tiff, .rtf, .html] + NSFilePromiseReceiver.readableDraggedTypes.map { .init($0) })
        eventView.onDragEntered = { [weak self] pasteboard in self?.dragEntered(pasteboard) ?? [] }
        eventView.onDragExited = { [weak self] in self?.dragExited() }
        eventView.onDrop = { [weak self] pasteboard in self?.dropped(pasteboard) ?? false }
        // Pasted from the tray: its work is done, so it closes, as Spotlight does.
        pasteWatch = NotificationCenter.default.publisher(for: Tray.didPaste).sink { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.model.state == .open else { return }
                self.close(holdUntilExit: true)
            }
        }

        // The live activity and the song announcements follow their settings as they change.
        playingWatch = nowPlaying.$isPlaying.removeDuplicates().sink { [weak self] playing in
            MainActor.assumeIsolated { self?.showActivity(playing) }
        }
        titleWatch = nowPlaying.$title.removeDuplicates().sink { [weak self] _ in
            MainActor.assumeIsolated { self?.announceTrack() }
        }
        songWatch = nowPlaying.$isSong.removeDuplicates().sink { [weak self] isSong in
            MainActor.assumeIsolated {
                withAnimation(.spring(response: 0.5, dampingFraction: 1)) { self?.model.songPlaying = isSong }
            }
        }
        menuWatches = [
            NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification).sink { [weak self] _ in
                MainActor.assumeIsolated { self?.menuOpened() }
            },
            NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification).sink { [weak self] _ in
                MainActor.assumeIsolated { self?.menuClosed() }
            },
        ]
        settingsWatch = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .map { _ in UserDefaults.standard.bool(forKey: Preferences.liveActivity) }
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.showActivity(self.nowPlaying.isPlaying, immediately: true)
                }
            }
    }

    /// Brought on screen: softly, or, as the notch is turned on, out of where it went when it was
    /// turned off.
    func show(expanding: Bool) {
        expanding ? expand() : fadeIn()
    }

    /// Taken off screen: softly, or, as the notch is turned off, into the camera housing on a display
    /// that has one, up into the top edge on one that doesn't, or, an island, into a dot that shrinks
    /// away.
    func tearDown(collapsing: Bool = false) {
        activityTask?.cancel()
        popTask?.cancel()
        openTask?.cancel()
        closeTask?.cancel()
        stopPolling()
        collapsing ? collapse() : fadeOut()
    }

    private func collapse() {
        // This controller is let go of as it's replaced; the model and the panel carry the motion.
        let model = model, panel = panel
        withAnimation(.spring(response: 0.35, dampingFraction: 1)) {
            model.state = .closed
            model.activity = false
            model.pop = false
            model.proximity = 0
            model.pressed = false
            model.stretch = 0
        }
        Task { @MainActor in
            if model.island {
                try? await Task.sleep(for: .seconds(0.3))
                withAnimation(.spring(response: 0.3, dampingFraction: 1)) { model.squeeze = 1 }
                try? await Task.sleep(for: .seconds(0.22))
                withAnimation(.easeIn(duration: 0.22)) { model.vanish = 1 }
                try? await Task.sleep(for: .seconds(0.24))
            } else if !model.hasCamera {
                try? await Task.sleep(for: .seconds(0.3))
                withAnimation(.easeIn(duration: 0.24)) { model.vanish = 1 }
                try? await Task.sleep(for: .seconds(0.26))
            } else {
                // Closed and without its wings it's the camera housing itself.
                try? await Task.sleep(for: .seconds(0.45))
            }
            panel.orderOut(nil)
        }
    }

    /// The way it went, backwards: an island's dot grows and stretches into the island, a notch on a
    /// display without one unfolds down from the top edge, and then, as when music starts, the
    /// wings come out.
    private func expand() {
        // Drawn first as it was left: no wings, and an island as a dot too small to see.
        activityTask?.cancel()
        model.activity = false
        if model.island {
            model.squeeze = 1
            model.vanish = 1
        } else if !model.hasCamera {
            model.vanish = 1
        }
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        let model = model
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(60))
            if model.island {
                withAnimation(.easeOut(duration: 0.24)) { model.vanish = 0 }
                try? await Task.sleep(for: .seconds(0.24))
                withAnimation(.spring(response: 0.3, dampingFraction: 1)) { model.squeeze = 0 }
                try? await Task.sleep(for: .seconds(0.24))
            } else if !model.hasCamera {
                withAnimation(.easeOut(duration: 0.26)) { model.vanish = 0 }
                try? await Task.sleep(for: .seconds(0.28))
            }
            guard let self else { return }
            self.showActivity(self.nowPlaying.isPlaying, immediately: true)
        }
    }

    /// The notch comes and goes softly: when it's made or removed (a change in Settings rebuilds it)
    /// and around full-screen apps.
    private func fadeIn() {
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            panel.animator().alphaValue = 1
        }
    }

    /// For good: once faded, it's taken off screen whatever its fade in was still doing, so a notch
    /// rebuilt just after it was made never stays behind the new one.
    private func fadeOut() {
        let panel = panel
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            panel.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated { panel.orderOut(nil) }
        }
    }

    /// The closed notch's live activity follows playback. A pause waits a couple of seconds before
    /// it folds away, as on the iPhone, so skipping between tracks doesn't make it blink.
    private func showActivity(_ playing: Bool, immediately: Bool = false) {
        activityTask?.cancel()
        let shown = playing && UserDefaults.standard.bool(forKey: Preferences.liveActivity)
        activityTask = Task { [weak self] in
            guard !Task.isCancelled else { return }
            // A pause folds it away after a moment; turning it off in Settings, at once.
            if !shown, !immediately {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
            }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                self?.model.activity = shown
                if !shown { self?.model.pop = false }
            }
        }
    }

    /// Switches to the layout chosen in Settings, in place: the notch reshapes and the player's
    /// pieces move to their new places.
    func relayout() {
        guard PlayerLayout.current != model.layout else { return }
        withAnimation(.spring(response: 0.5, dampingFraction: 1)) { model.use(PlayerLayout.current) }
    }

    /// A new song: the closed notch's wings widen for a few seconds to show its title and artist.
    private func announceTrack() {
        let defaults = UserDefaults.standard
        guard Date.now.timeIntervalSince(createdAt) > 2, defaults.bool(forKey: Preferences.liveActivity),
            defaults.bool(forKey: Preferences.musicTrackPop)
        else { return }
        popTask?.cancel()
        popTask = Task { [weak self] in
            // The title is announced before it's set, and the rest of the report follows it.
            try? await Task.sleep(for: .milliseconds(250))
            guard let model = self?.model, let nowPlaying = self?.nowPlaying, !Task.isCancelled,
                nowPlaying.isPlaying, nowPlaying.hasMedia, model.state == .closed
            else { return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                model.popWing = LiveActivityView.popWing(
                    title: nowPlaying.title, artist: nowPlaying.artist,
                    restingHeight: model.closedSize.height, island: model.island)
                model.activity = true
                model.pop = true
            }
            try? await Task.sleep(for: .seconds(3.5))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { model.pop = false }
        }
    }

    // MARK: Full screen

    /// In full screen, the notch follows the menu bar. Returns true while it's tucked away, when
    /// the pointer has nothing else to do with it.
    private func followMenuBar(_ p: CGPoint) -> Bool {
        let frame = screen.frame
        let onDisplay = p.x >= frame.minX && p.x <= frame.maxX && p.y >= frame.minY && p.y <= frame.maxY + 1
        if tucked {
            // Pushing the pointer against the top edge brings it down, as it does the menu bar.
            if onDisplay, p.y >= frame.maxY - 2 {
                if revealTask == nil {
                    revealTask = Task { [weak self] in
                        try? await Task.sleep(for: .milliseconds(120))
                        guard let self, !Task.isCancelled else { return }
                        revealTask = nil
                        untuck()
                    }
                }
            } else {
                revealTask?.cancel()
                revealTask = nil
            }
            if !panel.ignoresMouseEvents { panel.ignoresMouseEvents = true }
            return true
        }
        // Shown: it goes once the pointer is below the menu bar and off the notch, unless open.
        let inMenuBar = onDisplay && p.y >= frame.maxY - slideDistance
        if model.state == .closed, !inMenuBar, !interactiveZone.contains(p) {
            tuck()
            return true
        }
        return false
    }

    private func tuck() {
        guard !tucked else { return }
        tucked = true
        revealTask?.cancel()
        revealTask = nil
        close(holdUntilExit: false)
        panel.ignoresMouseEvents = true
        let panel = panel, raised = raisedFrame
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(raised, display: true)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated { if self?.tucked == true { panel.orderOut(nil) } }
        }
    }

    private func untuck() {
        guard tucked else { return }
        tucked = false
        revealTask?.cancel()
        revealTask = nil
        panel.setFrame(raisedFrame, display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        let panel = panel, resting = CGRect(origin: restingOrigin, size: panel.frame.size)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(resting, display: true)
            panel.animator().alphaValue = 1
        }
    }

    /// As far as the menu bar slides, and as tall as its band.
    private var slideDistance: CGFloat { max(model.closedSize.height, 24) + 6 }

    /// Out of sight above the top of the screen.
    private var raisedFrame: CGRect {
        CGRect(origin: CGPoint(x: restingOrigin.x, y: restingOrigin.y + slideDistance), size: panel.frame.size)
    }

    // MARK: Pointer

    func pointerMoved(to p: CGPoint) {
        if fullScreen, followMenuBar(p) { return }
        switch model.state {
        case .closed, .peek:
            if interactiveZone.contains(p) {
                if model.state == .closed, !holdUntilExit { peek() }
            } else {
                holdUntilExit = false
                if model.state == .peek { settle(at: p) } else { model.approach(closeness(to: p)) }
            }
        case .open:
            // Once the pointer has been on it, it closes as usual when the pointer leaves.
            if openZone.contains(p) { keyboardHold = false }
            if menuHold || keyboardHold || dragHold || openZone.contains(p) {
                closeTask?.cancel()
                closeTask = nil
            } else if closeTask == nil {
                scheduleClose()
            }
        }
        // Only swallow clicks while the pointer is actually on the notch.
        if !model.pressed {
            let capture = interactiveZone.contains(p)
            if panel.ignoresMouseEvents == capture { panel.ignoresMouseEvents = !capture }
        }
    }

    func clicked(outsideAt p: CGPoint) {
        if model.state == .open, !openZone.contains(p) { close(holdUntilExit: false) }
    }

    /// Pressing the closed notch squeezes it, and letting go opens it. The open notch ignores
    /// clicks outside its controls: it closes when the pointer leaves or with a swipe up.
    private func press() {
        pressBeganClosed = model.state != .open
        guard pressBeganClosed else { return }
        model.press(true)
        let opening = Opening.current
        // With a hold delay, the notch opens while the button is still down.
        if opening.onClick, opening.clickDelay > 0 {
            scheduleOpen(after: opening.clickDelay)
        }
    }

    private func release() {
        guard pressBeganClosed else { return }
        model.press(false)
        let opening = Opening.current
        if opening.clickDelay > 0 {
            // Let go before a hold delay ran out: no open.
            if model.state != .open { openTask?.cancel() }
        } else if opening.onClick, interactiveZone.contains(NSEvent.mouseLocation) {
            open()
        }
    }

    // MARK: Transitions

    private func peek() {
        model.peek()
        startPolling()
        let opening = Opening.current
        // With the button held, something's being dragged: a window, which shouldn't open the
        // notch, or something for the tray, which opens it as it comes over (see `dragEntered`).
        if opening.onHover, NSEvent.pressedMouseButtons & 1 == 0 { scheduleOpen(after: opening.hoverDelay) }
    }

    private func scheduleOpen(after delay: Double) {
        openTask?.cancel()
        openTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.open()
        }
    }

    private func settle(at p: CGPoint) {
        openTask?.cancel()
        model.settle(closeness: closeness(to: p))
        stopPolling()
    }

    /// Opens on the player, unless told otherwise.
    private func open(on page: NotchPage = .player) {
        guard model.state != .open else { return }
        openTask?.cancel()
        closeTask?.cancel()
        closeTask = nil
        popTask?.cancel()
        // Closed, nothing of either page shows: the page is simply set.
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) {
            model.page = page
            model.pageNudge = 0
        }
        model.open()
        Opening.tap()
        startPolling()
    }

    /// A page's shortcut: opens the notch on that page, switches to it if the notch is open on the
    /// other, or closes the notch if it's already showing it.
    func toggleFromKeyboard(_ page: NotchPage) {
        guard page == .player || Tray.isOn else { return }
        if model.state == .open {
            guard model.page != page else { return close(holdUntilExit: false) }
            turn(to: page)
            return
        }
        guard !tucked else { return }
        keyboardHold = true
        open(on: page)
    }

    private func close(holdUntilExit hold: Bool) {
        keyboardHold = false
        dragHold = false
        model.dropping = false
        openTask?.cancel()
        closeTask?.cancel()
        closeTask = nil
        holdUntilExit = hold
        model.close()
        stopPolling()
        pointerMoved(to: NSEvent.mouseLocation)
    }

    /// A menu opened while the pointer is in the open notch was opened from it.
    private func menuOpened() {
        guard model.state == .open, openZone.contains(NSEvent.mouseLocation) else { return }
        menuHold = true
        closeTask?.cancel()
        closeTask = nil
    }

    /// With the menu gone, the notch closes as usual if the pointer is no longer on it.
    private func menuClosed() {
        guard menuHold else { return }
        menuHold = false
        pointerMoved(to: NSEvent.mouseLocation)
    }

    /// A short grace period so grazing the edge doesn't snap the notch shut.
    private func scheduleClose() {
        closeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }
            self?.close(holdUntilExit: false)
        }
    }

    // MARK: Dropping in the tray

    /// A drag from another app carrying something for the tray: once it's past the middle of the
    /// display, on its way up, the notch opens on the tray to take it. The pointer needn't reach
    /// the notch, where the top edge would bring up Mission Control, nor click it. Back down, or let
    /// go somewhere else, and the notch closes again.
    func dragMoved(to p: CGPoint, carrying: Bool) {
        let frame = screen.frame
        let onDisplay = p.x >= frame.minX && p.x <= frame.maxX && p.y >= frame.minY && p.y <= frame.maxY + 1
        if carrying, onDisplay, p.y > frame.midY {
            guard !dragHold, !tucked, Tray.isOn else { return }
            dragHold = true
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                model.dropping = true
                model.trayScroll = 0
            }
            if model.state != .open { open(on: .tray) } else { turn(to: .tray) }
        } else if dragHold, !carrying || !onDisplay || p.y < frame.midY - frame.height * 0.05 {
            dragHold = false
            if model.dropping { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { model.dropping = false } }
            // Closed now unless the pointer is on it, as over the notch after a drop.
            pointerMoved(to: p)
        }
    }

    /// Something the tray takes, dragged over the notch from another app: it opens on the tray,
    /// with a place at the front of the row for it.
    private func dragEntered(_ pasteboard: NSPasteboard) -> NSDragOperation {
        guard Tray.isOn, !tucked, Tray.accepts(pasteboard) else { return [] }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            model.dropping = true
            model.trayScroll = 0
        }
        if model.state != .open {
            open(on: .tray)
        } else if model.page != .tray {
            turn(to: .tray)
        }
        return .copy
    }

    private func dragExited() {
        // Still in the top half of the display, it stays ready for the drop.
        guard model.dropping, !dragHold else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { model.dropping = false }
    }

    private func dropped(_ pasteboard: NSPasteboard) -> Bool {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { model.dropping = false }
        let taken = Tray.shared.drop(pasteboard)
        if taken { Opening.tap() }
        return taken
    }

    // MARK: Scroll: pull down to open, push up to dismiss, swipe sideways to skip

    private func scrolled(_ event: NSEvent) {
        // Positive means fingers (or wheel) moving down or right, whatever the natural-scrolling setting.
        let direction: CGFloat = event.isDirectionInvertedFromDevice ? 1 : -1
        let down = event.scrollingDeltaY * direction
        let right = event.scrollingDeltaX * direction
        let onTray = model.state == .open && model.page == .tray
        // A swipe on the tray let go: the row glides on, and settles within its ends.
        guard event.momentumPhase.isEmpty else {
            guard trayGliding, onTray else { return }
            glideCheck?.cancel()
            scrollTray(by: event.scrollingDeltaX)
            // Gliding past an end, it bounces back rather than running on.
            let past = model.trayScroll < -24 || model.trayScroll > trayReach + 24
            if past || event.momentumPhase == .ended || event.momentumPhase == .cancelled {
                trayGliding = false
                settleTray()
            }
            return
        }
        // Scrolling with Shift held goes sideways between the pages, as Shift makes any scroll go
        // sideways: toward the tray, which is to the right, or back to the player.
        let switches =
            model.state == .open && Tray.isOn && event.modifierFlags.contains(.shift)
            && UserDefaults.standard.bool(forKey: Preferences.swipeToSwitch)
        // A wheel, a notch at a time.
        if switches, event.phase.isEmpty {
            let along = event.scrollingDeltaX != 0 ? event.scrollingDeltaX : event.scrollingDeltaY
            if along != 0 { turn(to: along < 0 ? .tray : .player) }
            return
        }
        // A wheel that tilts sideways scrolls the tray.
        if onTray, event.phase.isEmpty, event.scrollingDeltaX != 0 {
            scrollTray(by: event.scrollingDeltaX * (event.hasPreciseScrollingDeltas ? 1 : 8))
            return settleTray()
        }

        let defaults = UserDefaults.standard
        let opens = defaults.bool(forKey: Preferences.swipeToOpen), skips = defaults.bool(forKey: Preferences.swipeToSkip)

        if event.phase.isEmpty {
            // A wheel mouse: each click is a decisive flick.
            guard opens else { return }
            if down > 0, model.state != .open { open() }
            if down < 0, model.state == .open { close(holdUntilExit: true) }
            return
        }

        switch event.phase {
        case .began, .mayBegin:
            pull = 0
            swipe = 0
            pullFired = false
            scrollAxis = nil
        case .changed:
            if scrollAxis == nil {
                guard abs(down) + abs(right) > 2 else { return }
                scrollAxis = abs(right) > abs(down) ? .horizontal : .vertical
            }
            if switches { return swipedPage(by: scrollAxis == .horizontal ? event.scrollingDeltaX : event.scrollingDeltaY) }
            if scrollAxis == .horizontal {
                // The row scrolls the way everything else does on this Mac.
                if onTray { return scrollTray(by: event.scrollingDeltaX) }
                return skips ? swiped(by: right) : ()
            }
            guard opens else { return }
            pull += down
            if !pullFired, model.state != .open, pull > 40 {
                pullFired = true
                pull = 0
                open()
            } else if !pullFired, model.state == .open, pull < -48 {
                pullFired = true
                close(holdUntilExit: true)
                return
            }
            guard model.state == .open || pull > 0 else { return }
            withAnimation(.interactiveSpring(response: 0.18, dampingFraction: 0.86)) {
                model.stretch = rubberBand(pull)
            }
        default:
            if onTray, scrollAxis == .horizontal, !switches {
                // Let go: it glides on if the fingers were still moving; if they'd stopped, it
                // just settles.
                trayGliding = true
                glideCheck?.cancel()
                glideCheck = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(120))
                    guard let self, !Task.isCancelled, self.trayGliding else { return }
                    self.trayGliding = false
                    self.settleTray()
                }
            }
            pull = 0
            swipe = 0
            scrollAxis = nil
            withAnimation(.spring(response: 0.45, dampingFraction: 0.5)) {
                model.stretch = 0
                model.nudge = 0
                model.pageNudge = 0
            }
        }
    }

    // MARK: The player and the tray

    /// Shift and a scroll: the pages move as a page scrolled sideways does, the way this Mac
    /// scrolls, the tray to the right of the player. The page leans along, then turns; past the
    /// last page, it only leans.
    private func swipedPage(by delta: CGFloat) {
        guard !pullFired else { return }
        swipe += delta
        // Scrolled toward the right: the tray.
        let target: NotchPage = swipe < 0 ? .tray : .player
        if abs(swipe) > 56, target != model.page {
            pullFired = true
            turn(to: target)
            Opening.tap()
            return
        }
        let lean = (swipe >= 0 ? 1 : -1) * 14 * (1 - 1 / (abs(swipe) * 0.04 + 1))
        withAnimation(.interactiveSpring(response: 0.18, dampingFraction: 0.86)) { model.pageNudge = lean }
    }

    /// To the other page, sliding.
    private func turn(to page: NotchPage) {
        guard model.page != page else { return }
        withAnimation(.spring(response: 0.42, dampingFraction: 1)) {
            model.page = page
            model.pageNudge = 0
        }
    }

    /// The tray's row follows the fingers, giving way past either end.
    private func scrollTray(by delta: CGFloat) {
        let reach = trayReach
        var next = model.trayScroll - delta
        if next < 0 || next > reach { next = model.trayScroll - delta * 0.3 }
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) { model.trayScroll = min(max(next, -48), reach + 48) }
    }

    /// Back within the row's ends, springing.
    private func settleTray() {
        let target = min(max(model.trayScroll, 0), trayReach)
        guard target != model.trayScroll else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { model.trayScroll = target }
    }

    private var trayReach: CGFloat {
        Shelf.reach(count: Tray.shared.items.count + (model.dropping ? 1 : 0), in: model.openSize.width)
    }

    /// Two fingers sideways: left for the next song, right for the previous one, as on a phone's
    /// player. The artwork leans along, then skips.
    private func swiped(by delta: CGFloat) {
        guard nowPlaying.hasMedia, !pullFired else { return }
        swipe += delta
        if abs(swipe) > 56 {
            pullFired = true
            if swipe < 0 { nowPlaying.next() } else { nowPlaying.previous() }
            Opening.tap()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { model.nudge = 0 }
            return
        }
        let lean = (swipe >= 0 ? 1 : -1) * 14 * (1 - 1 / (abs(swipe) * 0.04 + 1))
        withAnimation(.interactiveSpring(response: 0.18, dampingFraction: 0.86)) { model.nudge = lean }
    }

    private func rubberBand(_ x: CGFloat) -> CGFloat {
        let limit: CGFloat = x >= 0 ? 28 : 16
        return (x >= 0 ? 1 : -1) * limit * (1 - 1 / (abs(x) * 0.55 / limit + 1))
    }

    // MARK: Geometry (screen coordinates)

    /// An island's floats a little below the top of the screen.
    private var restingRect: CGRect {
        let width = model.restingWidth, height = model.closedSize.height
        return CGRect(x: centerX - width / 2, y: topY - model.gap - height, width: width, height: height)
    }

    private func rect(for state: NotchState) -> CGRect {
        let m = model.metrics(for: state)
        return CGRect(x: centerX - m.totalWidth / 2, y: topY - model.gap - m.height, width: m.totalWidth, height: m.height)
    }

    /// Where the pointer counts as "on" the notch. Reaches slightly past the top edge.
    private var interactiveZone: CGRect {
        // Up to the top edge, over an island's gap too, so pushing the pointer to the top finds it.
        let resting = CGRect(
            x: restingRect.minX - 4, y: restingRect.minY - 4,
            width: restingRect.width + 8, height: restingRect.height + model.gap + 6)
        switch model.state {
        case .closed: return resting
        case .peek: return resting.union(rect(for: .peek))
        case .open:
            let open = rect(for: .open)
            return CGRect(x: open.minX, y: open.minY, width: open.width, height: open.height + 2)
        }
    }

    /// A little forgiving margin before an open notch decides the pointer has left.
    private var openZone: CGRect { rect(for: .open).insetBy(dx: -8, dy: -8) }

    /// 1 on the notch, 0 from `proximityRange` away or off its display.
    private func closeness(to p: CGPoint) -> CGFloat {
        guard screen.frame.insetBy(dx: -1, dy: -1).contains(p) else { return 0 }
        return 1 - restingRect.distance(to: p) / Layout.proximityRange
    }

    // MARK: Helpers

    /// While peeking or open, poll the pointer so leaving is always noticed, even without events.
    private func startPolling() {
        guard pollTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerMoved(to: NSEvent.mouseLocation) }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}

/// A clear, borderless panel that floats above the menu bar. Being borderless, it never takes
/// keyboard focus and can't be dragged.
final class NotchPanel: NSPanel {
    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        // Allowed over full-screen apps; the "Hide in full screen" setting makes it follow the menu bar there.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        animationBehavior = .none
        ignoresMouseEvents = true
    }

    /// Free to slide above the top of the screen when it tucks away in full screen.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    /// Each time it comes on screen, into the layer that swiping between Spaces leaves in place, so
    /// it stays on the camera rather than sliding off with the desktop it was on.
    override func orderFrontRegardless() {
        super.orderFrontRegardless()
        NotchSpace.add(self)
    }

    override func orderOut(_ sender: Any?) {
        NotchSpace.remove(self)
        super.orderOut(sender)
    }

    /// Private AppKit hook. Liquid Glass renders a flat, frosted fallback in windows that don't look
    /// active, and this panel is never key (so it never steals focus). Claiming the active appearance
    /// regardless of key focus, as AppKit's own glass windows do, gets real glass, refraction included.
    @objc func _hasActiveAppearanceIgnoringKeyFocus() -> Bool { true }
}

/// Catches every pointer event aimed at the notch, except on the player's controls, which SwiftUI handles.
final class NotchEventView: NSView {
    /// Whether a point (top-left origin, like SwiftUI) is on a control.
    var passesThrough: (@MainActor (CGPoint) -> Bool)?
    var onMouseDown: (@MainActor () -> Void)?
    var onMouseUp: (@MainActor () -> Void)?
    var onRightMouseDown: (@MainActor (NSEvent) -> Void)?
    var onScroll: (@MainActor (NSEvent) -> Void)?
    var onMouseMoved: (@MainActor () -> Void)?
    /// Something dragged over the notch, and dropped on it.
    var onDragEntered: (@MainActor (NSPasteboard) -> NSDragOperation)?
    var onDragExited: (@MainActor () -> Void)?
    var onDrop: (@MainActor (NSPasteboard) -> Bool)?
    private var dragOperation: NSDragOperation = []

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard frame.contains(point) else { return nil }
        return passesThrough?(convert(point, from: superview)) == true ? super.hitTest(point) : self
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self
            ))
    }

    override func mouseDown(with event: NSEvent) { onMouseDown?() }
    override func mouseUp(with event: NSEvent) { onMouseUp?() }
    override func rightMouseDown(with event: NSEvent) { onRightMouseDown?(event) }
    override func scrollWheel(with event: NSEvent) { onScroll?(event) }
    override func mouseMoved(with event: NSEvent) { onMouseMoved?() }
    override func mouseExited(with event: NSEvent) { onMouseMoved?() }

    // Drags from the tray itself have a source here; they're on their way out, not in.
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        dragOperation = sender.draggingSource == nil ? onDragEntered?(sender.draggingPasteboard) ?? [] : []
        return dragOperation
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { dragOperation }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        dragOperation = []
        onDragExited?()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard !dragOperation.isEmpty else { return false }
        dragOperation = []
        return onDrop?(sender.draggingPasteboard) ?? false
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        guard !dragOperation.isEmpty else { return }
        dragOperation = []
        onDragExited?()
    }
}

/// Lets the first click on a control act right away, though the notch's window is never key.
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
