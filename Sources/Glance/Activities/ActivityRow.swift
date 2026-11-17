//
//  ActivityRow.swift
//  Glance
//
//  Created by Gaty on 15/11/2026.
//

import AppKit
import SwiftUI

/// An activity opened in one row, as AirDrop's and the Timer's are: a round picture at the left end,
/// which opens the app it comes from; its name beside the camera with a line under it that runs on
/// under the camera; round buttons at the right end. As tall as the Timer's, everything on its
/// middle, each end's part as far in from its end as from the top and bottom.
enum ActivityRowLayout {
    /// The most a name takes beside the camera before it's cut short, as the Timer's label.
    static func titleLimit(_ h: CGFloat) -> CGFloat { h * TimerLayout.titleLimit }
    /// The most the row grows for its line under the name; past this it's cut short, and said in full
    /// under the pointer and to VoiceOver.
    static let widest: CGFloat = 520

    /// Where the words start, from the left end: after the picture, as AirDrop's.
    static func wordsStart(_ h: CGFloat) -> CGFloat { PlayerLayout.padding + TimerLayout.content(h) + h * AirDropLayout.gap }

    /// The buttons at the right end, side by side, as the Timer's.
    static func buttonsWidth(_ count: Int, _ h: CGFloat) -> CGFloat {
        count == 0 ? 0 : CGFloat(count) * TimerLayout.content(h) + CGFloat(count - 1) * h * TimerLayout.buttonGap
    }

    @MainActor
    static func textWidth(_ text: String, weight: NSFont.Weight) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: NotchType.size, weight: weight)]).width) + 1
    }

    /// Either side of the camera as wide as the wider needs: the picture and the name on the left,
    /// against the camera, the buttons on the right; wider, up to a limit, for the line under the name
    /// to run on under the camera as far as the buttons.
    @MainActor
    static func width(title: String, detail: String, buttons: Int, restingHeight h: CGFloat, camera: CGFloat) -> CGFloat {
        let gap = LiveActivityView.cameraGap
        let left = wordsStart(h) + min(textWidth(title, weight: .semibold), titleLimit(h)) + gap
        let right = gap + buttonsWidth(buttons, h) + PlayerLayout.padding
        let around = camera + 2 * max(left, right)
        let line = wordsStart(h) + textWidth(detail, weight: .regular) + (buttons > 0 ? h * AirDropLayout.gap + buttonsWidth(buttons, h) : 0)
            + PlayerLayout.padding
        return max(around, min(line, widest))
    }
}

struct ActivityRow<Picture: View, Buttons: View>: View {
    let restingHeight: CGFloat
    let camera: CGFloat
    let width: CGFloat
    let title: String
    var titleColor: Color = .white
    let detail: String
    /// All there is to say about it, under the pointer and to VoiceOver, when the line is short of it.
    var explanation: String? = nil
    let buttons: Int
    /// The notch is open to it.
    var revealed = true
    @ViewBuilder let picture: Picture
    @ViewBuilder let trailing: Buttons

    var body: some View {
        let h = restingHeight
        let gap = LiveActivityView.cameraGap
        let side = max((width - camera) / 2, 0)
        let start = ActivityRowLayout.wordsStart(h)
        let titleRoom = max(side - start - gap, 0)
        let buttonsRoom = buttons > 0 ? h * AirDropLayout.gap + ActivityRowLayout.buttonsWidth(buttons, h) : 0
        let lineRoom = max(width - start - buttonsRoom - PlayerLayout.padding, 0)
        ZStack {
            HStack(spacing: h * AirDropLayout.gap) {
                picture
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(NotchType.title)
                        .foregroundStyle(titleColor)
                        .frame(maxWidth: titleRoom, alignment: .leading)
                    // A name alone, as Shortcuts' opened run, sits on the middle.
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
            }
            .padding(.leading, PlayerLayout.padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: h * TimerLayout.buttonGap) { trailing }
                .padding(.trailing, PlayerLayout.padding)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .modifier(IslandReveal(hidden: !revealed))
        .frame(width: width, height: TimerLayout.tallHeight(h))
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
