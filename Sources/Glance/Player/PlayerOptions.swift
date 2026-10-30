//
//  PlayerOptions.swift
//  Glance
//
//  Created by Gaty on 07/10/2026.
//

import AppKit
import CoreImage
import SwiftUI

/// The player's layouts, after the iPhone's Dynamic Island: the same padding on every side, the
/// artwork up in the corner beside the camera, and the shorter title and artist centered on it,
/// below the camera.
enum PlayerLayout: String, CaseIterable, Identifiable {
    case top, side

    var id: Self { self }
    var title: String {
        switch self {
        case .top: "Cover on top"
        case .side: "Cover on the side"
        }
    }

    static var current: PlayerLayout {
        PlayerLayout(rawValue: UserDefaults.standard.string(forKey: Preferences.musicLayout) ?? "") ?? .top
    }

    /// Around everything, on every side.
    static let padding: CGFloat = 18
    /// Kept between the camera housing and anything below it, and anything beside it.
    static let cameraGap: CGFloat = 4
    static let besideCamera: CGFloat = 8
    static let titleSize: CGFloat = 14
    static let timeSize: CGFloat = 10
    /// Apple's gray for the artist and the times: solid, so the background never tints it.
    static let secondary = Color(red: 158 / 255, green: 158 / 255, blue: 162 / 255)
    /// An option that's off: the gray of the iPhone's star and AirPods buttons, also solid.
    static let optionOff = Color(red: 130 / 255, green: 130 / 255, blue: 134 / 255)
    /// The title and the artist, one line each with no space between.
    static let headerHeight: CGFloat = 34
    static let waveform = CGSize(width: 21, height: 22)
    /// Between the artwork and what sits beside it.
    static let besideArtwork: CGFloat = 17
    static let timelineHeight: CGFloat = 16
    /// Play and pause are the largest glyphs, back and forward next, the two option buttons smallest.
    static let playGlyph: CGFloat = 28
    static let skipGlyph: CGFloat = 18
    static let optionGlyph: CGFloat = 17.5
    /// The open notch's corners, all four: the padding plus the top cover's corners, so they're
    /// concentric with it.
    static let cornerRadius: CGFloat = padding + 11

    var artwork: CGFloat { self == .top ? 60 : 120 }

    /// How far in from the controls' row its outer contact areas' centers are: the circles' edges sit
    /// on the padding, lined up with the artwork and the times.
    static let controlsInset: CGFloat = NowPlayingView.hitbox / 2
    /// The waveform sits centered over the time left, as on the iPhone; "-0:00" is the width taken.
    static let waveformInset: CGFloat = {
        let font = NSFont.monospacedDigitSystemFont(ofSize: timeSize, weight: .semibold)
        let width = ("-0:00" as NSString).size(withAttributes: [.font: font]).width
        return max((width - waveform.width) / 2, 0)
    }()
    var artworkRadius: CGFloat { self == .top ? 11 : 14 }

    /// The open notch's size around a camera housing of the given size. It's wide enough that the
    /// artwork, up in its corner, stays clear of the housing.
    func size(closed: CGSize) -> CGSize {
        let p = Self.padding
        let besideCamera = closed.width + 2 * (p + artwork + Self.besideCamera)
        let (width, height): (CGFloat, CGFloat) =
            switch self {
            case .top:
                // The controls' contact areas end the padding's width from the bottom edge, as the outer
                // ones do from the sides.
                (
                    max(p * 2 + 280, besideCamera),
                    p + artwork + 12 + Self.timelineHeight + 8 + NowPlayingView.hitbox + p
                )
            case .side:
                // The column beside the artwork starts below the camera.
                (
                    max(p * 2 + artwork + Self.besideArtwork + 280, besideCamera),
                    p + max(artwork, closed.height + Self.cameraGap - p + NowPlayingView.sideColumnHeight) + p
                )
            }
        return CGSize(width: (width / 2).rounded(.up) * 2, height: height)
    }
}

extension EnvironmentValues {
    /// The closed notch's size: the camera housing, on displays that have one.
    @Entry var closedNotch = CGSize(width: 185, height: 32)
    /// The notch's current layout, which changes in step with its size.
    @Entry var playerLayout = PlayerLayout.top
    /// In Settings' picture of the player, its controls' places are marked, and say where they are.
    @Entry var controlPlaces: ControlPlaces? = nil
    /// The notch itself on the screen, rather than a picture of it.
    @Entry var notchOnScreen = false
    /// Settings' pictures of the notch on pages not shown: nothing in them moves.
    @Entry var notchPaused = false
    /// Settings' small pictures of the notch, drawn whole at their own size: the glass as it looks,
    /// and the cover still.
    @Entry var notchThumbnail = false
    /// A light cover's colors are behind the player, so its grays have to be lighter.
    @Entry var playerOnLight = false
    @Entry var lyricsControl = LyricsControl()
    /// Where the welcome tour's pointer is, in the notch's own points from its top left
    /// (`NotchView.bodySpace`), so what's in the notch answers it as it answers the real one.
    @Entry var demoPointer: CGPoint? = nil
}

extension CGRect {
    /// Whether the tour's pointer is over this, in the notch's own points.
    func holds(_ pointer: CGPoint?) -> Bool { pointer.map(contains) ?? false }
}

/// The artwork's colors behind the open player: in place of the glass (under the black at the
/// top), as a spotlight around the cover, or not at all. The raw values keep earlier choices;
/// "spotlight" was Fullscreen, which is gone, and goes back to the first of these.
enum MusicBackground: String, CaseIterable, Identifiable {
    case replaceGlass = "artwork"
    case spotlight = "cover"
    case none

    var id: Self { self }
    var title: String {
        switch self {
        case .replaceGlass: "Replace glass"
        case .spotlight: "Spotlight"
        case .none: "None"
        }
    }
}

/// Where the player's color comes from: the playing artwork, the Mac's accent color, or one of the
/// colors System Settings offers for it.
enum AccentSource: String, CaseIterable, Identifiable {
    case artwork, system, blue, purple, pink, red, orange, yellow, green, graphite

    var id: Self { self }
    var title: String {
        switch self {
        case .artwork: "Artwork"
        case .system: "System"
        default: rawValue.capitalized
        }
    }

    /// nil for the artwork's, which changes with the song.
    var color: Color? { nsColor.map(Color.init(nsColor:)) }

    var nsColor: NSColor? {
        switch self {
        case .artwork: nil
        case .system: .controlAccentColor
        case .blue: .systemBlue
        case .purple: .systemPurple
        case .pink: .systemPink
        case .red: .systemRed
        case .orange: .systemOrange
        case .yellow: .systemYellow
        case .green: .systemGreen
        case .graphite: .systemGray
        }
    }
}

/// A palette's own wash, as the artwork's colors are: patches of its colors, lighter, deeper, and a
/// touch warmer and cooler, softly blurred together, so the swirl has shades to move through. Without
/// a color, as for a cover in black and white, a soft white's.
@MainActor
enum AccentWash {
    private static var made: [String: NSImage] = [:]
    private static let context = CIContext()

    static func image(for palette: [NSColor]) -> NSImage? {
        let colors = (palette.isEmpty ? [NSColor(white: 0.92, alpha: 1)] : palette).compactMap { $0.usingColorSpace(.sRGB) }
        guard let first = colors.first else { return nil }
        let key = colors.map { "\($0.redComponent) \($0.greenComponent) \($0.blueComponent)" }.joined(separator: " ")
        if let image = made[key] { return image }
        // The first color most, the others taking their turns.
        let second = colors.count > 1 ? colors[1] : first, third = colors.count > 2 ? colors[2] : second
        func shade(_ color: NSColor, hue shift: CGFloat, saturation s: CGFloat, brightness b: CGFloat) -> CGColor {
            NSColor(
                hue: (color.hueComponent + shift + 1).truncatingRemainder(dividingBy: 1), saturation: min(max(color.saturationComponent * s, 0), 1),
                brightness: min(max(color.brightnessComponent * b, 0), 1), alpha: 1
            ).cgColor
        }
        // Where each patch is, how big, and which shade.
        let patches: [(x: CGFloat, y: CGFloat, radius: CGFloat, color: CGColor)] = [
            (0.22, 0.28, 0.5, shade(first, hue: 0, saturation: 1, brightness: 1)),
            (0.78, 0.22, 0.45, shade(second, hue: 0.06, saturation: 1.1, brightness: 0.72)),
            (0.62, 0.74, 0.55, shade(third, hue: -0.06, saturation: 0.9, brightness: 1.05)),
            (0.16, 0.82, 0.42, shade(first, hue: 0, saturation: 0.45, brightness: 1.25)),
            (0.88, 0.86, 0.42, shade(second, hue: 0, saturation: 1.15, brightness: 0.4)),
            (0.48, 0.46, 0.3, shade(first, hue: 0.03, saturation: 0.65, brightness: 1.2)),
        ]
        let side = 64
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let bitmap = CGContext(
                data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        bitmap.setFillColor(shade(first, hue: 0, saturation: 1, brightness: 0.7))
        bitmap.fill(CGRect(x: 0, y: 0, width: side, height: side))
        for patch in patches {
            let center = CGPoint(x: patch.x * CGFloat(side), y: patch.y * CGFloat(side))
            let clear = patch.color.copy(alpha: 0) ?? patch.color
            guard let gradient = CGGradient(colorsSpace: space, colors: [patch.color, clear] as CFArray, locations: [0, 1]) else { continue }
            bitmap.drawRadialGradient(
                gradient, startCenter: center, startRadius: 0, endCenter: center,
                endRadius: patch.radius * CGFloat(side), options: [])
        }
        guard let drawn = bitmap.makeImage() else { return nil }
        let input = CIImage(cgImage: drawn)
        let soft = input.clampedToExtent().applyingGaussianBlur(sigma: 5)
        guard let output = context.createCGImage(soft, from: input.extent) else { return nil }
        let image = NSImage(cgImage: output, size: NSSize(width: side, height: side))
        made[key] = image
        return image
    }
}

/// What dims while the song is paused, the cover, the colors behind the player and the lyrics, dims
/// by the same amount, whatever is playing.
enum PausedLook {
    /// How much of its brightness each keeps.
    static let kept = 0.6
}

/// What the buttons on either side of the transport controls do, or that there's none.
enum PlayerSlot: String, CaseIterable, Identifiable {
    case favorite, shuffle, repeatMode = "repeat", output, lyrics, empty = "none"

    /// Every control there is, in the order Settings offers them.
    static let controls: [PlayerSlot] = [.favorite, .shuffle, .repeatMode, .output, .lyrics]

    var id: Self { self }
    var title: String {
        switch self {
        case .favorite: "Favorite"
        case .shuffle: "Shuffle"
        case .repeatMode: "Repeat"
        case .output: "Sound Output"
        case .lyrics: "Lyrics"
        case .empty: "None"
        }
    }

    var symbol: String {
        switch self {
        case .favorite: "star"
        case .shuffle: "shuffle"
        case .repeatMode: "repeat"
        case .output: "speaker.wave.2"
        case .lyrics: "quote.bubble"
        case .empty: "circle.dashed"
        }
    }

    /// What it does, in a few words.
    var summary: String {
        switch self {
        case .favorite: "Add the song to favorites."
        case .shuffle: "Turn shuffle on or off."
        case .repeatMode: "Repeat all songs or one song."
        case .output: "Choose where audio plays."
        case .lyrics: "Show lyrics for the song."
        case .empty: ""
        }
    }
}

/// A control's symbol as the player shows it at rest: Sound output's is the device playing now,
/// like AirPods or the Mac's speakers.
struct ControlSymbol: View {
    let control: PlayerSlot
    @ObservedObject private var output = AudioOutput.shared

    var body: some View {
        Image(systemName: control == .output ? output.symbol : control.symbol)
    }
}

/// Where a control can go in the player: either side of the transport controls.
enum ControlPlace: String, CaseIterable, Identifiable {
    case left, right

    var id: Self { self }
    /// What the player has there as it comes.
    var standard: PlayerSlot { self == .left ? .favorite : .output }
}

/// The lyrics, for a lyrics button in the player: whether they show, whether the song has any to
/// show, and showing or hiding them. The notch hands it down.
struct LyricsControl {
    var shown = false
    var available = false
    var toggle: () -> Void = {}
}

extension NowPlaying {
    func accent(from source: AccentSource) -> Color {
        source.color ?? accent
    }
}

extension Color {
    /// The color as words in it read on black, at `opacity`: as it is, if that's already as clear
    /// as text needs (4.5 to 1); otherwise lifted toward white just until it is. A deep blue cover's
    /// color, the darkest, gets the most.
    func readableOnBlack(opacity: Double = 1, contrast: Double = 4.5) -> Color {
        let color = NSColor(self).usingColorSpace(.sRGB) ?? .white
        // Seen at an opacity over black, it's simply darker.
        let seen = [color.redComponent, color.greenComponent, color.blueComponent].map { $0 * opacity * color.alphaComponent }
        let lifted = { (t: CGFloat) in seen.map { $0 + (1 - $0) * t } }
        var low: CGFloat = 0, high: CGFloat = 1
        if Self.contrastOnBlack(lifted(0)) < contrast {
            for _ in 0..<16 {
                let middle = (low + high) / 2
                if Self.contrastOnBlack(lifted(middle)) < contrast { low = middle } else { high = middle }
            }
        } else {
            high = 0
        }
        let rgb = lifted(high)
        return Color(.sRGB, red: rgb[0], green: rgb[1], blue: rgb[2])
    }

    /// How a color stands out on black, as WCAG measures it: 1 to 21.
    static func contrastOnBlack(_ rgb: [CGFloat]) -> Double {
        func linear(_ c: CGFloat) -> Double {
            let c = Double(c)
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(rgb[0]) + 0.7152 * linear(rgb[1]) + 0.0722 * linear(rgb[2])
        return (luminance + 0.05) / 0.05
    }
}
