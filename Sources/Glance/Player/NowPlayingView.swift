//
//  NowPlayingView.swift
//  Glance
//
//  Created by Gaty on 07/10/2026.
//

import AppKit
import SwiftUI

/// The player inside the open notch, styled after the iPhone's Dynamic Island. Everything sits on
/// one grid: the same inset on the sides and bottom, the same gap between rows, and the buttons'
/// contact areas starting and ending on the edges the artwork and the timeline do.
struct NowPlayingView: View {
    /// Every button's contact area. The glyphs inside it differ in size; the contact areas don't.
    static let hitbox: CGFloat = 40
    static let sideColumnHeight = PlayerLayout.headerHeight + 4 + PlayerLayout.timelineHeight + 4 + hitbox

    @EnvironmentObject private var nowPlaying: NowPlaying
    @ObservedObject private var output = AudioOutput.shared
    @Environment(\.notchThumbnail) private var thumbnail
    @Environment(\.soundMenuChanged) private var soundMenuChanged
    @Environment(\.playerLayout) private var layout
    @AppStorage(Preferences.musicAccentSource) private var accentSource = AccentSource.artwork
    @AppStorage(Preferences.musicAccentTimeline) private var accentTimeline = false
    @Environment(\.closedNotch) private var closedNotch
    @AppStorage(Preferences.musicLeftButton) private var leftSlot = PlayerSlot.favorite
    @AppStorage(Preferences.musicRightButton) private var rightSlot = PlayerSlot.output
    @Environment(\.controlPlaces) private var places
    @Environment(\.lyricsControl) private var lyricsControl
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.playerOnLight) private var onLight
    @Environment(\.playerKeys) private var keys
    @AppStorage(Preferences.musicDJButton) private var djButton = true
    /// The way the Mac's language reads, outside the rows that always run left to right.
    @Environment(\.layoutDirection) private var reading
    /// The clock and the scrolling titles only move, and options are only read, while it shows.
    let isVisible: Bool
    /// The artwork and the waveform are drawn by the notch, flying in from the closed notch; the
    /// player only marks where they land.
    let hero: Namespace.ID
    @State private var scrub: Double?
    @State private var soundPlace: PlayerControl?
    @State private var favoriteBursts = 0
    @State private var skipsBack = 0
    @State private var skipsForward = 0
    /// Repeat's slash, which waits, after repeating one song, for the 1 to go first.
    @State private var repeatSlashed = true

    private var accent: Color { nowPlaying.accent(from: accentSource) }

    var body: some View {
        // How far below the artwork's top the camera housing ends; what's under it starts there.
        let clearance = closedNotch.height + PlayerLayout.cameraGap - PlayerLayout.padding
        // Where the title starts: centered on the artwork, unless that puts it under the camera.
        let headerTop = layout == .top ? max((layout.artwork - PlayerLayout.headerHeight) / 2, clearance) : clearance
        let content = layout.size(closed: closedNotch)
        let width = content.width - PlayerLayout.padding * 2
        let beside = layout.artwork + PlayerLayout.besideArtwork
        let column = width - beside
        let topRow = max(layout.artwork, headerTop + PlayerLayout.headerHeight)
        let sideHeight = max(layout.artwork - clearance, Self.sideColumnHeight)
        let timelineTop = layout == .top ? topRow + 12 : clearance + sideHeight - Self.hitbox - 4 - PlayerLayout.timelineHeight
        let controlsTop = timelineTop + PlayerLayout.timelineHeight + (layout == .top ? 8 : 4)
        let rowLeading = layout == .top ? 0 : beside
        let rowWidth = layout == .top ? width : column
        ZStack(alignment: .topLeading) {
            artwork
            waveformPlace(top: headerTop)
            // These remain the same views in both layouts. Their frames and positions follow the
            // notch's spring, preserving the scrubber, scrolling titles and control focus mid-move.
            header
                .frame(width: column, height: PlayerLayout.headerHeight, alignment: .topLeading)
                .padding(.leading, beside)
                .padding(.top, headerTop)
                .allowsHitTesting(places == nil)
            timeline
                .frame(width: rowWidth, height: PlayerLayout.timelineHeight)
                .padding(.leading, rowLeading)
                .padding(.top, timelineTop)
                .allowsHitTesting(places == nil)
            controls
                .frame(width: rowWidth, height: Self.hitbox)
                .padding(.leading, rowLeading)
                .padding(.top, controlsTop)
        }
        .frame(width: width, height: content.height - PlayerLayout.padding * 2, alignment: .topLeading)
        .padding([.horizontal, .top], PlayerLayout.padding)
        .animation(.easeInOut(duration: 0.4), value: accentSource)
        .animation(.easeInOut(duration: 0.4), value: accentTimeline)
        .animation(.easeInOut(duration: 0.4), value: leftSlot)
        .animation(.easeInOut(duration: 0.4), value: showsDJ)
        .animation(.easeInOut(duration: 0.4), value: rightSlot)
        .animation(.easeInOut(duration: 0.3), value: nowPlaying.explicit)
        .frame(maxHeight: .infinity, alignment: .top)
        .foregroundStyle(.white)
        .onChange(of: isVisible) {
            if isVisible {
                nowPlaying.refreshOptions()
            } else {
                soundPlace = nil
                soundMenuChanged(false)
            }
        }
        .onDisappear { soundMenuChanged(false) }
        .onChange(of: nowPlaying.title) { if isVisible { nowPlaying.refreshOptions() } }
        .onChange(of: usableControls, initial: true) { keys?.usable = usableControls }
        .onChange(of: soundControl, initial: true) { keys?.soundControl = soundControl }
        .onChange(of: keys?.presses) { if let control = keys?.focus { press(control, fromKeys: true) } }
        .onChange(of: keys?.focus) { if let control = keys?.focus, !control.onActivity { announce(control) } }
        .task(id: isVisible) {
            // Keeps the clock, and the lyrics with it, exact while the player shows, and the star
            // true to Music.
            while isVisible, !Task.isCancelled {
                if nowPlaying.isPlaying { await nowPlaying.syncPosition() }
                await nowPlaying.syncFavorite()
                nowPlaying.syncDJ()
                // Soon while the DJ may have just stopped, so its button gives way to Shuffle quickly.
                try? await Task.sleep(for: .seconds(nowPlaying.djCheck))
            }
        }
    }

    /// The title and the artist, with room for the waveform at the end of the title's line, as on
    /// the iPhone. Both scroll when they don't fit.
    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                // The explicit badge follows the title and scrolls with it, as on the iPhone.
                MarqueeText(
                    text: nowPlaying.hasMedia ? nowPlaying.title : String(localized: "Not Playing"),
                    font: NotchType.title, active: isVisible, fills: false, explicit: nowPlaying.hasMedia && nowPlaying.explicit
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                MarqueeText(text: nowPlaying.artist, font: NotchType.detail, active: isVisible)
                    .foregroundStyle(NotchType.detailColor)
            }
            Color.clear
                .frame(width: PlayerLayout.waveform.width + PlayerLayout.waveformInset, height: PlayerLayout.waveform.height)
        }
    }

    /// Where the waveform lands: at the end of the title's line, `top` below the artwork's top,
    /// centered over the time left.
    private func waveformPlace(top: CGFloat) -> some View {
        Color.clear
            .frame(width: PlayerLayout.waveform.width, height: PlayerLayout.waveform.height)
            .matchedGeometryEffect(id: Hero.openWaveform, in: hero)
            .padding(.top, top)
            .padding(.trailing, PlayerLayout.waveformInset)
            .frame(maxWidth: .infinity, alignment: .topTrailing)
    }

    /// Where the artwork lands. The notch draws it, and its spotlight, there.
    private var artwork: some View {
        Color.clear
            .frame(width: layout.artwork, height: layout.artwork)
            .matchedGeometryEffect(id: Hero.openArtwork, in: hero)
    }

    /// Elapsed time, the bar, and time left, on one line as on the iPhone, the times flush with
    /// the edges. It runs left to right in every language; only the times' digits change.
    private var timeline: some View {
        TimelineView(.animation(minimumInterval: 0.5, paused: !(isVisible && nowPlaying.isPlaying))) { context in
            // With nothing playing, no times and an empty bar, as on the iPhone.
            let playing = nowPlaying.hasMedia
            // What the DJ says has no length, so no times, as in Spotify.
            let timed = playing && !nowPlaying.djTalking
            let duration = playing ? nowPlaying.duration : 0
            let position = scrub.map { $0 * duration } ?? (playing ? nowPlaying.position(at: context.date) : 0)
            HStack(spacing: 10) {
                Text(timed ? Self.time(position) : "--:--")
                    .frame(minWidth: 26, alignment: .leading)
                Scrubber(
                    fraction: duration > 0 ? position / duration : 0,
                    color: accentTimeline ? accent : .white.opacity(0.7),
                    spoken: playing ? String(localized: "\(Self.time(position)) of \(Self.time(duration))") : "",
                    // Ten seconds at a time.
                    step: duration > 0 ? min(10 / duration, 1) : 0
                ) {
                    scrub = $0
                } onCommit: { fraction in
                    nowPlaying.seek(to: fraction * duration)
                    scrub = nil
                }
                .disabled(duration <= 0)
                .keyRing(.position, in: Capsule(), outset: CGSize(width: 6, height: 0))
                Text(timed ? ClockText.left(Int(max(duration - position, 0).rounded())) : "--:--")
                    .frame(minWidth: 30, alignment: .trailing)
            }
            .font(NotchType.timeline)
            .foregroundStyle(buttonGray)
            .environment(\.layoutDirection, .leftToRight)
        }
        .frame(height: PlayerLayout.timelineHeight)
    }

    /// Five equal contact areas, their centers evenly spaced, the outer two starting and ending on the
    /// edges the artwork and the timeline do. Previous is on the left and next on the right in every
    /// language; the side buttons' own symbols still follow the language.
    private var controls: some View {
        EvenRow(leading: PlayerLayout.controlsInset, trailing: PlayerLayout.controlsInset) {
            // (Its places, in order: one side, the three transport controls, the other side.)
            if let places {
                ControlMark(place: .left, control: leftSlot, symbol: symbol(for: leftSlot), places: places)
                    .environment(\.layoutDirection, reading)
            } else if showsDJ {
                // As Spotify puts its DJ where shuffle was, while the DJ chooses the music.
                DJButton(color: sideGray, moving: isVisible && nowPlaying.isPlaying, talking: nowPlaying.djTalking && nowPlaying.isPlaying) {
                    nowPlaying.differentDJPicks()
                }
                .keyRing(.left)
                .transition(.opacity)
            } else {
                slot(leftSlot, at: .left)
                    .environment(\.layoutDirection, reading)
                    .keyRing(.left)
            }
            Group {
                GlyphButton(label: String(localized: "Previous")) {
                    press(.previous)
                } glyph: {
                    SkipSymbol(forward: false, skips: skipsBack)
                }
                .keyRing(.previous)
                IslandButton(
                    symbol: nowPlaying.isPlaying ? "pause.fill" : "play.fill", size: PlayerLayout.playGlyph,
                    label: nowPlaying.isPlaying ? String(localized: "Pause") : String(localized: "Play")
                ) {
                    press(.playPause)
                }
                .keyRing(.playPause)
                GlyphButton(label: String(localized: "Next")) {
                    press(.next)
                } glyph: {
                    SkipSymbol(forward: true, skips: skipsForward)
                }
                .keyRing(.next)
            }
            .disabled(!nowPlaying.hasMedia)
            .opacity(nowPlaying.hasMedia ? 1 : 0.4)
            .allowsHitTesting(places == nil)
            if let places {
                ControlMark(place: .right, control: rightSlot, symbol: symbol(for: rightSlot), places: places)
                    .environment(\.layoutDirection, reading)
            } else {
                slot(rightSlot, at: .right)
                    .environment(\.layoutDirection, reading)
                    .keyRing(.right)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .frame(height: Self.hitbox)
        .onChange(of: nowPlaying.options.repeatMode, initial: true) { old, new in
            let off = new.map { $0 == .off } ?? true
            guard off, old == .one else { return repeatSlashed = off }
            // From one song to none, the 1 goes first, then the slash comes.
            Task {
                try? await Task.sleep(for: .seconds(0.35))
                if nowPlaying.options.repeatMode == .off { repeatSlashed = true }
            }
        }
    }

    private func symbol(for slot: PlayerSlot) -> String {
        let options = nowPlaying.options
        return switch slot {
        case .favorite: options.favorite == true ? "star.fill" : "star"
        case .shuffle: "shuffle"
        case .repeatMode: options.repeatMode == .one ? "repeat.1" : "repeat"
        case .output: output.symbol
        case .lyrics: lyricsControl.shown ? "quote.bubble.fill" : "quote.bubble"
        case .empty: slot.symbol
        }
    }

    @ViewBuilder private func slot(_ slot: PlayerSlot, at place: PlayerControl) -> some View {
        let options = nowPlaying.options
        let state: (color: Color, slashed: Bool, disabled: Bool, value: String?) =
            switch slot {
            case .favorite: (optionColor(options.favorite), false, options.favorite == nil, Self.spoken(options.favorite))
            case .shuffle: (switchColor(options.shuffle), options.shuffle != true, options.shuffle == nil, Self.spoken(options.shuffle))
            case .repeatMode:
                (switchColor(options.repeatMode.map { $0 != .off }), repeatSlashed, options.repeatMode == nil, options.repeatMode?.rawValue.capitalized)
            case .lyrics:
                (optionColor(lyricsControl.available ? lyricsControl.shown : nil), false, !lyricsControl.available, Self.spoken(lyricsControl.available ? lyricsControl.shown : nil))
            case .output, .empty: (sideGray, false, false, nil)
            }
        if slot == .empty {
            Color.clear.frame(width: Self.hitbox, height: Self.hitbox)
        } else {
            // One button keeps its symbol identity when the assigned control changes, so the
            // system can transition between its old and new symbols.
            IslandButton(
                symbol: slot == .output ? output.buttonSymbol : symbol(for: slot), size: PlayerLayout.optionGlyph,
                symbolValue: slot == .output ? output.speakerLevel : nil, color: state.color, slashed: state.slashed,
                burst: favoriteBursts, burstEnabled: slot == .favorite, burstColor: accent,
                label: slot.title, value: state.value
            ) {
                use(slot, at: place)
            }
            .disabled(state.disabled)
            .background {
                if !thumbnail {
                    SoundMenuPresenter(
                        isPresented: Binding(
                            get: { soundPlace == place },
                            set: { shown in
                                if !shown {
                                    soundPlace = nil
                                    soundMenuChanged(false)
                                }
                            }),
                        alignTrailing: place != .left,
                        makeMenu: output.soundMenu
                    )
                }
            }
        }
    }

    /// An option's state as VoiceOver says a switch's.
    private static func spoken(_ on: Bool?) -> String? {
        on.map { $0 ? String(localized: "On") : String(localized: "Off") }
    }

    // MARK: The keyboard

    /// Spotify's DJ has the left button, unless it's turned off in Customize Controls.
    private var showsDJ: Bool { djButton && nowPlaying.djPlaying }

    /// Which of the sides is Sound Output, for the arrows to turn the sound up and down there.
    private var soundControl: PlayerControl? {
        if leftSlot == .output, !showsDJ { return .left }
        return rightSlot == .output ? .right : nil
    }

    /// The controls that can be used now, in the order Tab goes through them.
    private var usableControls: [PlayerControl] {
        guard isVisible, places == nil else { return [] }
        let media = nowPlaying.hasMedia
        func usable(_ slot: PlayerSlot) -> Bool {
            switch slot {
            case .favorite: nowPlaying.options.favorite != nil
            case .shuffle: nowPlaying.options.shuffle != nil
            case .repeatMode: nowPlaying.options.repeatMode != nil
            case .output: true
            case .lyrics: lyricsControl.available
            case .empty: false
            }
        }
        var controls: [PlayerControl] = []
        if media { controls.append(.cover) }
        if lyricsControl.available { controls.append(.lyrics) }
        if keys?.hasLines == true { controls.append(.line) }
        if media, nowPlaying.duration > 0 { controls.append(.position) }
        if showsDJ || usable(leftSlot) { controls.append(.left) }
        if media { controls += [.previous, .playPause, .next] }
        if usable(rightSlot) { controls.append(.right) }
        return controls
    }

    /// What a control does, by a click or from the keyboard. The progress bar is only moved.
    private func press(_ control: PlayerControl, fromKeys: Bool = false) {
        switch control {
        case .cover: nowPlaying.openSource()
        case .lyrics: lyricsControl.toggle()
        // The lines and an activity's buttons see to their own.
        case .line, .position, .activityFirst, .activitySecond, .activityThird, .activityFourth: break
        case .left:
            if showsDJ { nowPlaying.differentDJPicks() } else { use(leftSlot, fromKeys: fromKeys) }
        case .previous:
            skipsBack += 1
            nowPlaying.previous()
        case .playPause: nowPlaying.togglePlayPause()
        case .next:
            skipsForward += 1
            nowPlaying.next()
        case .right: use(rightSlot, fromKeys: fromKeys)
        }
    }

    private func use(_ slot: PlayerSlot, fromKeys: Bool = false, at place: PlayerControl? = nil) {
        switch slot {
        case .favorite:
            if nowPlaying.options.favorite == false { favoriteBursts += 1 }
            nowPlaying.toggleFavorite()
        case .shuffle: nowPlaying.toggleShuffle()
        case .repeatMode: nowPlaying.cycleRepeat()
        case .output:
            soundPlace = place ?? (keys?.focus == .left ? .left : (soundControl ?? .right))
            soundMenuChanged(true)
        case .lyrics: lyricsControl.toggle()
        case .empty: break
        }
    }

    /// Where the keys went, said to VoiceOver, as the same control is called anywhere else.
    private func announce(_ control: PlayerControl) {
        NSAccessibility.post(
            element: NSApp as Any, notification: .announcementRequested,
            userInfo: [.announcement: words(for: control), .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    private func words(for control: PlayerControl) -> String {
        func named(_ slot: PlayerSlot) -> String {
            let options = nowPlaying.options
            let state: String? =
                switch slot {
                case .favorite: Self.spoken(options.favorite)
                case .shuffle: Self.spoken(options.shuffle)
                case .repeatMode: options.repeatMode?.rawValue.capitalized
                case .lyrics: Self.spoken(lyricsControl.shown)
                case .output, .empty: nil
                }
            return [slot.title, state].compactMap { $0 }.joined(separator: ", ")
        }
        return switch control {
        case .cover: String(localized: "Show Where It's Playing")
        case .lyrics: lyricsControl.shown ? String(localized: "Hide Lyrics") : String(localized: "Show Lyrics")
        case .line: String(localized: "Lyrics")
        case .position: String(localized: "Track Position")
        case .left: showsDJ ? "DJ" : named(leftSlot)
        case .previous: String(localized: "Previous")
        case .playPause: nowPlaying.isPlaying ? String(localized: "Pause") : String(localized: "Play")
        case .next: String(localized: "Next")
        case .right: named(rightSlot)
        case .activityFirst, .activitySecond, .activityThird, .activityFourth: ""
        }
    }

    /// Shuffle and repeat: the side buttons' color, on or off (off, they're struck through); faint
    /// when the app doesn't offer them.
    private func switchColor(_ on: Bool?) -> Color {
        on == nil ? sideGray.opacity(0.4) : sideGray
    }

    /// The side buttons' color when on, so only play and the skip buttons are white on a dark
    /// background; a step dimmer when off, faint when the app doesn't offer it.
    private func optionColor(_ on: Bool?) -> Color {
        switch on {
        case true?: sideGray
        case false?: PlayerLayout.sideButtonOff(onLight: onLightBackground)
        case nil: sideGray.opacity(0.4)
        }
    }

    /// In light mode the glass at the bottom of the notch shows light windows through it, and a light
    /// cover's colors are light too.
    private var onLightBackground: Bool { colorScheme == .light || onLight }

    /// The artist's gray would vanish into a light background, so the times are lighter there.
    private var buttonGray: Color {
        onLightBackground ? Color(white: 0.88) : PlayerLayout.secondary
    }

    private var sideGray: Color { PlayerLayout.sideButton(onLight: onLightBackground) }

    private static func time(_ seconds: Double) -> String {
        ClockText.of(Int(max(seconds, 0).rounded()))
    }
}

/// Where each of the player's controls can go, in Settings' picture of the player, for the menus
/// beside them.
@MainActor
@Observable
final class ControlPlaces {
    nonisolated static let space = "controlPlaces"
    var frames: [ControlPlace: CGRect] = [:]
    /// While a control is dragged: which, the place it was taken from, and the place it's over.
    var dragging: PlayerSlot?
    var lifted: ControlPlace?
    var target: ControlPlace?
}

/// A place for a control, in Settings' picture of the player, as it's being chosen: what's there on
/// a faint disc, or, with nothing there, a dashed ring with a plus. It says where it is, so the
/// sheet can put its ring, its − and its click there.
struct ControlMark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let place: ControlPlace
    let control: PlayerSlot
    /// What the control shows now, as the player draws it.
    let symbol: String
    let places: ControlPlaces

    var body: some View {
        let targeted = places.target == place
        let shown: PlayerSlot? = targeted ? places.dragging : places.lifted == place || control == .empty ? nil : control
        ZStack {
            Circle()
                .fill(.white.opacity(targeted ? 0.28 : shown == nil ? 0 : 0.14))
            if let shown {
                Group {
                    if shown == control { Image(systemName: symbol) } else { ControlSymbol(control: shown) }
                }
                .font(.system(size: PlayerLayout.optionGlyph, weight: .medium))
                .foregroundStyle(.white)
                .transition(reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity))
            } else {
                Circle()
                    .strokeBorder(.white.opacity(0.5), style: StrokeStyle(lineWidth: 1.2, dash: [3, 2.5]))
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .frame(width: NowPlayingView.hitbox, height: NowPlayingView.hitbox)
        .onGeometryChange(for: CGRect.self) {
            $0.frame(in: .named(ControlPlaces.space))
        } action: {
            places.frames[place] = $0
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: control)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: targeted)
    }
}

/// Apple's skip symbols, moving as they do in the Dynamic Island when pressed: the front arrow slips
/// off ahead, fading, the back one slides into its place, and a new one grows in behind. Each arrow
/// is forward.fill's own front arrow (its back one is the same, partly covered by it), so at rest
/// it's exactly the symbol; backward.fill is its mirror image. Each press plays the motion once, and
/// the end looks just like the start.
struct SkipSymbol: View {
    let forward: Bool
    /// Presses so far.
    let skips: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// forward.fill at the skip buttons' size: 28 by 18 points at 18.
    private static let image: NSImage? = NSImage(systemSymbolName: "forward.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: PlayerLayout.skipGlyph, weight: .semibold))

    var body: some View {
        if let image = Self.image {
            SkipArrows(phase: Double(skips), image: image)
                .frame(width: image.size.width, height: image.size.height)
                .scaleEffect(x: forward ? 1 : -1)
                // Settling without overshoot: past the end, the motion would start over. With Reduce
                // Motion on, the arrows stay where they are.
                .animation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 1), value: skips)
        }
    }
}

private struct SkipArrows: View, Animatable {
    var phase: Double
    let image: NSImage

    /// Where forward.fill's front arrow starts, how far behind it the back one is, and where the
    /// front one's tip is, as shares of the symbol's width.
    static let split: CGFloat = 0.5337
    static let step: CGFloat = 0.4535
    static let tip: CGFloat = 0.987

    var animatableData: Double {
        get { phase }
        set { phase = newValue }
    }

    var body: some View {
        // How far through the current press, 0 to 1.
        let p = CGFloat(phase - phase.rounded(.down))
        GeometryReader { proxy in
            let width = proxy.size.width
            if p < 0.001 {
                // At rest, the symbol itself.
                Image(nsImage: image).renderingMode(.template).foregroundStyle(.white)
            } else {
                ZStack(alignment: .topLeading) {
                    // The new arrow, growing in behind.
                    arrow(width: width)
                        .scaleEffect(p, anchor: UnitPoint(x: Self.split, y: 0.5))
                        .offset(x: -width * Self.step)
                        .opacity(Double(p))
                    // The back arrow, sliding into the front one's place.
                    arrow(width: width)
                        .offset(x: -width * Self.step * (1 - p))
                    // The front arrow, slipping off ahead.
                    arrow(width: width)
                        .scaleEffect(1 - p * 0.6, anchor: UnitPoint(x: Self.tip, y: 0.5))
                        .offset(x: width * Self.step * p * 0.5)
                        .opacity(Double(1 - p))
                }
            }
        }
    }

    /// The symbol's front arrow, the rest of it cut away.
    private func arrow(width: CGFloat) -> some View {
        Image(nsImage: image)
            .renderingMode(.template)
            .foregroundStyle(.white)
            .mask(alignment: .trailing) {
                Rectangle().frame(width: width * (1 - Self.split))
            }
    }
}

/// A button around a drawn glyph, with the same contact area and press as every other.
private struct GlyphButton<Glyph: View>: View {
    /// A drawn glyph has no name of its own: what VoiceOver and Voice Control call it.
    let label: String
    let action: () -> Void
    @ViewBuilder let glyph: Glyph

    var body: some View {
        Button(action: action) { glyph }
            .buttonStyle(IslandPress())
            .notchControl()
            .accessibilityLabel(label)
    }
}

/// Buttons of equal size with their centers evenly spaced, from `leading` in from the left edge to
/// `trailing` in from the right.
private struct EvenRow: Layout {
    var leading: CGFloat
    var trailing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? 280, height: NowPlayingView.hitbox)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let first = bounds.minX + leading, last = bounds.maxX - trailing
        let step = subviews.count > 1 ? (last - first) / CGFloat(subviews.count - 1) : 0
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: first + step * CGFloat(index), y: bounds.midY), anchor: .center, proposal: .unspecified)
        }
    }
}
