//
//  NotchView.swift
//  Glance
//
//  Created by Gaty on 07/10/2026.
//

import AppKit
import SwiftUI

enum NotchState {
    case closed  // resting: exactly the size of the hardware notch
    case peek  // pointer is on it: a small swell that says "I see you"
    case open  // fully expanded
}

/// macOS's Reduce Transparency and Increase Contrast settings, watched so the notch follows them as
/// they change.
@MainActor
final class SystemAccessibility: ObservableObject {
    static let shared = SystemAccessibility()
    @Published private(set) var reducesTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    @Published private(set) var increasesContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast

    /// Either one makes the notch opaque, as macOS makes its own glass then.
    var opaque: Bool { reducesTransparency || increasesContrast }

    private init() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                withAnimation(.easeInOut(duration: 0.4)) {
                    self?.reducesTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
                    self?.increasesContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
                }
            }
        }
    }
}

/// How the open notch's glass looks: from completely clear Liquid Glass to solid black, and from
/// no blur of what's behind it to a full one. Shared by the notch and the pictures of it in Settings.
enum GlassLook {
    /// How much the glass blurs what's behind it: none at all, so it shows through sharp, to a
    /// smear at 24 points (Liquid Glass's own is 10). Eased in, so the slider's first half covers
    /// the subtle blurs.
    static func blur(_ amount: Double) -> CGFloat { 24 * pow(min(max(amount, 0), 1), 1.5) }
    /// Even clear, the glass is dimmed by a third, as Apple dims clear glass over bright content, so
    /// the player's times and buttons read over a light window; eased in, so most of the way is
    /// glass and it turns opaque near the end. The top is black whatever this is.
    static let floor = 0.35
    static func black(_ darkness: Double) -> Double { floor + (1 - floor) * darkness * darkness }
}

/// The notch's corners follow its height. Closed, it matches the hardware notch: small flares out
/// into the screen's edge at the top, small rounded corners at the bottom, and swelling under the
/// pointer it stays so. Opening, both grow to the player's radius, easing in and out, so all four
/// corners match by the height of the shortest thing that opens.
struct NotchCorners: Equatable {
    var restingHeight: CGFloat
    var radius: CGFloat

    static let restingFlare: CGFloat = 6
    private static let restingBottomRadius: CGFloat = 12
    /// The height, by the notch's at rest, of the tray and the player, with their top corners the
    /// radius: what's shorter has them in proportion.
    private static let fullHeight: CGFloat = 4.625

    struct Radii {
        var flare: CGFloat
        var bottom: CGFloat
    }

    /// With wings out, their ends are round, half the height across, as the Dynamic Island's are.
    func radii(forHeight height: CGFloat, wingEnds: CGFloat = 0) -> Radii {
        let swollen = restingHeight + NotchModel.peekSwell
        let grown = min(max((height - swollen) / max(restingHeight * TimerLayout.tall - swollen, 1), 0), 1)
        let progress = grown * grown * (3 - 2 * grown)
        let bottom = Self.restingBottomRadius + (radius - Self.restingBottomRadius) * progress
        let flare = min(radius * height / (restingHeight * Self.fullHeight), radius)
        return Radii(
            flare: Self.restingFlare + (flare - Self.restingFlare) * progress,
            bottom: bottom + (min(height / 2, radius) - bottom) * wingEnds)
    }
}

/// The size the view draws for a given moment.
struct NotchMetrics {
    var bodyWidth: CGFloat
    var height: CGFloat
    /// How far the top corners flare out on each side.
    var flare: CGFloat
    /// How much of the trailing wing is folded away, back to the camera (see `NotchModel.detached`).
    var fold: CGFloat = 0

    var totalWidth: CGFloat { bodyWidth + flare * 2 }
}

@MainActor
final class NotchModel: ObservableObject {
    let closedSize: CGSize
    /// The display has a camera housing at the top, which nothing should be drawn under.
    let hasCamera: Bool
    /// The player's layout and its open size. They change together, animated, when the layout
    /// changes in Settings.
    @Published var layout: PlayerLayout
    @Published var openSize: CGSize
    let corners: NotchCorners
    /// Added to the open notch's width while the lyrics show beside the player.
    let lyricsWidth: CGFloat = 250
    /// The widest a wing gets while a new song is announced; longer titles scroll.
    static let maxPopWing: CGFloat = 150

    @Published var state: NotchState = .closed {
        didSet {
            // How far the closed notch had swollen under the pointer as it opened, for what grows out
            // of it to start where it was (see `grownSwell`).
            if state == .open, oldValue != .open { grownSwell = swell(in: oldValue) }
            // Closing, it shrinks back to where it's closing to: swollen still under the pointer, or at
            // rest, so what shrinks back lands where it shows beside the camera, with no jump as it
            // hands over.
            if oldValue == .open, state != .open { grownSwell = swell(in: state) }
        }
    }
    /// Opened by a click on the detached bubble, so it opens out of the bubble, and closes back into it.
    @Published var openedFromBubble = false
    /// The bubble ran back into the notch's end as the notch opened from the notch, as the iPhone's
    /// does, and buds off again once it has closed.
    @Published var bubbleMerged = false
    /// How far past its trailing end the notch reaches toward the bubble: as far as the bubble's far
    /// side as it opens out of it, or closes back into it, and nothing otherwise. One outline grows
    /// from there, so the notch and the bubble are one shape, not two.
    @Published var bubbleReach: CGFloat = 0
    /// From the notch's trailing end to the bubble's far side.
    var bubbleSpan: CGFloat { closedSize.height * (1 + IslandBubble.gap) }
    private var reachTask: Task<Void, Never>?
    /// How much larger the closed notch was than at rest as it opened, at each end and at the bottom:
    /// the pointer swells it, and what shows beside the camera rides with its ends.
    private(set) var grownSwell: CGFloat = 0

    /// How much the closed notch swells in a state, at each end and at the bottom.
    func swell(in state: NotchState) -> CGFloat {
        switch state {
        case .closed: Self.nearSwell * proximity
        case .peek where restingTall: 0
        case .peek: Self.peekSwell
        default: 0
        }
    }
    /// 0...1, how close the pointer is while the notch is closed.
    @Published var proximity: CGFloat = 0
    /// Rubber-band offset from scroll gestures, in points. Negative squashes the open notch.
    @Published var stretch: CGFloat = 0
    /// How far a drag across has stretched the notch sideways, either way, as it stretches down: a
    /// drag at a slant stretches it both ways at once.
    @Published var lean: CGFloat = 0
    /// What's in the notch stretches this much of what the notch does.
    static let contentGive: CGFloat = 0.5
    @Published var pressed = false
    /// Music is playing: the closed notch grows wings for the artwork and the waveform.
    @Published var activity = false {
        didSet { arrived(.music, activity) }
    }
    /// A new song started: the wings widen for a moment to show its title and artist.
    @Published var pop = false
    /// Each wing's width while a new song is announced: just enough for its title and artist.
    @Published var popWing: CGFloat = NotchModel.maxPopWing
    /// What the Mac announces (see Activities), and each wing's width for it: for a few seconds the
    /// wings show it, over whatever else they show.
    @Published var alert: NotchAlert?
    @Published var alertWing: CGFloat = 0
    /// With the pointer on a device being announced, it extends, as the iPhone's AirPods do.
    @Published var alertExtended = false
    var alertExtendedWing: CGFloat = 0
    /// Between what the wings show and what's announced, the notch folds to rest first and opens
    /// again from there, as the Dynamic Island switches between activities.
    @Published var switching = false
    /// A full-screen app covers this display: the notch keeps to the camera housing, with nothing
    /// beside it, and opens from there as usual.
    @Published var collapsed = false
    /// Nothing shows beside the camera for now.
    var folded: Bool { switching || collapsed }
    /// Clock's timer counting down beside the camera, and its stopwatch counting up (see
    /// `ClockActivity`); and each wing's width for the one in the notch.
    @Published var timer: NotchTimer.State? {
        didSet { arrived(.timer, timer != nil) }
    }
    @Published var stopwatch: Stopwatch? {
        didSet { arrived(.stopwatch, stopwatch != nil) }
    }
    @Published var timerWing: CGFloat = 0
    /// The timer's label, as named in Clock.
    @Published var timerName: String?
    /// The speaker or TV the sound plays on over AirPlay (see `AirPlayWatch`).
    @Published var airplay: AirPlayRoute? {
        didSet { arrived(.airplay, airplay != nil) }
    }
    /// A call, ringing or going on.
    @Published var call: CallShown? {
        didSet { arrived(.call, call != nil) }
    }
    /// The screen being recorded, and a voice memo being recorded (see `ScreenRecordingWatch` and
    /// `VoiceMemoWatch`).
    @Published var screenRecording: ScreenRecording? {
        didSet { arrived(.screenRecording, screenRecording != nil) }
    }
    @Published var voiceMemo: VoiceMemo? {
        didSet { arrived(.voiceMemo, voiceMemo != nil) }
    }
    /// A file coming in over AirDrop (see `AirDropWatch`).
    @Published var airdrop: AirDropShown? {
        didSet { arrived(.airdrop, airdrop != nil) }
    }
    /// The lyrics are wanted: the open notch widens to show them beside the player, while a song plays.
    @Published var lyrics = false
    /// What's playing is a song, which can have lyrics.
    @Published var songPlaying = false
    /// The welcome tour's pointer, showing how, in the notch's own points (see `demoPointer`).
    @Published var demoPointer: CGPoint?
    /// Which page the open notch shows: the player, or the tray.
    @Published var page: NotchPage = .player
    /// Where the keyboard is in the open player.
    let keys = PlayerKeys()
    /// Something is being dragged over the notch, to be dropped in the tray.
    @Published var dropping = false
    /// How far the tray's row is scrolled.
    @Published var trayScroll: CGFloat = 0
    /// How far a swipe to the other page has stretched the notch's width, and what's in it with it,
    /// before it goes.
    @Published var pageStretch: CGFloat = 0
    /// How many items the tray holds, which its width follows.
    @Published var trayItems = 0
    /// Some item's name in the tray takes two lines, which its height follows.
    @Published var trayNamesWrap = true
    /// The widest the tray grows: room for six items and half the next, or less on a narrow display.
    var trayMaxWidth = Shelf.peekWidth
    /// The tray on the player's grid: the padding either side of its first and last icons, as of the
    /// cover and the buttons, and under its row. As wide as its items, from three items' width,
    /// fewer sitting in the middle of it, up to `trayMaxWidth`, past which its row scrolls; and
    /// always wider than the camera with the padding either side. Empty, as wide as the player, for
    /// its words; with something dragged in, as wide as the compact player, Cover on top, whatever
    /// the player's layout, for its two places to drop.
    var trayWidth: CGFloat {
        if dropping { return PlayerLayout.top.size(closed: closedSize).width }
        let least = trayItems == 0 ? openSize.width : max(Shelf.narrowest, closedSize.width + PlayerLayout.padding * 2)
        return min(max(Shelf.width(count: trayItems), least), max(trayMaxWidth, least))
    }

    /// The tray's row follows the fingers, giving way past either end.
    func slideTray(by delta: CGFloat, reach: CGFloat) {
        var next = trayScroll - delta
        if next < 0 || next > reach { next = trayScroll - delta * 0.3 }
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) { trayScroll = min(max(next, -48), reach + 48) }
    }

    /// Back within the row's ends, springing.
    func settleTray(reach: CGFloat) {
        let target = min(max(trayScroll, 0), reach)
        guard target != trayScroll else { return }
        withAnimation(.smooth(duration: 0.35)) { trayScroll = target }
    }

    /// Its row just below the camera, as the player's column below it starts, and the padding under it.
    var trayHeight: CGFloat {
        closedSize.height + PlayerLayout.cameraGap + Shelf.rowHeight(wrapping: trayNamesWrap || dropping) + PlayerLayout.padding
    }
    /// Where AirDrop's place to drop is, in the notch's points, while it shows; and whether something
    /// dragged is over it.
    var airDropFrame: CGRect?
    @Published var airDropTargeted = false

    /// The lyrics show only for a song, on the player; for a video, a podcast or nothing at all
    /// they fold away, and come back with the next song.
    var showsLyrics: Bool { lyrics && songPlaying && page == .player }
    /// How far a sideways swipe has pushed the artwork, before it skips.
    @Published var nudge: CGFloat = 0
    /// Where the player's buttons sit, so the window can hand clicks there to them.
    var controlFrames: [CGRect] = []
    /// Where a timer that's done has its buttons, which work in the closed notch, and which one the
    /// pointer is on.
    var alertButtons: [AlertButton: CGRect] = [:]
    @Published var hoveredButton: AlertButton?

    /// Opened to an activity's own view, as the Dynamic Island expands one, rather than to the
    /// player: AirDrop, the timer, the stopwatch, or AirPlay.
    @Published var expanded: Activity?

    /// What can show at once: a call, the screen being recorded, a voice memo being recorded, music, a
    /// file coming in over AirDrop, Clock's timer, its stopwatch, AirPlay.
    enum Activity: String, Hashable {
        case call, screenRecording, voiceMemo, music, airdrop, timer, stopwatch, airplay
    }

    /// When each one going on started, in turn: as on the iPhone, they take the notch first come,
    /// first served, whatever they are. One that ends and starts again goes to the back.
    private var arrivals: [Activity: Int] = [:]
    private var arrivalCount = 0

    /// The order they started in is kept for when Glance opens again, or the notch is made again: one
    /// still going takes its place back as it's found, if that's soon after (see `keepsOrder`). Only
    /// the notch on the screen keeps it, not Settings' pictures of it or a test's.
    var keepsOrder = false {
        didSet { if keepsOrder, !oldValue { restoreOrder() } }
    }
    /// Each activity going on before, by its place then, all before anything new.
    private var restoredOrder: [Activity: Int] = [:]
    private var restoredUntil = Date.distantPast
    /// How long after the notch is made what was going on before is waited for: a call in another
    /// app takes a few seconds to be found again.
    static let restoreWindow: TimeInterval = 30
    static let orderKey = "activityOrder"

    private func restoreOrder() {
        let saved = (UserDefaults.standard.stringArray(forKey: Self.orderKey) ?? []).compactMap(Activity.init(rawValue:))
        restoredOrder = Dictionary(saved.enumerated().map { ($1, $0 - saved.count) }, uniquingKeysWith: { first, _ in first })
        restoredUntil = .now + Self.restoreWindow
        // Any found already take their places back too.
        for (activity, place) in restoredOrder where arrivals[activity] != nil {
            arrivals[activity] = place
            restoredOrder[activity] = nil
        }
        saveOrder()
    }

    private func arrived(_ activity: Activity, _ present: Bool) {
        guard present else {
            arrivals[activity] = nil
            return saveOrder()
        }
        guard arrivals[activity] == nil else { return }
        if Date.now < restoredUntil, let place = restoredOrder.removeValue(forKey: activity) {
            arrivals[activity] = place
        } else {
            arrivalCount += 1
            arrivals[activity] = arrivalCount
        }
        saveOrder()
    }

    /// Those going on, in the order they started, with any still waited for from before in their
    /// places among them.
    private func saveOrder() {
        guard keepsOrder else { return }
        let waiting = Date.now < restoredUntil ? restoredOrder : [:]
        let order = arrivals.merging(waiting) { now, _ in now }.sorted { $0.value < $1.value }.map(\.key.rawValue)
        UserDefaults.standard.set(order, forKey: Self.orderKey)
    }

    /// Swiped away, each until it changes: Clock's timer or stopwatch, AirDrop, AirPlay. Music's
    /// goes with `activity`.
    @Published var dismissed: Set<Activity> = []

    /// Those showing now, in the order they started: every one going on, whatever else is. The first
    /// has the notch, the second is detached beside it, and the rest wait their turn.
    var activities: [Activity] {
        var shown: [Activity] = []
        if call != nil { shown.append(.call) }
        if screenRecording != nil { shown.append(.screenRecording) }
        if voiceMemo != nil { shown.append(.voiceMemo) }
        if activity { shown.append(.music) }
        if airdrop != nil { shown.append(.airdrop) }
        if timer != nil { shown.append(.timer) }
        if stopwatch != nil { shown.append(.stopwatch) }
        if airplay != nil { shown.append(.airplay) }
        return shown.filter { !dismissed.contains($0) }.enumerated()
            .sorted { (arrivals[$0.element] ?? .max, $0.offset) < (arrivals[$1.element] ?? .max, $1.offset) }.map(\.element)
    }

    /// Music has the notch's wings: it comes first. Second, it's detached beside the notch.
    var musicShown: Bool { activities.first == .music }

    /// An activity's timer or stopwatch, if it's one.
    func clock(of activity: Activity) -> ClockShown? {
        switch activity {
        case .call, .screenRecording, .voiceMemo, .music, .airdrop, .airplay: nil
        case .timer: timer.map(ClockShown.timer)
        case .stopwatch: stopwatch.map(ClockShown.stopwatch)
        }
    }

    /// Opened to a recording: Voice Memos as wide as the iPhone's island, the screen recording as its
    /// time needs.
    func openWidth(of recording: Recording) -> CGFloat {
        switch recording {
        case .voiceMemo: RecordingLook.memoWidth(restingHeight: closedSize.height, camera: camera)
        case .screen(let screen): RecordingLook.screenWidth(restingHeight: closedSize.height, camera: camera, length: screen.length())
        }
    }

    /// What the notch or its bubble shows has nothing to open to, as the screen recording's
    /// countdown hasn't, the iPhone's having no opened view of it: the pointer swells it, as it does
    /// Charging, but neither resting on it nor a click opens it.
    func opensToNothing(fromBubble onBubble: Bool) -> Bool {
        guard alert == nil, (onBubble ? detached : nil) ?? activities.first == .screenRecording, case .countdown? = screenRecording else {
            return false
        }
        return true
    }
    var opensToNothing: Bool { opensToNothing(fromBubble: false) }

    /// The pointer swells it, as it does whatever shows beside the camera; not what's as tall as the
    /// Alarm, which is as large as it gets already.
    var swells: Bool { !restingTall }

    /// An activity's recording, if it's one.
    func recording(of activity: Activity) -> Recording? {
        switch activity {
        case .screenRecording: screenRecording.map(Recording.screen)
        case .voiceMemo: voiceMemo.map(Recording.voiceMemo)
        default: nil
        }
    }

    /// The timer or stopwatch in the notch, when one comes first; the first of them, which has the
    /// notch once nothing plays.
    var notchClock: ClockShown? { activities.first.flatMap(clock(of:)) }
    var firstClock: ClockShown? { timer.map(ClockShown.timer) ?? stopwatch.map(ClockShown.stopwatch) }

    /// The Dynamic Island's minimal presentation. One activity has both sides of the camera; with
    /// more, two show: the first attached to the notch, by its leading side alone, and this one
    /// detached off its trailing side (see `IslandBubble`). Any others wait their turn. None while
    /// the notch is open, something else is announced, or a new song's name shows: it runs back into
    /// the notch while it does.
    var detached: Activity? {
        guard state != .open, alert == nil, !folded, !(musicShown && pop) else { return nil }
        return second
    }

    /// The second of those showing, which is detached while the notch is closed.
    var second: Activity? { activities.dropFirst().first }

    /// What opening shows, as the Dynamic Island expands what was clicked: the detached activity,
    /// or the notch's. Nil for music, which opens to the player.
    func expansion(fromBubble onBubble: Bool) -> Activity? {
        let activity = (onBubble ? detached : nil) ?? activities.first
        return activity == .music ? nil : activity
    }

    /// The timer or stopwatch opened to, and the room the camera takes in the middle of its row.
    var expandedClock: ClockShown? { expanded.flatMap(clock(of:)) }
    /// What the notch was opened to has gone: the timer ended, the stopwatch was reset, or the sound
    /// left AirPlay.
    var expandedGone: Bool {
        switch expanded {
        case .timer, .stopwatch: expandedClock == nil
        case .airplay: airplay == nil
        case .call: call == nil
        case .screenRecording: screenRecording == nil
        case .voiceMemo: voiceMemo == nil
        case .airdrop: airdrop == nil
        case .music, nil: false
        }
    }
    /// Its name as it shows and as VoiceOver says it: Timer, unless it was given a label in Clock,
    /// or Stopwatch.
    func name(of activity: Activity) -> String {
        switch activity {
        case .call: call?.name ?? String(localized: "Call")
        case .screenRecording: String(localized: "Screen Recording")
        case .voiceMemo: String(localized: "Voice Memo")
        case .music: String(localized: "Music")
        case .timer: timerName ?? String(localized: "Timer")
        case .stopwatch: String(localized: "Stopwatch")
        case .airplay: "AirPlay"
        case .airdrop: "AirDrop"
        }
    }
    var camera: CGFloat { closedSize.width }

    /// The pointer is on the detached activity, which swells a little, or pressing it, which squeezes.
    @Published var bubbleHovered = false
    @Published var bubblePressed = false
    /// Opens the detached activity, or the notch's own, as a click on it does, for VoiceOver (set by
    /// the notch's controller).
    var openBubble: () -> Void = {}
    var openNotch: () -> Void = {}

    /// Turning the notch off and on, 0 to 1: a notch on a display without one folds up into the top
    /// edge.
    @Published var vanish: CGFloat = 0

    init(closedSize: CGSize, layout: PlayerLayout, hasCamera: Bool) {
        self.closedSize = closedSize
        self.hasCamera = hasCamera
        self.layout = layout
        let openSize = layout.size(closed: closedSize)
        self.openSize = openSize
        corners = NotchCorners(restingHeight: closedSize.height, radius: TimerLayout.tallHeight(closedSize.height) / 2)
    }

    /// Switches to another layout in place.
    func use(_ layout: PlayerLayout) {
        self.layout = layout
        openSize = layout.size(closed: closedSize)
    }

    /// Each side of the camera while music plays: as wide as the artwork's square needs, right up to
    /// the camera, or wider while a new song is announced; as wide as an announcement or a timer
    /// needs, against the camera too.
    var wing: CGFloat {
        let resting = LiveActivityView.restingWing(restingHeight: closedSize.height)
        if folded { return 0 }
        if alert != nil { return max(alertExtended ? alertExtendedWing : alertWing, resting) }
        // With another detached, the first keeps its own side as it is; its trailing side folds away
        // (see `NotchMetrics.fold`), the other taking its place in a bubble.
        if activities.first == .call, let call { return CallLayout.wing(for: call, restingHeight: closedSize.height) }
        if let recording = activities.first.flatMap(recording(of:)) { return RecordingLook.wing(for: recording, restingHeight: closedSize.height) }
        if activity, pop { return max(popWing, resting) }
        // A timer or the stopwatch with the notch. AirPlay's symbols take the cover's squares.
        if notchClock != nil { return max(timerWing, resting) }
        return activities.isEmpty ? 0 : resting
    }

    /// The closed notch's width, with the activity's wings while music plays, a timer runs, or
    /// something's announced.
    var restingWidth: CGFloat { closedSize.width + wing * 2 }

    /// What's announced is as tall as the Dynamic Island's Alarm (see `NotchAlert.tall`).
    var restingTall: Bool { alert.map { $0.tall || alertExtended } == true && !folded }

    /// The closed notch's height: more than twice as tall while what's announced is.
    var restingHeight: CGFloat { restingTall ? TimerLayout.tallHeight(closedSize.height) : closedSize.height }

    /// Open on an activity's own view, rather than the player or the tray.
    var expandedShown: Bool { state == .open && expanded != nil }

    var metrics: NotchMetrics { metrics(for: state) }

    /// How much the closed notch swells under the pointer, and as the pointer nears: as much at its
    /// ends as at its bottom, so what its wings show keeps the same padding all round.
    static let peekSwell: CGFloat = 7
    static let nearSwell: CGFloat = 3

    /// The notch's size in this state; `short`, as if what's announced weren't taller than it.
    func metrics(for state: NotchState, short: Bool = false) -> NotchMetrics {
        let pull = max(stretch, 0)
        let across = abs(lean)
        let resting = short ? closedSize.height : restingHeight
        let near = swells ? proximity : 0
        let (bodyWidth, height): (CGFloat, CGFloat) =
            switch state {
            case .closed:
                (
                    restingWidth + 2 * Self.nearSwell * near + pull * 0.4 + across,
                    resting + Self.nearSwell * near + pull
                )
            // Tall already, it's as large as it gets under the pointer.
            case .peek where !swells: (restingWidth + pull * 0.4 + across, resting + pull)
            case .peek: (restingWidth + 2 * Self.peekSwell + pull * 0.4 + across, resting + Self.peekSwell + pull)
            case .open where expanded == .airdrop:
                (
                    AirDropLayout.width(restingHeight: closedSize.height, camera: camera) + pull * 0.35 + across,
                    TimerLayout.tallHeight(closedSize.height) + pull
                )
            case .open where expanded == .call:
                (
                    ExpandedCallView.width(
                        for: call ?? CallShown(name: "", over: "", phase: .ringing), restingHeight: closedSize.height, closedWidth: closedSize.width)
                        + pull * 0.35 + across,
                    ExpandedCallView.height(for: call ?? CallShown(name: "", over: "", phase: .ringing), restingHeight: closedSize.height) + pull
                )
            case .open where expanded == .airplay:
                (
                    ExpandedAirPlayView.width(for: airplay ?? AirPlayRoute(name: "", symbol: ""), restingHeight: closedSize.height)
                        + pull * 0.35 + across,
                    AirPlayLayout.height(closedSize.height) + pull
                )
            case .open where expanded.flatMap(recording(of:)) != nil:
                (
                    expanded.flatMap(recording(of:)).map(openWidth(of:)).map { $0 + pull * 0.35 + across } ?? 0,
                    TimerLayout.tallHeight(closedSize.height) + pull
                )
            case .open where expanded != nil:
                (
                    ExpandedTimerView.width(
                        for: expandedClock ?? .timer(.paused(left: 0, total: 0)), name: expanded.map(name(of:)) ?? String(localized: "Timer"),
                        restingHeight: closedSize.height, camera: camera)
                        + pull * 0.35 + across,
                    TimerLayout.tallHeight(closedSize.height) + pull
                )
            case .open where page == .tray: (trayWidth + pull * 0.35 + pageStretch + across, trayHeight + pull)
            case .open: (openSize.width + (showsLyrics ? lyricsWidth : 0) + pull * 0.35 + pageStretch + across, openSize.height + pull)
            }
        // Pressed, it squeezes a little toward the top: made smaller rather than shrunk as a picture,
        // which the glass, sized afresh with the notch, doesn't follow.
        let press: CGFloat = pressed ? 0.975 : 1
        let flare = corners.radii(forHeight: height * press).flare
        return NotchMetrics(bodyWidth: bodyWidth * press, height: height * press, flare: flare, fold: state == .open || detached == nil ? 0 : max(wing - pastHousing, 0))
    }

    /// With another detached, how far the notch's folded end reaches past the camera housing: far
    /// enough that its own corner, as round as the other end's, covers the housing's rounder-cut one,
    /// which would otherwise show at that end. Measured: a quarter more than the two corners differ, as
    /// their curves ease into the sides.
    var pastHousing: CGFloat {
        let h = closedSize.height
        return max(corners.radii(forHeight: h, wingEnds: 1).bottom - corners.radii(forHeight: h, wingEnds: 0).bottom, 0) * 1.25
    }
}

/// The Dynamic Island's bounce as its activities expand: past its size, by about a twentieth, and
/// back, a bounce that's seen. With Reduce Motion on, straight to its size.
enum NotchMotion {
    /// How fast the notch's motions run: 1 always, but slower in a test that films them a frame
    /// at a time.
    nonisolated(unsafe) static var pace: Double = 1
}

extension Animation {
    /// At the notch's pace: as it is, unless a test films it slower.
    var paced: Animation { NotchMotion.pace == 1 ? self : speed(NotchMotion.pace) }
}

extension NotchMotion {
    static var expand: Animation {
        (NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? Animation.spring(response: 0.42, dampingFraction: 1) : .spring(response: 0.5, dampingFraction: 0.68)).paced
    }

    /// A spring that bounces, or with Reduce Motion on, that settles straight where it's going.
    static func spring(
        response: Double, dampingFraction: Double, reduced: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    ) -> Animation {
        .spring(response: response, dampingFraction: reduced ? 1 : dampingFraction).paced
    }
}

/// How the notch moves between its states, the same on screen and in Settings' preview.
extension NotchModel {
    func peek() {
        withAnimation(NotchMotion.spring(response: 0.3, dampingFraction: 0.6)) { state = .peek }
    }

    /// Closed → a device extended, the notch and what it shows in one motion.
    func extend() {
        withAnimation(NotchMotion.expand) {
            state = .peek
            alertExtended = true
        }
    }

    /// Peek → closed, when the pointer slides off before the notch opens. A device extended folds with
    /// it, as an activity folds, without a bounce.
    func settle(closeness: CGFloat) {
        withAnimation(alertExtended ? IslandMotion.fold : NotchMotion.spring(response: 0.35, dampingFraction: 0.8)) {
            state = .closed
            alertExtended = false
            proximity = Self.eased(closeness)
        }
    }

    /// With the Dynamic Island's spring, as its activities expand (see `NotchMotion`).
    func open() {
        reachTask?.cancel()
        withAnimation(NotchMotion.expand) {
            state = .open
            proximity = 0
            pop = false
            bubbleReach = 0
        }
    }

    func close() {
        // What's open is the bubble's, and it goes back out into the bubble as the notch closes.
        let intoBubble = openedFromBubble && second != nil && alert == nil && !folded
        // Folding as the Dynamic Island's activities fold, from whatever's open: no bounce.
        withAnimation(IslandMotion.fold) {
            state = .closed
            stretch = 0
            if intoBubble { bubbleReach = bubbleSpan }
        }
        openedFromBubble = false
        guard intoBubble else { return }
        // Closed back into the bubble, the notch's end draws back from it, as it does when an
        // activity first goes out into the bubble.
        reachTask?.cancel()
        reachTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(380))
            guard let self, !Task.isCancelled, state == .closed else { return }
            withAnimation(IslandMotion.fold) { bubbleReach = 0 }
        }
    }

    /// Squeezed while pressed; let go, it springs back.
    func press(_ down: Bool) {
        withAnimation(down ? NotchMotion.spring(response: 0.2, dampingFraction: 0.7) : NotchMotion.spring(response: 0.4, dampingFraction: 0.5)) { pressed = down }
    }

    /// The closed notch swells a little as the pointer comes near: `closeness` from 0, far, to 1,
    /// on it.
    func approach(_ closeness: CGFloat) {
        let value = Self.eased(closeness)
        guard abs(value - proximity) > 0.01 || (value == 0 && proximity != 0) else { return }
        withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.8)) { proximity = value }
    }

    private static func eased(_ closeness: CGFloat) -> CGFloat {
        let t = min(max(closeness, 0), 1)
        return t * t * (3 - 2 * t)
    }
}

extension CGRect {
    /// How far a point is outside the rectangle; 0 inside it.
    func distance(to p: CGPoint) -> CGFloat {
        hypot(max(minX - p.x, 0, p.x - maxX), max(minY - p.y, 0, p.y - maxY))
    }
}

/// The artwork and the waveform exist once each and fly between their places in the closed notch
/// and the open player, as on the iPhone. Those places are marked with these ids.
enum Hero: Hashable {
    case liveArtwork, openArtwork, liveWaveform, openWaveform
}

struct NotchView: View {
    @ObservedObject var model: NotchModel
    @EnvironmentObject private var nowPlaying: NowPlaying
    @ObservedObject private var accessibility = SystemAccessibility.shared
    // Each display's own look.
    @AppStorage private var followsSystem: Bool
    @AppStorage private var chosenDarkness: Double
    @AppStorage private var blur: Double
    @AppStorage private var chosenBackground: MusicBackground
    /// Shown instead of the display's own background, for Settings' pictures of each one.
    private let backgroundShown: MusicBackground?
    /// In Settings' picture of the player, nothing in it responds.
    @Environment(\.controlPlaces) private var places
    /// Settings' pictures on pages not shown hold still.
    @Environment(\.notchPaused) private var paused
    /// Whether there are lyrics at all.
    @AppStorage(Preferences.lyrics) private var lyricsOn = true
    @Environment(\.notchThumbnail) private var thumbnail
    /// With Reduce Motion on, the player and the tray swap with a fade, without sliding.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(Preferences.tray) private var trayOn = true
    /// The tray shown: Glance's own, or the welcome tour's made-up one.
    @Environment(\.tray) private var trayStore
    @Namespace private var hero
    @AppStorage(Preferences.musicAccentSource) private var accentSource = AccentSource.artwork

    init(model: NotchModel, display: String, background: MusicBackground? = nil) {
        self.model = model
        func key(_ name: String) -> String { Preferences.lookKey(name, display: display) }
        _followsSystem = AppStorage(wrappedValue: false, key(Preferences.glassFollowsSystem))
        _chosenDarkness = AppStorage(wrappedValue: 0, key(Preferences.glassDarkness))
        _blur = AppStorage(wrappedValue: 0, key(Preferences.glassBlur))
        _chosenBackground = AppStorage(wrappedValue: .none, key(Preferences.musicBackground))
        self.backgroundShown = background
    }

    private var background: MusicBackground { backgroundShown ?? chosenBackground }

    /// With Reduce Transparency or Increase Contrast on, the notch is opaque whatever its setting.
    /// With the system's Liquid Glass, the glass itself is as dark as macOS makes it.
    private var darkness: Double {
        accessibility.opaque ? 1 : followsSystem ? 0 : min(max(chosenDarkness, 0), 1)
    }

    var body: some View {
        let m = model.metrics
        let isOpen = model.state == .open
        // Open on an activity's own view, which shows instead of the player or the tray.
        let expandedShown = model.expandedShown
        let tall = isOpen ? model.expanded != nil : model.restingTall
        let shape = NotchShape(corners: model.corners, wingEnds: model.wing > 0 ? 1 : 0, fold: m.fold)
        let onTray = model.page == .tray
        // Open on the player, rather than on the tray.
        let heroOpen = isOpen && !expandedShown
        let playerShown = heroOpen && !onTray
        let trayShown = heroOpen && onTray
        let closed = model.closedSize
        // Hidden at rest so no glass rim glints around the hardware notch; closed, it's black.
        let visible: Double = model.state != .closed || tall ? 1 : 0
        // With Increase Contrast on, the colors stay, darker (see `contrastDim`).
        let lit = playerShown && nowPlaying.artwork != nil && background != .none
        let lyricsShown = heroOpen && model.showsLyrics
        // The closed notch swells under the pointer, and the artwork and waveform with it, their
        // padding too.
        let swell = isOpen ? 1 : m.height / model.restingHeight

        ZStack(alignment: .top) {
            shade
            // The artwork's light: in place of the glass, it fills the bottom and fades out under the
            // black at the top, just where the glass shows; as a spotlight, it's a soft circle that
            // comes out of the cover and travels round the open notch, its colors turning. Choosing
            // between them morphs one into another.
            let travels = background == .spotlight && !reduceMotion
            LightClock(running: travels && lit && isOpen && !paused && nowPlaying.isPlaying, shown: lit) { travelled in
                let spot = spotlightCenter(m, travelled: travels ? travelled : 0)
                ArtworkLight(
                    dim: accessibility.increasesContrast ? Self.contrastDim : background == .spotlight ? 0 : Self.colorsDim,
                    active: isOpen && !paused, spread: lightSpread
                )
                .frame(width: lightSize.width, height: lightSize.height)
                .rotationEffect(
                    .radians(travels ? travelled * Self.spotlightTurn : 0),
                    anchor: UnitPoint(x: spot.x / lightSize.width, y: spot.y / lightSize.height)
                )
                .mask {
                    // It comes in as it's turned on or the notch opens: the background washing out of
                    // the notch until it fills it, the spotlight popping out of the cover.
                    lightShape(m, grown: lit, fills: background != .spotlight, spot: spot)
                        .animation(lightGrowth(lit, fills: background != .spotlight), value: lit)
                }
                .mask { insideTheEdges(m, spotlight: background == .spotlight) }
                .mask { belowTheBlack(lifted: background != .replaceGlass) }
                .mask { awayFromCamera }
            }
            .animation(lit ? .easeOut(duration: 0.5).delay(0.1) : .easeOut(duration: 0.2)) {
                $0.opacity(lit ? lightOpacity : 0)
            }
            .animation(.easeInOut(duration: 0.5), value: nowPlaying.isPlaying)
            // As wide as the notch is at each step, so what the wings show rides in and out with their
            // ends, as the Dynamic Island's activities do.
            LiveActivityView(restingHeight: closed.height, wing: model.wing, pop: model.pop, swell: swell)
                .atNotchStep(width: m.bodyWidth, height: m.height)
                .allowsHitTesting(places == nil)
                .islandFade(liveShown)
            // What the Mac announces, and a timer, in the same wings.
            SystemActivityView(
                restingHeight: closed.height, closedWidth: closed.width, wing: model.wing, alert: model.collapsed ? nil : model.alert,
                clock: model.musicShown || model.folded ? nil : model.notchClock,
                route: model.activities.first == .airplay && !model.folded ? model.airplay : nil,
                airdrop: model.activities.first == .airdrop && !model.folded ? model.airdrop : nil,
                call: model.activities.first == .call && !model.folded ? model.call : nil,
                recording: model.folded ? nil : model.activities.first.flatMap(model.recording(of:)),
                timerName: model.activities.first.map(model.name(of:)) ?? String(localized: "Timer"),
                leadingOnly: model.detached != nil, grown: isOpen && grownFrom != nil, hoveredButton: model.hoveredButton,
                open: { model.openNotch() },
                extended: model.alertExtended,
                notch: CGSize(width: m.bodyWidth, height: m.height)
            )
            .atNotchStep(width: m.bodyWidth, height: m.height)
            .allowsHitTesting(false)
            // What grew out of it takes over and hands back on its own (see `GrownAway`): faded here
            // too, it would dim for a moment as it hands back. AirDrop's symbol has nothing opened to
            // hand back from, so it fades.
            .islandFade(!isOpen || (grownFrom != nil && model.expanded != .airdrop))
            // The notch at rest, sharp, over what the wings show, as the Dynamic Island keeps its own
            // shape over an activity coming or going: what rides in with the wings' ends as they fold
            // passes under it. Kept at the closed size while open, so closing it never shrinks from the
            // open notch's height over the glass, and back only once the notch has all but closed.
            // Never taller than the notch itself, so what's announced below the camera shows; a device
            // extended, than the camera, as its words run just under it.
            let rest = isOpen ? model.metrics(for: .closed) : m
            let restHeight = model.alertExtended ? closed.height : min(rest.height, model.metrics(for: isOpen ? .closed : model.state, short: true).height)
            NotchShape(corners: model.corners).fill(.black)
                .frame(width: model.closedSize.width + model.corners.radii(forHeight: restHeight).flare * 2, height: restHeight)
                .frame(width: m.totalWidth, height: m.height, alignment: .top)
                .allowsHitTesting(false)
                .animation(isOpen ? .easeOut(duration: 0.1) : .easeOut(duration: 0.1).delay(0.2)) { $0.opacity(isOpen ? 0 : 1) }
            Group {
                expandedTimer(shown: expandedShown)
                expandedAirPlay(shown: expandedShown)
                expandedCall(shown: expandedShown)
                expandedAirDrop(shown: expandedShown)
                expandedRecording(shown: expandedShown)
            }
            // With another detached, the trailing side showed nothing beside the camera.
            .environment(\.trailingGrows, model.second == nil)
            // Laid out at their open sizes so they never reflow; the growing shape reveals them.
            // With the lyrics, the notch widens both ways: the player takes the left, the lyrics the
            // right. They start below the camera, which sits over their left side, and the line
            // being sung sits level with the middle of the notch.
            LyricsView(store: nowPlaying.lyricsStore, isVisible: lyricsShown, middle: model.openSize.height / 2 - lyricsTop)
                .frame(width: model.lyricsWidth, height: model.openSize.height - lyricsTop * 2 + model.closedSize.height)
                .padding(.leading, model.openSize.width)
                .padding(.top, lyricsTop)
                .frame(width: m.totalWidth, height: m.height, alignment: .top)
                .mask { awayFromCamera }
                // Shown or hidden with the lyrics button, they fade; with the notch, they come and go
                // as every opened view does.
                .animation(Self.fade(in: model.showsLyrics)) { $0.opacity(model.showsLyrics ? 1 : 0).blur(radius: model.showsLyrics ? 0 : 4) }
                .modifier(IslandReveal(hidden: !heroOpen))
                .allowsHitTesting(places == nil)
            // The player and the tray side by side, as pages are: going to the tray, the player
            // slides off to the left as the tray comes in from the right, and back. The tray stays
            // here turned off, to slide away: not showing, it costs nothing (see `TrayView`).
            NowPlayingView(isVisible: playerShown && !paused, hero: hero)
                .environment(
                    \.playerOnLight,
                    lit && background == .replaceGlass && !accessibility.increasesContrast && nowPlaying.flow(from: accentSource)?.isLight == true
                )
                .frame(width: model.openSize.width, height: model.openSize.height)
                .padding(.trailing, model.showsLyrics ? model.lyricsWidth : 0)
                .environment(\.notchControls, playerShown)
                .offset(x: onTray ? -pageShift : 0)
                // Sliding to the tray, it fades; opening and closing, it comes and goes as every
                // opened view does, the Dynamic Island's expanded activities' way.
                .modifier(PageFade(hidden: onTray))
                .modifier(IslandReveal(hidden: !heroOpen))
            TrayView(
                tray: tray, isVisible: trayShown && !paused, dropping: model.dropping, scroll: model.trayScroll,
                airDropTargeted: model.airDropTargeted
            )
            .frame(width: model.trayWidth, height: model.trayHeight)
            .environment(\.notchControls, trayShown)
            .offset(x: onTray ? 0 : pageShift)
            .modifier(PageFade(hidden: !onTray))
            .modifier(IslandReveal(hidden: !heroOpen))
            .allowsHitTesting(places == nil && trayShown)
            restingPlaces(m, swell: swell)
            // Its corners round as the notch's do, swollen or not.
            HeroArtwork(isOpen: heroOpen, restingSide: (closed.height - LiveActivityView.inset * 2) * swell)
                .matchedGeometryEffect(id: heroOpen ? Hero.openArtwork : Hero.liveArtwork, in: hero, isSource: false)
                .offset(x: model.nudge)
                // There open, or in the closed notch while something plays, coming and going as the
                // Dynamic Island's activities do, as everything in the notch does.
                .islandFade(heroOpen || artworkShown && !expandedShown)
                .modifier(PageFade(hidden: heroOpen && onTray))
                .environment(\.notchControls, !trayShown)
                .allowsHitTesting(places == nil && !trayShown)
            HeroWaveform(
                isOpen: heroOpen, lyricsShown: model.showsLyrics, lyricsAvailable: model.songPlaying && lyricsOn,
                toggleLyrics: toggleLyrics
            )
            .matchedGeometryEffect(id: heroOpen ? Hero.openWaveform : Hero.liveWaveform, in: hero, isSource: false)
            // There open, or in the closed notch while something plays, out of the way when a new
            // song's artist takes its place, coming and going as the Dynamic Island's activities do.
            .islandFade(heroOpen || waveformShown && !expandedShown)
            .modifier(PageFade(hidden: heroOpen && onTray))
            .environment(\.notchControls, !trayShown)
            .allowsHitTesting(places == nil && !trayShown)
        }
        .environment(\.closedNotch, closed)
        .environment(\.playerLayout, model.layout)
        .environment(\.lyricsControl, LyricsControl(shown: model.showsLyrics, available: model.songPlaying && lyricsOn, toggle: toggleLyrics))
        .environment(\.playerKeys, model.keys)
        // Turned off, any lyrics showing fold away.
        .onChange(of: lyricsOn) {
            if !lyricsOn { withAnimation(NotchMotion.expand) { model.lyrics = false } }
        }
        // Turned off while it shows, the tray slides away for the player, as swiping to it does.
        .onChange(of: trayOn) {
            if !trayOn, model.page == .tray { withAnimation(.spring(response: 0.4, dampingFraction: 1)) { model.page = .player } }
        }
        // Liquid Glass takes a new size at once, while a frame's size otherwise animates only in
        // the picture, so the glass and the notch's black and outline would part as it changes size
        // (opening, a new layout, the lyrics coming or going). Laid out afresh at every step, the
        // whole notch, glass and all, keeps together.
        // What's in it stays where it is while the notch reaches out to the bubble.
        .offset(x: -model.bubbleReach / 2)
        .modifier(SteppedFrame(width: m.bodyWidth + model.bubbleReach, height: m.height, corners: model.corners, least: model.collapsed ? .zero : model.closedSize))
        .coordinateSpace(.named(Self.bodySpace))
        .environment(\.demoPointer, model.demoPointer)
        // Stretched sideways, what's in it stretches with it, staying where it is.
        // Pulled down, too, what's in it stretches with it.
        // Less than the notch does, so it gives a little rather than stretching as far.
        .scaleEffect(contentStretch(m), anchor: .top)
        .clipShape(shape)
        // The second activity, detached off the notch's trailing end. Behind the notch, so in its
        // end, all of it is hidden there, under what the notch shows.
        .background(alignment: .top) { bubble(m).offset(x: -model.bubbleReach / 2) }
        .background {
            ZStack {
                if thumbnail {
                    // Liquid Glass can't be drawn this small: its rim and refraction stay their full
                    // size and smear. So it's drawn as it looks from afar, a veil with a bright rim.
                    let system = followsSystem && !accessibility.opaque
                    shape.fill(.white.opacity((system ? 0.14 : 0.06) * (1 - GlassLook.black(darkness)) * visible))
                    shape.fill(.black.opacity((system ? 0.2 : GlassLook.black(darkness)) * visible))
                    shape.stroke(.white.opacity(0.3 * (1 - GlassLook.black(darkness)) * visible), lineWidth: 3)
                        .mask { WithoutFlares(flare: m.flare) }
                } else if followsSystem && !accessibility.opaque {
                    // Liquid Glass as macOS draws it everywhere, as set in Appearance settings.
                    Color.clear
                        .glassEffect(.regular, in: shape)
                        .mask { WithoutFlares(flare: m.flare) }
                        .mask { shape }
                        .opacity(visible)
                } else {
                    // Clear Liquid Glass under black, as dark as set, blurring what's behind it as much as set.
                    Color.clear
                        .glassEffect(.clear, in: shape)
                        .background(GlassBlur(radius: GlassLook.blur(blur)))
                        .mask { WithoutFlares(flare: m.flare) }
                        .mask { shape }
                        .opacity(visible)
                    shape.fill(.black.opacity(GlassLook.black(darkness) * visible))
                }
            }
        }
        // Pushed up, the open notch shrinks a little as a whole, so nothing in it is cut off.
        .scaleEffect(1 + min(model.stretch, 0) * 0.005, anchor: .top)
        // Turned off: a notch on a display without one folds up into the top edge.
        .scaleEffect(x: 1, y: max(1 - model.vanish, 0.001), anchor: .top)
        // Reaching out to the bubble, it's that much wider on its trailing side alone.
        .offset(x: model.bubbleReach / 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .coordinateSpace(.named(ControlFrames.space))
        .onPreferenceChange(ControlFrames.self) { model.controlFrames = $0 }
        .onPreferenceChange(AirDropFrame.self) { model.airDropFrame = $0 }
        .onPreferenceChange(AlertButtonFrames.self) { model.alertButtons = $0 }
        // A change in Settings eases in rather than snapping.
        .animation(.easeInOut(duration: 0.6), value: background)
        .animation(.easeInOut(duration: 0.45), value: darkness)
        .animation(.easeInOut(duration: 0.45), value: followsSystem)
        .animation(.easeInOut(duration: 0.45), value: blur)
    }

    /// How much what's in the notch stretches with it, sideways and down: part of the notch's own.
    private func contentStretch(_ m: NotchMetrics) -> CGSize {
        let give = NotchModel.contentGive
        let down = max(model.stretch, 0)
        let across = model.pageStretch + abs(model.lean) + down * (model.state == .open ? 0.35 : 0.4)
        return CGSize(width: m.bodyWidth / max(m.bodyWidth - give * across, 1), height: m.height / max(m.height - give * down, 1))
    }

    /// The music's wings make way for what's announced, blurring away as the notch folds.
    private var musicAway: Bool { model.alert != nil || model.folded }
    /// In the closed notch: music's wings, its cover, and its waveform unless a new song's artist
    /// takes its place, or another activity is detached, which leaves music the leading side alone.
    private var liveShown: Bool { model.musicShown && !musicAway && model.state != .open }
    private var artworkShown: Bool { model.musicShown && !musicAway }
    private var waveformShown: Bool { model.musicShown && !model.pop && !musicAway && model.detached == nil }

    private func bubble(_ m: NotchMetrics) -> some View {
        // Open, it stays where it was, under the notch, which came out over it.
        let activity = model.detached ?? (model.state == .open ? model.second : nil)
        // Riding on the notch's end under the pointer. Opened from the notch, it goes on running into
        // the end it ran towards, riding with it as the notch opens, so the two run together as drops
        // do rather than the opening notch covering it at once. Opened from the bubble, the notch
        // reaches over it where it rests, off the camera's end, and grows from there.
        let restingEnd = model.closedSize.width / 2
        let runsIn = model.state == .open && model.bubbleMerged && !model.openedFromBubble
        return IslandBubble(
            shown: activity != nil && !model.bubbleMerged, clock: activity.flatMap(model.clock(of:)),
            route: activity == .airplay ? model.airplay : nil,
            airdrop: activity == .airdrop ? model.airdrop : nil,
            recording: activity.flatMap(model.recording(of:)),
            call: activity == .call ? model.call : nil,
            music: activity == .music, artwork: activity == .music ? nowPlaying.artwork : nil,
            paused: activity == .music && nowPlaying.hasMedia && !nowPlaying.isPlaying,
            name: activity.map(model.name(of:)) ?? String(localized: "Timer"), open: { model.openBubble() },
            restingHeight: model.closedSize.height,
            notchEnd: model.state != .open ? m.bodyWidth / 2 - m.fold : runsIn ? m.bodyWidth / 2 : restingEnd,
            hidden: model.state == .open, runsIn: runsIn,
            hovered: model.bubbleHovered, pressed: model.bubblePressed)
    }

    /// How wide the notch is closed, when what it's open to shows beside the camera there, alone, and
    /// grows out of that; with another detached, or from a bubble, it doesn't.
    private var grownFrom: CGFloat? {
        // A call's parts only fade, opening and closing, whatever app it's in.
        !model.openedFromBubble && model.expanded != nil && model.expanded != .call && model.activities.first == model.expanded
            ? model.restingWidth + 2 * model.grownSwell : nil
    }

    /// How far below the closed notch's middle at rest its middle was, swollen as it opened.
    private var grownDrop: CGFloat { model.grownSwell / 2 }

    /// Opened to the timer or the stopwatch: its own view, laid out at its open size, as the player
    /// is, so the growing shape reveals it.
    @ViewBuilder private func expandedTimer(shown: Bool) -> some View {
        if let clock = model.expandedClock {
            let h = model.closedSize.height
            let name = model.expanded.map(model.name(of:)) ?? String(localized: "Timer")
            let width = ExpandedTimerView.width(for: clock, name: name, restingHeight: h, camera: model.camera)
            ExpandedTimerView(
                shown: clock, name: name, restingHeight: h, camera: model.camera, width: width, revealed: shown, closedWidth: grownFrom,
                closedDrop: grownDrop
            )
            .frame(width: width, height: TimerLayout.tallHeight(h))
            .allowsHitTesting(places == nil && shown)
        }
    }

    /// Opened to a call: its own view, laid out at its open size, so the growing shape reveals it.
    @ViewBuilder private func expandedCall(shown: Bool) -> some View {
        if model.expanded == .call, let call = model.call {
            let h = model.closedSize.height
            ExpandedCallView(
                call: call, restingHeight: h, width: ExpandedCallView.width(for: call, restingHeight: h, closedWidth: model.closedSize.width), revealed: shown,
                closedWidth: grownFrom, closedDrop: grownDrop
            )
            .allowsHitTesting(places == nil && shown)
        }
    }

    /// Opened to AirPlay: its own view, laid out at its open size, so the growing shape reveals it.
    @ViewBuilder private func expandedAirPlay(shown: Bool) -> some View {
        if model.expanded == .airplay, let route = model.airplay {
            let h = model.closedSize.height
            let width = ExpandedAirPlayView.width(for: route, restingHeight: h)
            ExpandedAirPlayView(route: route, restingHeight: h, width: width, revealed: shown, closedWidth: grownFrom, closedDrop: grownDrop)
                .allowsHitTesting(places == nil && shown)
        }
    }

    /// Opened to AirDrop: its own view, laid out at its open size, so the growing shape reveals it.
    @ViewBuilder private func expandedAirDrop(shown: Bool) -> some View {
        if model.expanded == .airdrop, let transfer = model.airdrop {
            let h = model.closedSize.height
            let width = AirDropLayout.width(restingHeight: h, camera: model.camera)
            ExpandedAirDropView(shown: transfer, restingHeight: h, width: width, revealed: shown, closedWidth: grownFrom, closedDrop: grownDrop)
                .allowsHitTesting(places == nil && shown)
        }
    }

    /// Opened to a recording: its own view, laid out at its open size, so the growing shape reveals it.
    @ViewBuilder private func expandedRecording(shown: Bool) -> some View {
        if let recording = model.expanded.flatMap(model.recording(of:)) {
            let h = model.closedSize.height
            let width = model.openWidth(of: recording)
            ExpandedRecordingView(
                recording: recording, restingHeight: h, camera: model.camera, width: width, revealed: shown, closedWidth: grownFrom,
                closedDrop: grownDrop
            )
            .allowsHitTesting(places == nil && shown)
        }
    }

    /// Where the cover and the waveform rest in the closed notch: at its ends, as far in from them as
    /// from its top and bottom (see `LiveActivityView`). Laid out at the size the notch is going to,
    /// rather than at each step of its animation, so closing, they fly straight there, shrinking as
    /// the notch does, inside it all the way and never past the camera, rather than chasing its ends.
    private func restingPlaces(_ m: NotchMetrics, swell: CGFloat) -> some View {
        let h = model.closedSize.height
        let side = (h - LiveActivityView.inset * 2) * swell
        let edge = LiveActivityView.inset * swell
        return ZStack(alignment: .topLeading) {
            Color.clear
                .frame(width: side, height: side)
                .matchedGeometryEffect(id: Hero.liveArtwork, in: hero)
                .position(x: m.flare + edge + side / 2, y: m.height / 2)
            Color.clear
                .frame(width: side, height: side)
                .matchedGeometryEffect(id: Hero.liveWaveform, in: hero)
                .position(x: m.flare + m.bodyWidth - edge - side / 2, y: m.height / 2)
        }
        .frame(width: m.totalWidth, height: m.height)
        .allowsHitTesting(false)
    }

    /// The notch's own points, from the top left of its whole shape, flares and all.
    static let bodySpace = "notch body"

    private var tray: Tray { trayStore ?? .shared }
    /// How far a page slides as the other takes its place.
    private var pageShift: CGFloat { reduceMotion ? 0 : 28 }

    /// The lyrics open beside the player, widening the notch with the Dynamic Island's spring, from
    /// the waveform or a lyrics button.
    private func toggleLyrics() {
        withAnimation(NotchMotion.expand) { model.lyrics.toggle() }
    }

    /// The lyrics keep the same space below the camera as above the notch's bottom edge.
    private var lyricsTop: CGFloat { model.closedSize.height + LyricsView.gap }

    /// Laid out once at the largest the open notch gets, centered, reaching past its sides (the top
    /// corners flare out beyond the body) and below it, so no edge of it ever shows.
    private var lightSize: CGSize {
        CGSize(width: model.openSize.width + model.lyricsWidth + 160, height: model.openSize.height + 80)
    }

    /// All of the colors, across the open notch and a little past its corners, as wide as it is
    /// with the lyrics or without.
    private var lightSpread: CGSize {
        CGSize(width: model.openSize.width + (model.showsLyrics ? model.lyricsWidth : 0) + 60, height: model.openSize.height + 40)
    }

    /// In place of the glass, as Apple Music dims its own, measured from it: evenly, whatever the
    /// color, so white is a soft gray, and a red a deep one. With the colors' own dimming, a little
    /// over half of their brightness is left.
    static let colorsDim = 0.38
    /// The colors' brightest, a white cover's, before they're dimmed.
    static let colorsBrightest = 0.88
    /// With Increase Contrast on, dimmed further, so the artist's gray reads 4.5 to 1 even on a white
    /// cover's colors, the title far more.
    static let contrastDim = 0.77

    /// Dimmed while paused (see `PausedLook`).
    private var lightOpacity: Double {
        let full: Double =
            switch background {
            case .replaceGlass: 1
            case .spotlight: 0.9
            case .none: 0
            }
        return full * (nowPlaying.isPlaying ? 1 : PausedLook.kept)
    }

    /// The background spreads out from the middle slowly enough to be seen, once the notch has
    /// begun to open; the spotlight pops. Going, it just fades: the shape only resets once it's gone.
    private func lightGrowth(_ growing: Bool, fills: Bool) -> Animation {
        guard growing else { return .linear(duration: 0.01).delay(0.25) }
        return fills ? .easeOut(duration: 0.7).delay(0.1) : NotchMotion.spring(response: 0.6, dampingFraction: 0.72)
    }

    /// One circle: for the background, centered on the notch at the top, from the notch's own
    /// width to large enough to fill everything; for the spotlight, a soft glow at `spot`, from
    /// nothing. It grows and shrinks between them, so one morphs into the other.
    private func lightShape(_ m: NotchMetrics, grown: Bool, fills: Bool, spot: CGPoint) -> some View {
        let size = lightSize
        let artwork = model.layout.artwork
        // The background grows out of the middle of the open notch, evenly to both sides, to just
        // past its far corners, so the whole growth is seen.
        let middle = CGPoint(x: size.width / 2, y: model.openSize.height / 2)
        let reach = hypot(model.openSize.width / 2 + (model.showsLyrics ? model.lyricsWidth / 2 : 0) + 40, model.openSize.height / 2 + 40)
        let diameter = fills ? (grown ? reach * 2 + 80 : 0) : (grown ? artwork * 1.2 : 0)
        return Circle()
            .frame(width: diameter, height: diameter)
            .blur(radius: fills ? 30 : artwork * 0.14)
            .position(fills ? middle : spot)
            .frame(width: size.width, height: size.height)
    }

    /// One loop round the open notch, in seconds, and how fast the spotlight's colors turn, in
    /// radians a second: slow enough to read as light drifting, not as something to watch.
    static let spotlightLoop: TimeInterval = 20
    static let spotlightTurn = 2 * Double.pi / 14

    /// Where the spotlight is, `travelled` seconds into its journey. It comes out below and left
    /// of the cover's middle, so the glow first shows around its bottom and left, off its top
    /// right, where the camera housing is only a few points away; over the first second and a
    /// half it eases onto a loop round the open notch, as far in from its sides as that, and
    /// clockwise round from there. The loop keeps to the lower part, low enough that the glow
    /// never reaches the camera housing, whose cut-out has a hard edge.
    private func spotlightCenter(_ m: NotchMetrics, travelled: TimeInterval) -> CGPoint {
        let size = lightSize
        let artwork = model.layout.artwork
        let cover = CGPoint(
            x: size.width / 2 - m.bodyWidth / 2 + PlayerLayout.padding + artwork * 0.36,
            y: PlayerLayout.padding + artwork * 0.64)
        guard travelled > 0 else { return cover }
        let middle = CGPoint(x: size.width / 2, y: m.height * 0.7)
        let across = max(middle.x - cover.x, 1)
        let down = m.height * 0.12
        // Starting at the point of the loop toward the cover.
        let start = atan2((cover.y - middle.y) / down, (cover.x - middle.x) / across)
        let angle = start + travelled / Self.spotlightLoop * 2 * .pi
        let loop = CGPoint(x: middle.x + across * cos(angle), y: middle.y + down * sin(angle))
        let onto = min(travelled / 1.5, 1)
        let eased = onto * onto * (3 - 2 * onto)
        return CGPoint(x: cover.x + (loop.x - cover.x) * eased, y: cover.y + (loop.y - cover.y) * eased)
    }

    /// The spotlight fades out softly a few points before the notch's edges, so its rounded
    /// corners never cut the glow off. The background fills right to the edges.
    private func insideTheEdges(_ m: NotchMetrics, spotlight: Bool) -> some View {
        let margin: CGFloat = spotlight ? 8 : -40
        return RoundedRectangle(cornerRadius: max(PlayerLayout.cornerRadius - margin, 0), style: .continuous)
            .frame(width: m.bodyWidth - margin * 2, height: m.height - margin * 2)
            .blur(radius: spotlight ? 6 : 0)
            .position(x: lightSize.width / 2, y: m.height / 2)
            .frame(width: lightSize.width, height: lightSize.height)
    }

    /// Content fades in once the notch has begun to grow, and out quickly as it shrinks, so it is
    /// never squeezed into the closing shape.
    static func fade(in showing: Bool) -> Animation {
        (showing ? Animation.easeOut(duration: 0.3).delay(0.08) : .easeOut(duration: 0.12)).paced
    }

    /// Everything but the camera housing, on displays that have one: nothing is drawn under it.
    /// Cut exactly to its size, with no soft edge, so nothing shows around it either.
    private var awayFromCamera: some View {
        let closed = model.closedSize
        return ZStack(alignment: .top) {
            Color.black
            if model.hasCamera {
                UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8, style: .continuous)
                    .frame(width: closed.width, height: closed.height)
                    .blendMode(.destinationOut)
            }
        }
        .compositingGroup()
    }

    /// In place of the glass: visible where the black at the top lets the glass show, as if it were
    /// under it. The spotlight shines over the black, so this lifts away.
    private func belowTheBlack(lifted lights: Bool) -> some View {
        VStack(spacing: 0) {
            ZStack {
                LinearGradient(
                    stops: Self.shadeStops(start: model.closedSize.height * 0.6 / model.openSize.height, inverted: true),
                    startPoint: .top, endPoint: .bottom)
                Color.black.opacity(lights ? 1 : 0)
            }
            .frame(height: model.openSize.height)
            Color.black
        }
        .frame(width: lightSize.width, height: lightSize.height, alignment: .top)
    }

    /// Black at the top, fading smoothly all the way down to fully transparent glass at the open
    /// player's bottom edge. Pinned to the top, as a mask, so however tall the notch stands it shows as
    /// much glass as it reaches: a resting notch all black, a short activity a little, a tall one more.
    private var shade: some View {
        let height = model.openSize.height
        return LinearGradient(
            stops: Self.shadeStops(start: model.closedSize.height * 0.6 / height, inverted: false),
            startPoint: .top, endPoint: .bottom
        )
        .frame(height: height)
    }

    /// Eased in perceived brightness rather than opacity, and flat at both ends, so the fade has no
    /// visible line where it starts or ends. Inverted, it's clear exactly where the black is, so
    /// what shows through it stands just where the glass does.
    private static func shadeStops(start: CGFloat, inverted: Bool) -> [Gradient.Stop] {
        let fade = (0...48).map { i -> Gradient.Stop in
            let t = CGFloat(i) / 48
            let perceived = t * t * (3 - 2 * t)
            let black = 1 - pow(perceived, 1.2)
            return .init(color: .black.opacity(inverted ? 1 - black : black), location: start + (1 - start) * t)
        }
        return [.init(color: .black.opacity(inverted ? 0 : 1), location: 0)] + fade
    }
}

/// How everything on a page comes and goes as the notch opens, closes, or turns to the other page:
/// the player's words and buttons, its cover and its waveform, and the tray, all with one fade and
/// one blur, so nothing lingers or leaves ahead of the rest.
/// Seconds that run only while `running`, from nothing each time `shown` comes back: how far the
/// spotlight has travelled, which holds where it is while the music pauses, and starts at the
/// cover again each time it comes out.
private struct LightClock<Content: View>: View {
    let running: Bool
    let shown: Bool
    @ViewBuilder let content: (TimeInterval) -> Content
    @State private var banked: TimeInterval = 0
    @State private var since: Date?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !running)) { context in
            content(banked + (since.map { max(context.date.timeIntervalSince($0), 0) } ?? 0))
        }
        .onChange(of: running, initial: true) { _, running in
            if running {
                since = .now
            } else if let start = since {
                banked += Date.now.timeIntervalSince(start)
                since = nil
            }
        }
        .onChange(of: shown) { _, shown in
            guard shown else { return }
            banked = 0
            since = running ? .now : nil
        }
    }
}

struct PageFade: ViewModifier {
    let hidden: Bool

    func body(content: Content) -> some View {
        content.animation(NotchView.fade(in: !hidden)) { $0.opacity(hidden ? 0 : 1).blur(radius: hidden ? 4 : 0) }
    }
}

/// Frames of the controls inside the notch, in the notch view's own coordinates.
struct ControlFrames: PreferenceKey {
    static let space = "notch"
    static let defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) { value += nextValue() }
}

extension View {
    /// Lets clicks inside this view reach it instead of the notch's own press-and-close handling.
    /// Off while the view is hidden, so clicks there aren't taken from what's showing.
    func notchControl(enabled: Bool = true) -> some View {
        modifier(NotchControl(enabled: enabled))
    }
}

private struct NotchControl: ViewModifier {
    let enabled: Bool
    /// Off for the whole page that isn't showing: the player under the tray, or the tray under it.
    @Environment(\.notchControls) private var pageShown

    func body(content: Content) -> some View {
        content.background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ControlFrames.self, value: enabled && pageShown ? [proxy.frame(in: .named(ControlFrames.space))] : [])
            })
    }
}

extension EnvironmentValues {
    @Entry var notchControls = true
    @Entry var tray: Tray? = nil
}

/// The notch silhouette: a rectangle whose top corners flare out into the screen's edge and whose
/// bottom corners are rounded, all four with the same continuous (squircle) curve. Radii come from
/// the rect's height, so they change continuously while the frame animates.
struct NotchShape: Shape {
    var corners: NotchCorners
    /// 1 with wings out beside the camera, whose ends then round as the Dynamic Island's do, half
    /// the height across; 0 at rest.
    var wingEnds: CGFloat = 0
    /// How much of the trailing wing is folded away, back to the camera, with another activity
    /// detached (see `NotchModel.detached`). What's left is laid out as it always is, only cut short.
    var fold: CGFloat = 0

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(wingEnds, fold) }
        set { (wingEnds, fold) = (newValue.first, newValue.second) }
    }

    private func radii(in rect: CGRect) -> NotchCorners.Radii {
        corners.radii(forHeight: rect.height, wingEnds: wingEnds)
    }

    /// How far the top corners flare out on each side, at this size.
    func flare(in rect: CGRect) -> CGFloat {
        max(0, min(radii(in: rect).flare, rect.width / 4, rect.height / 2))
    }

    /// How far past its radius a bottom corner reaches along its sides, with room for it, as Apple's
    /// continuous corners do; and a flare, which stays in its square as the camera housing's does.
    private static let cornerReach: CGFloat = 1.52866
    private static let flareSmoothing: CGFloat = 0.1

    /// One outline, the same curve at all four corners, so nothing shows where they meet the sides or
    /// each other at any height. A bottom corner gives up reach as the flare above it takes the side.
    func path(in full: CGRect) -> Path {
        let rect = CGRect(x: full.minX, y: full.minY, width: max(full.width - fold, 0), height: full.height)
        let flare = flare(in: rect)
        let body = rect.insetBy(dx: flare, dy: 0)
        let bottom = max(min(radii(in: rect).bottom, body.width / 2, body.height - flare), 0)
        let reach = min(bottom * Self.cornerReach, body.height - flare, body.width / 2)
        let flareRadius = flare / (1 + Self.flareSmoothing)
        let (right, left, up, down) = (CGVector(dx: 1, dy: 0), CGVector(dx: -1, dy: 0), CGVector(dx: 0, dy: -1), CGVector(dx: 0, dy: 1))
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addCorner(at: CGPoint(x: body.maxX, y: rect.minY), from: right, to: down, radius: flareRadius, reach: flare)
        path.addCorner(at: CGPoint(x: body.maxX, y: rect.maxY), from: up, to: left, radius: bottom, reach: reach)
        path.addCorner(at: CGPoint(x: body.minX, y: rect.maxY), from: right, to: up, radius: bottom, reach: reach)
        path.addCorner(at: CGPoint(x: body.minX, y: rect.minY), from: down, to: left, radius: flareRadius, reach: flare)
        path.closeSubpath()
        return path
    }
}

extension Path {
    /// A corner between two straight sides: from `reach` along the side it comes in on, in a line from
    /// where the path is, to `reach` along the side it leaves on. With no more reach than its radius
    /// it's a quarter circle. Past that, the middle of it is still a circle of that radius, and it eases
    /// into each side, its bend fading to nothing there, so the eye finds no join.
    fileprivate mutating func addCorner(at corner: CGPoint, from first: CGVector, to second: CGVector, radius r: CGFloat, reach p: CGFloat) {
        func at(_ along: CGFloat, _ across: CGFloat) -> CGPoint {
            CGPoint(x: corner.x + first.dx * along + second.dx * across, y: corner.y + first.dy * along + second.dy * across)
        }
        guard r > 0.01 else { return addLine(to: corner) }
        let smoothing = min(max(p / r - 1, 0), 1)
        let arc = CGFloat.pi / 2 * (1 - smoothing)
        let bend = CGFloat.pi / 4 * smoothing
        // Where the circle starts and ends, as far along each side as its tangent there reaches.
        let tangent = r * tan(bend / 2)
        let (along, drop) = (tangent * cos(bend), tangent * sin(bend))
        let near = sin(arc / 2) * r * 2.squareRoot() + drop
        // Long enough for the curve to arrive at the circle bent exactly as much as the circle is.
        let ease = bend > 0.001 ? 1.5 * tangent * tangent / (r * sin(bend)) : 0
        let handle = 4 / 3 * tan(arc / 4)
        addLine(to: at(p, 0))
        addCurve(to: at(near, drop), control1: at(near + along + ease, 0), control2: at(near + along, 0))
        addCurve(
            to: at(drop, near),
            control1: at(near + (drop - r) * handle, drop + (r - near) * handle),
            control2: at(drop - (near - r) * handle, near - (r - drop) * handle))
        addCurve(to: at(0, p), control1: at(0, near + along), control2: at(0, near + along + ease))
    }
}

/// Lays its content out at a size that changes step by step as it animates, rather than at the new
/// size at once with only its picture moving there.
private struct SteppedFrame: ViewModifier, Animatable {
    /// Less its flares, which follow from its height at each step, so its ends move on its spring
    /// alone, whatever the corners are doing.
    var width: CGFloat
    var height: CGFloat
    let corners: NotchCorners
    /// Never smaller than the camera housing, however hard a spring carries it: closing just after it
    /// opened, still moving inward from its bounce, it would otherwise shrink past the housing and
    /// show its edge.
    var least = CGSize.zero

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(width, height) }
        set { (width, height) = (newValue.first, newValue.second) }
    }

    func body(content: Content) -> some View {
        let width = max(width, least.width), height = max(height, least.height)
        content.frame(width: width + corners.radii(forHeight: height).flare * 2, height: height, alignment: .top)
    }
}

extension View {
    /// As wide as the notch is at each step as it animates, less its flares, so what the wings show
    /// rides in and out with their ends, as the Dynamic Island's activities do.
    fileprivate func atNotchStep(width: CGFloat, height: CGFloat) -> some View {
        modifier(AtNotchStep(width: width, height: height))
    }
}

private struct AtNotchStep: ViewModifier, Animatable {
    var width: CGFloat
    let height: CGFloat

    var animatableData: CGFloat {
        get { width }
        set { width = newValue }
    }

    func body(content: Content) -> some View {
        content.frame(width: width, height: height)
    }
}

/// All of the notch but its flared top corners, where it meets the top of the screen. Glass there
/// would light the flares' curved edges, under the black of the notch's top, as a thin bright line;
/// they're the notch's black alone.
struct WithoutFlares: View {
    let flare: CGFloat
    /// The glass's own bright rim along the top edge would show as a line across the top of the
    /// screen; the notch comes out of the edge of the display, with no edge of its own there.
    private static let top: CGFloat = 1.5

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                let size = proxy.size, corner = flare + 1, top = Self.top
                path.move(to: CGPoint(x: corner, y: top))
                path.addLine(to: CGPoint(x: size.width - corner, y: top))
                path.addLine(to: CGPoint(x: size.width - corner, y: max(corner, top)))
                path.addLine(to: CGPoint(x: size.width, y: max(corner, top)))
                path.addLine(to: CGPoint(x: size.width, y: size.height))
                path.addLine(to: CGPoint(x: 0, y: size.height))
                path.addLine(to: CGPoint(x: 0, y: max(corner, top)))
                path.addLine(to: CGPoint(x: corner, y: max(corner, top)))
                path.closeSubpath()
            }
            .fill()
        }
    }
}

/// Sets how much the Liquid Glass it sits behind blurs what's behind it. Liquid Glass has no setting
/// for that, and in a window that looks active (as the notch's always does, for real refraction) it
/// shows what's behind it sharp whatever its own blur radius says. So this finds the glass's own
/// backdrop layer, the one it sits behind, and puts a Gaussian blur first among its filters: what's
/// behind is blurred, then the glass is drawn over it, edges and refraction and all. SwiftUI can
/// rebuild the glass, as when the notch opens and closes, so it looks again whenever it's laid out
/// or updated.
struct GlassBlur: NSViewRepresentable {
    var radius: CGFloat

    func makeNSView(context: Context) -> GlassBlurView { GlassBlurView() }

    func updateNSView(_ view: GlassBlurView, context: Context) {
        view.radius = radius
        view.apply()
    }
}

final class GlassBlurView: NSView {
    var radius: CGFloat = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        apply()
        // The glass is put in place just after this view.
        DispatchQueue.main.async { [weak self] in self?.apply() }
    }

    override func layout() {
        super.layout()
        apply()
    }

    /// The glass's own layers, found last time. Finding them means walking every layer in the
    /// window, too slow to do each time the notch moves or redraws, so they're kept, and looked
    /// for again only once one has gone (SwiftUI made the glass anew).
    private let backdrops = NSHashTable<CALayer>.weakObjects()
    /// The blur last given to the glass. SwiftUI sets the glass's filters afresh each frame the
    /// notch changes size, dropping the blur; while this is set, a missing blur was dropped that
    /// way, not turned on.
    private var given: CGFloat = 0

    func apply() {
        guard var root = layer, bounds.width > 0 else { return }
        // The window's top layer, whichever views it's made of.
        while let parent = root.superlayer { root = parent }
        let kept = backdrops.allObjects
        if kept.isEmpty || kept.contains(where: { Self.top(of: $0) !== root }) {
            backdrops.removeAllObjects()
            find(in: root)
        }
        for backdrop in backdrops.allObjects { set(backdrop) }
        given = radius
    }

    private func find(in root: CALayer) {
        let mine = layer!
        let area = root.convert(mine.bounds, from: mine).insetBy(dx: -2, dy: -2)
        func visit(_ layer: CALayer) {
            if NSStringFromClass(type(of: layer)) == "CABackdropLayer",
                layer.filters?.contains(where: { ($0 as? NSObject)?.value(forKey: "type") as? String == "glassBackground" }) == true
            {
                let frame = root.convert(layer.bounds, from: layer)
                if area.contains(CGPoint(x: frame.midX, y: frame.midY)) { backdrops.add(layer) }
                return
            }
            layer.sublayers?.forEach(visit)
        }
        visit(root)
    }

    private static func top(of layer: CALayer) -> CALayer {
        var top = layer
        while let parent = top.superlayer { top = parent }
        return top
    }

    private static let name = "notchBlur"
    private static let easing: CFTimeInterval = 0.15

    /// A big change, as going to the tray and back, eases over quickly, most of it at the start, so
    /// the blur is there as the page arrives; a slider's small steps follow it at once.
    private func ease(_ backdrop: CALayer, from: CGFloat, to: CGFloat) {
        guard abs(to - from) > 2, window != nil else { return }
        let animation = CABasicAnimation(keyPath: "filters.\(Self.name).inputRadius")
        animation.fromValue = from
        animation.toValue = to
        animation.duration = Self.easing
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        backdrop.add(animation, forKey: Self.name)
    }

    private func set(_ backdrop: CALayer) {
        var filters = backdrop.filters ?? []
        let existing = filters.firstIndex { ($0 as? NSObject)?.value(forKey: "name") as? String == Self.name }
        let current = existing.flatMap { (filters[$0] as? NSObject)?.value(forKey: "inputRadius") as? CGFloat }
        if radius <= 0.01 {
            guard let current, current > 0.01 else {
                // Eased down to nothing: only then does the blur go.
                if let existing, backdrop.animation(forKey: Self.name) == nil {
                    filters.remove(at: existing)
                    backdrop.filters = filters
                }
                return
            }
            ease(backdrop, from: current, to: 0)
            backdrop.setValue(0, forKeyPath: "filters.\(Self.name).inputRadius")
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.easing + 0.05) { [weak self] in self?.apply() }
        } else if let current {
            if current != radius {
                ease(backdrop, from: current, to: radius)
                backdrop.setValue(radius, forKeyPath: "filters.\(Self.name).inputRadius")
            }
        } else if let type = NSClassFromString("CAFilter") as? NSObject.Type,
            let blur = type.perform(NSSelectorFromString("filterWithType:"), with: "gaussianBlur")?.takeUnretainedValue() as? NSObject
        {
            blur.setValue(Self.name, forKey: "name")
            blur.setValue(radius, forKey: "inputRadius")
            // Blurred right to the glass's edges, with nothing faded in from outside them.
            blur.setValue(true, forKey: "inputNormalizeEdges")
            backdrop.filters = [blur] + filters
            // Only a blur being turned on eases in. One SwiftUI dropped goes straight back as it
            // was: easing in from nothing each frame, it would never build up while the notch opens,
            // and what's behind would flicker sharp. An ease under way carries on, as it goes by
            // the blur's name.
            if given <= 0.01 { ease(backdrop, from: 0, to: radius) }
        }
        // The glass's own blur, which it uses in a window that doesn't look active: none, so the
        // blur above is all there is either way.
        let keyPath = "filters.glassBackground.inputBlurRadius"
        if (backdrop.value(forKeyPath: keyPath) as? CGFloat) != 0 { backdrop.setValue(0, forKeyPath: keyPath) }
        // A half-size copy is blurry even with no blur; it only saves work once it's blurred anyway.
        let scale: CGFloat = radius < 8 ? 1 : 0.5
        if (backdrop.value(forKey: "scale") as? CGFloat) != scale { backdrop.setValue(scale, forKey: "scale") }
    }
}
