//
//  LiveActivityView.swift
//  Glance
//
//  Created by Gaty on 07/10/2026.
//

import AppKit
import SwiftUI

/// The closed notch while music plays, like the Dynamic Island's compact activity: the artwork on
/// one side of the camera, the waveform on the other. The notch draws those two, flying them in and
/// out of the open player; this marks their places, and shows a new song's title and artist when
/// the wings widen to announce it.
struct LiveActivityView: View {
    @EnvironmentObject private var nowPlaying: NowPlaying
    @AppStorage(Preferences.musicAccentSource) private var accentSource = AccentSource.artwork
    /// The closed notch's height at rest, which the layout is made for.
    let restingHeight: CGFloat
    /// On a Dynamic Island, shorter than a notch and round at its ends, they sit differently.
    let island: Bool
    /// Each wing's width beside the camera.
    let wing: CGFloat
    /// Announcing a new song.
    let pop: Bool
    let hero: Namespace.ID
    /// Above and below the artwork and the waveform: a little less on an island, which is shorter
    /// than a notch, so they're about as big there. Both sit in squares of the same size.
    static func inset(island: Bool) -> CGFloat { island ? 3.5 : 6 }

    /// In from the ends. An island's ends are round, so the artwork sits in from them by as much as
    /// keeps its rounded corners as far from the curve as from the top and bottom, as the iPhone's
    /// does; nearer, it crowds the end.
    static func edgeInset(island: Bool, restingHeight: CGFloat) -> CGFloat {
        let inset = inset(island: island)
        guard island else { return inset }
        let side = restingHeight - inset * 2
        return max(restingHeight / 2 - side * ArtworkShape.restingRadius, inset)
    }
    /// Between the song's title or artist and the camera.
    static let cameraGap: CGFloat = 10
    /// Between the artwork and the title.
    static let textGap: CGFloat = 8

    static func textSize(for restingHeight: CGFloat) -> CGFloat { min(max(restingHeight * 0.4, 11), 13) }

    /// How wide each wing must be for the title and the artist to show in full, up to a limit
    /// past which they scroll instead. The notch stays centered, so both wings take the wider one.
    static func popWing(title: String, artist: String, restingHeight: CGFloat, island: Bool) -> CGFloat {
        let inset = inset(island: island), edge = edgeInset(island: island, restingHeight: restingHeight)
        let size = textSize(for: restingHeight)
        func width(_ text: String, _ weight: NSFont.Weight) -> CGFloat {
            // A point to spare, so rounding never sets a title that fits scrolling.
            ceil((text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight)]).width) + 2
        }
        let side = restingHeight - inset * 2
        let left = edge + side + textGap + width(title, .semibold) + cameraGap
        let right = cameraGap + width(artist, .regular) + edge
        return min(max(left, right, restingHeight), NotchModel.maxPopWing)
    }

    var body: some View {
        let edge = Self.edgeInset(island: island, restingHeight: restingHeight)
        let side = restingHeight - Self.inset(island: island) * 2
        let lane = max(wing - edge - Self.cameraGap, side)
        let size = Self.textSize(for: restingHeight)
        let accent = nowPlaying.accent(from: accentSource)
        HStack(spacing: 0) {
            HStack(spacing: Self.textGap) {
                Color.clear
                    .frame(width: side, height: side)
                    .matchedGeometryEffect(id: Hero.liveArtwork, in: hero)
                if pop {
                    // In the cover's color, made light enough to read on the black notch.
                    MarqueeText(text: nowPlaying.title, font: .system(size: size, weight: .semibold), active: true)
                        .foregroundStyle(accent.readableOnBlack())
                        .transition(Self.announce)
                }
            }
            .frame(width: lane, alignment: .leading)
            Spacer(minLength: 0)
            ZStack(alignment: .trailing) {
                Color.clear
                    .frame(width: side, height: side)
                    .matchedGeometryEffect(id: Hero.liveWaveform, in: hero)
                if pop {
                    MarqueeText(text: nowPlaying.artist, font: .system(size: size), active: true, alignment: .trailing)
                        .foregroundStyle(accent.readableOnBlack(opacity: 0.7))
                        .transition(Self.announce)
                }
            }
            .frame(width: lane, alignment: .trailing)
        }
        .padding(.horizontal, edge)
        .frame(maxHeight: .infinity)
    }

    /// The words come in once the wings have opened, and leave before they fold.
    private static let announce = AnyTransition.asymmetric(
        insertion: .opacity.animation(.easeOut(duration: 0.3).delay(0.25)),
        removal: .opacity.animation(.easeOut(duration: 0.12)))
}
