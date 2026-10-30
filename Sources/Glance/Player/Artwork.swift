//
//  Artwork.swift
//  Glance
//
//  Created by Gaty on 07/10/2026.
//

import AppKit
import SwiftUI

/// The one artwork that flies between the closed notch and the open player, its corners rounding
/// from the closed notch's to the player's as it grows. The playing app's icon sits on its corner
/// in the player. Clicked, the cover or the icon goes where it plays from: its tab in the browser,
/// the playlist it plays from.
struct HeroArtwork: View {
    @EnvironmentObject private var nowPlaying: NowPlaying
    @ObservedObject private var motion = MotionArtworkStore.shared
    @Environment(\.playerLayout) private var layout
    @AppStorage(Preferences.musicAnimatedArtwork) private var animated = true
    @AppStorage(Preferences.musicAppBadge) private var showsBadge = false
    let isOpen: Bool
    /// The artwork's side in the closed notch.
    let restingSide: CGFloat
    @State private var motionReady = false
    @Environment(\.notchThumbnail) private var thumbnail
    /// With Reduce Motion on, the cover is its picture, never the moving one.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The pointer on the open cover, which lifts it a little and lights it, and a click held on it,
    /// which squashes it down, as a soft button (see `CoverMotion`).
    @State private var coverHovered = false
    @State private var coverPressed = false

    /// The app icon's tile on the cover, one size in every layout, and how far past the cover's
    /// corner its corner is.
    static let badgeTile: CGFloat = 25
    static let badgePast: CGFloat = 3

    var body: some View {
        let size = layout.artwork
        let video =
            animated && !nowPlaying.isDemo && !reduceMotion ? motion.video(artist: nowPlaying.artist, album: nowPlaying.album) : nil
        // Under the pointer, it lights and rises, with a soft shadow that spreads as it lifts and
        // draws in close as it's pressed down.
        let light: Double = coverHovered ? (coverPressed ? 0.04 : 0.08) : 0
        let shadow: Double = coverHovered ? (coverPressed ? 0.3 : 0.45) : 0
        let shadowRadius: CGFloat = coverHovered ? (coverPressed ? 4 : 14) : 6
        let shadowY: CGFloat = coverHovered ? (coverPressed ? 1.5 : 7) : 2
        let rise: CGFloat = coverHovered && !coverPressed && !reduceMotion ? -1.5 : 0
        // Exactly the square it's given: artwork that isn't square, like a video's thumbnail, is
        // cropped to fill it.
        Color.clear
            .overlay {
                // A new song's cover comes in as the last one goes, as the Dynamic Island's activities
                // come and go.
                ZStack {
                    if let artwork = nowPlaying.artwork {
                        Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fill)
                            .id(ObjectIdentifier(artwork))
                            .transition(IslandMotion.fade)
                    } else {
                        // A disc while nothing plays; a note for a song without artwork.
                        GeometryReader { proxy in
                            Image(systemName: nowPlaying.hasMedia ? "music.note" : "opticaldisc.fill")
                                .font(.system(size: proxy.size.width * 0.34))
                                .foregroundStyle(.white.opacity(0.5))
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .background(.white.opacity(0.08))
                        .transition(IslandMotion.fade)
                    }
                }
                .animation(IslandMotion.open, value: nowPlaying.artwork.map(ObjectIdentifier.init))
            }
            .overlay {
                // The moving cover, in the open player, once it can show its first frame.
                if let video, !thumbnail {
                    MotionArtworkView(url: video, playing: isOpen && nowPlaying.isPlaying) { motionReady = $0 }
                        .id(video)
                        .opacity(isOpen && motionReady ? 1 : 0)
                        .animation(.easeInOut(duration: 0.5), value: motionReady)
                }
            }
            // Like Music's mini player: the artwork dims (see `PausedLook`), and settles back a
            // little, while paused.
            .overlay(Color.black.opacity(nowPlaying.hasMedia && !nowPlaying.isPlaying ? 1 - PausedLook.kept : 0))
            .overlay(Color.white.opacity(light))
            .clipShape(
                ArtworkShape(
                    small: restingSide, smallRadius: restingSide * ArtworkShape.restingRadius,
                    large: size, largeRadius: layout.artworkRadius)
            )
            .shadow(color: .black.opacity(shadow), radius: shadowRadius, y: shadowY)
            // The light and the shadow ease in and out, without the cover's bounce.
            .animation(CoverMotion.light, value: coverHovered)
            .animation(CoverMotion.light, value: coverPressed)
            .onChange(of: video) { motionReady = false }
            // Looked up when the player opens on a new album.
            .onChange(
                of: isOpen && animated ? [nowPlaying.artist, nowPlaying.album, nowPlaying.artwork == nil ? "" : "cover"] : [],
                initial: true
            ) {
                if isOpen, animated, !nowPlaying.isDemo, !reduceMotion {
                    motion.load(
                        title: nowPlaying.title, artist: nowPlaying.artist, album: nowPlaying.album,
                        albumID: nowPlaying.albumID, artwork: nowPlaying.artwork)
                }
            }
            .overlay { sourceButton }
            .overlay {
                // The playing app, on the artwork's corner. Click it to go there, as the cover. One size
                // always, whatever the layout or the cover's size as it flies; its corner just past the
                // cover's, which it moves with. An icon's tile fills four fifths of its image.
                if let icon = nowPlaying.appIcon {
                    GeometryReader { proxy in
                        let tile = Self.badgeTile, past = Self.badgePast
                        let mark = tile / 0.8
                        Button {
                            nowPlaying.openSource()
                        } label: {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: mark, height: mark)
                                .shadow(color: .black.opacity(0.4), radius: 2.5, y: 1)
                        }
                        .buttonStyle(IslandPress(highlight: false, contactSize: nil))
                        .notchControl(enabled: showsBadge && isOpen)
                        .accessibilityLabel(
                            nowPlaying.appBundleID.flatMap(InstalledApps.name).map { "Open \($0)" } ?? "Open App"
                        )
                        .accessibilityHidden(!(showsBadge && isOpen))
                        .position(x: proxy.size.width + past - tile / 2, y: proxy.size.height + past - tile / 2)
                    }
                    // Only its fading has timing of its own, as everything in the notch comes and goes;
                    // where it is and how large come with the cover's own motion.
                    .islandFade(isOpen && showsBadge)
                    .allowsHitTesting(showsBadge && isOpen)
                }
            }
            .scaleEffect(isOpen && nowPlaying.hasMedia && !nowPlaying.isPlaying ? 0.92 : 1)
            .animation(.spring(response: 0.45, dampingFraction: 0.8), value: nowPlaying.isPlaying)
            // Lifted under the pointer, squashed while held, sprung back past its lift when let go.
            .scaleEffect(x: coverScale.width, y: coverScale.height)
            .offset(y: rise)
            .animation(CoverMotion.hover, value: coverHovered)
            .animation(coverPressed ? CoverMotion.press : CoverMotion.release, value: coverPressed)
            .onChange(of: isOpen) { _, open in
                if !open {
                    coverHovered = false
                    coverPressed = false
                }
            }
    }

    /// Lifted under the pointer, squashed while held; with Reduce Motion on, it only lights.
    private var coverScale: CGSize {
        guard !reduceMotion else { return CGSize(width: 1, height: 1) }
        if coverPressed { return CoverMotion.squashed }
        return coverHovered ? CoverMotion.lifted : CGSize(width: 1, height: 1)
    }
}

/// How the open cover answers the pointer, as a soft button does: it lifts gently, with a little
/// bounce; pressed, it squashes down quickly, a little more in height than in width; let go, it
/// springs back on a looser spring, past its lift, and settles.
enum CoverMotion {
    static let hover = Animation.spring(response: 0.45, dampingFraction: 0.55)
    static let press = Animation.spring(response: 0.16, dampingFraction: 0.82)
    static let release = Animation.spring(response: 0.48, dampingFraction: 0.45)
    /// The light on it and its shadow.
    static let light = Animation.easeOut(duration: 0.3)

    static let lifted = CGSize(width: 1.04, height: 1.04)
    static let squashed = CGSize(width: 0.96, height: 0.935)
}

extension HeroArtwork {
    /// The open cover goes where it plays from (see `PlayingSource`).
    private var sourceButton: some View {
        let clickable = isOpen && nowPlaying.hasMedia
        return Button {
            nowPlaying.openSource()
        } label: {
            Color.clear.contentShape(Rectangle())
        }
        .buttonStyle(PressReporting(pressed: $coverPressed))
        .onHover { coverHovered = $0 && clickable }
        .notchControl(enabled: clickable)
        .allowsHitTesting(clickable)
        .help(nowPlaying.appBundleID.flatMap(InstalledApps.name).map { "Show in \($0)" } ?? "Show Where It's Playing")
        .accessibilityLabel("Show Where It's Playing")
        .accessibilityHidden(!clickable)
    }
}

/// A button that tells whether it's held down, so what it sits on can press in as a whole.
private struct PressReporting: ButtonStyle {
    @Binding var pressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, down in pressed = down }
    }
}

/// A rounded square whose corners follow its size: the closed notch's radius when small, the
/// player's when large, and in between while it flies.
struct ArtworkShape: Shape {
    /// The artwork's corner radius in the closed notch, for its side.
    static let restingRadius: CGFloat = 0.3

    var small: CGFloat
    var smallRadius: CGFloat
    var large: CGFloat
    var largeRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let progress = min(max((rect.width - small) / max(large - small, 1), 0), 1)
        let radius = smallRadius + (largeRadius - smallRadius) * progress
        return RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect)
    }
}

/// The artwork's light behind the open player: its colors flowing, as in Apple Music, or the accent
/// color's. The notch gives it its shape: across the whole bottom, or a round glow in a corner.
struct ArtworkLight: View {
    @EnvironmentObject private var nowPlaying: NowPlaying
    @AppStorage(Preferences.musicAccentSource) private var accentSource = AccentSource.artwork
    let active: Bool

    var body: some View {
        let flow = nowPlaying.flow(from: accentSource)
        ZStack {
            if let flow {
                ArtworkSwirl(flow: flow, active: active && nowPlaying.isPlaying, demo: nowPlaying.isDemo)
                    .transition(.opacity)
                    .id(ObjectIdentifier(flow))
            } else {
                nowPlaying.accent(from: accentSource)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.8), value: flow.map(ObjectIdentifier.init))
        .animation(.easeInOut(duration: 0.5), value: accentSource)
    }
}

/// The flowing colors (see `ArtworkFlow`), filling the background. On each beat of the music, as
/// it's heard, they swell and brighten just a little and ease back.
struct ArtworkSwirl: View {
    let flow: ArtworkFlow
    let active: Bool
    /// The welcome tour's made-up song, whose beat is made up too.
    var demo = false
    /// With Reduce Motion on, the colors stay where they are.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !active || reduceMotion)) { context in
                let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
                let pulse = active && !reduceMotion ? CGFloat(demo ? WaveformGlyph.demoKick(at: t) * 0.5 : Double(AudioLevels.shared.pulse)) : 0
                if let frame = flow.frame(at: t) {
                    Image(decorative: frame.background, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .scaleEffect(1 + 0.015 * pulse)
                        .brightness(0.03 * pulse)
                }
            }
        }
        .clipped()
    }
}
