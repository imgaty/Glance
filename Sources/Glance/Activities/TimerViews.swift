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
    static let handTo: CGFloat = 0.21
    // Opened, and done.
    static let tall: CGFloat = 2.4
    static let buttonGap: CGFloat = 0.23
    static let time: CGFloat = 0.9375
    static let titleGap: CGFloat = 0.228
    /// Digits sit low in their line and short of its end: how far up, and out, brings them level
    /// with the middle, and as far from the end as the buttons are from theirs.
    static let timeLift: CGFloat = 0.022
    static let timeBearing: CGFloat = 0.057
    /// Clock's orange, measured, for the timer and the stopwatch alike.
    static let ink = Color(.sRGB, red: 0xFD / 255, green: 0x95 / 255, blue: 0)
    // The stopwatch opened.
    static let stopwatchPauseBar = CGSize(width: 0.171, height: 0.571)
    static let stopwatchPauseGap: CGFloat = 0.076
    static let stopwatchTracking: CGFloat = -0.018
    static let stopwatchPauseFill = Color(.sRGB, red: 0x40 / 255, green: 0x25 / 255, blue: 0x0C / 255)
    static let stopwatchResetFill = Color(.sRGB, red: 0x3B / 255, green: 0x3B / 255, blue: 0x3D / 255)
    /// How long a timer's name runs, once it's done, before it's cut short.
    static let titleLimit: CGFloat = 4
    // Done, as the iPhone's Timer: its name, large.
    /// Opened and done, as tall as the iPhone's, for a notch this tall.
    static func tallHeight(_ h: CGFloat) -> CGFloat { (h * tall).rounded() }
    /// Opened and done, how far in from its end each side sits, buttons and words alike: the notch's
    /// one padding, as they are from the top and bottom.
    static func buttonEdge(_ h: CGFloat) -> CGFloat { PlayerLayout.padding }
    /// What stands at the ends of anything this tall, as tall as the padding leaves: round, it's
    /// concentric with the notch's round end.
    static func content(_ h: CGFloat) -> CGFloat { tallHeight(h) - PlayerLayout.padding * 2 }

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
    /// A preview can exercise this appearance without changing the Mac's setting.
    var reduceMotionOverride: Bool? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var motionReduced: Bool { reduceMotionOverride ?? reduceMotion }

    var body: some View {
        let line = height * TimerLayout.ringLine
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let left = state.total > 0 ? min(max(state.left(at: context.date) / state.total, 0), 1) : 0
            ZStack {
                Circle().stroke(TimerLayout.ink.opacity(0.3), lineWidth: line)
                Circle()
                    .trim(from: 0, to: left)
                    .stroke(TimerLayout.ink, style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Capsule()
                    .fill(TimerLayout.ink)
                    .frame(width: line, height: height * (TimerLayout.handTo - TimerLayout.handFrom))
                    .offset(y: -height * (TimerLayout.handFrom + TimerLayout.handTo) / 2)
                    .rotationEffect(.degrees(left * 360))
            }
            .padding(line / 2)
            .animation(motionReduced ? nil : .linear(duration: 0.5), value: left)
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
    /// The time reading keeps updating; only the decorative hand stops moving.
    var reduceMotionOverride: Bool? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var motionReduced: Bool { reduceMotionOverride ?? reduceMotion }

    var body: some View {
        let line = height * TimerLayout.ringLine
        let side = height * TimerLayout.ring
        // The crown and its button stand out past the ring by as much as the ring is thick.
        let stem = height * TimerLayout.ringLine * 2
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: motionReduced || !watch.isRunning)) { context in
            let second = watch.elapsed(at: context.date).truncatingRemainder(dividingBy: 60)
            ZStack {
                Circle().stroke(TimerLayout.ink, lineWidth: line).padding(line / 2)
                ForEach([0.0, 45], id: \.self) { degrees in
                    Capsule()
                        .fill(TimerLayout.ink)
                        .frame(width: line, height: stem)
                        .offset(y: -(side + stem) / 2 + line / 2)
                        .rotationEffect(.degrees(degrees))
                }
                Capsule()
                    .fill(TimerLayout.ink)
                    .frame(width: line, height: height * (TimerLayout.handTo - TimerLayout.handFrom))
                    .offset(y: -height * (TimerLayout.handFrom + TimerLayout.handTo) / 2)
                    .rotationEffect(.degrees(second / 60 * 360))
            }
            .frame(width: side, height: side)
        }
        // Its crown stands out at the top alone: lowered by half of that, all of it is centered.
        .offset(y: (stem - line / 2) / 2)
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
                    .font(.system(size: size * StopwatchReading.share(size), weight: .semibold).monospacedDigit())
                    .baselineOffset(StopwatchReading.raised(size))
            }
        }
    }

    /// The hundredths a little under two thirds the seconds' size, level with their tops, just apart
    /// from them.
    static let small: CGFloat = 0.64
    static let gap: CGFloat = 0.06

    /// How far above the seconds' baseline, for the tops of the two to be level.
    static func raised(_ size: CGFloat) -> CGFloat {
        NSFont.systemFont(ofSize: size, weight: .semibold).capHeight * (1 - share(size))
    }

    /// The hundredths' share of the seconds' size, but never under the Mac's smallest text.
    static func share(_ size: CGFloat) -> CGFloat { max(small, smallest / max(size, 1)) }
    static let smallest: CGFloat = 10

    /// As wide as it reads with its widest digits.
    @MainActor
    static func width(_ elapsed: TimeInterval, size: CGFloat) -> CGFloat {
        let shown = Stopwatch.format(elapsed).replacingOccurrences(of: "[0-9]", with: "0", options: .regularExpression)
        func measure(_ text: String, _ size: CGFloat) -> CGFloat {
            ceil((text as NSString).size(withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: .semibold)]).width)
        }
        return measure(shown, size) + size * gap + measure("00", size * share(size)) + 1
    }
}

/// Opened to a timer, as the iPhone's Timer expands, as tall: round buttons to pause or go on and to
/// cancel left of the camera, the time left, large, right of it, its name under the camera, as the
/// player's title sits under it. Opened to the stopwatch, as the iPhone's: its buttons to stop it and
/// to start it over, or, stopped, to start it and to reset it, and its time alone, to the hundredth.
/// Each side at its end, as far in from it as from the top and bottom; the notch only as wide as the wider side needs, for the time as it reads now. They're Clock's, pressed through Clock (see `ClockActivity`); without
/// Accessibility, the buttons are dimmed, and a press asks for it.
struct ExpandedTimerView: View {
    let shown: ClockShown
    /// Its name beside the time: Timer, the label Clock's timer was given, or Stopwatch.
    var name = String(localized: "Timer")
    let restingHeight: CGFloat
    /// The camera housing's width, which the row goes either side of.
    let camera: CGFloat
    /// Its own width (see `width(for:name:restingHeight:camera:at:)`), which changes as the time
    /// loses or gains a digit.
    let width: CGFloat
    /// The notch is open to it.
    var revealed = true
    /// How wide the notch is closed, if it shows beside the camera there, and grows out of that.
    var closedWidth: CGFloat? = nil
    /// How far below its middle at rest the closed notch's middle was, swollen under the pointer.
    var closedDrop: CGFloat = 0
    /// A preview can exercise this appearance without changing the Mac's setting.
    var reduceMotionOverride: Bool? = nil
    @ObservedObject private var clock = ClockActivity.shared
    @Environment(\.trailingGrows) private var trailingGrows
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var motionReduced: Bool { reduceMotionOverride ?? reduceMotion }

    var body: some View {
        let h = restingHeight
        // The buttons at the left end, the time at the right, the time's name under the camera; to
        // spare, beside the camera.
        let side = max((width - camera) / 2, 0)
        let out = revealed
        let rise = (h - TimerLayout.tallHeight(h)) / 2 + closedDrop
        let spread = ((closedWidth ?? width) - width) / 2
        let timeFrom = CGSize(width: spread - LiveActivityView.textEdge(restingHeight: h) + Self.timeEdge(h), height: rise)
        let ringFrom = CGSize(width: SystemActivityView.ringEdge(h) - TimerLayout.buttonEdge(h) - spread, height: rise)
        let small = LiveActivityView.textSize(for: h) / (h * TimerLayout.time)
        HStack(spacing: 0) {
            buttons(h)
                .modifier(GrowsOut(out: out || closedWidth == nil, scale: TimerLayout.ring / TimerLayout.content(h) * h, anchor: .leading, from: ringFrom))
                .modifier(IslandReveal(hidden: !revealed))
                .padding(.leading, TimerLayout.buttonEdge(h))
                .frame(width: side, alignment: .leading)
            Color.clear.frame(width: camera)
            time(h)
                .modifier(GrowsOut(out: out || closedWidth == nil || !trailingGrows, scale: small, anchor: .trailing, from: timeFrom))
                .modifier(GrownFade(shown: revealed, grows: closedWidth != nil && trailingGrows))
                .padding(.trailing, Self.timeEdge(h))
                .frame(width: side, alignment: .trailing)
        }
        // In the middle of its height, as the iPhone's is.
        .frame(height: TimerLayout.content(h))
        .frame(maxHeight: .infinity)
    }

    /// Pause or go on, and cancel; or start or stop, and start over or reset.
    private func buttons(_ h: CGFloat) -> some View {
        let running = shown.isRunning
        let stopwatch = { if case .stopwatch = shown { return true } else { return false } }()
        return HStack(spacing: h * TimerLayout.buttonGap) {
            IslandCircleButton(
                control: .activityFirst, height: h, tint: TimerLayout.ink,
                label: running ? (stopwatch ? String(localized: "Stop") : String(localized: "Pause")) : (stopwatch ? String(localized: "Start") : String(localized: "Resume")),
                fill: stopwatch ? TimerLayout.stopwatchPauseFill : nil
            ) {
                stopwatch ? clock.startStopStopwatch() : clock.toggleTimer()
            } glyph: {
                if running {
                    PauseGlyph(height: h, stopwatch: stopwatch)
                } else {
                    Image(systemName: "play.fill")
                        .font(.system(size: h * 0.62, weight: .bold))
                        .foregroundStyle(TimerLayout.ink)
                }
            }
            IslandCircleButton(
                control: .activitySecond, height: h, tint: .white, label: stopwatch ? (running ? String(localized: "Restart") : String(localized: "Reset")) : String(localized: "Cancel"),
                fill: stopwatch ? TimerLayout.stopwatchResetFill : nil
            ) {
                stopwatch ? clock.resetStopwatch() : clock.cancelTimer()
            } glyph: {
                // Running, it starts over: round again.
                if stopwatch, running {
                    ResetArrow(height: h)
                } else {
                    CrossGlyph(height: h)
                }
            }
        }
        .opacity(clock.canControl ? 1 : 0.45)
        .accessibilityHint(clock.canControl ? "" : String(localized: "Needs Accessibility"))
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
                        .font(NotchType.time(h))
                        .tracking(h * TimerLayout.stopwatchTracking)
                }
            } else {
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    Text(shown.reading(at: context.date))
                        .font(NotchType.time(h))
                        .contentTransition(motionReduced ? .identity : .numericText(countsDown: true))
                        .animation(motionReduced ? nil : .snappy, value: shown.reading(at: context.date))
                }
            }
        }
        .overlay(alignment: Alignment(horizontal: .leading, vertical: .firstTextBaseline)) {
            if case .timer = shown {
                let label = max(min(Self.titleWidth(name, h), room), 0)
                Text(name)
                    .font(NotchType.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: label, alignment: .trailing)
                    // Its end just before the time's start.
                    .offset(x: -(label + h * TimerLayout.titleGap))
                    .modifier(IslandReveal(hidden: !revealed))
            }
        }
        .foregroundStyle(TimerLayout.ink)
        .fixedSize()
        .offset(y: -h * TimerLayout.timeLift)
    }

    private static func isStopwatch(_ shown: ClockShown) -> Bool {
        if case .stopwatch = shown { return true }
        return false
    }

    /// Either side of the camera, as wide as the wider of the buttons and the time needs, each from
    /// its end. For the time as it reads then: it narrows or widens as it loses or gains a digit.
    @MainActor
    static func width(for shown: ClockShown, name: String = String(localized: "Timer"), restingHeight h: CGFloat, camera: CGFloat, at date: Date = .now) -> CGFloat {
        let buttons = TimerLayout.buttonEdge(h) + TimerLayout.content(h) * 2 + h * TimerLayout.buttonGap
        let time = timeWidth(shown, h, at: date) + timeEdge(h)
        return camera + 2 * (max(buttons, time) + LiveActivityView.cameraGap)
    }

    /// From the right end to the time: as far as the buttons are from the left end.
    static func timeEdge(_ h: CGFloat) -> CGFloat { TimerLayout.buttonEdge(h) - h * TimerLayout.timeBearing }

    /// The time as it reads then, its digits all as wide as each other.
    @MainActor
    private static func timeWidth(_ shown: ClockShown, _ h: CGFloat, at date: Date = .now) -> CGFloat {
        let reading = shown.reading(at: date).replacingOccurrences(of: "[0-9]", with: "0", options: .regularExpression)
        let font = NSFont.monospacedDigitSystemFont(ofSize: h * TimerLayout.time, weight: .semibold)
        let tracking = isStopwatch(shown) ? CGFloat(reading.count) * h * TimerLayout.stopwatchTracking : 0
        return ceil((reading as NSString).size(withAttributes: [.font: font]).width + tracking) + 2
    }

    @MainActor
    private static func titleWidth(_ name: String, _ h: CGFloat) -> CGFloat {
        ceil((name as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: NotchType.size, weight: .semibold)]).width) + 1
    }
}

/// Something in an activity opened that grows out of where it shows beside the camera, as the cover
/// and the waveform do, on the notch's own spring: from there, at that size, to its place.
struct GrowsOut: ViewModifier {
    /// In its place in the open notch.
    let out: Bool
    /// Its size beside the camera, by its size here.
    let scale: CGFloat
    let anchor: UnitPoint
    /// Where it shows beside the camera, from its place here.
    let from: CGSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(out || reduceMotion ? 1 : scale, anchor: anchor)
            .offset(out || reduceMotion ? .zero : from)
    }
}

/// What shows only in the open notch, as the Dynamic Island's expanded activities show it: out of a
/// blur and faded in on the island's own curves, measured from it, and a little smaller at first,
/// growing on the notch's spring as the notch does, so it rides out with it rather than fading in
/// where it ends up. Closing, it blurs away as fast as the wings' do, shrinking back. With Reduce
/// Motion on, it only fades.
struct IslandReveal: ViewModifier {
    let hidden: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How large it starts, by its size.
    static let start: CGFloat = 0.86

    func body(content: Content) -> some View {
        content
            .islandFade(!hidden)
            .animation(hidden ? IslandMotion.fold : NotchMotion.expand) { $0.scaleEffect(hidden && !reduceMotion ? Self.start : 1) }
    }
}

/// A shared glyph's closed position when its activity lives in the detached bubble.
private struct ActivityBubbleCenterKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
    var activityBubbleCenter: CGFloat? {
        get { self[ActivityBubbleCenterKey.self] }
        set { self[ActivityBubbleCenterKey.self] = newValue }
    }
}

/// What grows out of the notch takes over from what's beside the camera at once, as they're in the
/// same place at the same size, and hands back only once it has shrunk there. What doesn't fades as
/// the rest of the page does.
struct GrownFade: ViewModifier {
    let shown: Bool
    let grows: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// When what grew hands back to what's beside the camera, once it has all but shrunk there: the
    /// fold's spring is within half a point of its place by then, so the two are one.
    static let handBack = 0.4

    func body(content: Content) -> some View {
        if grows && !reduceMotion {
            content.animation((shown ? Animation.linear(duration: 0.01) : .linear(duration: 0.08).delay(Self.handBack)).paced) {
                $0.opacity(shown ? 1 : 0)
            }
        } else {
            content.modifier(IslandReveal(hidden: !shown))
        }
    }
}

/// A timer that's done, as the iPhone's Timer says so in the Dynamic Island, taller than the notch:
/// its name, large, and round buttons to start it again and to stop it. The closed notch hands
/// them its clicks by where they are (see `AlertButtonFrames`).
struct TimerDoneView: View {
    let length: TimeInterval
    /// Timer, or the label it was given in Clock.
    var name = String(localized: "Timer")
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
                .font(NotchType.title)
                .foregroundStyle(TimerLayout.ink)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: max(wing - nameEdge - gap, 0), alignment: .leading)
                .padding(.leading, nameEdge)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)
            HStack(spacing: h * TimerLayout.buttonGap) {
                IslandCircle(height: h, tint: TimerLayout.ink, highlighted: hovered == .again) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: h * 0.58, weight: .semibold))
                        .foregroundStyle(TimerLayout.ink)
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
    static func wing(length: TimeInterval, name: String = String(localized: "Timer"), restingHeight h: CGFloat) -> CGFloat {
        let gap = LiveActivityView.cameraGap
        let words = min(
            ceil((name as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: NotchType.size, weight: .semibold)]).width) + 2,
            h * TimerLayout.titleLimit)
        let left = nameEdge(h) + words + gap
        let right = gap + TimerLayout.content(h) * 2 + h * TimerLayout.buttonGap + TimerLayout.buttonEdge(h)
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
    /// A call coming in.
    case accept, decline
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
    /// Its own solid fill, in place of its color showing faintly.
    var fill: Color?
    /// Its own size, in place of as tall as the padding leaves.
    var side: CGFloat?
    @ViewBuilder let glyph: Glyph

    /// Orange shows at a little over a third, white at a fifth, as the iPhone's.
    private var faint: Double { (tint == .white ? 0.2 : 0.35) + (highlighted ? 0.1 : 0) }

    var body: some View {
        let side = side ?? TimerLayout.content(height)
        glyph
            .frame(width: side, height: side)
            .background(
                Circle()
                    .fill(fill ?? tint.opacity(faint))
                    .overlay(Circle().fill(.white.opacity(fill != nil && highlighted ? 0.08 : 0)))
            )
            .animation(.easeOut(duration: 0.15), value: highlighted)
    }
}

/// An `IslandCircle` that's a button, in the open notch.
struct IslandCircleButton<Glyph: View>: View {
    let control: PlayerControl
    let height: CGFloat
    let tint: Color
    let label: String
    var fill: Color?
    var side: CGFloat?
    let action: () -> Void
    @ViewBuilder let glyph: Glyph
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            IslandCircle(height: height, tint: tint, highlighted: hovering, fill: fill, side: side) { glyph }
                .contentShape(Circle())
        }
        .buttonStyle(IslandPress(highlight: false, contactSize: nil))
        .onHover { hovering = $0 }
        .notchControl()
        .keyControl(control, outset: CGSize(width: 3, height: 3), spoken: label, action: action)
        .accessibilityLabel(label)
    }
}

/// The Stopwatch's arrow round to the start, as the iPhone draws it, measured from it: a ring from a
/// little past the top, its end round, most of the way back to the top, where it runs into a solid
/// arrowhead.
private struct ResetArrow: View {
    let height: CGFloat

    var body: some View {
        let h = height
        let side = TimerLayout.content(h)
        let middle = CGPoint(x: side / 2 + h * 0.008, y: side / 2 + h * 0.02)
        let line = h * 0.097
        // Rounded by a stroke round its edge, so drawn that much smaller.
        let corner = h * 0.04
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: middle.x + h * x, y: middle.y + h * y) }
        return ZStack {
            Path { path in
                path.addArc(center: middle, radius: h * 0.324, startAngle: .degrees(-49.6), endAngle: .degrees(-102.5), clockwise: false)
            }
            .stroke(.white, style: StrokeStyle(lineWidth: line, lineCap: .round))
            let head = Path { path in
                path.move(to: point(-0.055, -0.418))
                path.addLine(to: point(0.08, -0.318))
                path.addLine(to: point(-0.055, -0.218))
                path.closeSubpath()
            }
            head.fill(.white)
            head.stroke(.white, style: StrokeStyle(lineWidth: corner, lineJoin: .round))
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

/// Two rounded bars, as the Timer's pause.
private struct PauseGlyph: View {
    let height: CGFloat
    var stopwatch = false

    var body: some View {
        let bar = stopwatch ? TimerLayout.stopwatchPauseBar : TimerLayout.pauseBar
        HStack(spacing: height * (stopwatch ? TimerLayout.stopwatchPauseGap : TimerLayout.pauseGap)) {
            ForEach(0..<2, id: \.self) { _ in
                RoundedRectangle(cornerRadius: height * 0.05, style: .continuous)
                    .fill(TimerLayout.ink)
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
