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
    /// How far the picture's ink reaches below its square, as a shortcut's laid tile does.
    var pictureReach: CGFloat = 0

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
        // The disc and the buttons as far in from the ends as every row's (the user, 2026-11-28: the
        // padding "consistent all around").
        return .init(
            height: 84 * k, pictureSide: 51 * k, pictureEdge: TimerLayout.buttonEdge(h), wordsStart: 81.5 * k, titleSize: 16 * k,
            titleWeight: .semibold, titleOpticalSize: 16, buttonSide: 51 * k, buttonEdge: TimerLayout.buttonEdge(h), buttonGap: 8 * k)
    }

    /// "No song found.": no picture, its one button 17 from the end and its words as far in from the
    /// other, rather than the iPhone's 33.9, which on the notch's flat-sided end looked set in; as
    /// tall as it listens, the iPhone's 84 points, its words standing under the camera rather than in
    /// the middle of the iPhone's taller 92.7.
    static func noMatch(_ h: CGFloat) -> ActivityRowMetrics {
        let k = scale(h)
        return .init(
            height: 84 * k, pictureSide: 0, pictureEdge: 0, wordsStart: TimerLayout.buttonEdge(h), titleSize: 16 * k,
            titleWeight: .semibold, titleOpticalSize: 16, buttonSide: 51 * k, buttonEdge: TimerLayout.buttonEdge(h), buttonGap: 8 * k)
    }

    /// Shortcuts running, measured: 374 by 83.7 points; the icon view and the ring's 50-point views,
    /// the icon's 16.8 in, the ring's 16.7 from the end; the name in 17-point medium from 82.
    static func shortcut(_ h: CGFloat) -> ActivityRowMetrics {
        let k = scale(h)
        // The icon's tiles stand a little in from its square: its ink, rather than its square, as far
        // in as the ring's.
        return .init(
            height: 83.7 * k, pictureSide: 50 * k, pictureEdge: TimerLayout.buttonEdge(h) - 50 * k * shortcutMargin, wordsStart: 82 * k,
            titleSize: 17 * k, titleWeight: .medium, titleOpticalSize: 17, buttonSide: 50 * k, buttonEdge: TimerLayout.buttonEdge(h), buttonGap: 8 * k,
            pictureReach: 50 * k * shortcutReach)
    }
    /// How far below its square a shortcut's icon's laid tile reaches, of its side, measured.
    static let shortcutReach: CGFloat = 0.03
    /// How far in from its square a shortcut's icon's tiles stand, of its side, measured.
    static let shortcutMargin: CGFloat = 0.044
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

    /// What stands at the ends, the taller of the picture and the buttons.
    static func side(_ m: ActivityRowMetrics) -> CGFloat { max(m.pictureSide, m.buttonSide) }

    /// The middle of what stands at the ends: level with the name alone; with a line under it, ending
    /// where that line does (see `UnderCamera`).
    static func sidesMiddle(title: String, detail: String, metrics m: ActivityRowMetrics, restingHeight h: CGFloat) -> CGFloat {
        if detail.isEmpty { return UnderCamera.oneLineMiddle(font: m.titleNSFont, restingHeight: h) }
        let bottom = UnderCamera.twoLineBottom([title], first: m.titleNSFont, line: detail, font: .systemFont(ofSize: NotchType.size), restingHeight: h)
        return UnderCamera.twoLineSidesMiddle(bottom: max(bottom, m.buttonEdge + side(m)), side: side(m))
    }

    /// How tall the row stands: as far under what's lowest in it as the buttons stand in from the end,
    /// the words as high as they go under the camera (see `UnderCamera`).
    static func height(title: String, detail: String, metrics m: ActivityRowMetrics, restingHeight h: CGFloat) -> CGFloat {
        let middle = sidesMiddle(title: title, detail: detail, metrics: m, restingHeight: h)
        // Under the lowest of them: the buttons, or the picture with what of it reaches below.
        let below = max(m.buttonSide, m.pictureSide + 2 * m.pictureReach)
        if detail.isEmpty { return UnderCamera.oneLineHeight(middle: middle, side: below, edge: m.buttonEdge) }
        return UnderCamera.twoLineHeight(bottom: middle + below / 2, edge: m.buttonEdge)
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

/// Where letters' ink starts and stops within their line, so what's seen, rather than the line's
/// box, keeps the padding (the user, 2026-11-28: the padding "consistent all around").
enum Ink {
    /// How far in from where `text` starts, set in `font`, its first letter's ink begins.
    static func lead(_ text: String, font: NSFont) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        return bounds.isNull ? 0 : bounds.minX
    }

    /// How far short of where `text` ends, set in `font`, its last letter's ink stops.
    static func trail(_ text: String, font: NSFont) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        return bounds.isNull ? 0 : CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) - bounds.maxX
    }
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

    /// How far below its baseline this line reaches, set in this font: not at all, or as low as its
    /// own letters go, as a g's or a p's tail does.
    static func depth(_ text: String, font: NSFont) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        return bounds.isNull ? 0 : max(-bounds.minY, 0)
    }

    /// Where the first line's baseline falls, down from the notch's top, for these words to stand
    /// just under a camera `h` tall.
    static func baseline(_ words: [String], font: NSFont, restingHeight h: CGFloat) -> CGFloat {
        h + clearance + reach(words, font: font)
    }

    /// From one baseline to the next, as a line follows another in this font.
    static func lineStep(_ font: NSFont) -> CGFloat { ceil(font.ascender - font.descender + font.leading) }

    /// How low two lines of words under the camera reach, the first these `words` in `first`, the
    /// second `line` in `font` under it: as low as the second line's own letters go, its baseline when
    /// none hangs below it.
    static func twoLineBottom(_ words: [String], first: NSFont, line: String, font: NSFont, restingHeight h: CGFloat) -> CGFloat {
        baseline(words, font: first, restingHeight: h) + lineStep(font) + depth(line, font: font)
    }

    /// Where the pictures and buttons, `side` across, beside two lines of words under the camera stand
    /// (the user, 2026-11-28: "the padding isnt consistent all throughout the bottom, i get the top is
    /// impossible"): their middle, so they end where the words do, at `bottom`. What's in the row is
    /// laid out twice as tall as that middle, so what's centered in it stands there.
    static func twoLineSidesMiddle(bottom: CGFloat, side: CGFloat) -> CGFloat { bottom - side / 2 }

    /// How tall a row with two lines of words under the camera opens: the words stay as high as they
    /// go, everything ends where they do, at `bottom`, and the notch's edge comes up under it as far
    /// as the pictures and buttons stand in from the row's ends, `edge`, so the room under the row is
    /// the same all along it and at its ends.
    static func twoLineHeight(bottom: CGFloat, edge: CGFloat) -> CGFloat { (bottom + edge).rounded() }

    /// The middle of a single line of words under the camera, in this font: halfway from its
    /// capitals, just under the camera, to its baseline. The pictures and buttons stand level with it,
    /// in a row laid out twice as tall, so what's centered in it stands there.
    static func oneLineMiddle(font: NSFont, restingHeight h: CGFloat) -> CGFloat {
        (h + clearance + baseline([], font: font, restingHeight: h)) / 2
    }

    /// How tall a row with a single line of words under the camera stands, the pictures and buttons,
    /// `side` across, level with the line's `middle`: as far under them as they stand in from the
    /// ends, `edge`, or as far above them too where the line leaves room (the user, 2026-11-28: the
    /// padding "consistent all around", the top the exception where the camera keeps the words down).
    static func oneLineHeight(middle: CGFloat, side: CGFloat, edge: CGFloat) -> CGFloat {
        max(middle + side / 2 + edge, side + 2 * edge).rounded()
    }
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
        let h = restingHeight
        // Laid out twice as tall as the middle of what stands at the ends, so they, centered in it,
        // stand there; the notch ends sooner, under them.
        let row = 2 * ActivityRowLayout.sidesMiddle(title: title, detail: detail, metrics: m, restingHeight: h)
        // The words run on under the camera, as far as what stands at the right end, as high as they
        // go; a name alone, the row as tall as it needs for what's at its ends to stand level with it.
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
            .firstBaseline(UnderCamera.baseline([title], font: m.titleNSFont, restingHeight: h))
            .padding(.leading, m.wordsStart)
            HStack(spacing: m.buttonGap) { trailing }
                .padding(.trailing, m.buttonEdge)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .modifier(IslandReveal(hidden: !revealed))
        .frame(width: width, height: row)
        .frame(height: ActivityRowLayout.height(title: title, detail: detail, metrics: m, restingHeight: h), alignment: .top)
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
    /// How large the mark's ink is: it stands as far in from its end as from the top and bottom, and
    /// the caption's ink as far from the other (the user, 2026-11-28: the padding "consistent all
    /// around").
    var markInk: CGSize? = nil
    @ViewBuilder let mark: Mark

    var body: some View {
        let h = restingHeight
        let side = SystemActivityView.side(h)
        let size = LiveActivityView.textSize(for: h)
        let ink = markInk ?? CGSize(width: side, height: side)
        let edge = LiveActivityView.concentric(ink.height, in: h)
        let font = NSFont.systemFont(ofSize: size, weight: .semibold)
        ZStack {
            mark
                .frame(width: ink.width, height: ink.height)
                .padding(.leading, edge)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !leadingOnly {
                MarqueeText(text: caption, font: .system(size: size, weight: .semibold), active: true, alignment: .trailing)
                    .foregroundStyle(captionColor)
                    .frame(width: max(CompactActivityLayout.wing(caption: caption, restingHeight: h) - LiveActivityView.textEdge(restingHeight: h) - LiveActivityView.cameraGap, side), alignment: .trailing)
                    .padding(.trailing, edge - Ink.trail(caption, font: font))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}
