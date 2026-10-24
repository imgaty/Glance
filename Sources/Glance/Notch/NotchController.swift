//
//  NotchController.swift
//  Glance
//
//  Created by Gaty on 07/10/2026.
//

import AppKit
import Carbon.HIToolbox
import Combine
import Quartz
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
    /// Until when an announcement is folding away for the notch to open (see `foldAnnouncement`).
    private var foldingUntil = Date.distantPast
    private var closeTask: Task<Void, Never>?
    private var pollTimer: Timer?
    /// After an explicit close, stay shut until the pointer leaves the notch.
    private var holdUntilExit = false
    private var pull: CGFloat = 0
    private var pullFired = false
    /// Music's wings were swiped away, until the next song or until it plays again.
    private var musicDismissed = false
    private var playingWatch: AnyCancellable?
    private var activityTask: Task<Void, Never>?
    private var titleWatch: AnyCancellable?
    private var settingsWatch: AnyCancellable?
    private var songWatch: AnyCancellable?
    private var popTask: Task<Void, Never>?
    /// Folding to rest before an announcement opens, or before what it covered comes back.
    private var switchTask: Task<Void, Never>?
    /// What the Mac announces, and the timer, followed into the closed notch.
    private var alertWatch: AnyCancellable?
    private var timerWatch: AnyCancellable?
    private var clockNameWatch: AnyCancellable?
    private var airPlayWatch: AnyCancellable?
    private var airDropWatch: AnyCancellable?
    /// Songs reported in the first moments are what was already playing, not new ones.
    private let createdAt = Date.now
    /// A trackpad gesture's direction, settled by its first movement.
    private var scrollAxis: Axis?
    private var swipe: CGFloat = 0
    /// Whether the current click began on a closed notch, so letting go opens rather than closes it.
    private var pressBeganClosed = false
    /// Fits the timer's wings to its seconds as its last minute starts.
    private var timerWingTask: Task<Void, Never>?
    /// A new layout chosen while the notch is closed, taken once things have settled.
    private var relayoutTask: Task<Void, Never>?
    /// Pressed on one of a done timer's buttons, which acts rather than opening the notch.
    private var pressedButton: AlertButton?
    /// A menu opened from inside the open notch, like the sound output's, is up: the pointer is on
    /// the menu, outside the notch, but the notch stays open under it until it's gone.
    private var menuHold = false
    /// Opened from the keyboard: it stays open with the pointer elsewhere, until the shortcut comes
    /// again, a click lands outside it, or the pointer visits it and leaves.
    private var keyboardHold = false
    /// Opened from the keyboard, it takes the keyboard too, as Spotlight's window does, until it
    /// closes or the keyboard goes elsewhere: Escape, the arrows, Space, Return, a few ⌘ keys and
    /// typing a name work it (see `typed`). Keys come through a watch on Glance's own, ahead of its
    /// menus.
    private var hasKeys = false
    private var keyWatch: Any?
    private var keyLoss: AnyCancellable?
    /// What's been typed of a name in the tray, and when last (see `choose(typing:)`).
    private var typedName = ""
    private var typedAt = Date.distantPast
    /// Something dragged for the tray has come near the notch: a moment's wait, then it opens.
    private var dropDwell: Task<Void, Never>?
    private var menuWatches: [AnyCancellable] = []
    private var pasteWatch: AnyCancellable?
    private var trayWatch: AnyCancellable?
    private var trayTouch: AnyCancellable?
    /// Something for the tray was dragged near the notch and rested there: the notch is open on the
    /// tray to take it, until the drag goes away or ends.
    private var dragHold = false
    /// A sideways swipe on the tray was let go and the row glides on.
    private var trayGliding = false
    private var glideCheck: Task<Void, Never>?
    /// When a wheel with Shift held brought the tray's row to its end toward the player.
    private var trayEdgeSince: Date?

    /// A full-screen app covers this display and the user chose to hide the notch then. Like the
    /// menu bar there, it stays out of sight until the pointer reaches the top edge, slides down
    /// with it, and slides away again once the pointer leaves it and the menu bar.
    var fullScreen = false {
        didSet {
            guard fullScreen != oldValue else { return }
            if fullScreen { tuck() } else { untuck() }
        }
    }

    /// A full-screen app covers this display, around the notch all black, as around the Dynamic
    /// Island: the notch's outline shows then.
    var coveredByFullScreen = false {
        didSet {
            guard coveredByFullScreen != oldValue else { return }
            model.fullScreen = coveredByFullScreen
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

        // Room for the largest layout with the lyrics open, and for the tray at its widest, so
        // switching layouts or the tray growing never resizes it.
        model.trayMaxWidth = Self.widestTray(on: screen)
        let largest = PlayerLayout.allCases.map { $0.size(closed: closedSize) }
        let size = CGSize(
            width: max(largest.map(\.width).max()! + model.lyricsWidth, Self.widestTray(on: screen)) + Layout.windowPadding.width * 2,
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
        // Opened without the pointer, as VoiceOver opens a bubble: it stays open with the keyboard, as
        // when opened with a shortcut, until Escape, or the pointer has been on it and gone.
        model.openBubble = { [weak self] side in
            guard let self, self.model.bubble(side) != nil, !self.tucked else { return }
            self.model.bubbleHovered = side
            self.open()
            self.keyboardHold = true
            self.takeKeys()
        }
        model.openNotch = { [weak self] in
            guard let self, !self.tucked else { return }
            self.model.bubbleHovered = nil
            self.open()
            self.keyboardHold = true
            self.takeKeys()
        }
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
        eventView.onDragMoved = { [weak self] pasteboard, point, own in self?.dragMoved(pasteboard, at: point, own: own) ?? [] }
        eventView.onDragExited = { [weak self] in self?.dragExited() }
        eventView.onDrop = { [weak self] pasteboard, point, own in self?.dropped(pasteboard, at: point, own: own) ?? false }
        // Pasted from the tray: its work is done, so it closes, as Spotlight does.
        pasteWatch = NotificationCenter.default.publisher(for: Tray.didPaste).sink { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.model.state == .open else { return }
                self.close(holdUntilExit: true)
            }
        }
        // The tray grows with what's in it, up to its widest, then scrolls.
        trayWatch = Tray.shared.$items.map(\.count).removeDuplicates().sink { [weak self] count in
            MainActor.assumeIsolated {
                guard let self else { return }
                withAnimation(.smooth(duration: 0.3)) { self.model.trayItems = count }
                // Once the tray has its new items: within its row's new ends.
                Task { @MainActor in self.settleTray() }
            }
        }
        // A click in the tray gives it the keyboard, as a click in a Finder window does: the arrows,
        // Space, ⌘C and ⌘Z work it from then on, until it closes.
        trayTouch = NotificationCenter.default.publisher(for: Tray.didTouch).sink { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, self.model.state == .open, self.model.page == .tray,
                    (note.object as? NSView)?.window === self.panel
                else { return }
                self.takeKeys()
            }
        }
        keyLoss = NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification, object: panel).sink { [weak self] _ in
            MainActor.assumeIsolated { self?.lostKeys() }
        }

        alertWatch = Activities.shared.$alert.removeDuplicates().sink { [weak self] alert in
            MainActor.assumeIsolated { self?.show(alert) }
        }
        // Clock's timer and stopwatch (see `ClockActivity`).
        ClockActivity.shared.start()
        timerWatch = ClockActivity.shared.$timer.combineLatest(ClockActivity.shared.$stopwatch)
            .removeDuplicates { $0 == $1 }
            .sink { [weak self] timer, stopwatch in
                MainActor.assumeIsolated { self?.show(timer: timer, stopwatch: stopwatch) }
            }
        clockNameWatch = ClockActivity.shared.$timerTitle.removeDuplicates().sink { [weak self] title in
            MainActor.assumeIsolated { self?.model.timerName = title }
        }
        // The sound going to AirPlay (see `AirPlayWatch`).
        airPlayWatch = AirPlayWatch.shared.$route.removeDuplicates().sink { [weak self] route in
            MainActor.assumeIsolated { self?.show(airplay: route) }
        }
        // A file coming in over AirDrop (see `AirDropWatch`).
        airDropWatch = AirDropWatch.shared.$transfer.removeDuplicates().sink { [weak self] transfer in
            MainActor.assumeIsolated { self?.show(airdrop: transfer) }
        }

        // The live activity and the song announcements follow their settings as they change.
        playingWatch = nowPlaying.$isPlaying.removeDuplicates().sink { [weak self] playing in
            MainActor.assumeIsolated {
                // Playing again, what was swiped away comes back.
                if playing { self?.musicDismissed = false }
                self?.showActivity(playing)
            }
        }
        titleWatch = nowPlaying.$title.removeDuplicates().sink { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // A new song brings back what was swiped away.
                if self.musicDismissed {
                    self.musicDismissed = false
                    self.showActivity(self.nowPlaying.isPlaying, immediately: true)
                }
                self.announceTrack()
            }
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
        giveBackKeys()
        Tray.shared.hold(false, for: self)
        dropDwell?.cancel()
        NotchSwipes.shared.set(nil, for: self)
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
        let shown = playing && UserDefaults.standard.bool(forKey: Preferences.liveActivity) && !musicDismissed
        activityTask = Task { [weak self] in
            guard !Task.isCancelled else { return }
            // A pause folds it away after a moment; turning it off in Settings, at once.
            if !shown, !immediately {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
            }
            withAnimation(shown ? IslandMotion.open : IslandMotion.fold) {
                self?.model.activity = shown
                if !shown { self?.model.pop = false }
            }
        }
    }

    /// Switches to the layout chosen in Settings, in place: open, the notch reshapes and the
    /// player's pieces move to their new places. Closed, nothing of the new layout shows: it's taken
    /// once the click that chose it has settled, rather than adding to the moment that click takes,
    /// or as the notch opens, if that's sooner.
    func relayout() {
        relayoutTask?.cancel()
        guard PlayerLayout.current != model.layout else { return }
        guard model.state == .open else {
            relayoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(0.6))
                guard let self, !Task.isCancelled else { return }
                self.model.use(PlayerLayout.current)
            }
            return
        }
        withAnimation(NotchMotion.expand) { model.use(PlayerLayout.current) }
    }

    /// Something the Mac announces: the wings widen to show it, and fold back once it's said, with
    /// the Dynamic Island's springs, measured from it: a touch of bounce opening, none folding. With
    /// music or a timer showing, the notch first folds to rest, what it shows blurring away, and
    /// opens again from there; once it's said, it folds, and what was there opens again.
    private func show(_ alert: NotchAlert?) {
        switchTask?.cancel()
        let fold = IslandMotion.fold, open = IslandMotion.open
        let wingsShowing = !model.activities.isEmpty
        guard let alert else {
            withAnimation(fold) {
                model.alert = nil
                model.switching = wingsShowing
            }
            // Folded for the notch to open: what was there shows in the open notch, not first beside
            // the camera.
            guard wingsShowing, foldingUntil < .now else { return }
            switchTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(Self.switchPause))
                guard let self, !Task.isCancelled else { return }
                withAnimation(open) { self.model.switching = false }
            }
            return
        }
        let wing = SystemActivityView.wing(
            for: alert, restingHeight: model.closedSize.height, island: model.island, notchWidth: model.closedSize.width)
        func announce() {
            withAnimation(open) {
                model.switching = false
                model.alertWing = wing
                model.alert = alert
            }
        }
        guard wingsShowing, model.alert == nil, !model.switching else { return announce() }
        withAnimation(fold) { model.switching = true }
        switchTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.switchPause))
            guard self != nil, !Task.isCancelled else { return }
            announce()
        }
    }

    /// How long the notch rests between one activity folding and the next opening, as the Dynamic
    /// Island's does.
    private static let switchPause = 0.18

    /// The timer or the stopwatch started, paused or ended: its wings come, or go. Opened to it,
    /// ended, cancelled or reset, the notch closes, for what it's done to show.
    private func show(timer: NotchTimer.State?, stopwatch: Stopwatch?) {
        let ending = (timer == nil && model.timer != nil) || (stopwatch == nil && model.stopwatch != nil)
        withAnimation(ending ? IslandMotion.fold : IslandMotion.open) {
            // Started, paused or ended, one swiped away comes back.
            if timer != model.timer { model.dismissed.remove(.timer) }
            if stopwatch != model.stopwatch { model.dismissed.remove(.stopwatch) }
            model.timer = timer
            model.stopwatch = stopwatch
            fitTimerWing()
        }
        // Opened to one that has ended, been cancelled or reset, the notch closes, for that to show.
        if model.state == .open, model.expandedGone { close(holdUntilExit: true) }
        refitAsTimersCount()
    }

    /// A file started coming in over AirDrop, came further, or is in: AirDrop's wings come, fill, or
    /// go. Opened to it as it goes, the notch closes.
    private func show(airdrop transfer: AirDropShown?) {
        guard (transfer == nil) != (model.airdrop == nil) || transfer?.id != model.airdrop?.id else {
            // Only further along: the ring fills on its own.
            model.airdrop = transfer
            return
        }
        withAnimation(transfer == nil ? IslandMotion.fold : IslandMotion.open) {
            if transfer?.id != model.airdrop?.id { model.dismissed.remove(.airdrop) }
            model.airdrop = transfer
        }
        if model.state == .open, model.expandedGone { close(holdUntilExit: true) }
    }

    /// The sound went to AirPlay, or left it: AirPlay's wings come, or go. Opened to it as it
    /// leaves, the notch closes.
    private func show(airplay route: AirPlayRoute?) {
        withAnimation(route == nil ? IslandMotion.fold : IslandMotion.open) {
            if route != model.airplay { model.dismissed.remove(.airplay) }
            model.airplay = route
        }
        if model.state == .open, model.expandedGone { close(holdUntilExit: true) }
    }

    /// Refits the notch whenever what it shows of a timer or the stopwatch gains or loses a digit,
    /// closed or opened, so it's never wider than they need: a timer from hours to minutes and from
    /// minutes to seconds, the stopwatch from minutes to hours.
    private func refitAsTimersCount() {
        timerWingTask?.cancel()
        let now = Date.now
        let clocks = [model.timer.map(ClockShown.timer), model.stopwatch.map(ClockShown.stopwatch)].compactMap { $0 }
        guard let next = clocks.compactMap({ SystemActivityView.widthChange(after: now, of: $0) }).min() else { return }
        let wait = next.timeIntervalSince(now) + 0.05
        timerWingTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard let self, !Task.isCancelled else { return }
            withAnimation(IslandMotion.open) {
                self.fitTimerWing()
                // Opened to a timer, the notch is as wide as its time is now.
                self.model.objectWillChange.send()
            }
            self.refitAsTimersCount()
        }
    }

    /// The wings as wide as the time for the notch needs: the first one's, in the notch once nothing
    /// plays.
    private func fitTimerWing() {
        guard let clock = model.firstClock else { return }
        model.timerWing = SystemActivityView.wing(for: clock, restingHeight: model.closedSize.height, island: model.island)
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
            withAnimation(IslandMotion.open) {
                model.popWing = LiveActivityView.popWing(
                    title: nowPlaying.title, artist: nowPlaying.artist,
                    restingHeight: model.closedSize.height, island: model.island)
                model.activity = true
                model.pop = true
            }
            try? await Task.sleep(for: .seconds(3.5))
            guard !Task.isCancelled else { return }
            withAnimation(IslandMotion.fold) { model.pop = false }
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
        // Where three fingers turn the page: the open notch, kept up to date as it opens and closes.
        NotchSwipes.shared.set(swipeZone, for: self)
        if fullScreen, followMenuBar(p) { return }
        let button = alertButton(at: p)
        if model.hoveredButton != button { model.hoveredButton = button }
        switch model.state {
        case .closed, .peek:
            let onBubble = button == nil ? bubble(at: p) : nil
            if onBubble != model.bubbleHovered { hoverBubble(onBubble, at: p) }
            if button != nil {
                // On a done timer's button the notch stays as it is, so a click there is the button's.
                openTask?.cancel()
            } else if onBubble != nil {
                // The bubble's own: the notch beside it stays as it is.
            } else if interactiveZone.contains(p) {
                if model.state == .closed, !holdUntilExit { peek() }
            } else {
                holdUntilExit = false
                if model.state == .peek { settle(at: p) } else { model.approach(closeness(to: p)) }
            }
        case .open:
            // Once the pointer has been on it, it closes as usual when the pointer leaves.
            if openZone.contains(p) { keyboardHold = false }
            // Share's picker over it holds it open too, as a menu from it does.
            if menuHold || keyboardHold || dragHold || Tray.shared.sharing || openZone.contains(p) {
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
        // With the pointer on the tray, new copies wait, so its row doesn't move under it.
        Tray.shared.hold(model.state == .open && model.page == .tray && openZone.contains(p), for: self)
    }

    /// The pointer onto a bubble beside the notch, or off it: it swells a little, as the notch does.
    /// Only a click opens it, to what it shows.
    private func hoverBubble(_ side: NotchModel.Side?, at p: CGPoint) {
        if side != nil, model.state == .peek { settle(at: p) }
        openTask?.cancel()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { model.bubbleHovered = side }
        if side != nil {
            startPolling()
        } else if model.state == .closed {
            stopPolling()
        }
    }

    /// The button of a timer that's done, or Low Battery's, in the closed notch, at a point on the
    /// screen.
    private func alertButton(at p: CGPoint) -> AlertButton? {
        guard model.alert?.tall == true, model.state != .open, let view = panel.contentView else { return nil }
        let local = view.convert(panel.convertPoint(fromScreen: p), from: nil)
        let inNotch = CGPoint(x: local.x, y: local.y - Layout.pastTop)
        return model.alertButtons.first { $0.value.contains(inNotch) }?.key
    }

    func clicked(outsideAt p: CGPoint) {
        if model.state == .open, !openZone.contains(p) { close(holdUntilExit: false) }
    }

    /// Pressing the closed notch squeezes it, and letting go opens it. The open notch ignores
    /// clicks outside its controls: it closes when the pointer leaves or with a swipe up.
    private func press() {
        // A done timer's buttons, in the closed notch, are buttons of their own.
        pressedButton = alertButton(at: NSEvent.mouseLocation)
        if pressedButton != nil { return }
        pressBeganClosed = model.state != .open
        // A click on the tray, off its items, lets go of any chosen ones, as in Finder.
        if !pressBeganClosed, model.page == .tray { Tray.shared.deselect() }
        guard pressBeganClosed else { return }
        if let side = model.bubbleHovered {
            // A bubble opens with a plain click, as it's let go.
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) { model.bubblePressed = side }
            return
        }
        model.press(true)
        let opening = Opening.current
        // With a hold delay, the notch opens while the button is still down.
        if opening.onClick, opening.clickDelay > 0 {
            scheduleOpen(after: opening.clickDelay)
        }
    }

    private func release() {
        if let button = pressedButton {
            pressedButton = nil
            guard alertButton(at: NSEvent.mouseLocation) == button else { return }
            switch button {
            case .again: ClockActivity.shared.repeatTimer()
            case .stop: ClockActivity.shared.dismissRing()
            case .lowPower:
                LowPowerMode.shared.turnOn()
                // Long enough to see it come on.
                Activities.shared.keep(.lowBattery, for: 2.5)
            }
            model.hoveredButton = nil
            return
        }
        guard pressBeganClosed else { return }
        if let side = model.bubblePressed {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) { model.bubblePressed = nil }
            if bubble(at: NSEvent.mouseLocation) == side { open() }
            return
        }
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
        foldAnnouncement()
        let opening = Opening.current
        // With the button held, something's being dragged: a window, which shouldn't open the
        // notch, or something for the tray, which opens it as it comes over (see `dragEntered`).
        if opening.onHover, NSEvent.pressedMouseButtons & 1 == 0 { scheduleOpen(after: opening.hoverDelay) }
    }

    /// An announcement, which has nothing of its own to open to, folds away the moment the pointer
    /// comes onto the notch, and the notch opens only once it has, as the Dynamic Island finishes
    /// one activity's motion before the next. One with buttons, as a rung timer, stays for them.
    private func foldAnnouncement() {
        guard let alert = model.alert, !alert.tall, model.state != .open else { return }
        foldingUntil = .now + Self.foldTime
        Activities.shared.dismiss(alert.kind)
    }

    /// As long as an announcement takes to fold away.
    private static let foldTime = 0.32

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
        // Gone before the notch opened, after an announcement folded away for it: what was there
        // comes back beside the camera.
        if foldingUntil > .distantPast, model.alert == nil, model.switching {
            withAnimation(IslandMotion.open) { model.switching = false }
        }
        foldingUntil = .distantPast
    }

    /// Opens on the player, unless told otherwise; for something dragged to it, with its places to
    /// drop.
    private func open(on page: NotchPage = .player, forDrop: Bool = false) {
        guard model.state != .open else { return }
        // An announcement folds away first, from a click or a shortcut as from the pointer (see
        // `foldAnnouncement`); something dragged to the notch doesn't wait for it.
        if !forDrop {
            foldAnnouncement()
            let wait = foldingUntil.timeIntervalSinceNow
            if wait > 0 {
                openTask?.cancel()
                openTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(wait))
                    guard !Task.isCancelled else { return }
                    self?.open(on: page)
                }
                return
            }
        }
        // A timer that's done has been seen: it's no longer said.
        ClockActivity.shared.dismissRing()
        openTask?.cancel()
        closeTask?.cancel()
        closeTask = nil
        popTask?.cancel()
        // Closed, nothing of either page shows: the page is simply set. It opens to what was clicked,
        // as the Dynamic Island expands it: a bubble's own activity, or the notch's; a timer to its
        // own view, music to the player.
        let expansion = model.expansion(fromBubble: model.bubbleHovered)
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) {
            // What an announcement folded away for shows in the open notch.
            if model.alert == nil { model.switching = false }
            if model.layout != PlayerLayout.current {
                relayoutTask?.cancel()
                model.use(PlayerLayout.current)
            }
            model.bubbleHovered = nil
            model.bubblePressed = nil
            model.expanded = page == .player && !forDrop && !keyboardHold ? expansion : nil
            model.page = page
            model.pageNudge = 0
            if !forDrop {
                model.dropping = false
                model.airDropTargeted = false
            }
        }
        model.open()
        Opening.tap()
        startPolling()
        // Accessibility may have been allowed since: three fingers can turn the page now.
        NotchSwipes.shared.start()
    }

    /// A page's shortcut: opens the notch on that page, switches to it if the notch is open on the
    /// other, or closes the notch if it's already showing it.
    func toggleFromKeyboard(_ page: NotchPage) {
        guard page == .player || Tray.isOn else { return }
        if model.state == .open {
            guard model.page != page else { return close(holdUntilExit: false) }
            turn(to: page)
            takeKeys()
            return
        }
        guard !tucked else { return }
        keyboardHold = true
        open(on: page)
        takeKeys()
    }

    // MARK: The keyboard

    private var lookWatch: AnyCancellable?

    /// The notch takes the keyboard, and every key typed comes to it, ahead of Glance's menus, so
    /// ⌘Q or ⌘H can't quit or hide it from there.
    private func takeKeys() {
        guard !hasKeys else { return }
        hasKeys = true
        panel.takesKeys = true
        panel.makeKey()
        keyWatch = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let used = MainActor.assumeIsolated { () -> Bool in
                guard let self, self.hasKeys, event.window === self.panel else { return false }
                if !self.typed(event) { NSSound.beep() }
                return true
            }
            return used ? nil : event
        }
    }

    /// Back to the window that had the keyboard before the notch took it.
    private func giveBackKeys() {
        guard hasKeys else { return }
        hasKeys = false
        if let keyWatch { NSEvent.removeMonitor(keyWatch) }
        keyWatch = nil
        lookWatch = nil
        let wasKey = panel.isKeyWindow
        panel.takesKeys = false
        if wasKey, panel.isVisible {
            // A window can't hand the keyboard to another app's. Out of sight for an instant and
            // back, the notch lets it go back to where it was.
            panel.orderOut(nil)
            panel.orderFrontRegardless()
        }
        // Quick Look brought Glance to the front; with no window of its own up, the app that was in
        // front before comes back.
        // Not while Share's picker, which needs Glance in front, is up.
        if NSApp.isActive, !Tray.shared.sharing, !NSApp.windows.contains(where: { $0.isVisible && !($0 is NSPanel) }) {
            NSApp.deactivate()
        }
    }

    /// The keyboard went elsewhere, as to a window clicked or an app switched to: the notch's turn
    /// is over. Quick Look, showing the tray's items, only borrows it, and gives it back as it goes.
    private func lostKeys() {
        guard hasKeys else { return }
        // Asked a moment later, once the keyboard has landed.
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.hasKeys, !self.panel.isKeyWindow else { return }
                if QLPreviewPanel.sharedPreviewPanelExists(), let look = QLPreviewPanel.shared(), look.isVisible {
                    self.lookWatch = NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification, object: look)
                        .sink { [weak self] _ in
                            DispatchQueue.main.async { MainActor.assumeIsolated { self?.quickLookDone() } }
                        }
                    return
                }
                self.giveBackKeys()
                // Share's picker took it: the notch stays under it.
                if self.model.state == .open, !Tray.shared.sharing { self.close(holdUntilExit: false) }
            }
        }
    }

    private func quickLookDone() {
        guard hasKeys else { return }
        lookWatch = nil
        let look = QLPreviewPanel.sharedPreviewPanelExists() ? QLPreviewPanel.shared() : nil
        if look?.isVisible != true, NSApp.isActive, model.state == .open {
            panel.makeKey()
        } else {
            giveBackKeys()
        }
    }

    /// A key typed while the notch has the keyboard, as Finder and Music take them: Escape closes
    /// it. On the player, Space plays or pauses, and the arrows go to the song before or after. On
    /// the tray, the arrows choose an item (with Shift, a run of them), Space shows the chosen ones
    /// in Quick Look, Return pastes them, ⌘C copies them, ⌘A chooses everything, ⌘Delete removes
    /// them, and ⌘Z brings back what was last removed. Returns whether the notch had a use for the
    /// key.
    private func typed(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let command = flags.contains(.command), shift = flags.contains(.shift)
        let key = Int(event.keyCode)
        // ⌘ and a letter, wherever the letter is on this keyboard.
        let letter = command ? event.charactersIgnoringModifiers?.lowercased() : nil
        if (key == kVK_Escape && !command) || letter == "w" {
            close(holdUntilExit: false)
            return true
        }
        guard model.page == .tray else {
            guard !command, nowPlaying.hasMedia else { return false }
            switch key {
            case kVK_Space: nowPlaying.togglePlayPause()
            case kVK_LeftArrow: nowPlaying.previous()
            case kVK_RightArrow: nowPlaying.next()
            default: return false
            }
            return true
        }
        let tray = Tray.shared
        switch (key, letter) {
        case (kVK_LeftArrow, nil), (kVK_RightArrow, nil):
            guard let id = tray.move(by: key == kVK_LeftArrow ? -1 : 1, extending: shift) else { return false }
            reveal(id)
        case (kVK_Space, nil) where Date.now.timeIntervalSince(typedAt) < Self.typingPause:
            // Partway through typing a name, as in Finder, a space is part of it.
            return choose(typing: event)
        case (kVK_Space, nil):
            let urls = tray.files(of: tray.chosen)
            guard !urls.isEmpty else { return false }
            TrayQuickLook.shared.show(urls)
        case (kVK_Return, nil), (kVK_ANSI_KeypadEnter, nil):
            guard !tray.chosen.isEmpty else { return false }
            tray.paste(tray.chosen)
        case (_, "c"):
            guard !tray.chosen.isEmpty else { return false }
            tray.copy(tray.chosen)
        case (_, "a"):
            tray.choose(all: tray.items)
        case (_, "z"):
            // What was last taken out comes back, chosen, in sight.
            guard let first = tray.undoRemove().first else { return false }
            reveal(first)
        case (kVK_Delete, _) where command, (kVK_ForwardDelete, _) where command:
            guard !tray.chosen.isEmpty else { return false }
            tray.remove(Set(tray.chosen.map(\.id)))
        default:
            return choose(typing: event)
        }
        return true
    }

    /// A name typed in the tray, as in a Finder window: each letter typed soon after the last adds
    /// to it, and the first item whose name starts with it is chosen, in sight.
    private func choose(typing event: NSEvent) -> Bool {
        // Not ⌘ or Control keys, nor the arrows, function keys, Tab, Return or Delete.
        guard event.modifierFlags.isDisjoint(with: [.command, .control, .function]), let characters = event.characters,
            !characters.isEmpty, characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
        else { return false }
        let now = Date.now
        typedName = now.timeIntervalSince(typedAt) < Self.typingPause ? typedName + characters : characters
        typedAt = now
        if let id = Tray.shared.first(named: typedName) {
            Tray.shared.choose(id)
            reveal(id)
        }
        return true
    }

    /// Longer than this between letters, and a new name is being typed.
    static let typingPause: TimeInterval = 1

    /// The tray's row scrolled, if it must be, so the item the keyboard is on shows whole.
    private func reveal(_ id: UUID) {
        let tray = Tray.shared
        guard let index = tray.items.firstIndex(where: { $0.id == id }) else { return }
        let width = model.trayWidth
        let start = CGFloat(index) * (Shelf.tile.width + Shelf.spacing)
        let end = start + Shelf.tile.width + Shelf.inset * 2
        var scroll = model.trayScroll
        if start < scroll { scroll = start }
        if end > scroll + width { scroll = end - width }
        scroll = min(max(scroll, 0), trayReach)
        guard scroll != model.trayScroll else { return }
        withAnimation(.smooth(duration: 0.3)) { model.trayScroll = scroll }
    }

    private func close(holdUntilExit hold: Bool) {
        giveBackKeys()
        keyboardHold = false
        dragHold = false
        // The places to drop stay as the notch closes, rather than the tray showing on its way
        // out; once it's shut, they go.
        if model.dropping { clearDropOnceClosed() }
        model.airDropTargeted = false
        Tray.shared.deselect()
        NotchSwipes.shared.set(nil, for: self)
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

    /// A drag from another app carrying something for the tray: once it comes near the notch and
    /// rests there a moment, as a folder springs open under a dragged file, the notch opens on the
    /// tray to take it. The pointer needn't reach the notch, where the top edge would bring up
    /// Mission Control, nor click it; a drag passing by, or anywhere else on the screen, leaves it
    /// be. Taken away, or let go somewhere else, and the notch closes again.
    func dragMoved(to p: CGPoint, carrying: Bool) {
        let near = rect(for: .open).insetBy(dx: -Self.dropReach, dy: -Self.dropReach)
        if carrying, near.contains(p) {
            guard !dragHold, dropDwell == nil, !tucked, Tray.isOn else { return }
            dropDwell = Task { [weak self] in
                try? await Task.sleep(for: .seconds(0.25))
                guard let self, !Task.isCancelled else { return }
                self.dropDwell = nil
                self.openForDrop()
            }
            return
        }
        dropDwell?.cancel()
        dropDwell = nil
        // A little further out before it closes again, so its edge doesn't flicker.
        if dragHold, !carrying || !near.insetBy(dx: -40, dy: -40).contains(p) {
            dragHold = false
            // Let go on the notch itself, with nothing dropped: it stays, and shows the tray.
            if !carrying, model.dropping, model.state == .open, openZone.contains(p) {
                withAnimation(.smooth(duration: 0.3)) { model.dropping = false }
            }
            // Closed now unless the pointer is on it, its places to drop still in it as it goes.
            pointerMoved(to: p)
        }
    }

    /// The places to drop go once the notch has shut, without a fade: closing, it never shows the
    /// tray behind them on its way out.
    private func clearDropOnceClosed() {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.45))
            guard let self, self.model.state == .closed, !self.dragHold else { return }
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) {
                self.model.dropping = false
                self.model.airDropTargeted = false
            }
        }
    }

    /// How far around the open notch a drag for the tray opens it.
    static let dropReach: CGFloat = 80

    private func openForDrop() {
        dragHold = true
        withAnimation(.smooth(duration: 0.3)) {
            model.dropping = true
            model.trayScroll = 0
        }
        if model.state != .open { open(on: .tray, forDrop: true) } else { turn(to: .tray) }
    }

    /// Something dragged over the notch, at a point in the window's own (flipped) points. From
    /// another app, the notch opens on the tray with its two places to drop: the tray, and
    /// AirDrop. Dragged out of the tray, it's on its way elsewhere: the notch takes nothing back.
    private func dragMoved(_ pasteboard: NSPasteboard, at point: CGPoint, own: Bool) -> NSDragOperation {
        guard Tray.isOn, !tucked, !own else { return [] }
        let onWell = isOnAirDrop(point)
        if model.airDropTargeted != onWell {
            withAnimation(.smooth(duration: 0.25)) { model.airDropTargeted = onWell }
            if onWell { Opening.tap() }
        }
        guard Tray.accepts(pasteboard) else { return [] }
        // Back to the row, with a place at its front for the drop.
        if !model.dropping {
            withAnimation(.smooth(duration: 0.3)) {
                model.dropping = true
                model.trayScroll = 0
            }
        }
        if model.state != .open {
            open(on: .tray, forDrop: true)
        } else if model.page != .tray {
            turn(to: .tray)
        }
        return .copy
    }

    private func isOnAirDrop(_ point: CGPoint) -> Bool {
        guard model.state == .open, model.page == .tray, let well = model.airDropFrame else { return false }
        return well.insetBy(dx: -6, dy: -6).contains(CGPoint(x: point.x, y: point.y - Layout.pastTop))
    }

    /// The drag left the notch's window. Its places to drop stay: near the notch, for the drop; going
    /// away, they close with the notch (see `close`).
    private func dragExited() {
        if model.airDropTargeted { withAnimation(.smooth(duration: 0.25)) { model.airDropTargeted = false } }
    }

    /// Onto AirDrop's place: sent, as soon as a device is picked. Anywhere else on the notch: kept in
    /// the tray.
    private func dropped(_ pasteboard: NSPasteboard, at point: CGPoint, own: Bool) -> Bool {
        guard !own else { return false }
        let onWell = isOnAirDrop(point)
        withAnimation(.smooth(duration: 0.3)) {
            model.dropping = false
            model.airDropTargeted = false
        }
        if onWell {
            let items = Self.shareable(from: pasteboard)
            guard !items.isEmpty else { return false }
            Tray.shared.airDrop(items)
            return true
        }
        let taken = Tray.shared.drop(pasteboard)
        if taken { Opening.tap() }
        return taken
    }

    /// What a drag carries, as AirDrop takes it: files, or else links, or else text.
    private static func shareable(from pasteboard: NSPasteboard) -> [Any] {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            return urls
        }
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL], !urls.isEmpty { return urls }
        return (pasteboard.readObjects(forClasses: [NSString.self]) as? [String]) ?? []
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
        // A mouse's wheel on a tray with more than fits scrolls its row, as a wheel scrolls any row on
        // a Mac: down or with Shift, toward its end; up, back. A notch at a time, gliding there.
        if onTray, event.phase.isEmpty, trayReach > 0 {
            let along = event.scrollingDeltaX != 0 ? event.scrollingDeltaX : event.scrollingDeltaY
            return wheelTray(by: along * (event.hasPreciseScrollingDeltas ? 1 : 24), switches: switches)
        }
        // A wheel, a notch at a time.
        if switches, event.phase.isEmpty {
            let along = event.scrollingDeltaX != 0 ? event.scrollingDeltaX : event.scrollingDeltaY
            if along != 0 { turn(to: (along < 0) != switchReversed ? .tray : .player) }
            return
        }
        let defaults = UserDefaults.standard
        let opens = defaults.bool(forKey: Preferences.swipeToOpen), skips = defaults.bool(forKey: Preferences.swipeToSkip)

        if event.phase.isEmpty {
            // A wheel mouse: each click is a decisive flick.
            guard opens else { return }
            if down > 0, model.state != .open { open() }
            if down < 0 { pushedUp() }
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
                // Songs change from the player, or the closed notch; never from the tray.
                return skips && (model.state != .open || model.page == .player) ? swiped(by: right) : ()
            }
            guard opens else { return }
            pull += down
            // Pushing up on the closed notch, it waits to open on hover: it's being swiped away.
            if model.state != .open, pull < 0 { openTask?.cancel() }
            if !pullFired, model.state != .open, pull > 40 {
                pullFired = true
                pull = 0
                open()
            } else if !pullFired, pull < (model.state == .open ? -48 : -30) {
                pullFired = true
                pushedUp()
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

    /// Swiped up: the open notch closes, and opened to an activity's own view, that goes too; the
    /// closed notch's live activity goes, as the Dynamic Island's do when they're swiped away.
    private func pushedUp() {
        if model.state == .open {
            let expanded = model.expanded
            close(holdUntilExit: true)
            if let expanded { dismiss(expanded) }
            return
        }
        if let alert = model.alert {
            // A timer that's done stops ringing; anything else announced folds away.
            if alert.kind == .timerDone { ClockActivity.shared.dismissRing() } else { Activities.shared.dismiss(alert.kind) }
        } else if let first = model.activities.first {
            dismiss(first)
        } else {
            return
        }
        // It stays closed until the pointer leaves it and comes back.
        close(holdUntilExit: true)
    }

    /// A live activity swiped away, until it changes: music until the next song, or until it
    /// plays again; a timer or the stopwatch until it's started, paused or ended; AirDrop until
    /// the next file; AirPlay until the next speaker.
    private func dismiss(_ activity: NotchModel.Activity) {
        withAnimation(IslandMotion.fold) {
            if activity == .music {
                musicDismissed = true
                activityTask?.cancel()
                popTask?.cancel()
                model.activity = false
                model.pop = false
            } else {
                model.dismissed.insert(activity)
            }
        }
    }

    // MARK: The player and the tray

    /// The widest the tray grows: six items and the next peeking, and never closer than 100
    /// points to either side of the display.
    static func widestTray(on screen: NSScreen) -> CGFloat {
        min(Shelf.peekWidth, screen.frame.width - 200)
    }

    /// Whether a three-finger swipe starting here is the notch's: on it, open, with the tray on.
    func takesSwipe(at p: CGPoint) -> Bool {
        swipeZone?.contains(p) ?? false
    }

    /// Where three-finger swipes are the notch's: all of it, while it's open with the tray on.
    private var swipeZone: CGRect? {
        guard model.state == .open, Tray.isOn, UserDefaults.standard.bool(forKey: Preferences.swipeToSwitch) else { return nil }
        return openZone
    }

    /// Three fingers on the open notch: toward the page on the right, the tray, or back.
    func swipe(right: Bool) {
        let page: NotchPage = right != switchReversed ? .tray : .player
        guard page != model.page else { return }
        turn(to: page)
        Opening.tap()
    }

    /// Shift and a scroll: the pages move as a page scrolled sideways does, the way this Mac
    /// scrolls, the tray to the right of the player. The page leans along, then turns; past the
    /// last page, it only leans.
    private func swipedPage(by delta: CGFloat) {
        guard !pullFired else { return }
        swipe += delta
        // Scrolled toward the right: the tray, unless that's turned around in Settings.
        let target: NotchPage = (swipe < 0) != switchReversed ? .tray : .player
        if abs(swipe) > 56, target != model.page {
            pullFired = true
            turn(to: target)
            Opening.tap()
            return
        }
        let lean = (swipe >= 0 ? 1 : -1) * 14 * (1 - 1 / (abs(swipe) * 0.04 + 1))
        withAnimation(.interactiveSpring(response: 0.18, dampingFraction: 0.86)) { model.pageNudge = lean }
    }

    /// To the other page, sliding, the notch taking the new page's width with the Dynamic Island's
    /// spring.
    private func turn(to page: NotchPage) {
        guard model.page != page || model.expanded != nil else { return }
        withAnimation(NotchMotion.expand) {
            model.expanded = nil
            model.page = page
            model.pageNudge = 0
        }
    }

    /// Turned around in Settings: the other way reaches the tray.
    private var switchReversed: Bool { UserDefaults.standard.bool(forKey: Preferences.swipeToSwitchReversed) }

    /// The tray's row follows the fingers, giving way past either end.
    private func scrollTray(by delta: CGFloat) {
        let reach = trayReach
        var next = model.trayScroll - delta
        if next < 0 || next > reach { next = model.trayScroll - delta * 0.3 }
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) { model.trayScroll = min(max(next, -48), reach + 48) }
    }

    /// A wheel's notch: the row glides there, never past its ends. With Shift held, scrolling on
    /// past its end toward the player turns back to it, as Shift turns the pages everywhere else;
    /// only after a moment there, so a wheel spun along the row stops at its end first.
    private func wheelTray(by delta: CGFloat, switches: Bool) {
        // Toward the player: back along the row, or onward if the pages are turned around.
        let towardPlayer = delta != 0 && (delta < 0) == switchReversed
        let edge = switchReversed ? trayReach : 0
        if switches, towardPlayer, abs(model.trayScroll - edge) < 0.5 {
            if let since = trayEdgeSince, Date.now.timeIntervalSince(since) > Self.edgePause {
                trayEdgeSince = nil
                turn(to: .player)
            } else if trayEdgeSince == nil {
                trayEdgeSince = .now
            }
            return
        }
        let target = min(max(model.trayScroll - delta, 0), trayReach)
        trayEdgeSince = switches && towardPlayer && abs(target - edge) < 0.5 ? .now : nil
        guard target != model.trayScroll else { return }
        withAnimation(.smooth(duration: 0.2)) { model.trayScroll = target }
    }

    /// How long a wheel rests at the row's end before scrolling on turns the page.
    private static let edgePause = 0.25

    /// Back within the row's ends, springing.
    private func settleTray() {
        let target = min(max(model.trayScroll, 0), trayReach)
        guard target != model.trayScroll else { return }
        withAnimation(.smooth(duration: 0.35)) { model.trayScroll = target }
    }

    private var trayReach: CGFloat {
        Shelf.reach(count: Tray.shared.items.count, in: model.trayWidth)
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
        let width = model.restingWidth, height = model.restingHeight
        return CGRect(x: centerX - width / 2, y: topY - model.gap - height, width: width, height: height)
    }

    private func rect(for state: NotchState) -> CGRect {
        let m = model.metrics(for: state)
        return CGRect(x: centerX - m.totalWidth / 2, y: topY - model.gap - m.height, width: m.totalWidth, height: m.height)
    }

    /// Where the pointer counts as "on" the notch, or the bubbles beside it. Reaches slightly past
    /// the top edge.
    private var interactiveZone: CGRect {
        // Up to the top edge, over an island's gap too, so pushing the pointer to the top finds it.
        var resting = CGRect(
            x: restingRect.minX - 4, y: restingRect.minY - 4,
            width: restingRect.width + 8, height: restingRect.height + model.gap + 6)
        for side in [NotchModel.Side.trailing, .leading] {
            if let zone = bubbleZone(side) { resting = resting.union(zone) }
        }
        switch model.state {
        case .closed: return resting
        case .peek: return resting.union(rect(for: .peek))
        case .open:
            let open = rect(for: .open)
            return CGRect(x: open.minX, y: open.minY, width: open.width, height: open.height + 2)
        }
    }

    /// Where a bubble beside the notch is, while there's one (see `IslandBubble`), with the same
    /// margin as the notch's, up to the top edge.
    private func bubbleZone(_ side: NotchModel.Side) -> CGRect? {
        guard model.bubble(side) != nil else { return nil }
        let h = model.closedSize.height
        let off = model.metrics(for: .closed).bodyWidth / 2 + h * IslandBubble.gap
        let left = side == .trailing ? centerX + off : centerX - off - h
        return CGRect(x: left - 4, y: topY - model.gap - h - 4, width: h + 8, height: h + model.gap + 6)
    }

    /// The bubble at a point on the screen, if any.
    private func bubble(at p: CGPoint) -> NotchModel.Side? {
        [NotchModel.Side.trailing, .leading].first { bubbleZone($0)?.contains(p) == true }
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

/// A clear, borderless panel that floats above the menu bar. It can't be dragged, and it takes the
/// keyboard only while the notch is opened from it, as Spotlight's window does, without making
/// Glance the app in front.
final class NotchPanel: NSPanel {
    /// Opened with a shortcut: the notch has the keyboard until it closes.
    var takesKeys = false
    override var canBecomeKey: Bool { takesKeys }

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
    /// With where it is, in this view's points, and whether it came from the tray itself.
    var onDragMoved: (@MainActor (NSPasteboard, CGPoint, Bool) -> NSDragOperation)?
    var onDragExited: (@MainActor () -> Void)?
    var onDrop: (@MainActor (NSPasteboard, CGPoint, Bool) -> Bool)?
    private var dragOperation: NSDragOperation = []

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard frame.contains(point) else { return nil }
        let local = convert(point, from: superview)
        guard passesThrough?(local) == true else { return self }
        // A tray item gets its own clicks, found by where it is. Asked, SwiftUI could answer with
        // a layer over it that isn't even showing, and the click went nowhere, or a right-click to
        // the notch's own menu.
        return tile(at: local) ?? super.hitTest(point)
    }

    /// The tray item, on the page showing, at a point in this view's own points.
    private func tile(at point: CGPoint) -> TileInteractionView? {
        func search(_ view: NSView) -> TileInteractionView? {
            for child in view.subviews.reversed() {
                if let tile = child as? TileInteractionView {
                    if tile.live, tile.convert(tile.bounds, to: self).contains(point) { return tile }
                } else if let found = search(child) {
                    return found
                }
            }
            return nil
        }
        return search(self)
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

    // Drags from the tray itself have a source here; they're on their way out, and only the AirDrop
    // well takes them.
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { moved(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { moved(sender) }

    private func moved(_ sender: NSDraggingInfo) -> NSDragOperation {
        dragOperation =
            onDragMoved?(sender.draggingPasteboard, convert(sender.draggingLocation, from: nil), sender.draggingSource != nil) ?? []
        return dragOperation
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        dragOperation = []
        onDragExited?()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard !dragOperation.isEmpty else { return false }
        dragOperation = []
        return onDrop?(sender.draggingPasteboard, convert(sender.draggingLocation, from: nil), sender.draggingSource != nil) ?? false
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
