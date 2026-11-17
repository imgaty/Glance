//
//  ActivityRow.swift
//  Glance
//
//  Created by Gaty on 15/11/2026.
//

import AppKit
import SwiftUI

/// An activity opened in one row, as iOS 27 opens Shortcuts and Music Recognition: a picture at
/// the left end, its words beside the camera, round buttons at the right end, each where the
/// iPhone puts it. Measured from the iPhone by the island's height beside the camera, so the
/// notch's height scales them all.
struct ActivityRowMetrics {
    /// The row's height.
    var height: CGFloat
    /// The picture's side, and how far in from the left end it starts.
    var pictureSide: CGFloat
    var pictureEdge: CGFloat
    /// Where the words start, from the left end.
    var wordsStart: CGFloat
    /// How far below the middle the words sit, as the iPhone's do.
    var wordsDrop: CGFloat
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
    /// "Listening…" in 16-point semibold from 81.5, 51-point buttons 16 from the end.
    static func recognition(_ h: CGFloat) -> ActivityRowMetrics {
        let k = scale(h)
        return .init(
            height: 84 * k, pictureSide: 51 * k, pictureEdge: 18.2 * k, wordsStart: 81.5 * k, wordsDrop: drop * k, titleSize: 16 * k,
            titleWeight: .semibold, titleOpticalSize: 16, buttonSide: 51 * k, buttonEdge: 16.3 * k, buttonGap: 8 * k)
    }

    /// "No song found.", measured: taller, 92.7 points, no picture, the words from 33.9 and only half a
    /// point below the middle, its one button 17 from the end.
    static func noMatch(_ h: CGFloat) -> ActivityRowMetrics {
        let k = scale(h)
        return .init(
            height: 92.7 * k, pictureSide: 0, pictureEdge: 0, wordsStart: 33.9 * k, wordsDrop: 0.5 * k, titleSize: 16 * k,
            titleWeight: .semibold, titleOpticalSize: 16, buttonSide: 51 * k, buttonEdge: 17 * k, buttonGap: 8 * k)
    }

    /// Shortcuts running, measured: 374 by 83.7 points, the icon's diamond 46 wide 19 in, the name
    /// in 17-point medium from 82, the ring 48.7 points across its outside, 17.3 from the end.
    static func shortcut(_ h: CGFloat) -> ActivityRowMetrics {
        let k = scale(h)
        return .init(
            height: 83.7 * k, pictureSide: 46 * k, pictureEdge: 19 * k, wordsStart: 82 * k, wordsDrop: drop * k, titleSize: 17 * k,
            titleWeight: .medium, titleOpticalSize: 17, buttonSide: 49.3 * k, buttonEdge: 16.9 * k, buttonGap: 8 * k)
    }

    /// The words stand 1.6 points below the row's middle on the iPhone, as it listens and runs.
    private static let drop: CGFloat = 1.6
}

enum ActivityRowLayout {
    /// The most a name takes beside the camera before it's cut short, as the Timer's label.
    static func titleLimit(_ h: CGFloat) -> CGFloat { h * TimerLayout.titleLimit }
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

    /// Either side of the camera as wide as the wider needs: the picture and the name on the left,
    /// against the camera, the buttons on the right; wider, up to a limit, for the line under the name
    /// to run on under the camera as far as the buttons. `extra` is what stands before the buttons
    /// that isn't one, as Music Recognition's waveform.
    @MainActor
    static func width(
        title: String, detail: String, buttons: Int, extra: CGFloat = 0, metrics m: ActivityRowMetrics, restingHeight h: CGFloat, camera: CGFloat
    ) -> CGFloat {
        let gap = LiveActivityView.cameraGap
        let left = m.wordsStart + min(textWidth(title, font: m.titleNSFont), titleLimit(h)) + gap
        let right = gap + extra + buttonsWidth(buttons, m) + m.buttonEdge
        let around = camera + 2 * max(left, right)
        let line = m.wordsStart + textWidth(detail, weight: .regular) + (buttons > 0 ? m.buttonGap + extra + buttonsWidth(buttons, m) : 0) + m.buttonEdge
        return max(around, min(line, widest))
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
        let gap = LiveActivityView.cameraGap
        let side = max((width - camera) / 2, 0)
        let titleRoom = max(side - m.wordsStart - gap, 0)
        let buttonsRoom = buttons > 0 ? m.buttonGap + extra + ActivityRowLayout.buttonsWidth(buttons, m) : 0
        let lineRoom = max(width - m.wordsStart - buttonsRoom - m.buttonEdge, 0)
        ZStack {
            picture
                .frame(width: m.pictureSide, height: m.pictureSide)
                .padding(.leading, m.pictureEdge)
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(m.titleFont)
                    .foregroundStyle(titleColor)
                    .frame(maxWidth: titleRoom, alignment: .leading)
                // A name alone, as the iPhone's, sits on the middle.
                if !detail.isEmpty {
                    Text(detail)
                        .font(NotchType.detail)
                        .foregroundStyle(NotchType.detailColor)
                        .frame(maxWidth: lineRoom, alignment: .leading)
                }
            }
            .lineLimit(1)
            .truncationMode(.tail)
            .help(explanation ?? detail)
            .accessibilityElement(children: .combine)
            .accessibilityHint(explanation ?? "")
            .offset(y: m.wordsDrop)
            .padding(.leading, m.wordsStart)
            .frame(maxWidth: .infinity, alignment: .leading)
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
