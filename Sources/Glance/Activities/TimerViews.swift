//
//  TimerViews.swift
//  Glance
//
//  Created by Gaty on 18/10/2026.
//

import AppKit
import SwiftUI

/// The Timer as the iPhone draws it in the Dynamic Island, measured from it, by the island's
/// height: beside the camera, a ring emptying as the time runs out, and the minutes left; opened,
/// round buttons to pause and to cancel it beside its name and the time left, large; done, as the
/// Alarm goes off, its symbol and its length beside buttons to start it again and to stop it. The
/// opened and the done ones are as tall as the iPhone's, more than twice the notch.
enum TimerLayout {
    // Beside the camera.
    static let ring: CGFloat = 0.573
    static let ringLine: CGFloat = 0.064
    static let ringInset: CGFloat = 0.227
    /// The hand, from and to how far out from the ring's middle.
    static let handFrom: CGFloat = 0.06
    static let handTo: CGFloat = 0.17
    static let textInset: CGFloat = 0.255
    /// The least each wing reaches past the island at rest.
    static let wing: CGFloat = 1.02
    /// Between what the wings show and the camera, which the iPhone's runs right up to.
    static let snug: CGFloat = 0.06
    // Opened, and done.
    static let tall: CGFloat = 2.4
    /// As wide as the iPhone's expanded Timer.
    static let wide: CGFloat = 10.2
    /// Its round corners at the bottom, the Dynamic Island's 44 points.
    static let corner: CGFloat = 1.2
    static let button: CGFloat = 1.364
    static let buttonGap: CGFloat = 0.23
    static let buttonInset: CGFloat = 0.455
    static let title: CGFloat = 0.464
    static let time: CGFloat = 1.277
    static let titleGap: CGFloat = 0.228
    // Done, as the Alarm: its symbol, and its length small above its name, lower than the middle.
    static let iconInset: CGFloat = 0.7
    static let icon: CGFloat = 1.16
    static let iconGap: CGFloat = 0.44
    static let small: CGFloat = 0.4
    static let name: CGFloat = 0.46
    static let wordsLower: CGFloat = 0.27
    // Inside the round buttons.
    static let pauseBar = CGSize(width: 0.19, height: 0.6)
    static let pauseGap: CGFloat = 0.09
    static let cross: CGFloat = 0.509
    static let crossLine: CGFloat = 0.09
}

/// The time left as a ring, as the iPhone's Timer shows it beside the camera: full when it starts,
/// emptying back toward the top as the time goes, what's gone dimmed, a hand where what's left ends.
struct TimerRing: View {
    let state: NotchTimer.State
    /// The notch's height, which it's measured by.
    let height: CGFloat

    var body: some View {
        let line = height * TimerLayout.ringLine
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let left = state.total > 0 ? min(max(state.left(at: context.date) / state.total, 0), 1) : 0
            ZStack {
                Circle().stroke(.orange.opacity(0.3), lineWidth: line)
                Circle()
                    .trim(from: 0, to: left)
                    .stroke(.orange, style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Capsule()
                    .fill(.orange)
                    .frame(width: line, height: height * (TimerLayout.handTo - TimerLayout.handFrom))
                    .offset(y: -height * (TimerLayout.handFrom + TimerLayout.handTo) / 2)
                    .rotationEffect(.degrees(left * 360))
            }
            .padding(line / 2)
            .animation(.linear(duration: 0.5), value: left)
        }
        .frame(width: height * TimerLayout.ring, height: height * TimerLayout.ring)
        .accessibilityHidden(true)
    }
}

/// Opened while a timer runs, as the iPhone's Timer expands, as tall: round buttons to pause or go on
/// and to cancel left of the camera, the time left, large, right of it, its name under the camera,
/// as the player's title sits under it. In from the notch's ends as far as the player is, and as
/// far from the camera as the player's cover; the notch only as wide as that needs, for the time as
/// it reads now. macOS's own timer is paused and cancelled through Clock; without Accessibility,
/// its buttons are dimmed, and a press asks for it.
struct ExpandedTimerView: View {
    let state: NotchTimer.State
    let restingHeight: CGFloat
    /// The camera housing's width, which the row goes either side of; none on an island.
    let camera: CGFloat
    /// Its own width (see `width(for:restingHeight:camera:system:at:)`), which changes as the time
    /// loses a digit.
    let width: CGFloat
    var system = false
    @ObservedObject private var clock = SystemTimer.shared

    var body: some View {
        let h = restingHeight
        Group {
            if camera > 0 {
                // The buttons left of the camera, the time right of it, the time's name under it.
                let side = max((width - camera) / 2, 0)
                HStack(spacing: 0) {
                    buttons(h)
                        .padding(.leading, PlayerLayout.padding)
                        .frame(width: side, alignment: .leading)
                    Color.clear.frame(width: camera)
                    time(h)
                        .padding(.trailing, PlayerLayout.padding)
                        .frame(width: side, alignment: .trailing)
                }
            } else {
                // As the iPhone's: the buttons at the left end, the time at the right.
                ZStack {
                    buttons(h)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    time(h)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(.horizontal, PlayerLayout.padding)
            }
        }
        // In the middle of its height, as the iPhone's is.
        .frame(height: h * TimerLayout.button)
        .frame(maxHeight: .infinity)
    }

    /// Pause or go on, and cancel: Glance's own timer, or macOS's, through Clock (see `SystemTimer`).
    private func buttons(_ h: CGFloat) -> some View {
        let timer = NotchTimer.shared
        let locked = system && !clock.canControl
        return HStack(spacing: h * TimerLayout.buttonGap) {
            IslandCircleButton(height: h, tint: .orange, label: state.isRunning ? "Pause" : "Resume") {
                if system {
                    clock.toggle()
                } else {
                    state.isRunning ? timer.pause() : timer.resume()
                }
            } glyph: {
                if state.isRunning {
                    PauseGlyph(height: h)
                } else {
                    Image(systemName: "play.fill")
                        .font(.system(size: h * 0.62, weight: .bold))
                        .foregroundStyle(.orange)
                }
            }
            IslandCircleButton(height: h, tint: .white, label: "Cancel") {
                system ? clock.cancel() : timer.cancel()
            } glyph: {
                CrossGlyph(height: h)
            }
        }
        .opacity(locked ? 0.45 : 1)
        .accessibilityHint(locked ? "Needs Accessibility" : "")
    }

    /// Its name, small, and the time left, large, on one line.
    private func time(_ h: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: h * TimerLayout.titleGap) {
            Text("Timer")
                .font(.system(size: h * TimerLayout.title, weight: .semibold))
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                Text(NotchTimer.format(state.left(at: context.date)))
                    .font(.system(size: h * TimerLayout.time).monospacedDigit())
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.snappy, value: NotchTimer.format(state.left(at: context.date)))
            }
        }
        .foregroundStyle(.orange)
        .fixedSize()
    }

    /// Either side of the camera, as wide as the wider of the buttons and the time needs, with the
    /// player's room at the ends and beside the camera; on an island, as wide as the iPhone's, or as
    /// they need. For the time as it reads then: it narrows as it loses a digit.
    @MainActor
    static func width(for state: NotchTimer.State, restingHeight h: CGFloat, camera: CGFloat, at date: Date = .now) -> CGFloat {
        let buttons = h * (TimerLayout.button * 2 + TimerLayout.buttonGap)
        // Its digits all as wide as each other.
        let shown = NotchTimer.format(state.left(at: date)).replacingOccurrences(of: "[0-9]", with: "0", options: .regularExpression)
        let time = ceil((shown as NSString).size(withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: h * TimerLayout.time, weight: .regular)]).width) + 2
        let padding = PlayerLayout.padding
        guard camera > 0 else {
            let title = ceil(("Timer" as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: h * TimerLayout.title, weight: .semibold)]).width)
            return max(h * TimerLayout.wide, padding * 2 + buttons + h + title + h * TimerLayout.titleGap + time)
        }
        return camera + 2 * (padding + max(buttons, time) + PlayerLayout.besideCamera)
    }
}

/// A timer that's done, as the iPhone's Alarm goes off in the Dynamic Island, taller than the notch:
/// its symbol shaking, its length small above its name, and round buttons to start it again and to
/// stop it. The closed notch hands them its clicks by where they are (see `AlertButtonFrames`).
struct TimerDoneView: View {
    let length: TimeInterval
    let restingHeight: CGFloat
    /// Which button the pointer is on.
    let hovered: AlertButton?

    var body: some View {
        let h = restingHeight
        ZStack {
            HStack(spacing: h * TimerLayout.iconGap) {
                // Solid, its hand cut out, as the Alarm's clock is.
                ArrivingSymbol(symbol: "timer.circle.fill", color: .orange, size: h * TimerLayout.icon * 0.9, side: h * TimerLayout.icon, shakes: true)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(Self.name(length))
                        .font(.system(size: h * TimerLayout.small, weight: .semibold))
                        .foregroundStyle(.orange.opacity(0.47))
                    Text("Timer")
                        .font(.system(size: h * TimerLayout.name, weight: .bold))
                        .foregroundStyle(.orange)
                }
                .fixedSize()
                .offset(y: h * TimerLayout.wordsLower)
            }
            .padding(.leading, h * TimerLayout.iconInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: h * TimerLayout.buttonGap) {
                IslandCircle(height: h, tint: .orange, highlighted: hovered == .again) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: h * 0.56, weight: .bold))
                        .foregroundStyle(.orange)
                }
                .reportsFrame(.again)
                .spokenButton("Repeat") { NotchTimer.shared.repeatLast() }
                IslandCircle(height: h, tint: .white, highlighted: hovered == .stop) {
                    CrossGlyph(height: h)
                }
                .reportsFrame(.stop)
                .spokenButton("Stop") { NotchTimer.shared.stop() }
            }
            .padding(.trailing, h * TimerLayout.buttonInset)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(maxHeight: .infinity)
    }

    /// Its length, as its preset is named: 5 Minutes, 1 Hour.
    static func name(_ length: TimeInterval) -> String {
        NotchTimer.name(minutes: max(Int((length / 60).rounded()), 1))
    }

    /// Each wing: as wide as the wider side, the symbol and the words or the buttons, and the camera
    /// between them.
    static func wing(length: TimeInterval, restingHeight h: CGFloat) -> CGFloat {
        func width(_ text: String, _ size: CGFloat, _ weight: NSFont.Weight) -> CGFloat {
            ceil((text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight)]).width) + 2
        }
        let words = max(width(name(length), h * TimerLayout.small, .semibold), width("Timer", h * TimerLayout.name, .bold))
        let left = h * (TimerLayout.iconInset + TimerLayout.icon + TimerLayout.iconGap) + words
        let right = h * (TimerLayout.buttonInset + TimerLayout.button * 2 + TimerLayout.buttonGap)
        return max(left, right) + h * TimerLayout.snug
    }
}

/// The buttons a timer that's done has in the closed notch.
enum AlertButton: Hashable {
    case again, stop
}

/// Where the closed notch's buttons are, in the notch's points, while they show.
struct AlertButtonFrames: PreferenceKey {
    static let defaultValue: [AlertButton: CGRect] = [:]
    static func reduce(value: inout [AlertButton: CGRect], nextValue: () -> [AlertButton: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// A drawn button, which the closed notch presses by where it is, as a button VoiceOver can name
    /// and press.
    fileprivate func spokenButton(_ label: String, action: @escaping () -> Void) -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default, action)
    }

    fileprivate func reportsFrame(_ button: AlertButton) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(key: AlertButtonFrames.self, value: [button: proxy.frame(in: .named(ControlFrames.space))])
            }
        }
    }
}

/// A round button as the Dynamic Island's Timer and Alarm have: its symbol on a faint fill of its
/// color, orange or white, brighter under the pointer.
struct IslandCircle<Glyph: View>: View {
    let height: CGFloat
    let tint: Color
    var highlighted = false
    @ViewBuilder let glyph: Glyph

    /// Orange shows at a little over a third, white at a fifth, as the iPhone's.
    private var fill: Double { (tint == .white ? 0.2 : 0.35) + (highlighted ? 0.1 : 0) }

    var body: some View {
        glyph
            .frame(width: height * TimerLayout.button, height: height * TimerLayout.button)
            .background(Circle().fill(tint.opacity(fill)))
            .animation(.easeOut(duration: 0.15), value: highlighted)
    }
}

/// An `IslandCircle` that's a button, in the open notch.
struct IslandCircleButton<Glyph: View>: View {
    let height: CGFloat
    let tint: Color
    let label: String
    let action: () -> Void
    @ViewBuilder let glyph: Glyph
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            IslandCircle(height: height, tint: tint, highlighted: hovering) { glyph }
                .contentShape(Circle())
        }
        .buttonStyle(IslandPress(highlight: false, contactSize: nil))
        .onHover { hovering = $0 }
        .notchControl()
        .accessibilityLabel(label)
    }
}

/// Two rounded bars, as the Timer's pause.
private struct PauseGlyph: View {
    let height: CGFloat

    var body: some View {
        let bar = TimerLayout.pauseBar
        HStack(spacing: height * TimerLayout.pauseGap) {
            ForEach(0..<2, id: \.self) { _ in
                RoundedRectangle(cornerRadius: height * 0.05, style: .continuous)
                    .fill(.orange)
                    .frame(width: height * bar.width, height: height * bar.height)
            }
        }
    }
}

/// The Timer's and the Alarm's ✕, white, its strokes rounded.
struct CrossGlyph: View {
    let height: CGFloat

    var body: some View {
        let side = height * TimerLayout.cross, line = height * TimerLayout.crossLine
        Path { path in
            let a = line / 2, b = side - line / 2
            path.move(to: CGPoint(x: a, y: a))
            path.addLine(to: CGPoint(x: b, y: b))
            path.move(to: CGPoint(x: b, y: a))
            path.addLine(to: CGPoint(x: a, y: b))
        }
        .stroke(.white, style: StrokeStyle(lineWidth: line, lineCap: .round))
        .frame(width: side, height: side)
    }
}

/// The thin line in an activity's color that the Dynamic Island draws around itself over a dark
/// background, so its edge shows: just outside the notch's sides and bottom, never along the top,
/// which is the screen's edge. Drawn in full screen, all black around the notch.
struct KeyLine: Shape {
    var notch: NotchShape
    /// How thick, by the notch's height.
    static let width: CGFloat = 0.045
    var width: CGFloat

    var animatableData: NotchShape.AnimatableData {
        get { notch.animatableData }
        set { notch.animatableData = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let outline = notch.path(in: rect)
        let ring = outline.strokedPath(StrokeStyle(lineWidth: width * 2)).subtracting(outline)
        let top = notch.island ? rect.minY - width * 2 : rect.minY + notch.flare(in: rect) + 0.5
        return ring.intersection(Path(CGRect(x: rect.minX - width * 2, y: top, width: rect.width + width * 4, height: rect.maxY + width * 2 - top)))
    }
}
