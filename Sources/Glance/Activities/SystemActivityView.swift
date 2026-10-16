//
//  SystemActivityView.swift
//  Glance
//
//  Created by Gaty on 16/10/2026.
//

import AppKit
import SwiftUI

/// What the Mac announces, and a running timer, in the closed notch's wings, as the iPhone's
/// Dynamic Island draws its own, the two sides read as one: a device's symbol turning in beside its
/// battery's ring; the Mac's battery as a word beside its level; a state's symbol in its color beside
/// a word. A timer counts down on the right, its symbol on the left, or the cover there while music
/// plays. With Reduce Motion on, nothing turns or shakes.
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
                    leading(alert.content, side: side, size: size)
                        .frame(width: lane, alignment: .leading)
                    Spacer(minLength: 0)
                    trailing(alert.content, side: side, size: size)
                        .frame(width: lane, alignment: .trailing)
                }
                .id(alert.id)
                .transition(Self.announce)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(alert.spoken)
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
                            // The digits roll down as they change, as the Timer's own do.
                            .contentTransition(.numericText(countsDown: true))
                            .animation(.snappy, value: NotchTimer.format(timer.left(at: context.date)))
                            // Paused, it waits, dimmed.
                            .opacity(timer.isRunning ? 1 : 0.55)
                    }
                }
                .transition(Self.announce)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, edge)
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder private func leading(_ content: NotchAlert.Content, side: CGFloat, size: CGFloat) -> some View {
        switch content {
        case .device(let symbol, _):
            TurningSymbol(symbol: symbol, side: side)
        case .battery(let title, _):
            Text(title)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
        case .status(let symbol, let tint, _):
            ArrivingSymbol(symbol: symbol, color: tint, size: size + 2, side: side)
        case .timerDone:
            ArrivingSymbol(symbol: "timer", color: .orange, size: size + 2, side: side, shakes: true)
        }
    }

    @ViewBuilder private func trailing(_ content: NotchAlert.Content, side: CGFloat, size: CGFloat) -> some View {
        switch content {
        case .device(_, let battery):
            if let battery {
                BatteryRing(percent: battery, side: side)
            } else {
                Text("Connected")
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
        case .battery(_, let level):
            HStack(spacing: 5) {
                Text("\(level.percent)%")
                    .font(.system(size: size, weight: .semibold).monospacedDigit())
                    .foregroundStyle(level.color)
                BatteryGlyph(level: level, color: level.color, height: size * 0.92)
            }
        case .status(_, _, let text):
            MarqueeText(text: text, font: .system(size: size, weight: .semibold), active: true, alignment: .trailing)
                .foregroundStyle(.white)
        case .timerDone:
            Text("Stop")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .frame(height: side)
                .background(Capsule().fill(.orange))
        }
    }

    /// A symbol's square, as the cover's beside the camera.
    static func side(_ restingHeight: CGFloat, _ island: Bool) -> CGFloat {
        restingHeight - LiveActivityView.inset(island: island) * 2
    }

    /// How wide each wing must be for an announcement, up to a limit, a little past a song's
    /// announcement's, beyond which a long name scrolls. A device's, with only symbols, is a little
    /// wider than at rest, so it's seen to arrive. The notch stays centered, so both wings take the
    /// wider one.
    static func wing(for alert: NotchAlert, restingHeight: CGFloat, island: Bool) -> CGFloat {
        let edge = LiveActivityView.edgeInset(island: island, restingHeight: restingHeight)
        let size = LiveActivityView.textSize(for: restingHeight)
        let side = side(restingHeight, island)
        let gap = LiveActivityView.cameraGap
        let (left, right): (CGFloat, CGFloat) =
            switch alert.content {
            case .device(_, let battery):
                (edge + side + gap, gap + (battery == nil ? width("Connected", size, .semibold) : side) + edge)
            case .battery(let title, let level):
                (
                    edge + width(title, size, .semibold) + gap,
                    gap + width("\(level.percent)%", size, .semibold) + 5 + BatteryGlyph.width(height: size * 0.92) + edge
                )
            case .status(_, _, let text):
                (edge + side + gap, gap + width(text, size, .semibold) + edge)
            case .timerDone:
                (edge + side + gap, gap + width("Stop", size, .semibold) + 20 + edge)
            }
        return min(max(left, right, restingHeight * 1.4), maxWing)
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
        insertion: .opacity.animation(.easeOut(duration: 0.3).delay(0.2)),
        removal: .opacity.animation(.easeOut(duration: 0.12)))
}

/// A device arriving, as AirPods arrive in the Dynamic Island: its symbol turning in, a full turn and
/// a little past, then settling face on.
private struct TurningSymbol: View {
    let symbol: String
    let side: CGFloat
    @State private var turn: Double = -200
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: side * 0.95, weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.white)
            .frame(width: side, height: side)
            .rotation3DEffect(.degrees(reduceMotion ? 0 : turn), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            .scaleEffect(shown ? 1 : 0.6)
            .opacity(shown ? 1 : 0)
            .onAppear {
                withAnimation(.easeOut(duration: 0.25).delay(0.15)) { shown = true }
                withAnimation(.spring(response: 1.1, dampingFraction: 0.72).delay(0.15)) { turn = 0 }
            }
    }
}

/// A battery as a ring, as AirPods' is in the Dynamic Island: green, or red at 20% and below,
/// filling to its level as it arrives.
struct BatteryRing: View {
    let percent: Int
    let side: CGFloat
    @State private var filled = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let line = max(side * 0.14, 2.5)
        let color: Color = percent <= 20 ? .red : .green
        ZStack {
            Circle().stroke(color.opacity(0.25), lineWidth: line)
            Circle()
                .trim(from: 0, to: filled || reduceMotion ? CGFloat(percent) / 100 : 0)
                .stroke(color, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(line / 2 + 1)
        .frame(width: side, height: side)
        .onAppear { withAnimation(.easeOut(duration: 0.7).delay(0.35)) { filled = true } }
        .accessibilityLabel("\(percent) percent")
    }
}

/// A state's symbol in its color, bouncing in as the iPhone's do; a timer that's done, shaking until
/// it's stopped.
private struct ArrivingSymbol: View {
    let symbol: String
    let color: Color
    let size: CGFloat
    let side: CGFloat
    var shakes = false
    @State private var arrived = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: side, height: side)
            .symbolEffect(.bounce, value: arrived)
            .symbolEffect(.wiggle, options: .repeat(.continuous), isActive: shakes)
            .onAppear { arrived = true }
    }
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
