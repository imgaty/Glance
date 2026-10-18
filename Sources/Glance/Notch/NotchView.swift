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
    /// On the tray, the least the glass blurs what's behind it, whatever it's set to: enough for
    /// the row and its name to read over a busy window, as a menu's glass does.
    static let trayBlur = 0.55
    /// On the tray, the least black over the glass: the items' names are words to read, and Apple
    /// keeps words on its frosted glass, so it's dimmed further than the player.
    static let trayBlack = 0.6
}

/// The notch's corners follow its height. Closed, it matches the hardware notch: small flares out
/// into the screen's edge at the top, small rounded corners at the bottom. Opening, both grow to the
/// same radius, so all four corners match, in Apple's continuous (squircle) curve.
struct NotchCorners: Equatable {
    var restingHeight: CGFloat
    var openHeight: CGFloat
    var openRadius: CGFloat
    /// A Dynamic Island instead, away from the top edge: no flares, all four corners round alike,
    /// and closed, a capsule.
    var island = false

    private static let restingFlare: CGFloat = 6
    private static let restingBottomRadius: CGFloat = 12

    struct Radii {
        var flare: CGFloat
        var bottom: CGFloat
    }

    func radii(forHeight height: CGFloat) -> Radii {
        // Settled at the open size: a pull never rounds the corners past it.
        let progress = min(max((height - restingHeight) / max(openHeight - restingHeight, 1), 0), 1)
        if island {
            return Radii(flare: 0, bottom: height / 2 + (openRadius - height / 2) * progress)
        }
        return Radii(
            flare: Self.restingFlare + (openRadius - Self.restingFlare) * progress,
            bottom: Self.restingBottomRadius + (openRadius - Self.restingBottomRadius) * progress)
    }
}

/// The size the view draws for a given moment.
struct NotchMetrics {
    var bodyWidth: CGFloat
    var height: CGFloat
    /// How far the top corners flare out on each side.
    var flare: CGFloat

    var totalWidth: CGFloat { bodyWidth + flare * 2 }
}

@MainActor
final class NotchModel: ObservableObject {
    let closedSize: CGSize
    /// The display has a camera housing at the top, which nothing should be drawn under.
    let hasCamera: Bool
    /// The player's layout, its open size and corners. They change together, animated, when the
    /// layout changes in Settings.
    @Published var layout: PlayerLayout
    @Published var openSize: CGSize
    @Published var corners: NotchCorners
    /// Added to the open notch's width while the lyrics show beside the player.
    let lyricsWidth: CGFloat = 250
    /// The widest a wing gets while a new song is announced; longer titles scroll.
    static let maxPopWing: CGFloat = 150

    @Published var state: NotchState = .closed
    /// 0...1, how close the pointer is while the notch is closed.
    @Published var proximity: CGFloat = 0
    /// Rubber-band offset from scroll gestures, in points. Negative squashes the open notch.
    @Published var stretch: CGFloat = 0
    @Published var pressed = false
    /// Music is playing: the closed notch grows wings for the artwork and the waveform.
    @Published var activity = false
    /// A new song started: the wings widen for a moment to show its title and artist.
    @Published var pop = false
    /// Each wing's width while a new song is announced: just enough for its title and artist.
    @Published var popWing: CGFloat = NotchModel.maxPopWing
    /// What the Mac announces (see Activities), and each wing's width for it: for a few seconds the
    /// wings show it, over whatever else they show.
    @Published var alert: NotchAlert?
    @Published var alertWing: CGFloat = 0
    /// Between what the wings show and what's announced, the notch folds to rest first and opens
    /// again from there, as the Dynamic Island switches between activities.
    @Published var switching = false
    /// A timer counting down beside the camera, and each wing's width for it.
    @Published var timer: NotchTimer.State?
    @Published var timerWing: CGFloat = 0
    /// The lyrics are wanted: the open notch widens to show them beside the player, while a song plays.
    @Published var lyrics = false
    /// What's playing is a song, which can have lyrics.
    @Published var songPlaying = false
    /// The welcome tour's pointer, showing how, in the notch's own points (see `demoPointer`).
    @Published var demoPointer: CGPoint?
    /// Which page the open notch shows: the player, or the tray.
    @Published var page: NotchPage = .player
    /// Something is being dragged over the notch, to be dropped in the tray.
    @Published var dropping = false
    /// How far the tray's row is scrolled.
    @Published var trayScroll: CGFloat = 0
    /// How far a swipe to the other page has pushed this one, before it goes.
    @Published var pageNudge: CGFloat = 0
    /// How many items the tray holds, which its width follows.
    @Published var trayItems = 0
    /// The widest the tray grows: room for six items and half the next, or less on a narrow display.
    var trayMaxWidth = Shelf.peekWidth
    /// The tray on the player's grid: the padding either side of its first and last icons, as of the
    /// cover and the buttons, and under its row. As wide as its items, from three items' width,
    /// fewer sitting in the middle of it, up to `trayMaxWidth`, past which its row scrolls; and
    /// always wider than the camera with the padding either side. Empty, or with something dragged
    /// in, as wide as the player, for its words and its two places to drop.
    var trayWidth: CGFloat {
        let least =
            trayItems == 0 || dropping ? openSize.width : max(Shelf.narrowest, closedSize.width + PlayerLayout.padding * 2)
        return min(max(Shelf.width(count: trayItems), least), max(trayMaxWidth, least))
    }

    /// Its row just below the camera, as the player's column below it starts, and the padding under it.
    var trayHeight: CGFloat { Self.trayHeight(closed: closedSize) }

    static func trayHeight(closed: CGSize) -> CGFloat {
        closed.height + PlayerLayout.cameraGap + Shelf.tile.height + PlayerLayout.padding
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
    /// Where a timer that's done has its Stop, which works in the closed notch, and whether the
    /// pointer is on it.
    var stopFrame: CGRect?
    @Published var stopHovered = false

    /// A Dynamic Island, floating just below the top of the screen, rather than a notch.
    @Published var island: Bool {
        didSet { corners.island = island }
    }

    /// How far below the top of the screen the island floats: just clear of it, so the island can
    /// be as tall as the menu bar allows.
    static let islandGap: CGFloat = 1
    /// Turning the notch off and on, 0 to 1: an island draws into a dot (`squeeze`), which then
    /// shrinks away (`vanish`); a notch on a display without one folds up into the top edge (`vanish`).
    @Published var squeeze: CGFloat = 0
    @Published var vanish: CGFloat = 0
    var gap: CGFloat { island ? Self.islandGap : 0 }

    init(closedSize: CGSize, layout: PlayerLayout, hasCamera: Bool, island: Bool = false) {
        self.closedSize = closedSize
        self.hasCamera = hasCamera
        self.layout = layout
        self.island = island
        let openSize = layout.size(closed: closedSize)
        self.openSize = openSize
        // Fully round by the shorter of the two pages, so both have the same corners.
        corners = NotchCorners(
            restingHeight: closedSize.height, openHeight: min(openSize.height, Self.trayHeight(closed: closedSize)),
            openRadius: PlayerLayout.cornerRadius, island: island)
    }

    /// Switches to another layout in place.
    func use(_ layout: PlayerLayout) {
        self.layout = layout
        openSize = layout.size(closed: closedSize)
        corners.openHeight = min(openSize.height, trayHeight)
    }

    /// Each side of the camera while music plays: as wide as the notch is tall, so the artwork and
    /// waveform sit in squares (on an island, a little wider, so they don't crowd its ends), or
    /// wider while a new song is announced.
    var wing: CGFloat {
        let resting = island ? (closedSize.height * 1.25).rounded() : closedSize.height
        if switching { return 0 }
        if alert != nil { return max(alertWing, resting) }
        if activity, pop { return max(popWing, resting) }
        if timer != nil { return max(timerWing, resting) }
        return activity ? resting : 0
    }

    /// The closed notch's width, with the activity's wings while music plays, a timer runs, or
    /// something's announced.
    var restingWidth: CGFloat { closedSize.width + wing * 2 }

    var metrics: NotchMetrics { metrics(for: state) }

    func metrics(for state: NotchState) -> NotchMetrics {
        let pull = max(stretch, 0)
        let (bodyWidth, height): (CGFloat, CGFloat) =
            switch state {
            case .closed:
                (
                    (restingWidth + 10 * proximity + pull * 0.4) * (1 - squeeze) + closedSize.height * squeeze,
                    closedSize.height + 3 * proximity + pull
                )
            case .peek: (restingWidth + 28 + pull * 0.4, closedSize.height + 7 + pull)
            case .open where page == .tray: (trayWidth + pull * 0.35, trayHeight + pull)
            case .open: (openSize.width + (showsLyrics ? lyricsWidth : 0) + pull * 0.35, openSize.height + pull)
            }
        // Pressed, it squeezes a little toward the top: made smaller rather than shrunk as a picture,
        // which the glass, sized afresh with the notch, doesn't follow.
        let press: CGFloat = pressed ? 0.975 : 1
        return NotchMetrics(
            bodyWidth: bodyWidth * press, height: height * press, flare: corners.radii(forHeight: height * press).flare)
    }
}

/// How the notch moves between its states, the same on screen and in Settings' preview.
extension NotchModel {
    func peek() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { state = .peek }
    }

    /// Peek → closed, when the pointer slides off before the notch opens.
    func settle(closeness: CGFloat) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            state = .closed
            proximity = Self.eased(closeness)
        }
    }

    /// Critically damped: it grows straight to its size, never past it.
    func open() {
        withAnimation(.spring(response: 0.42, dampingFraction: 1)) {
            state = .open
            proximity = 0
            pop = false
        }
    }

    func close() {
        withAnimation(.spring(response: 0.36, dampingFraction: 0.88)) {
            state = .closed
            stretch = 0
        }
    }

    /// Squeezed while pressed; let go, it springs back.
    func press(_ down: Bool) {
        withAnimation(down ? .spring(response: 0.2, dampingFraction: 0.7) : .spring(response: 0.4, dampingFraction: 0.5)) { pressed = down }
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

    init(model: NotchModel, display: String, background: MusicBackground? = nil) {
        self.model = model
        func key(_ name: String) -> String { Preferences.lookKey(name, display: display) }
        _followsSystem = AppStorage(wrappedValue: false, key(Preferences.glassFollowsSystem))
        _chosenDarkness = AppStorage(wrappedValue: 0, key(Preferences.glassDarkness))
        _blur = AppStorage(wrappedValue: 0, key(Preferences.glassBlur))
        _chosenBackground = AppStorage(wrappedValue: .replaceGlass, key(Preferences.musicBackground))
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
        // With wings out, their ends round as the Dynamic Island's do.
        let shape = NotchShape(corners: model.corners, wingEnds: model.wing > 0 ? 1 : 0)
        let isOpen = model.state == .open
        let onTray = trayOn && model.page == .tray
        // Open on the player, rather than on the tray.
        let playerShown = isOpen && !onTray
        let trayShown = isOpen && onTray
        let glassBlur = trayShown ? max(blur, GlassLook.trayBlur) : blur
        let closed = model.closedSize
        // Hidden at rest so no glass rim glints around the hardware notch; closed, it's black.
        let visible: Double = model.state != .closed ? 1 : 0
        // With Increase Contrast on, the player's words and buttons sit on plain black.
        let lit = playerShown && nowPlaying.artwork != nil && background != .none && !accessibility.increasesContrast
        let lyricsShown = isOpen && model.showsLyrics
        // The closed notch swells under the pointer, and the artwork and waveform with it.
        let swell = isOpen ? 1 : m.height / closed.height

        ZStack(alignment: .top) {
            shade
            // The artwork's light: in place of the glass, it fills the bottom and fades out under the
            // black at the top, just where the glass shows; full screen, it covers the whole notch;
            // as a spotlight, it's a soft circle around the cover. Choosing between them morphs one
            // into another.
            ArtworkLight(dim: background == .spotlight ? 0 : 0.3, active: isOpen && !paused)
                .frame(width: lightSize.width, height: lightSize.height)
                .mask {
                    // It comes in as it's turned on or the notch opens: the background washing out of
                    // the notch until it fills it, the spotlight popping out of the cover.
                    lightShape(m, grown: lit, fills: background != .spotlight)
                        .animation(lightGrowth(lit, fills: background != .spotlight), value: lit)
                }
                .mask { insideTheEdges(m, spotlight: background == .spotlight) }
                .mask { belowTheBlack(lifted: background != .replaceGlass) }
                .mask { awayFromCamera }
                .animation(lit ? .easeOut(duration: 0.5).delay(0.1) : .easeOut(duration: 0.2)) {
                    $0.opacity(lit ? lightOpacity : 0)
                }
                .animation(.easeInOut(duration: 0.5), value: nowPlaying.isPlaying)
            // As wide as the notch is at each step, so what the wings show rides in and out with their
            // ends, as the Dynamic Island's activities do.
            LiveActivityView(restingHeight: closed.height, island: model.island, wing: model.wing, pop: model.pop, hero: hero)
                .atNotchStep(flare: m.flare, height: m.height, otherwise: m.bodyWidth)
                .allowsHitTesting(places == nil)
                .islandFade(liveShown)
            // What the Mac announces, and a timer, in the same wings.
            SystemActivityView(
                restingHeight: closed.height, island: model.island, wing: model.wing, alert: model.alert,
                timer: model.activity && model.pop || model.switching ? nil : model.timer, music: model.activity,
                stopHovered: model.stopHovered
            )
            .atNotchStep(flare: m.flare, height: m.height, otherwise: m.bodyWidth)
            .allowsHitTesting(false)
            .islandFade(!isOpen)
            // The notch at rest, sharp, over what the wings show, as the Dynamic Island keeps its own
            // shape over an activity coming or going: what rides in with the wings' ends as they fold
            // passes under it. Kept at the closed size while open, so closing it never shrinks from the
            // open notch's height over the glass, and back only once the notch has all but closed.
            let rest = isOpen ? model.metrics(for: .closed) : m
            NotchShape(corners: model.corners).fill(.black)
                .frame(width: restingBody(m) + rest.flare * 2, height: rest.height)
                .frame(width: m.totalWidth, height: m.height, alignment: .top)
                .allowsHitTesting(false)
                .animation(isOpen ? .easeOut(duration: 0.1) : .easeOut(duration: 0.1).delay(0.2)) { $0.opacity(isOpen ? 0 : 1) }
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
                .islandFade(lyricsShown)
                .allowsHitTesting(places == nil)
            // The player and the tray side by side, as pages are: going to the tray, the player
            // slides off to the left as the tray comes in from the right, and back.
            NowPlayingView(isVisible: playerShown && !paused, hero: hero)
                .frame(width: model.openSize.width, height: model.openSize.height)
                .padding(.trailing, model.showsLyrics ? model.lyricsWidth : 0)
                .environment(\.notchControls, playerShown)
                .offset(x: (onTray ? -pageShift : 0) + (playerShown ? model.pageNudge : 0))
                .modifier(PageFade(hidden: !playerShown))
            if trayOn {
                TrayView(
                    tray: tray, isVisible: trayShown && !paused, dropping: model.dropping, scroll: model.trayScroll,
                    airDropTargeted: model.airDropTargeted
                )
                .frame(width: model.trayWidth, height: model.trayHeight)
                .environment(\.notchControls, trayShown)
                .offset(x: (onTray ? 0 : pageShift) + (trayShown ? model.pageNudge : 0))
                .modifier(PageFade(hidden: !trayShown))
                .allowsHitTesting(places == nil && trayShown)
            }
            HeroArtwork(isOpen: isOpen, restingSide: closed.height - LiveActivityView.inset(island: model.island) * 2)
                .matchedGeometryEffect(id: isOpen ? Hero.openArtwork : Hero.liveArtwork, in: hero, isSource: false)
                .scaleEffect(isOpen ? 1 : swell, anchor: isOpen ? .center : .leading)
                .offset(x: model.nudge)
                // There open, or in the closed notch while something plays, coming and going as the
                // Dynamic Island's activities do, as everything in the notch does.
                .islandFade(isOpen || artworkShown)
                .modifier(PageFade(hidden: isOpen && onTray))
                .environment(\.notchControls, !trayShown)
                // Over the tray, though unseen there: clicks go through it to the tray's items.
                .allowsHitTesting(places == nil && !trayShown)
            HeroWaveform(
                isOpen: isOpen, lyricsShown: model.showsLyrics, lyricsAvailable: model.songPlaying && lyricsOn,
                toggleLyrics: toggleLyrics
            )
            .matchedGeometryEffect(id: isOpen ? Hero.openWaveform : Hero.liveWaveform, in: hero, isSource: false)
            .scaleEffect(isOpen ? 1 : swell, anchor: isOpen ? .center : .trailing)
            // There open, or in the closed notch while something plays, out of the way when a new
            // song's artist takes its place, coming and going as the Dynamic Island's activities do.
            .islandFade(isOpen || waveformShown)
            .modifier(PageFade(hidden: isOpen && onTray))
            .environment(\.notchControls, !trayShown)
            .allowsHitTesting(places == nil && !trayShown)
        }
        .environment(\.closedNotch, closed)
        .environment(\.playerLayout, model.layout)
        .environment(\.lyricsControl, LyricsControl(shown: model.showsLyrics, available: model.songPlaying && lyricsOn, toggle: toggleLyrics))
        // Turned off, any lyrics showing fold away.
        .onChange(of: lyricsOn) {
            if !lyricsOn { withAnimation(.spring(response: 0.5, dampingFraction: 1)) { model.lyrics = false } }
        }
        // Liquid Glass takes a new size at once, while a frame's size otherwise animates only in
        // the picture, so the glass and the notch's black and outline would part as it changes size
        // (opening, a new layout, the lyrics coming or going). Laid out afresh at every step, the
        // whole notch, glass and all, keeps together.
        .modifier(SteppedFrame(width: m.totalWidth, height: m.height))
        .coordinateSpace(.named(Self.bodySpace))
        .environment(\.demoPointer, model.demoPointer)
        .clipShape(shape)
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
                        .background(GlassBlur(radius: GlassLook.blur(glassBlur)))
                        .mask { WithoutFlares(flare: m.flare) }
                        .mask { shape }
                        .opacity(visible)
                    shape.fill(.black.opacity((trayShown ? max(GlassLook.black(darkness), GlassLook.trayBlack) : GlassLook.black(darkness)) * visible))
                        // The tray's darker glass is there as the tray arrives, as its blur is,
                        // rather than following the page's slower slide.
                        .animation(.easeOut(duration: 0.15), value: trayShown)
                }
            }
        }
        // Pushed up, the open notch shrinks a little as a whole, so nothing in it is cut off.
        .scaleEffect(1 + min(model.stretch, 0) * 0.005, anchor: .top)
        // Turned off: an island's dot shrinks away into its middle; a notch on a display without one
        // folds up into the top edge.
        .scaleEffect(
            x: model.island ? max(1 - model.vanish, 0.001) : 1, y: max(1 - model.vanish, 0.001),
            anchor: model.island ? .center : .top
        )
        // An island floats a little below the top of the screen.
        .padding(.top, model.gap)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .coordinateSpace(.named(ControlFrames.space))
        .onPreferenceChange(ControlFrames.self) { model.controlFrames = $0 }
        .onPreferenceChange(AirDropFrame.self) { model.airDropFrame = $0 }
        .onPreferenceChange(StopFrame.self) { model.stopFrame = $0 }
        // A change in Settings eases in rather than snapping.
        .animation(.easeInOut(duration: 0.6), value: background)
        .animation(.easeInOut(duration: 0.45), value: darkness)
        .animation(.easeInOut(duration: 0.45), value: followsSystem)
        .animation(.easeInOut(duration: 0.45), value: blur)
    }

    /// The music's wings make way for what's announced, blurring away as the notch folds.
    private var musicAway: Bool { model.alert != nil || model.switching }
    /// In the closed notch: music's wings, its cover, and its waveform unless a new song's artist or
    /// a timer takes its place.
    private var liveShown: Bool { model.activity && !musicAway && model.state != .open }
    private var artworkShown: Bool { model.activity && !musicAway }
    private var waveformShown: Bool { model.activity && !model.pop && !musicAway && model.timer == nil }

    /// The closed notch's width without its wings, as it narrows to a dot while turning off.
    private func restingBody(_ m: NotchMetrics) -> CGFloat {
        let closed = model.closedSize
        return closed.width * (1 - model.squeeze) + closed.height * model.squeeze
    }

    /// The notch's own points, from the top left of its whole shape, flares and all.
    static let bodySpace = "notch body"

    private var tray: Tray { trayStore ?? .shared }
    /// How far a page slides as the other takes its place.
    private var pageShift: CGFloat { reduceMotion ? 0 : 28 }

    /// The lyrics open beside the player, widening the notch, from the waveform or a lyrics button.
    private func toggleLyrics() {
        withAnimation(.spring(response: 0.5, dampingFraction: 1)) { model.lyrics.toggle() }
    }

    /// The lyrics keep the same space below the camera as above the notch's bottom edge.
    private static let lyricsGap: CGFloat = 12
    private var lyricsTop: CGFloat { model.closedSize.height + Self.lyricsGap }

    /// Laid out once at the largest the open notch gets, centered, reaching past its sides (the top
    /// corners flare out beyond the body) and below it, so no edge of it ever shows.
    private var lightSize: CGSize {
        CGSize(width: model.openSize.width + model.lyricsWidth + 160, height: model.openSize.height + 80)
    }

    /// Faded to 30% while paused.
    private var lightOpacity: Double {
        let full: Double =
            switch background {
            case .replaceGlass: 0.6 + 0.4 * darkness
            case .fullscreen: 0.85
            case .spotlight: 0.9
            case .none: 0
            }
        return full * (nowPlaying.isPlaying ? 1 : 0.3)
    }

    /// The background spreads out from the middle slowly enough to be seen, once the notch has
    /// begun to open; the spotlight pops. Going, it just fades: the shape only resets once it's gone.
    private func lightGrowth(_ growing: Bool, fills: Bool) -> Animation {
        guard growing else { return .linear(duration: 0.01).delay(0.25) }
        return fills ? .easeOut(duration: 0.7).delay(0.1) : .spring(response: 0.6, dampingFraction: 0.72)
    }

    /// One circle: for the background, centered on the notch at the top, from the notch's own
    /// width to large enough to fill everything; for the spotlight, a soft glow around the cover,
    /// from nothing. It grows and shrinks between them, so one morphs into the other.
    private func lightShape(_ m: NotchMetrics, grown: Bool, fills: Bool) -> some View {
        let size = lightSize
        let artwork = model.layout.artwork
        // Below and left of the cover's middle, so the glow shows around its bottom and left and
        // stays off its top right, where the camera housing is only a few points away.
        let cover = CGPoint(
            x: size.width / 2 - m.bodyWidth / 2 + PlayerLayout.padding + artwork * 0.36,
            y: PlayerLayout.padding + artwork * 0.64)
        // The background grows out of the middle of the open notch, evenly to both sides, to just
        // past its far corners, so the whole growth is seen.
        let middle = CGPoint(x: size.width / 2, y: model.openSize.height / 2)
        let reach = hypot(model.openSize.width / 2 + (model.showsLyrics ? model.lyricsWidth / 2 : 0) + 40, model.openSize.height / 2 + 40)
        let diameter = fills ? (grown ? reach * 2 + 80 : 0) : (grown ? artwork * 1.2 : 0)
        return Circle()
            .frame(width: diameter, height: diameter)
            .blur(radius: fills ? 30 : artwork * 0.14)
            .position(fills ? middle : cover)
            .frame(width: size.width, height: size.height)
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

    /// In place of the glass: visible exactly where the black at the top lets the glass show, as if
    /// it were under it. Full screen and the spotlight shine over the black, so this lifts away.
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

    /// Black at the top, fading smoothly all the way down to fully transparent glass at the
    /// bottom edge. Pinned to the top, so a resting notch stays all black.
    private var shade: some View {
        let height = model.openSize.height
        return LinearGradient(
            stops: Self.shadeStops(start: model.closedSize.height * 0.6 / height, inverted: false),
            startPoint: .top, endPoint: .bottom
        )
        .frame(height: height)
    }

    /// Eased in perceived brightness rather than opacity, and flat at both ends, so the fade has no
    /// visible line where it starts or ends. Inverted, it's clear where the black is.
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
/// the player's words and buttons, its cover and its waveform, and the tray, as the Dynamic Island's
/// activities come and go, so nothing lingers or leaves ahead of the rest.
private struct PageFade: ViewModifier {
    let hidden: Bool

    func body(content: Content) -> some View {
        content.islandFade(!hidden)
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

    var animatableData: CGFloat {
        get { wingEnds }
        set { wingEnds = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var radii = corners.radii(forHeight: rect.height)
        if !corners.island, wingEnds > 0 {
            // Opening, the open notch's own corners take over.
            let open = min(max((rect.height - corners.restingHeight) / max(corners.openHeight - corners.restingHeight, 1), 0), 1)
            radii.bottom += (rect.height / 2 - radii.bottom) * wingEnds * (1 - open)
        }
        let flare = max(0, min(radii.flare, rect.width / 4, rect.height / 2))
        let body = rect.insetBy(dx: flare, dy: 0)
        if corners.island {
            let radius = min(radii.bottom, rect.width / 2, rect.height / 2)
            return RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect)
        }
        let bottom = min(radii.bottom, body.width / 2, body.height - flare)
        let path = UnevenRoundedRectangle(
            topLeadingRadius: 0, bottomLeadingRadius: bottom,
            bottomTrailingRadius: bottom, topTrailingRadius: 0,
            style: .continuous
        ).path(in: body)
        guard flare > 0.1 else { return path }
        // Each flare runs from the screen's edge into the body's side. Its handles sit closer to
        // the corner than a circle's would, which spreads the bend out like Apple's continuous
        // corners. It overlaps the body a point so they join without a seam.
        let handle: CGFloat = 0.62
        var flares = Path()
        for (edge, side) in [(rect.minX, body.minX), (rect.maxX, body.maxX)] {
            let inward: CGFloat = side > edge ? 1 : -1
            flares.move(to: CGPoint(x: edge, y: rect.minY))
            flares.addLine(to: CGPoint(x: side + inward, y: rect.minY))
            flares.addLine(to: CGPoint(x: side + inward, y: rect.minY + flare))
            flares.addLine(to: CGPoint(x: side, y: rect.minY + flare))
            flares.addCurve(
                to: CGPoint(x: edge, y: rect.minY),
                control1: CGPoint(x: side, y: rect.minY + flare * (1 - handle)),
                control2: CGPoint(x: edge + (side - edge) * handle, y: rect.minY))
            flares.closeSubpath()
        }
        return path.union(flares)
    }
}

/// Lays its content out at a size that changes step by step as it animates, rather than at the new
/// size at once with only its picture moving there.
private struct SteppedFrame: ViewModifier, Animatable {
    var width: CGFloat
    var height: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(width, height) }
        set { (width, height) = (newValue.first, newValue.second) }
    }

    func body(content: Content) -> some View {
        content.frame(width: width, height: height, alignment: .top)
            .environment(\.notchStep, width)
    }
}

extension EnvironmentValues {
    /// The notch's width at this step as it animates, flares and all (see `SteppedFrame`).
    @Entry var notchStep: CGFloat?
}

extension View {
    /// As wide as the notch is at each step as it animates, less its flares, so what the wings show
    /// rides in and out with their ends, as the Dynamic Island's activities do.
    fileprivate func atNotchStep(flare: CGFloat, height: CGFloat, otherwise width: CGFloat) -> some View {
        modifier(AtNotchStep(flare: flare, height: height, width: width))
    }
}

private struct AtNotchStep: ViewModifier {
    @Environment(\.notchStep) private var step
    let flare: CGFloat
    let height: CGFloat
    let width: CGFloat

    func body(content: Content) -> some View {
        content.frame(width: step.map { max($0 - flare * 2, 0) } ?? width, height: height)
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
            ease(backdrop, from: 0, to: radius)
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
