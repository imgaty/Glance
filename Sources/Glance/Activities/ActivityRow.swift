//
//  ActivityRow.swift
//  Glance
//
//  Created by Gaty on 15/11/2026.
//

import AppKit
import SwiftUI

/// An activity opened in one row, as iOS 27 opens Shortcuts and Music Recognition: a picture at
/// the left end, round buttons at the right end, each where the iPhone puts it, and its words as
/// high as they go under the camera, so they run on beneath it. Measured from the iPhone by the island's height
/// beside the camera, so the notch's height scales them all.
struct ActivityRowMetrics {
    /// The row's height.
    var height: CGFloat
    /// The picture's side, and how far in from the left end it starts.
    var pictureSide: CGFloat
    var pictureEdge: CGFloat
    /// Where the words start, from the left end.
    var wordsStart: CGFloat
    var titleSize: CGFloat
    var titleWeight: NSFont.Weight
    /// The size the iPhone sets it at: its letters are drawn for that size, then scaled, so they're
    /// as narrow as the iPhone's rather than as wide as small type's.
    var titleOpticalSize: CGFloat
    /// The round buttons' side, how far in from the right end they stop, and between them.
    var buttonSide: CGFloat
    var buttonEdge: CGFloat
    var buttonGap: CGFloat

    var titleNSFont: NSFont {
        let font = NSFont.systemFont(ofSize: titleSize, weight: titleWeight)
        let optical = font.fontDescriptor.addingAttributes([.init(kCTFontOpticalSizeAttribute as String): titleOpticalSize])
        return NSFont(descriptor: optical, size: titleSize) ?? font
    }
    var titleFont: Font { Font(titleNSFont) }

    /// By the iPhone's island height beside the camera, 36.7 points.
    static func scale(_ h: CGFloat) -> CGFloat { h / 36.7 }


    /// Music Recognition listening, measured on iOS 27: 374 by 84 points, a 51-point disc 18.2 in,
    /// "Listening…" in 16-point semibold from 81.5, 51-point buttons 16 from the end. The words stand
    /// as high as they go under the camera (see `UnderCamera`).
    static func recognition(_ h: CGFloat) -> ActivityRowMetrics {
        let k = scale(h)
        return .init(
            height: 84 * k, pictureSide: 51 * k, pictureEdge: 18.2 * k, wordsStart: 81.5 * k, titleSize: 16 * k,
            titleWeight: .semibold, titleOpticalSize: 16, buttonSide: 51 * k, buttonEdge: 16.3 * k, buttonGap: 8 * k)
    }

    /// "No song found.", measured: no picture, the words from 33.9, its one button 17 from the end; as
    /// tall as it listens, the iPhone's 84 points, its words standing under the camera rather than in
    /// the middle of the iPhone's taller 92.7.
    static func noMatch(_ h: CGFloat) -> ActivityRowMetrics {
        let k = scale(h)
        return .init(
            height: 84 * k, pictureSide: 0, pictureEdge: 0, wordsStart: 33.9 * k, titleSize: 16 * k,
            titleWeight: .semibold, titleOpticalSize: 16, buttonSide: 51 * k, buttonEdge: 17 * k, buttonGap: 8 * k)
    }

    /// Shortcuts running, measured: 374 by 83.7 points; the icon view and the ring's 50-point views,
    /// the icon's 16.8 in, the ring's 16.7 from the end; the name in 17-point medium from 82.
    static func shortcut(_ h: CGFloat) -> ActivityRowMetrics {
        let k = scale(h)
        return .init(
            height: 83.7 * k, pictureSide: 50 * k, pictureEdge: 16.8 * k, wordsStart: 82 * k, titleSize: 17 * k,
            titleWeight: .medium, titleOpticalSize: 17, buttonSide: 50 * k, buttonEdge: 16.7 * k, buttonGap: 8 * k)
    }
}

enum ActivityRowLayout {
    /// The most the row grows for its line under the name; past this it's cut short, and said in full
    /// under the pointer and to VoiceOver.
    static let widest: CGFloat = 520

    /// The buttons at the right end, side by side.
    static func buttonsWidth(_ count: Int, _ m: ActivityRowMetrics) -> CGFloat {
        count == 0 ? 0 : CGFloat(count) * m.buttonSide + CGFloat(count - 1) * m.buttonGap
    }

    @MainActor
    static func textWidth(_ text: String, size: CGFloat = NotchType.size, weight: NSFont.Weight) -> CGFloat {
        textWidth(text, font: NSFont.systemFont(ofSize: size, weight: weight))
    }

    @MainActor
    static func textWidth(_ text: String, font: NSFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width) + 1
    }

    /// Only as wide as the camera needs: what stands as high as the camera, the picture at the left and
    /// the buttons at the right, sits beside it, and the words run on beneath it, so a long name is
    /// cut short, as the iPhone's is, rather than widening the notch.
    /// A line under the name widens it, up to a limit, to run as far as the buttons. `extra` is what
    /// stands before the buttons that isn't one, as Music Recognition's waveform.
    @MainActor
    static func width(
        detail: String, buttons: Int, extra: CGFloat = 0, metrics m: ActivityRowMetrics, restingHeight h: CGFloat, camera: CGFloat
    ) -> CGFloat {
        let gap = LiveActivityView.cameraGap
        let left = m.pictureSide > 0 ? m.pictureEdge + m.pictureSide + gap : 0
        let right = gap + extra + buttonsWidth(buttons, m) + m.buttonEdge
        let around = camera + 2 * max(left, right)
        let line = m.wordsStart + textWidth(detail, weight: .regular) + trailingRoom(buttons: buttons, extra: extra, m) + m.buttonEdge
        return max(around, detail.isEmpty ? 0 : min(line, widest)).rounded(.up)
    }

    /// What stands at the right end before its edge: the buttons, what's before them, and the gap
    /// the words keep from them.
    static func trailingRoom(buttons: Int, extra: CGFloat, _ m: ActivityRowMetrics) -> CGFloat {
        buttons > 0 || extra > 0 ? m.buttonGap + extra + buttonsWidth(buttons, m) : 0
    }

}

/// Type in an activity as the iPhone sets it, at the notch's scale: drawn for the size the iPhone sets
/// it at, then made smaller with the notch, so its letters are as narrow as the iPhone's rather than as
/// wide as small type's, and words take the same share of the notch as of the island.
enum IslandType {
    static func nsFont(_ size: CGFloat, weight: NSFont.Weight = .regular, restingHeight h: CGFloat, digits: Bool = false) -> NSFont {
        let base = digits ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
        let optical = size / ActivityRowMetrics.scale(h)
        let descriptor = base.fontDescriptor.addingAttributes([.init(kCTFontOpticalSizeAttribute as String): optical])
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    static func font(_ size: CGFloat, weight: NSFont.Weight = .regular, restingHeight h: CGFloat, digits: Bool = false) -> Font {
        Font(nsFont(size, weight: weight, restingHeight: h, digits: digits))
    }

    /// Most activities' words: a name, semibold, and what it's about, regular.
    static func title(_ h: CGFloat) -> Font { font(NotchType.size, weight: .semibold, restingHeight: h) }
    static func detail(_ h: CGFloat) -> Font { font(NotchType.size, restingHeight: h) }
}

/// Words under the camera stand as high as they go, in every activity alike: the tops of their
/// tallest letters just clear of its lower edge. Pictures, buttons and large digits, as tall as the
/// camera, stand beside it instead.
enum UnderCamera {
    /// Between the camera's lower edge and the letters' tops.
    static let clearance: CGFloat = 1

    /// How far above their baseline these words reach, set on one line in this font: as high as a
    /// capital, or higher where their own letters are, as tall lowercase letters and accents are.
    static func reach(_ words: [String], font: NSFont) -> CGFloat {
        words.reduce(top("H", font)) { max($0, top($1, font)) }
    }

    private static func top(_ text: String, _ font: NSFont) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        return bounds.isNull ? 0 : bounds.maxY
    }

    /// Where the first line's baseline falls, down from the notch's top, for these words to stand
    /// just under a camera `h` tall.
    static func baseline(_ words: [String], font: NSFont, restingHeight h: CGFloat) -> CGFloat {
        h + clearance + reach(words, font: font)
    }

    /// From one baseline to the next, as a line follows another in this font.
    static func lineStep(_ font: NSFont) -> CGFloat { ceil(font.ascender - font.descender + font.leading) }
}

extension View {
    /// Sets these words with their first baseline `y` down from the top of what holds them, from its
    /// leading or trailing edge.
    func firstBaseline(_ y: CGFloat, alignment: HorizontalAlignment = .leading) -> some View {
        Color.clear.overlay(alignment: Alignment(horizontal: alignment, vertical: .top)) {
            self.alignmentGuide(.top) { $0[.firstTextBaseline] - y }
        }
    }
}

struct ActivityRow<Picture: View, Buttons: View>: View {
    let restingHeight: CGFloat
    let camera: CGFloat
    let width: CGFloat
    let metrics: ActivityRowMetrics
    let title: String
    var titleColor: Color = .white
    let detail: String
    /// All there is to say about it, under the pointer and to VoiceOver, when the line is short of it.
    var explanation: String? = nil
    let buttons: Int
    /// What stands before the buttons that isn't one (see `ActivityRowLayout.width`).
    var extra: CGFloat = 0
    /// The notch is open to it.
    var revealed = true
    @ViewBuilder let picture: Picture
    @ViewBuilder let trailing: Buttons

    var body: some View {
        let m = metrics
        // The words run on under the camera, as far as what stands at the right end.
        let room = max(width - m.wordsStart - ActivityRowLayout.trailingRoom(buttons: buttons, extra: extra, m) - m.buttonEdge, 0)
        ZStack {
            picture
                .frame(width: m.pictureSide, height: m.pictureSide)
                .padding(.leading, m.pictureEdge)
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(m.titleFont)
                    .foregroundStyle(titleColor)
                    .frame(maxWidth: room, alignment: .leading)
                // A name alone, as the iPhone's, sits on the middle.
                if !detail.isEmpty {
                    Text(detail)
                        .font(IslandType.detail(restingHeight))
                        .foregroundStyle(NotchType.detailColor)
                        .frame(maxWidth: room, alignment: .leading)
                }
            }
            .lineLimit(1)
            .truncationMode(.tail)
            .help(explanation ?? detail)
            .accessibilityElement(children: .combine)
            .accessibilityHint(explanation ?? "")
            .firstBaseline(UnderCamera.baseline([title], font: m.titleNSFont, restingHeight: restingHeight))
            .padding(.leading, m.wordsStart)
            HStack(spacing: m.buttonGap) { trailing }
                .padding(.trailing, m.buttonEdge)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .modifier(IslandReveal(hidden: !revealed))
        .frame(width: width, height: m.height)
        .accessibilityElement(children: .contain)
    }
}

/// An activity beside the camera, as an announcement is: its mark at the left end, a word or two at
/// the right, each as far in from its end as from the top and bottom, and the notch only as wide as
/// the wider side needs.
enum CompactActivityLayout {
    @MainActor
    static func wing(caption: String, restingHeight h: CGFloat) -> CGFloat {
        let size = LiveActivityView.textSize(for: h)
        let gap = LiveActivityView.cameraGap
        let left = LiveActivityView.inset + SystemActivityView.side(h) + gap
        let words = ceil((caption as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: .semibold)]).width) + 2
        let right = gap + words + LiveActivityView.textEdge(restingHeight: h)
        return min(max(left, right), SystemActivityView.maxWing)
    }
}

struct CompactActivityMark<Mark: View>: View {
    let caption: String
    var captionColor: Color = .white
    let restingHeight: CGFloat
    var leadingOnly = false
    @ViewBuilder let mark: Mark

    var body: some View {
        let h = restingHeight
        let side = SystemActivityView.side(h)
        let size = LiveActivityView.textSize(for: h)
        ZStack {
            mark
                .frame(width: side, height: side)
                .padding(.leading, LiveActivityView.inset)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !leadingOnly {
                MarqueeText(text: caption, font: .system(size: size, weight: .semibold), active: true, alignment: .trailing)
                    .foregroundStyle(captionColor)
                    .frame(width: max(CompactActivityLayout.wing(caption: caption, restingHeight: h) - LiveActivityView.textEdge(restingHeight: h) - LiveActivityView.cameraGap, side), alignment: .trailing)
                    .padding(.trailing, LiveActivityView.textEdge(restingHeight: h))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}
