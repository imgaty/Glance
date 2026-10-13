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
/// in the player.
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

    /// The app icon's tile on the cover, one size in every layout, and how far past the cover's
    /// corner its corner is.
    static let badgeTile: CGFloat = 25
    static let badgePast: CGFloat = 3

    var body: some View {
        let size = layout.artwork
        let video =
            animated && !nowPlaying.isDemo && !reduceMotion ? motion.video(artist: nowPlaying.artist, album: nowPlaying.album) : nil
        // Exactly the square it's given: artwork that isn't square, like a video's thumbnail, is
        // cropped to fill it.
        Color.clear
            .overlay {
                if let artwork = nowPlaying.artwork {
                    Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fill)
                } else {
                    // A disc while nothing plays; a note for a song without artwork.
                    GeometryReader { proxy in
                        Image(systemName: nowPlaying.hasMedia ? "music.note" : "opticaldisc.fill")
                            .font(.system(size: proxy.size.width * 0.34))
                            .foregroundStyle(.white.opacity(0.5))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .background(.white.opacity(0.08))
                }
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
            // Like Music's mini player: the artwork dims, and settles back a little, while paused.
            .overlay(Color.black.opacity(nowPlaying.hasMedia && !nowPlaying.isPlaying ? 0.4 : 0))
            .clipShape(
                ArtworkShape(
                    small: restingSide, smallRadius: restingSide * ArtworkShape.restingRadius,
                    large: size, largeRadius: layout.artworkRadius)
            )
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
            .overlay {
                // The playing app, on the artwork's corner. Click it to switch to the app. One size
                // always, whatever the layout or the cover's size as it flies; its corner just past the
                // cover's, which it moves with. An icon's tile fills four fifths of its image.
                if let icon = nowPlaying.appIcon {
                    GeometryReader { proxy in
                        let tile = Self.badgeTile, past = Self.badgePast
                        let mark = tile / 0.8
                        Button {
                            nowPlaying.openApp()
                        } label: {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: mark, height: mark)
                                .shadow(color: .black.opacity(0.4), radius: 2.5, y: 1)
                        }
                        .buttonStyle(IslandPress(highlight: false, contactSize: nil))
                        .notchControl(enabled: showsBadge && isOpen)
                        .accessibilityLabel(
                            nowPlaying.appBundleID.flatMap(TrayItemPicture.appName).map { "Open \($0)" } ?? "Open App"
                        )
                        .accessibilityHidden(!(showsBadge && isOpen))
                        .position(x: proxy.size.width + past - tile / 2, y: proxy.size.height + past - tile / 2)
                    }
                    // Only its fading has timing of its own; where it is and how large come with the
                    // cover's own motion.
                    .animation(isOpen ? .easeOut(duration: 0.15) : .easeOut(duration: 0.1)) {
                        $0.opacity(isOpen && showsBadge ? 1 : 0)
                    }
                    .allowsHitTesting(showsBadge && isOpen)
                }
            }
            .scaleEffect(isOpen && nowPlaying.hasMedia && !nowPlaying.isPlaying ? 0.92 : 1)
            .animation(.spring(response: 0.45, dampingFraction: 0.8), value: nowPlaying.isPlaying)
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

/// The artwork's light behind the open player: the artwork itself, hugely blurred and slowly
/// turning, as in Apple Music, or the accent color, darkened by `dim`. The notch gives it its shape:
/// across the whole bottom, or a round glow in a corner.
struct ArtworkLight: View {
    @EnvironmentObject private var nowPlaying: NowPlaying
    @AppStorage(Preferences.musicAccentSource) private var accentSource = AccentSource.artwork
    let dim: Double
    let active: Bool

    var body: some View {
        ZStack {
            if accentSource == .artwork, let image = nowPlaying.wash {
                ArtworkSwirl(image: image, active: active && nowPlaying.isPlaying)
                    .transition(.opacity)
                    .id(ObjectIdentifier(image))
            } else if let color = accentSource.nsColor, let image = AccentWash.image(for: color) {
                // A color moves through its own shades, as the artwork's colors do.
                ArtworkSwirl(image: image, active: active && nowPlaying.isPlaying)
                    .transition(.opacity)
                    .id(ObjectIdentifier(image))
            } else {
                nowPlaying.accent(from: accentSource)
                    .transition(.opacity)
            }
        }
        .overlay(Color.black.opacity(dim))
        .animation(.easeInOut(duration: 0.8), value: nowPlaying.wash.map(ObjectIdentifier.init))
        .animation(.easeInOut(duration: 0.5), value: dim)
        .animation(.easeInOut(duration: 0.5), value: accentSource)
    }
}

/// Three copies of an already blurred artwork, large, middling and small, each turning and drifting
/// at its own pace, so the colors keep slowly moving through one another. The smaller two fade out
/// toward their edges, so no edge ever shows.
struct ArtworkSwirl: View {
    let image: NSImage
    let active: Bool
    /// With Reduce Motion on, the colors stay where they are.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let side = max(proxy.size.width, proxy.size.height)
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !active || reduceMotion)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                ZStack {
                    layer(side * 1.5, turn: t / 24, drift: .zero, soft: false)
                    layer(
                        side * 0.9, turn: -t / 17 + 0.3,
                        drift: CGSize(width: cos(t / 3) * side * 0.2, height: sin(t / 3.7) * side * 0.14))
                    layer(
                        side * 0.65, turn: t / 13 + 0.6,
                        drift: CGSize(width: sin(t / 2.4) * side * 0.24, height: cos(t / 2.7) * side * 0.16))
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .clipped()
    }

    private func layer(_ size: CGFloat, turn: Double, drift: CGSize, soft: Bool = true) -> some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .mask {
                if soft {
                    RadialGradient(
                        colors: [.black, .black.opacity(0.8), .clear], center: .center,
                        startRadius: 0, endRadius: size / 2)
                } else {
                    Color.black
                }
            }
            .rotationEffect(.radians(turn * 2 * .pi))
            .offset(drift)
    }
}
