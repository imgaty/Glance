//
//  SystemActivityView.swift
//  Glance
//
//  Created by Gaty on 16/10/2026.
//

import AppKit
import SwiftUI

/// What the Mac announces, and a running timer, in the closed notch's wings, laid out as a new
/// song's announcement is (see LiveActivityView): a symbol and a title on the camera's left, a few
/// words or a battery on its right. A timer counts down on the right, its symbol on the left, or the
/// cover there while music plays.
struct SystemActivityView: View {
    let restingHeight: CGFloat
    let island: Bool
    let wing: CGFloat
    let alert: NotchAlert?
    let timer: NotchTimer.State?
    /// Music is playing: its cover keeps the left wing beside a timer.
    let music: Bool

    var body: some View {
        let edge = LiveActivityView.edgeInset(island: island, restingHeight: restingHeight)
        let side = Self.side(restingHeight, island)
        let lane = max(wing - edge - LiveActivityView.cameraGap, side)
        let size = LiveActivityView.textSize(for: restingHeight)
        ZStack {
            if let alert {
                HStack(spacing: 0) {
                    HStack(spacing: LiveActivityView.textGap) {
                        if let symbol = alert.symbol {
                            Image(systemName: symbol)
                                .font(.system(size: size + 1, weight: .semibold))
                                .foregroundStyle(alert.tint)
                                .frame(width: side, height: side)
                        }
                        MarqueeText(text: alert.title, font: .system(size: size, weight: .semibold), active: true)
                            .foregroundStyle(.white)
                    }
                    .frame(width: lane, alignment: .leading)
                    Spacer(minLength: 0)
                    HStack(spacing: 5) {
                        if let detail = alert.detail {
                            Text(detail)
                                .font(.system(size: size, weight: alert.battery == nil ? .regular : .semibold).monospacedDigit())
                                .foregroundStyle(alert.detailTint)
                                .lineLimit(1)
                        }
                        if let battery = alert.battery {
                            BatteryGlyph(level: battery, color: alert.detailTint, height: size * 0.92)
                        }
                    }
                    .frame(width: lane, alignment: .trailing)
                }
                .id(alert.id)
                .transition(Self.announce)
            } else if let timer {
                HStack(spacing: 0) {
                    Image(systemName: "timer")
                        .font(.system(size: size + 1, weight: .semibold))
                        .foregroundStyle(.orange)
                        .frame(width: side, height: side)
                        // While music plays, its cover is there instead.
                        .opacity(music ? 0 : 1)
                    Spacer(minLength: 0)
                    TimelineView(.periodic(from: .now, by: 0.5)) { context in
                        Text(NotchTimer.format(timer.left(at: context.date)))
                            .font(.system(size: size + 1, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.orange)
                            // Paused, it waits, dimmed.
                            .opacity(timer.isRunning ? 1 : 0.55)
                    }
                }
                .transition(Self.announce)
            }
        }
        .padding(.horizontal, edge)
        .frame(maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// A symbol's square, as the cover's beside the camera.
    static func side(_ restingHeight: CGFloat, _ island: Bool) -> CGFloat {
        restingHeight - LiveActivityView.inset(island: island) * 2
    }

    /// How wide each wing must be for an announcement to show in full, up to a limit, a little past
    /// a song's announcement's, beyond which its title scrolls. The notch stays centered, so both
    /// wings take the wider one.
    static func wing(for alert: NotchAlert, restingHeight: CGFloat, island: Bool) -> CGFloat {
        let edge = LiveActivityView.edgeInset(island: island, restingHeight: restingHeight)
        let size = LiveActivityView.textSize(for: restingHeight)
        let side = side(restingHeight, island)
        let left =
            edge + (alert.symbol == nil ? 0 : side + LiveActivityView.textGap) + width(alert.title, size, .semibold)
            + LiveActivityView.cameraGap
        let detail = alert.detail.map { width($0, size, alert.battery == nil ? .regular : .semibold) } ?? 0
        let glyph = alert.battery == nil ? 0 : BatteryGlyph.width(height: size * 0.92) + 5
        let right = LiveActivityView.cameraGap + detail + glyph + edge
        return min(max(left, right, restingHeight), maxWing)
    }

    static let maxWing: CGFloat = 170

    /// Room for the timer's time, as long as it can get, and its symbol.
    static func wing(for timer: NotchTimer.State, restingHeight: CGFloat, island: Bool) -> CGFloat {
        let edge = LiveActivityView.edgeInset(island: island, restingHeight: restingHeight)
        let size = LiveActivityView.textSize(for: restingHeight)
        // Every digit as wide as a 0, as the time's are.
        let longest = NotchTimer.format(timer.total).replacingOccurrences(of: "[0-9]", with: "0", options: .regularExpression)
        let right = LiveActivityView.cameraGap + width(longest, size + 1, .semibold) + edge
        return max(right, edge + side(restingHeight, island) + LiveActivityView.cameraGap, restingHeight)
    }

    private static func width(_ text: String, _ size: CGFloat, _ weight: NSFont.Weight) -> CGFloat {
        // A point to spare, so rounding never sets text that fits scrolling.
        ceil((text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight)]).width) + 2
    }

    /// The words come in once the wings have opened, and leave before they fold.
    private static let announce = AnyTransition.asymmetric(
        insertion: .opacity.animation(.easeOut(duration: 0.3).delay(0.25)),
        removal: .opacity.animation(.easeOut(duration: 0.12)))
}

extension NotchTimer.State {
    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}

/// A battery, as the iPhone draws one beside its level: an outline with a cap, filled as far as it's
/// charged, with a bolt while it charges.
struct BatteryGlyph: View {
    let level: BatteryLevel
    let color: Color
    let height: CGFloat

    static func width(height: CGFloat) -> CGFloat { height * 2.05 }

    var body: some View {
        let width = Self.width(height: height)
        let cap = height * 0.12, line = max(height * 0.09, 1)
        HStack(spacing: line) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height * 0.3, style: .continuous)
                    .strokeBorder(color.opacity(0.45), lineWidth: line)
                RoundedRectangle(cornerRadius: height * 0.18, style: .continuous)
                    .fill(color)
                    .frame(width: max((width - cap - line * 5) * CGFloat(level.percent) / 100, line))
                    .padding(line * 2)
            }
            .overlay {
                if level.charging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: height * 0.7, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.4), radius: 1)
                }
            }
            RoundedRectangle(cornerRadius: cap / 2)
                .fill(color.opacity(0.45))
                .frame(width: cap, height: height * 0.36)
        }
        .frame(width: width, height: height)
        .accessibilityLabel("\(level.percent) percent\(level.charging ? ", charging" : "")")
    }
}
