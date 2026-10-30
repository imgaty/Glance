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
    static let sideColumnHeight = PlayerLayout.headerHeight + 6 + PlayerLayout.timelineHeight + 6 + hitbox

    @EnvironmentObject private var nowPlaying: NowPlaying
    @ObservedObject private var output = AudioOutput.shared
    @Environment(\.playerLayout) private var layout
    @AppStorage(Preferences.musicAccentSource) private var accentSource = AccentSource.artwork
    @AppStorage(Preferences.musicAccentTimeline) private var accentTimeline = true
    @Environment(\.closedNotch) private var closedNotch
    @AppStorage(Preferences.musicLeftButton) private var leftSlot = PlayerSlot.favorite
    @AppStorage(Preferences.musicRightButton) private var rightSlot = PlayerSlot.output
    @Environment(\.controlPlaces) private var places
    @Environment(\.lyricsControl) private var lyricsControl
    @Environment(\.colorScheme) private var colorScheme
    /// The clock and the scrolling titles only move, and options are only read, while it shows.
    let isVisible: Bool
    /// The artwork and the waveform are drawn by the notch, flying in from the closed notch; the
    /// player only marks where they land.
    let hero: Namespace.ID
    @State private var scrub: Double?
    @State private var favoriteBursts = 0
    @State private var skipsBack = 0
    @State private var skipsForward = 0
    /// Repeat's slash, which waits, after repeating one song, for the 1 to go first.
    @State private var repeatSlashed = true

    private var accent: Color { nowPlaying.accent(from: accentSource) }

    var body: some View {
        // How far below the artwork's top the camera housing ends; what's under it starts there.
        let clearance = closedNotch.height + PlayerLayout.cameraGap - PlayerLayout.padding
        ZStack(alignment: .topLeading) {
            // The artwork's and the waveform's places are the same views in every layout, so when
            // the layout changes they just move and resize, and the notch's artwork and waveform
            // glide along with them.
            artwork
            waveformPlace(top: layout == .top ? (layout.artwork - PlayerLayout.headerHeight) / 2 : clearance)
            // The rest steps out and comes back in its new places once the notch has reshaped,
            // rather than sliding or stretching across.
            Group {
                switch layout {
                case .top:
                    // The title and artist are shorter than the artwork and centered on it,
                    // which keeps them below the camera.
                    VStack(spacing: 0) {
                        HStack(spacing: PlayerLayout.besideArtwork) {
                            Color.clear.frame(width: layout.artwork, height: layout.artwork)
                            header
                        }
                        .allowsHitTesting(places == nil)
                        timeline
                            .allowsHitTesting(places == nil)
                            .padding(.top, 12)
                        controls
                            .padding(.top, 8)
                    }
                    .transition(Self.relayout)
                case .side:
                    HStack(alignment: .top, spacing: PlayerLayout.besideArtwork) {
                        Color.clear.frame(width: layout.artwork, height: layout.artwork)
                        // The title starts just below the camera; the space between it and the
                        // timeline gives way, so the controls end level with the artwork's bottom edge.
                        VStack(spacing: 0) {
                            header
                                .frame(height: PlayerLayout.headerHeight, alignment: .top)
                                .allowsHitTesting(places == nil)
                            Spacer(minLength: 6)
                            timeline
                                .allowsHitTesting(places == nil)
                            controls
                                .padding(.top, 6)
                        }
                        .frame(height: max(layout.artwork - clearance, Self.sideColumnHeight))
                        .padding(.top, clearance)
                    }
                    .transition(Self.relayout)
                }
            }
        }
        .padding([.horizontal, .top], PlayerLayout.padding)
        .animation(.easeInOut(duration: 0.4), value: accentSource)
        .animation(.easeInOut(duration: 0.4), value: accentTimeline)
        .animation(.easeInOut(duration: 0.4), value: leftSlot)
        .animation(.easeInOut(duration: 0.4), value: nowPlaying.djPlaying)
        .animation(.easeInOut(duration: 0.4), value: rightSlot)
        .animation(.easeInOut(duration: 0.3), value: nowPlaying.explicit)
        .frame(maxHeight: .infinity, alignment: .top)
        .foregroundStyle(.white)
        .onChange(of: isVisible) { if isVisible { nowPlaying.refreshOptions() } }
        .onChange(of: nowPlaying.title) { if isVisible { nowPlaying.refreshOptions() } }
        .task(id: isVisible) {
            // Keeps the clock, and the lyrics with it, exact while the player shows.
            while isVisible, !Task.isCancelled {
                if nowPlaying.isPlaying { await nowPlaying.syncPosition() }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private static let relayout = AnyTransition.asymmetric(
        insertion: .opacity.animation(.easeOut(duration: 0.22).delay(0.3)),
        removal: .opacity.animation(.easeOut(duration: 0.1)))

    /// The title and the artist, with room for the waveform at the end of the title's line, as on
    /// the iPhone. Both scroll when they don't fit.
    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                // The explicit badge follows the title, as on the iPhone.
                HStack(spacing: 5) {
                    MarqueeText(
                        text: nowPlaying.hasMedia ? nowPlaying.title : "Not Playing",
                        font: .system(size: PlayerLayout.titleSize, weight: .semibold), active: isVisible, fills: false)
                    if nowPlaying.explicit {
                        Image(systemName: "e.square.fill")
                            .font(.system(size: PlayerLayout.titleSize * 0.8))
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                MarqueeText(text: nowPlaying.artist, font: .system(size: PlayerLayout.titleSize), active: isVisible)
                    .foregroundStyle(PlayerLayout.secondary)
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
    /// the edges.
    private var timeline: some View {
        TimelineView(.animation(minimumInterval: 0.5, paused: !(isVisible && nowPlaying.isPlaying))) { context in
            // With nothing playing, no times and an empty bar, as on the iPhone.
            let playing = nowPlaying.hasMedia
            let duration = playing ? nowPlaying.duration : 0
            let position = scrub.map { $0 * duration } ?? (playing ? nowPlaying.position(at: context.date) : 0)
            HStack(spacing: 10) {
                Text(playing ? Self.time(position) : "--:--")
                    .frame(minWidth: 26, alignment: .leading)
                Scrubber(
                    fraction: duration > 0 ? position / duration : 0,
                    color: accentTimeline ? accent : .white.opacity(0.7),
                    spoken: playing ? Self.time(position) + " of " + Self.time(duration) : "",
                    // Ten seconds at a time.
                    step: duration > 0 ? min(10 / duration, 1) : 0
                ) {
                    scrub = $0
                } onCommit: { fraction in
                    nowPlaying.seek(to: fraction * duration)
                    scrub = nil
                }
                .disabled(duration <= 0)
                Text(playing ? "-" + Self.time(duration - position) : "--:--")
                    .frame(minWidth: 30, alignment: .trailing)
            }
            .font(.system(size: PlayerLayout.timeSize, weight: .semibold).monospacedDigit())
            .foregroundStyle(PlayerLayout.secondary)
        }
        .frame(height: PlayerLayout.timelineHeight)
    }

    /// Five equal contact areas, their centers evenly spaced, the outer two starting and ending on the
    /// edges the artwork and the timeline do.
    private var controls: some View {
        EvenRow(leading: PlayerLayout.controlsInset, trailing: PlayerLayout.controlsInset) {
            // (Its places, in order: one side, the three transport controls, the other side.)
            if let places {
                ControlMark(place: .left, control: leftSlot, symbol: symbol(for: leftSlot), places: places)
            } else if nowPlaying.djPlaying {
                // As Spotify puts its DJ where shuffle was, while the DJ chooses the music.
                DJButton(color: buttonGray, talking: nowPlaying.djTalking && nowPlaying.isPlaying) { nowPlaying.openApp() }
                    .transition(.opacity)
            } else {
                slot(leftSlot)
            }
            Group {
                GlyphButton(label: "Previous") {
                    skipsBack += 1
                    nowPlaying.previous()
                } glyph: {
                    SkipSymbol(forward: false, skips: skipsBack)
                }
                IslandButton(
                    symbol: nowPlaying.isPlaying ? "pause.fill" : "play.fill", size: PlayerLayout.playGlyph,
                    label: nowPlaying.isPlaying ? "Pause" : "Play"
                ) {
                    nowPlaying.togglePlayPause()
                }
                GlyphButton(label: "Next") {
                    skipsForward += 1
                    nowPlaying.next()
                } glyph: {
                    SkipSymbol(forward: true, skips: skipsForward)
                }
            }
            .disabled(!nowPlaying.hasMedia)
            .opacity(nowPlaying.hasMedia ? 1 : 0.4)
            .allowsHitTesting(places == nil)
            if let places {
                ControlMark(place: .right, control: rightSlot, symbol: symbol(for: rightSlot), places: places)
            } else {
                slot(rightSlot)
            }
        }
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

    @ViewBuilder private func slot(_ slot: PlayerSlot) -> some View {
        let options = nowPlaying.options
        let size = PlayerLayout.optionGlyph
        let burstColor = accent
        switch slot {
        case .favorite:
            IslandButton(
                symbol: symbol(for: .favorite), size: size,
                color: optionColor(options.favorite), burst: favoriteBursts, burstColor: burstColor, swapsAtOnce: true,
                label: slot.title, value: Self.spoken(options.favorite)
            ) {
                if options.favorite == false { favoriteBursts += 1 }
                nowPlaying.toggleFavorite()
            }
            .disabled(options.favorite == nil)
        case .shuffle:
            // Off, struck through rather than dimmed.
            IslandButton(
                symbol: "shuffle", size: size, color: switchColor(options.shuffle), slashed: options.shuffle != true,
                label: slot.title, value: Self.spoken(options.shuffle)
            ) {
                nowPlaying.toggleShuffle()
            }
            .disabled(options.shuffle == nil)
        case .repeatMode:
            IslandButton(
                symbol: symbol(for: .repeatMode), size: size, color: switchColor(options.repeatMode.map { $0 != .off }),
                slashed: repeatSlashed, label: slot.title, value: options.repeatMode?.rawValue.capitalized
            ) {
                nowPlaying.cycleRepeat()
            }
            .disabled(options.repeatMode == nil)
        case .output:
            IslandButton(symbol: output.symbol, size: size, color: buttonGray, label: slot.title) { output.showMenu() }
        case .lyrics:
            IslandButton(
                symbol: symbol(for: .lyrics), size: size,
                color: optionColor(lyricsControl.available ? lyricsControl.shown : nil),
                label: slot.title, value: Self.spoken(lyricsControl.available ? lyricsControl.shown : nil)
            ) {
                lyricsControl.toggle()
            }
            .disabled(!lyricsControl.available)
        case .empty:
            // Nothing, but the space stays, so the transport controls stay where they are.
            Color.clear.frame(width: Self.hitbox, height: Self.hitbox)
        }
    }

    /// An option's state as VoiceOver says a switch's.
    private static func spoken(_ on: Bool?) -> String? {
        on.map { $0 ? "On" : "Off" }
    }

    /// Shuffle and repeat: the artist's gray, on or off (off, they're struck through); faint when the
    /// app doesn't offer them.
    private func switchColor(_ on: Bool?) -> Color {
        on == nil ? buttonGray.opacity(0.4) : buttonGray
    }

    /// The artist's gray when on, as on the iPhone, so only play and the skip buttons are white;
    /// a step dimmer when off (the iPhone's resting star), faint when the app doesn't offer it.
    private func optionColor(_ on: Bool?) -> Color {
        switch on {
        case true?: buttonGray
        case false?: colorScheme == .light ? Color(white: 0.78) : PlayerLayout.optionOff
        case nil: buttonGray.opacity(0.4)
        }
    }

    /// In light mode the glass at the bottom of the notch shows light windows through it, which the
    /// artist's gray would vanish into, so the side buttons are lighter there.
    private var buttonGray: Color {
        colorScheme == .light ? Color(white: 0.88) : PlayerLayout.secondary
    }

    private static func time(_ seconds: Double) -> String {
        let total = Int(max(seconds, 0).rounded())
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
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
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            } else {
                Circle()
                    .strokeBorder(.white.opacity(0.5), style: StrokeStyle(lineWidth: 1.2, dash: [3, 2.5]))
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
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

    /// forward.fill at the skip buttons' size: 28 by 18 points at 18.
    private static let image: NSImage? = NSImage(systemSymbolName: "forward.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: PlayerLayout.skipGlyph, weight: .semibold))

    var body: some View {
        if let image = Self.image {
            SkipArrows(phase: Double(skips), image: image)
                .frame(width: image.size.width, height: image.size.height)
                .scaleEffect(x: forward ? 1 : -1)
                // Settling without overshoot: past the end, the motion would start over.
                .animation(.spring(response: 0.36, dampingFraction: 1), value: skips)
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
