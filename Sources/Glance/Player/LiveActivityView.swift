//
//  LiveActivityView.swift
//  Glance
//
//  Created by Gaty on 07/10/2026.
//

import AppKit
import SwiftUI

/// The closed notch while music plays, like the Dynamic Island's compact activity: the artwork on
/// one side of the camera, the waveform on the other, each at its wing's end, as far in from it as
/// from the top and bottom, so it sits concentric with the round end. The notch draws those two,
/// flying them in and out of the open player, and marks where they rest; this keeps room for them,
/// and shows a new song's title and artist when the wings widen to announce it, from the ends too,
/// any room to spare beside the camera.
struct LiveActivityView: View {
    @EnvironmentObject private var nowPlaying: NowPlaying
    @AppStorage(Preferences.musicAccentSource) private var accentSource = AccentSource.artwork
    /// The closed notch's height at rest, which the layout is made for.
    let restingHeight: CGFloat
    /// On a Dynamic Island, shorter than a notch and round at its ends, they sit differently.
    /// Each wing's width beside the camera.
    let wing: CGFloat
    /// Announcing a new song.
    let pop: Bool
    /// How much the notch has swollen under the pointer: the artwork and the waveform swell as
    /// much, and their padding with them, so they stay as far from its ends as from its top and
    /// bottom.
    var swell: CGFloat = 1
    /// Above, below and in from the ends of what other activities show beside the camera.
    static let inset: CGFloat = 6

    /// iOS 27's island Now Playing (`MRUActivityNowPlayingView`), by the island's height, 36.67
    /// points: the cover a 23-point square 9 in from its end, centered; the waveform's 22-point box 9
    /// in from the other end.
    static func coverSide(_ h: CGFloat) -> CGFloat { h * 23 / 36.67 }
    static func waveformSide(_ h: CGFloat) -> CGFloat { h * 22 / 36.67 }
    static func musicEdge(_ h: CGFloat) -> CGFloat { h * 9 / 36.67 }
    /// Where the cover and the waveform stand in their wings, which stay as wide as iOS 27's: as far
    /// in from the ends as the cover is from the top and bottom (the user, 2026-11-28: the padding
    /// "consistent all around").
    static func musicPadding(_ h: CGFloat) -> CGFloat { concentric(coverSide(h), in: h) }

    /// The least between what the wings show and the camera housing, both black: as near as can be
    /// without anything going under it.
    static let cameraGap: CGFloat = 3

    /// How far in from a wing's round end something as tall as this sits: as far as from the top and
    /// bottom, so it's concentric with the end, as the Dynamic Island keeps its own.
    static func concentric(_ content: CGFloat, in height: CGFloat) -> CGFloat { max((height - content) / 2, 0) }

    /// A line of words' height at this size, as it's laid out.
    static func lineHeight(_ size: CGFloat, _ weight: NSFont.Weight = .semibold) -> CGFloat {
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        return font.ascender - font.descender + font.leading
    }

    /// How far in from a wing's end its words sit: as far as above and below their line.
    static func textEdge(restingHeight h: CGFloat) -> CGFloat { concentric(lineHeight(textSize(for: h)), in: h) }

    /// Each wing at rest with music: the cover and the waveform where iOS 27 puts them, up to the
    /// camera.
    static func restingWing(restingHeight h: CGFloat) -> CGFloat { musicEdge(h) + max(coverSide(h), waveformSide(h)) + cameraGap }
    /// Between the artwork and the title.
    static let textGap: CGFloat = 8

    /// As the iPhone's words and numbers beside the camera, measured from it.
    static func textSize(for restingHeight: CGFloat) -> CGFloat { min(max(restingHeight * 0.426, 11), 14) }

    /// How wide each wing must be for the title and the artist to show in full, up to a limit
    /// past which they scroll instead. The notch stays centered, so both wings take the wider one.
    static func popWing(title: String, artist: String, restingHeight: CGFloat) -> CGFloat {
        let size = textSize(for: restingHeight)
        func width(_ text: String, _ weight: NSFont.Weight) -> CGFloat {
            // A point to spare, so rounding never sets a title that fits scrolling.
            ceil((text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight)]).width) + 2
        }
        let left = musicEdge(restingHeight) + coverSide(restingHeight) + textGap + width(title, .semibold) + cameraGap
        let right = cameraGap + width(artist, .medium) + textEdge(restingHeight: restingHeight)
        return min(max(left, right, restingHeight), NotchModel.maxPopWing)
    }

    /// A new song's name, kept on once its moment is over as it fades while the wings fold, so it
    /// rides in with their ends, as the Dynamic Island's activities do, rather than standing where it
    /// was; and the room it had. Kept from the start, so it never leaves as well as fading.
    @State private var popKept = false
    @State private var popLane: CGFloat = 0
    /// Counted, so the name goes only if nothing has changed since.
    @State private var popChanges = 0

    var body: some View {
        let edge = Self.musicPadding(restingHeight) * swell
        let side = Self.coverSide(restingHeight) * swell
        let waveform = Self.waveformSide(restingHeight) * swell
        let popLeaving = popKept && !pop
        let words = pop || popKept
        let lane = popLeaving ? max(popLane, wing - edge - Self.cameraGap, side) : max(wing - edge - Self.cameraGap, side)
        // The artist, in place of the waveform, as far in as above and below its line.
        let textEdge = Self.textEdge(restingHeight: restingHeight)
        let size = Self.textSize(for: restingHeight)
        let accent = nowPlaying.accent(from: accentSource)
        // Each side kept to its own end, so it rides in and out with it.
        ZStack {
            HStack(spacing: Self.textGap) {
                // The cover's room (see `NotchView.restingPlaces`).
                Color.clear
                    .frame(width: side, height: side)
                if words {
                    // In the cover's color, made light enough to read on the black notch.
                    MarqueeText(text: nowPlaying.title, font: .system(size: size, weight: .semibold), active: true)
                        .foregroundStyle(accent.readableOnBlack())
                        .islandFade(pop)
                        .transition(IslandMotion.fade)
                }
            }
            // From the end; to spare, beside the camera.
            .frame(width: lane, alignment: .leading)
            .padding(.leading, edge)
            .frame(maxWidth: .infinity, alignment: .leading)
            ZStack(alignment: .trailing) {
                // The waveform's room.
                Color.clear
                    .frame(width: waveform, height: waveform)
                    .padding(.trailing, edge)
                if words {
                    MarqueeText(text: nowPlaying.artist, font: .system(size: size, weight: .medium), active: true, alignment: .trailing)
                        .foregroundStyle(accent.readableOnBlack(opacity: 0.7))
                        .islandFade(pop)
                        .transition(IslandMotion.fade)
                        .frame(width: max(lane + edge - textEdge, 0), alignment: .trailing)
                        .padding(.trailing, textEdge)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(maxHeight: .infinity)
        .onChange(of: wing, initial: true) {
            if pop { popLane = max(wing - edge - Self.cameraGap, side) }
        }
        .onChange(of: pop, initial: true) { _, new in
            popChanges += 1
            if new { popKept = true; return }
            let change = popChanges
            Task { @MainActor in
                try? await Task.sleep(for: SystemActivityView.folding)
                if popChanges == change { popKept = false }
            }
        }
    }
}
