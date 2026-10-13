//
//  MarqueeText.swift
//  Glance
//
//  Created by Gaty on 07/10/2026.
//

import AppKit
import SwiftUI

/// One line that scrolls when it doesn't fit, as in Apple Music: it rests, glides left one full
/// length at an even pace, and starts over. Its edges fade so the text slides in and out softly.
struct MarqueeText: View {
    let text: String
    let font: Font
    let active: Bool
    /// Where the text sits when it fits.
    var alignment: Alignment = .leading
    /// Takes all the width it's offered; otherwise only as much as its text needs.
    var fills = true

    @State private var textWidth: CGFloat = 0
    @State private var boxWidth: CGFloat = 0
    @State private var start = Date()
    /// With Reduce Motion on, a line too long ends in an ellipsis instead of scrolling.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let gap: CGFloat = 36
    private static let speed: CGFloat = 32  // points a second
    private static let rest: Double = 2.5
    private static let fade: CGFloat = 10

    var body: some View {
        let overflows = textWidth > boxWidth + 1
        // One line tall and only as wide as it's given: the text itself rides on top and is clipped.
        Text(text).font(font).lineLimit(1).hidden()
            .frame(maxWidth: fills ? .infinity : nil, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) {
                $0.size.width
            } action: {
                boxWidth = $0
            }
            .overlay(alignment: .leading) {
                if overflows && reduceMotion {
                    Text(text).font(font).lineLimit(1).truncationMode(.tail)
                        .frame(width: boxWidth, alignment: .leading)
                } else {
                    scrolling(overflows: overflows)
                }
            }
            .clipped()
            .background(
                label.hidden().onGeometryChange(for: CGFloat.self) {
                    $0.size.width
                } action: {
                    textWidth = $0
                }
            )
            .onChange(of: text) { start = .now }
    }

    private func scrolling(overflows: Bool) -> some View {
        TimelineView(.animation(paused: !(active && overflows))) { context in
            let offset = overflows ? self.offset(at: context.date) : 0
            // The left fade comes in as the text sets off, and is gone by the time the next
            // copy reaches its resting place, so it never fades the start of the text.
            let lead = overflows ? max(min(Self.fade, offset, textWidth + Self.gap - offset), 0) : 0
            HStack(spacing: Self.gap) {
                label
                if overflows { label }
            }
            .offset(x: -offset)
            .frame(width: boxWidth, alignment: overflows ? .leading : alignment)
            .mask(edges(leading: lead, trailing: overflows))
        }
    }

    private var label: some View {
        Text(text).font(font).lineLimit(1).fixedSize()
    }

    private func offset(at date: Date) -> CGFloat {
        let travel = Double((textWidth + Self.gap) / Self.speed)
        let elapsed = date.timeIntervalSince(start).truncatingRemainder(dividingBy: Self.rest + travel)
        return elapsed < Self.rest ? 0 : CGFloat(elapsed - Self.rest) * Self.speed
    }

    private func edges(leading: CGFloat, trailing: Bool) -> some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                .frame(width: leading)
            Color.black
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: trailing ? Self.fade : 0)
        }
    }
}
