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
/// round buttons to pause and to cancel it beside its name and the time left, large; done, its name
/// beside buttons to start it again and to stop it. The opened and the done ones are as tall as the
/// iPhone's, more than twice the notch.
enum TimerLayout {
    // Beside the camera.
    static let ring: CGFloat = 0.573
    static let ringLine: CGFloat = 0.064
    /// The hand, from and to how far out from the ring's middle.
    static let handFrom: CGFloat = 0.06
    static let handTo: CGFloat = 0.17
    // Opened, and done.
    static let tall: CGFloat = 2.4
    /// Its round corners at the bottom, the Dynamic Island's 44 points.
    static let corner: CGFloat = 1.2
    static let button: CGFloat = 1.364
    static let buttonGap: CGFloat = 0.23
    static let title: CGFloat = 0.464
    static let time: CGFloat = 1.277
    static let titleGap: CGFloat = 0.228
    /// The stopwatch's time opened, as the iPhone's: smaller than the timer's, for its hundredths.
    static let stopwatchTime: CGFloat = 0.92
    /// How long a timer's name runs, once it's done, before it's cut short.
    static let titleLimit: CGFloat = 4
    // Done, as the iPhone's Timer: its name, large.
    static let doneName: CGFloat = 0.71
    /// Opened and done, as tall as the iPhone's, for a notch this tall.
    static func tallHeight(_ h: CGFloat) -> CGFloat { (h * tall).rounded() }
    /// Opened and done, how far in from its end each side sits, buttons and words alike: as far as
    /// the round buttons are from the top and bottom, so they're concentric with the round ends,
    /// and the words at the other end match them.
    static func buttonEdge(_ h: CGFloat) -> CGFloat { LiveActivityView.concentric(h * button, in: tallHeight(h)) }

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

/// What the notch opens to beside the camera: Clock's timer, or its stopwatch.
enum ClockShown: Equatable {
    case timer(NotchTimer.State)
    case stopwatch(Stopwatch)

    var isRunning: Bool {
        switch self {
        case .timer(let state): state.isRunning
        case .stopwatch(let watch): watch.isRunning
        }
    }

    /// A timer's digits roll down as they change; the stopwatch's, up.
    var countsDown: Bool {
        if case .timer = self { return true }
        return false
    }

    /// The time as it reads at a moment: what's left of the timer; what's on the stopwatch, to the
    /// hundredth.
    func reading(at date: Date = .now) -> String {
        switch self {
        case .timer(let state): NotchTimer.format(state.left(at: date))
        case .stopwatch(let watch): Stopwatch.format(watch.elapsed(at: date), hundredths: true)
        }
    }
}

/// The stopwatch beside the camera, where a timer's ring sits, as the iPhone draws it: a ring the
/// timer's size, its crown on top and its button beside it, and a hand going round once a minute.
struct StopwatchMark: View {
    let watch: Stopwatch
    let height: CGFloat

    var body: some View {
        let line = height * TimerLayout.ringLine
        let side = height * TimerLayout.ring
        // The crown and its button stand out past the ring by as much as the ring is thick.
        let stem = height * TimerLayout.ringLine * 2
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !watch.isRunning)) { context in
            let second = watch.elapsed(at: context.date).truncatingRemainder(dividingBy: 60)
            ZStack {
                Circle().stroke(.orange, lineWidth: line).padding(line / 2)
                ForEach([0.0, 45], id: \.self) { degrees in
                    Capsule()
                        .fill(.orange)
                        .frame(width: line, height: stem)
                        .offset(y: -(side + stem) / 2 + line / 2)
                        .rotationEffect(.degrees(degrees))
                }
                Capsule()
                    .fill(.orange)
                    .frame(width: line, height: height * (TimerLayout.handTo - TimerLayout.handFrom))
                    .offset(y: -height * (TimerLayout.handFrom + TimerLayout.handTo) / 2)
                    .rotationEffect(.degrees(second / 60 * 360))
            }
            .frame(width: side, height: side)
        }
        .accessibilityHidden(true)
    }
}

/// The stopwatch's time as the iPhone shows it beside the camera: to the second, its hundredths
/// small and raised after it, 0:09⁷¹.
struct StopwatchReading: View {
    let watch: Stopwatch
    let size: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !watch.isRunning)) { context in
            let elapsed = watch.elapsed(at: context.date)
            HStack(alignment: .firstTextBaseline, spacing: size * StopwatchReading.gap) {
                Text(Stopwatch.format(elapsed))
                    .font(.system(size: size, weight: .semibold).monospacedDigit())
                Text(Stopwatch.hundredths(elapsed))
                    .font(.system(size: size * StopwatchReading.small, weight: .semibold).monospacedDigit())
                    .baselineOffset(size * StopwatchReading.raised)
            }
        }
    }

    /// Measured from the iPhone's: the hundredths a little under half the seconds' size, their tops
    /// a little below the seconds', just apart from them.
    static let small: CGFloat = 0.47
    static let raised: CGFloat = 0.32
    static let gap: CGFloat = 0.06

    /// As wide as it reads with its widest digits.
    @MainActor
    static func width(_ elapsed: TimeInterval, size: CGFloat) -> CGFloat {
        let shown = Stopwatch.format(elapsed).replacingOccurrences(of: "[0-9]", with: "0", options: .regularExpression)
        func measure(_ text: String, _ size: CGFloat) -> CGFloat {
            ceil((text as NSString).size(withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: .semibold)]).width)
        }
        return measure(shown, size) + size * gap + measure("00", size * small) + 2
    }
}

/// Opened to a timer, as the iPhone's Timer expands, as tall: round buttons to pause or go on and to
/// cancel left of the camera, the time left, large, right of it, its name under the camera, as the
/// player's title sits under it. Opened to the stopwatch, as the iPhone's: its buttons to stop it and
/// to start it over, or, stopped, to start it and to reset it, and its time alone, to the hundredth.
/// Each side at its end, as far in from it as from the top and bottom, the round buttons concentric
/// with the round end; the notch only as wide as the wider side needs, for the time as it reads now. They're Clock's, pressed through Clock (see `ClockActivity`); without
/// Accessibility, the buttons are dimmed, and a press asks for it.
struct ExpandedTimerView: View {
    let shown: ClockShown
    /// Its name beside the time: Timer, the label Clock's timer was given, or Stopwatch.
    var name = "Timer"
    let restingHeight: CGFloat
    /// The camera housing's width, which the row goes either side of.
    let camera: CGFloat
    /// Its own width (see `width(for:name:restingHeight:camera:at:)`), which changes as the time
    /// loses or gains a digit.
    let width: CGFloat
    @ObservedObject private var clock = ClockActivity.shared

    var body: some View {
        let h = restingHeight
        // The buttons at the left end, the time at the right, the time's name under the camera; to
        // spare, beside the camera.
        let side = max((width - camera) / 2, 0)
        HStack(spacing: 0) {
            buttons(h)
                .padding(.leading, TimerLayout.buttonEdge(h))
                .frame(width: side, alignment: .leading)
            Color.clear.frame(width: camera)
            time(h)
                .padding(.trailing, Self.timeEdge(shown, h))
                .frame(width: side, alignment: .trailing)
        }
        // In the middle of its height, as the iPhone's is.
        .frame(height: h * TimerLayout.button)
        .frame(maxHeight: .infinity)
    }

    /// Pause or go on, and cancel; or start or stop, and start over or reset.
    private func buttons(_ h: CGFloat) -> some View {
        let running = shown.isRunning
        let stopwatch = { if case .stopwatch = shown { return true } else { return false } }()
        return HStack(spacing: h * TimerLayout.buttonGap) {
            IslandCircleButton(height: h, tint: .orange, label: running ? (stopwatch ? "Stop" : "Pause") : (stopwatch ? "Start" : "Resume")) {
                stopwatch ? clock.startStopStopwatch() : clock.toggleTimer()
            } glyph: {
                if running {
                    PauseGlyph(height: h)
                } else {
                    Image(systemName: "play.fill")
                        .font(.system(size: h * 0.62, weight: .bold))
                        .foregroundStyle(.orange)
                }
            }
            IslandCircleButton(height: h, tint: .white, label: stopwatch ? (running ? "Restart" : "Reset") : "Cancel") {
                stopwatch ? clock.resetStopwatch() : clock.cancelTimer()
            } glyph: {
                // Running, it starts over: round again.
                if stopwatch, running {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: h * 0.58, weight: .semibold))
                        .foregroundStyle(.white)
                } else {
                    CrossGlyph(height: h)
                }
            }
        }
        .opacity(clock.canControl ? 1 : 0.45)
        .accessibilityHint(clock.canControl ? "" : "Needs Accessibility")
    }

    /// The time, large, its name small before it, on one line: under the camera, beside it, as far
    /// as the camera's far side.
    private func time(_ h: CGFloat) -> some View {
        let room = camera + LiveActivityView.cameraGap - h * TimerLayout.titleGap
        let ticking: Bool = { if case .stopwatch(let watch) = shown { return watch.isRunning } else { return false } }()
        return Group {
            if case .stopwatch = shown {
                // Alone, to the hundredth, as Clock's own counts, while it runs.
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !ticking)) { context in
                    Text(shown.reading(at: context.date))
                        .font(Self.timeFont(shown, h))
                }
            } else {
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    Text(shown.reading(at: context.date))
                        .font(Self.timeFont(shown, h))
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.snappy, value: shown.reading(at: context.date))
                }
            }
        }
        .overlay(alignment: Alignment(horizontal: .leading, vertical: .firstTextBaseline)) {
            if case .timer = shown {
                let label = max(min(Self.titleWidth(name, h), room), 0)
                Text(name)
                    .font(.system(size: h * TimerLayout.title, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: label, alignment: .trailing)
                    // Its end just before the time's start.
                    .offset(x: -(label + h * TimerLayout.titleGap))
            }
        }
        .foregroundStyle(.orange)
        .fixedSize()
    }

    /// Either side of the camera, as wide as the wider of the buttons and the time needs, each from
    /// its end. For the time as it reads then: it narrows or widens as it loses or gains a digit.
    @MainActor
    static func width(for shown: ClockShown, name: String = "Timer", restingHeight h: CGFloat, camera: CGFloat, at date: Date = .now) -> CGFloat {
        let buttons = TimerLayout.buttonEdge(h) + h * (TimerLayout.button * 2 + TimerLayout.buttonGap)
        let time = timeWidth(shown, h, at: date) + timeEdge(shown, h)
        return camera + 2 * (max(buttons, time) + LiveActivityView.cameraGap)
    }

    /// From the right end to the time: as far as the buttons are from the left end.
    static func timeEdge(_ shown: ClockShown, _ h: CGFloat) -> CGFloat { TimerLayout.buttonEdge(h) }

    /// The timer's time large, as the iPhone's Timer; the stopwatch's a little smaller, medium, as
    /// its stopwatch.
    private static func timeFont(_ shown: ClockShown, _ h: CGFloat) -> Font {
        if case .stopwatch = shown { return .system(size: h * TimerLayout.stopwatchTime, weight: .medium).monospacedDigit() }
        return .system(size: h * TimerLayout.time).monospacedDigit()
    }

    /// The time as it reads then, its digits all as wide as each other.
    @MainActor
    private static func timeWidth(_ shown: ClockShown, _ h: CGFloat, at date: Date = .now) -> CGFloat {
        let reading = shown.reading(at: date).replacingOccurrences(of: "[0-9]", with: "0", options: .regularExpression)
        let font: NSFont = {
            if case .stopwatch = shown { return .monospacedDigitSystemFont(ofSize: h * TimerLayout.stopwatchTime, weight: .medium) }
            return .monospacedDigitSystemFont(ofSize: h * TimerLayout.time, weight: .regular)
        }()
        return ceil((reading as NSString).size(withAttributes: [.font: font]).width) + 2
    }

    @MainActor
    private static func titleWidth(_ name: String, _ h: CGFloat) -> CGFloat {
        ceil((name as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: h * TimerLayout.title, weight: .semibold)]).width) + 1
    }
}

/// A timer that's done, as the iPhone's Timer says so in the Dynamic Island, taller than the notch:
/// its name, large, and round buttons to start it again and to stop it. The closed notch hands
/// them its clicks by where they are (see `AlertButtonFrames`).
struct TimerDoneView: View {
    let length: TimeInterval
    /// Timer, or the label it was given in Clock.
    var name = "Timer"
    let restingHeight: CGFloat
    /// Each wing's width beside the camera (see `wing(length:name:restingHeight:)`).
    var wing: CGFloat = 0
    /// Which button the pointer is on.
    let hovered: AlertButton?

    var body: some View {
        let h = restingHeight
        let gap = LiveActivityView.cameraGap
        let nameEdge = Self.nameEdge(h)
        // Each from its end, as far as from the top and bottom; to spare, beside the camera.
        ZStack {
            Text(name)
                .font(.system(size: h * TimerLayout.doneName, weight: .semibold))
                .foregroundStyle(.orange)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: max(wing - nameEdge - gap, 0), alignment: .leading)
                .padding(.leading, nameEdge)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)
            HStack(spacing: h * TimerLayout.buttonGap) {
                IslandCircle(height: h, tint: .orange, highlighted: hovered == .again) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: h * 0.58, weight: .semibold))
                        .foregroundStyle(.orange)
                }
                .reportsFrame(.again)
                .spokenButton("Repeat") { ClockActivity.shared.repeatTimer() }
                IslandCircle(height: h, tint: .white, highlighted: hovered == .stop) {
                    CrossGlyph(height: h)
                }
                .reportsFrame(.stop)
                .spokenButton("Stop") { ClockActivity.shared.dismissRing() }
            }
            .padding(.trailing, TimerLayout.buttonEdge(h))
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(maxHeight: .infinity)
    }

    /// Each wing: as wide as the wider side, the name or the buttons, each from its end. A long
    /// label is cut short at its limit.
    static func wing(length: TimeInterval, name: String = "Timer", restingHeight h: CGFloat) -> CGFloat {
        let gap = LiveActivityView.cameraGap
        let words = min(
            ceil((name as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: h * TimerLayout.doneName, weight: .semibold)]).width) + 2,
            h * TimerLayout.titleLimit)
        let left = nameEdge(h) + words + gap
        let right = gap + h * (TimerLayout.button * 2 + TimerLayout.buttonGap) + TimerLayout.buttonEdge(h)
        return max(left, right)
    }

    /// From the left end to its name: as far as the buttons are from the right end, so the two
    /// sides sit alike.
    static func nameEdge(_ h: CGFloat) -> CGFloat { TimerLayout.buttonEdge(h) }
}

/// The buttons a timer that's done, and Low Battery, have in the closed notch.
enum AlertButton: Hashable {
    case again, stop
    /// Low Battery's, which turns on Low Power Mode.
    case lowPower
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
    func spokenButton(_ label: String, action: @escaping () -> Void) -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default, action)
    }

    func reportsFrame(_ button: AlertButton) -> some View {
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
