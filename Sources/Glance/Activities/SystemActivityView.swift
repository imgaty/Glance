//
//  SystemActivityView.swift
//  Glance
//
//  Created by Gaty on 16/10/2026.
//

import AppKit
import SwiftUI

/// What the Mac announces, and Clock's timer or stopwatch, in the closed notch's wings, as the
/// iPhone's Dynamic Island draws its own, the two sides read as one: a device's symbol turning in
/// beside its battery's ring; the Mac's battery as a word beside its level; a state's symbol in its
/// color beside a word. A timer counts down on the right, its ring on the left; the stopwatch counts
/// up beside its symbol; AirDrop shows its symbol and a ring filling as a file comes in; AirPlay shows
/// its symbol and the device's; music playing beside them goes in a bubble of its own (see
/// `IslandBubble`).
/// Each side sits at its wing's end, as far in from it as from the top and bottom, concentric with
/// the round end; any room to spare is beside the camera. With Reduce Motion on, nothing turns or
/// shakes.
struct SystemActivityView: View {
    let restingHeight: CGFloat
    let island: Bool
    let wing: CGFloat
    let alert: NotchAlert?
    /// Clock's timer or stopwatch, when it has the notch.
    let clock: ClockShown?
    /// Where the sound plays over AirPlay, when that has the notch.
    var route: AirPlayRoute? = nil
    /// A file coming in over AirDrop, when that has the notch.
    var airdrop: AirDropShown? = nil
    /// The timer's name, as VoiceOver says it.
    var timerName = "Timer"
    /// Which of a timer's buttons the pointer is on, in the closed notch, which leaves it closed.
    var hoveredButton: AlertButton? = nil
    /// Opens the notch to the timer or stopwatch, as VoiceOver's press does.
    var open: () -> Void = {}
    /// What shows, kept on once it's gone as it fades while the wings fold, so it rides in with their
    /// ends, as the Dynamic Island's activities do, rather than standing where it was. Kept from the
    /// start, so it never leaves as well as fading.
    @State private var leaving: NotchAlert?
    @State private var leavingClock: ClockShown?
    @State private var leavingRoute: AirPlayRoute?
    @State private var leavingAirDrop: AirDropShown?
    /// Counted, so what's kept goes only if nothing has come since.
    @State private var changes = (alert: 0, clock: 0, route: 0, airdrop: 0)

    var body: some View {
        let side = Self.side(restingHeight, island)
        let size = LiveActivityView.textSize(for: restingHeight)
        let shownAlert = alert ?? leaving
        let shownClock = shownAlert == nil ? clock ?? leavingClock : nil
        let shownAirDrop = shownAlert == nil && shownClock == nil ? airdrop ?? leavingAirDrop : nil
        let shownRoute = shownAlert == nil && shownClock == nil && shownAirDrop == nil ? route ?? leavingRoute : nil
        let (inset, outset) = Self.insets(for: shownAlert?.content, restingHeight: restingHeight, island: island)
        ZStack {
            if let alert = shownAlert, case .timerDone(let length, let name) = alert.content {
                TimerDoneView(length: length, name: name, restingHeight: restingHeight, wing: wing, hovered: hoveredButton)
                    .islandFade(self.alert != nil)
                    .id(alert.id)
                    .transition(IslandMotion.fade)
                    // Its buttons inside, which VoiceOver can press.
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(alert.spoken)
            } else if let alert = shownAlert, case .lowBattery(let percent) = alert.content {
                LowBatteryView(percent: percent, restingHeight: restingHeight, wing: wing, hovered: hoveredButton == .lowPower)
                    .islandFade(self.alert != nil)
                    .id(alert.id)
                    .transition(IslandMotion.fade)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(alert.spoken)
            } else if let alert = shownAlert, case .device(let symbol, let model, let pictures, let battery) = alert.content {
                device(symbol: symbol, model: model, pictures: pictures, battery: battery, size: size, leaving: self.alert == nil)
                    .islandFade(self.alert != nil)
                    .id(alert.id)
                    .transition(IslandMotion.fade)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(alert.spoken)
            } else if let alert = shownAlert {
                // Each side kept to its own end, so it rides in and out with it, and from the end
                // within it.
                ZStack {
                    leading(alert.content, side: side, size: size)
                        .frame(width: max(wing - inset - LiveActivityView.cameraGap, side), alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    trailing(alert.content, side: side, size: size)
                        .frame(width: max(wing - outset - LiveActivityView.cameraGap, side), alignment: .trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(.leading, inset)
                .padding(.trailing, outset)
                .islandFade(self.alert != nil)
                .id(alert.id)
                .transition(IslandMotion.fade)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(alert.spoken)
            } else if let shown = shownClock {
                // As the iPhone's Timer beside the camera: a ring emptying as the time runs out on the
                // left, the minutes left on the right; the stopwatch's symbol, and its time.
                ZStack {
                    Group {
                        switch shown {
                        case .timer(let timer): TimerRing(state: timer, height: restingHeight)
                        case .stopwatch(let watch): StopwatchMark(watch: watch, height: restingHeight)
                        }
                    }
                    // From its end, as far as from the top and bottom.
                    .padding(.leading, Self.ringEdge(restingHeight))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    TimelineView(.periodic(from: .now, by: shown.countsDown ? 0.5 : 1)) { context in
                        let reading = Self.reading(shown, at: context.date)
                        HStack(spacing: Self.pauseGap) {
                            // Paused or stopped, it says so with a symbol before the time, which waits.
                            if !shown.isRunning {
                                Image(systemName: "pause.fill")
                                    .font(.system(size: size - 1, weight: .semibold))
                                    .frame(width: Self.pauseWidth(size))
                            }
                            switch shown {
                            case .timer:
                                Text(reading)
                                    .font(.system(size: size, weight: .semibold).monospacedDigit())
                                    // The digits roll down as they change, as the Timer's own do.
                                    .contentTransition(.numericText(countsDown: true))
                                    .animation(.snappy, value: reading)
                            case .stopwatch(let watch):
                                StopwatchReading(watch: watch, size: size)
                            }
                        }
                        .foregroundStyle(.orange)
                        .fixedSize()
                        // In words, rather than the pause symbol's name and the digits.
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Self.spoken(shown, name: timerName, at: context.date))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction(.default, open)
                    }
                    .padding(.trailing, LiveActivityView.textEdge(restingHeight: restingHeight))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .islandFade(self.clock != nil)
                .transition(IslandMotion.fade)
                .accessibilityElement(children: .combine)
            } else if let shownAirDrop {
                AirDropMark(shown: shownAirDrop, restingHeight: restingHeight, island: island)
                    .islandFade(airdrop != nil)
                    .transition(IslandMotion.fade)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction(.default, open)
            } else if let shownRoute {
                AirPlayMark(route: shownRoute, restingHeight: restingHeight, island: island)
                    .islandFade(route != nil)
                    .transition(IslandMotion.fade)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction(.default, open)
            }
        }
        .frame(maxHeight: .infinity)
        .onChange(of: alert, initial: true) { _, new in
            changes.alert += 1
            if let new { leaving = new; return }
            let change = changes.alert
            Task { @MainActor in
                try? await Task.sleep(for: Self.folding)
                if changes.alert == change { leaving = nil }
            }
        }
        .onChange(of: clock, initial: true) { _, new in
            changes.clock += 1
            if let new { leavingClock = new; return }
            let change = changes.clock
            Task { @MainActor in
                try? await Task.sleep(for: Self.folding)
                if changes.clock == change { leavingClock = nil }
            }
        }
        .onChange(of: airdrop, initial: true) { _, new in
            changes.airdrop += 1
            if let new { leavingAirDrop = new; return }
            let change = changes.airdrop
            Task { @MainActor in
                try? await Task.sleep(for: Self.folding)
                if changes.airdrop == change { leavingAirDrop = nil }
            }
        }
        .onChange(of: route, initial: true) { _, new in
            changes.route += 1
            if let new { leavingRoute = new; return }
            let change = changes.route
            Task { @MainActor in
                try? await Task.sleep(for: Self.folding)
                if changes.route == change { leavingRoute = nil }
            }
        }
    }

    /// The time beside the camera: the timer's left, condensed as the iPhone's; the stopwatch's, to
    /// the second.
    static func reading(_ shown: ClockShown, at date: Date = .now) -> String {
        switch shown {
        case .timer(let timer): NotchTimer.condensed(timer.left(at: date))
        case .stopwatch(let watch): Stopwatch.format(watch.elapsed(at: date))
        }
    }

    static func spoken(_ shown: ClockShown, name: String, at date: Date = .now) -> String {
        switch shown {
        case .timer(let timer): NotchTimer.spoken(timer, name: name, at: date)
        case .stopwatch(let watch): Stopwatch.spoken(watch, at: date)
        }
    }

    /// Long enough for what's leaving to have faded as the wings fold.
    static let folding = Duration.milliseconds(300)

    /// The pause symbol before a paused timer's time, and the space between them.
    static func pauseWidth(_ size: CGFloat) -> CGFloat { (size * 0.8).rounded() }
    static let pauseGap: CGFloat = 4

    /// A device arriving, sized as the Dynamic Island shows AirPods, by the notch's height: the device
    /// a little under half of it tall, its battery's ring a little over half of it across. Each is at
    /// its end, as far in from it as from the top and bottom: the device as near as it comes as it
    /// turns.
    private func device(symbol: String, model: Headphones?, pictures: [String], battery: Int?, size: CGFloat, leaving: Bool) -> some View {
        let layout = DeviceLayout(height: restingHeight)
        let axis = Self.deviceAxis(model: model, pictures: pictures, layout: layout)
        let reach = Self.deviceReach(model: model, pictures: pictures, layout: layout)
        return ZStack {
            Group {
                if let model, let turn = DeviceTurn.cached(model) {
                    TurningDevice(turn: turn, height: layout.picture)
                } else if let images = DevicePictures.images(pictures) {
                    TurningPictures(images: images, height: layout.picture)
                } else {
                    TurningSymbol(symbol: symbol, side: layout.picture)
                }
            }
            // Its middle as far in from the end as it reaches, turning.
            .padding(.leading, layout.edge + max(reach - axis, 0))
            .frame(maxWidth: .infinity, alignment: .leading)
            // Its battery as a ring alone, as AirPods' is: a device that doesn't tell it isn't
            // announced (see `DeviceWatch`).
            if let battery {
                BatteryRing(percent: battery, diameter: layout.ring)
                    .modifier(RingArrival(leaving: leaving))
                    .padding(.trailing, layout.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    @ViewBuilder private func leading(_ content: NotchAlert.Content, side: CGFloat, size: CGFloat) -> some View {
        switch content {
        // Laid out on its own (see `device`).
        case .device:
            EmptyView()
        case .battery(let title, _):
            Text(title)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
        case .status(let symbol, let tint, _):
            ArrivingSymbol(symbol: symbol, color: tint, size: size + 2, side: side)
        // Laid out on their own (see `TimerDoneView` and `LowBatteryView`).
        case .timerDone, .lowBattery:
            EmptyView()
        }
    }

    @ViewBuilder private func trailing(_ content: NotchAlert.Content, side: CGFloat, size: CGFloat) -> some View {
        switch content {
        case .device:
            EmptyView()
        case .battery(_, let level):
            HStack(spacing: restingHeight * BatteryGlyph.gap) {
                Text("\(level.percent)%")
                    .font(.system(size: size, weight: .semibold).monospacedDigit())
                    .foregroundStyle(level.color)
                BatteryGlyph(level: level, color: level.color, height: restingHeight * BatteryGlyph.height)
            }
        case .status(_, _, let text):
            MarqueeText(text: text, font: .system(size: size, weight: .semibold), active: true, alignment: .trailing)
                .foregroundStyle(.white)
        case .timerDone, .lowBattery:
            EmptyView()
        }
    }

    /// In from each end, as far as from the top and bottom: words by their line, a battery's level
    /// too, which its battery is no taller than; a symbol by its square, as the cover is.
    static func insets(for content: NotchAlert.Content?, restingHeight h: CGFloat, island: Bool) -> (CGFloat, CGFloat) {
        let edge = LiveActivityView.edgeInset(island: island, restingHeight: h)
        let words = LiveActivityView.textEdge(restingHeight: h)
        switch content {
        case .battery: return (words, words)
        case .status: return (edge, words)
        default: return (edge, edge)
        }
    }

    /// How far in from its end the timer's ring or the stopwatch's symbol sits: as far as from the
    /// top and bottom, concentric with the end.
    static func ringEdge(_ h: CGFloat) -> CGFloat { LiveActivityView.concentric(h * TimerLayout.ring, in: h) }

    /// A symbol's square, as the cover's beside the camera.
    static func side(_ restingHeight: CGFloat, _ island: Bool) -> CGFloat {
        restingHeight - LiveActivityView.inset(island: island) * 2
    }

    /// How wide each wing must be for an announcement, up to a limit, so it covers little of the menu
    /// bar beside the notch, beyond which a long name scrolls. A device's, with only symbols, is a little
    /// wider than at rest, so it's seen to arrive. The notch stays centered, so both wings take the
    /// wider one.
    @MainActor
    static func wing(for alert: NotchAlert, restingHeight: CGFloat, island: Bool) -> CGFloat {
        let size = LiveActivityView.textSize(for: restingHeight)
        let side = side(restingHeight, island)
        let gap = LiveActivityView.cameraGap
        // A device's wings as wide as it turns, against the camera, with none of it going under the
        // camera; or as its ring or its word needs.
        if case .device(_, let model, let pictures, let battery) = alert.content {
            let layout = DeviceLayout(height: restingHeight)
            let axis = deviceAxis(model: model, pictures: pictures, layout: layout)
            let reach = deviceReach(model: model, pictures: pictures, layout: layout)
            let device = layout.edge + max(axis, reach) + reach + gap
            let end = battery == nil ? 0 : layout.ring + layout.trailing
            return min(max(device, gap + end), maxWing)
        }
        // As tall as the Alarm, as wide as its words or its buttons.
        if case .lowBattery(let percent) = alert.content { return LowBatteryLayout.wing(percent: percent, restingHeight: restingHeight) }
        if case .timerDone(let length, let name) = alert.content { return TimerDoneView.wing(length: length, name: name, restingHeight: restingHeight) }
        let (inset, outset) = insets(for: alert.content, restingHeight: restingHeight, island: island)
        let (left, right): (CGFloat, CGFloat) =
            switch alert.content {
            case .device, .timerDone, .lowBattery:
                (0, 0)
            case .battery(let title, let level):
                (
                    inset + width(title, size, .semibold) + gap,
                    gap + width("\(level.percent)%", size, .semibold) + restingHeight * BatteryGlyph.gap
                        + BatteryGlyph.width(height: restingHeight * BatteryGlyph.height) + outset
                )
            case .status(_, _, let text):
                (inset + side + gap, gap + width(text, size, .semibold) + outset)
            }
        return min(max(left, right), maxWing)
    }

    static let maxWing: CGFloat = 120

    /// A device's width face on.
    @MainActor
    static func deviceWidth(model: Headphones?, pictures: [String], layout: DeviceLayout) -> CGFloat {
        model.flatMap(DeviceTurn.cached).map { TurningDevice.width($0, height: layout.picture) }
            ?? DevicePictures.images(pictures).map { TurningPictures.width($0, height: layout.picture) } ?? layout.picture
    }

    /// The furthest a device reaches from the middle it turns about, either side, all the way round.
    @MainActor
    static func deviceReach(model: Headphones?, pictures: [String], layout: DeviceLayout) -> CGFloat {
        model.flatMap(DeviceTurn.cached).map { TurningDevice.reach($0, height: layout.picture) }
            ?? deviceWidth(model: model, pictures: pictures, layout: layout) / 2
    }

    /// From a device's left face on to the middle it turns about.
    @MainActor
    static func deviceAxis(model: Headphones?, pictures: [String], layout: DeviceLayout) -> CGFloat {
        model.flatMap(DeviceTurn.cached).map { TurningDevice.axis($0, height: layout.picture) }
            ?? deviceWidth(model: model, pictures: pictures, layout: layout) / 2
    }

    /// As wide as the ring and the time need, each from its end, the time as it reads now, its
    /// digits all as wide as each other; paused, with the pause symbol too. The notch refits as the
    /// time gains or loses a digit (see `widthChange(after:)`).
    static func wing(for clock: ClockShown, restingHeight h: CGFloat, island: Bool, at date: Date = .now) -> CGFloat {
        let size = LiveActivityView.textSize(for: h)
        let gap = LiveActivityView.cameraGap
        let time: CGFloat
        switch clock {
        case .timer:
            // As wide as the time is, with nothing to spare: it never scrolls.
            let font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .semibold)
            time = ceil((shape(reading(clock, at: date)) as NSString).size(withAttributes: [.font: font]).width)
        case .stopwatch(let watch):
            // Its hundredths small after it.
            time = StopwatchReading.width(watch.elapsed(at: date), size: size)
        }
        let paused = clock.isRunning ? 0 : pauseWidth(size) + pauseGap
        let right = gap + paused + time + LiveActivityView.textEdge(restingHeight: h)
        let left = ringEdge(h) + h * TimerLayout.ring + gap
        return max(right, left)
    }

    /// A reading with every digit as 0: what its width depends on.
    static func shape(_ reading: String) -> String {
        reading.replacingOccurrences(of: "[0-9]", with: "0", options: .regularExpression)
    }

    /// When what shows beside the camera next gains or loses a digit, opened or closed, so the notch
    /// refits to it: a timer from hours to minutes, and from minutes to seconds; the stopwatch from
    /// minutes to hours. Within a day; none while paused or stopped.
    static func widthChange(after date: Date, of clock: ClockShown) -> Date? {
        guard clock.isRunning else { return nil }
        func shapes(_ at: Date) -> [String] { [shape(reading(clock, at: at)), shape(clock.reading(at: at))] }
        let now = shapes(date)
        // Second by second, to the next change, for up to an hour; then minute by minute.
        var step = 1.0, at = date
        for _ in 0..<(3600 + 23 * 60) {
            at += step
            if shapes(at) != now { return at }
            if at.timeIntervalSince(date) >= 3600 { step = 60 }
        }
        return nil
    }

    private static func width(_ text: String, _ size: CGFloat, _ weight: NSFont.Weight) -> CGFloat {
        // A point to spare, so rounding never sets text that fits scrolling.
        ceil((text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight)]).width) + 2
    }
}

/// How large a device arriving shows, by the notch's height, measured frame by frame from the
/// iPhone's AirPods in the Dynamic Island, which stands no taller for them: the device 46.4% of the
/// height tall; the ring 54% of it across. Each as far in from its end as from the top and bottom.
struct DeviceLayout {
    let height: CGFloat
    var picture: CGFloat { height * 0.464 }
    var ring: CGFloat { height * 0.54 }
    /// From the left end to the device, as it reaches furthest turning.
    var edge: CGFloat { LiveActivityView.concentric(picture, in: height) }
    var trailing: CGFloat { LiveActivityView.concentric(ring, in: height) }
}

/// AirPods or Beats arriving, in 3D, facing you as they arrive and turning steadily about their
/// middle, as on a turntable, the whole time they show, as fast as the iPhone turns AirPods. With
/// Reduce Motion on, they stay face on.
struct TurningDevice: View {
    let turn: DeviceTurn
    /// The pair's height, face on.
    let height: CGFloat
    @State private var start = Date.now
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A turn every five and a half seconds, measured frame by frame from the iPhone.
    static let degreesPerSecond = 66.1

    /// The pair's width, face on.
    static func width(_ turn: DeviceTurn, height: CGFloat) -> CGFloat { turn.rest.width * height / turn.rest.height }

    /// From the pair's left, face on, to the middle it turns about.
    static func axis(_ turn: DeviceTurn, height: CGFloat) -> CGFloat { (turn.canvas.width / 2 - turn.rest.minX) * height / turn.rest.height }

    /// The furthest it reaches from the middle it turns about, either side, all the way round.
    static func reach(_ turn: DeviceTurn, height: CGFloat) -> CGFloat { turn.reach * height / turn.rest.height }

    /// How far round the pair has turned since it arrived.
    static func degrees(after seconds: TimeInterval) -> Double { max(seconds, 0) * degreesPerSecond }

    var body: some View {
        let scale = height / turn.rest.height
        TimelineView(.animation(paused: reduceMotion)) { context in
            Image(decorative: turn.frame(at: reduceMotion ? 0 : Self.degrees(after: context.date.timeIntervalSince(start))), scale: 1)
                .resizable()
                .interpolation(.high)
                .frame(width: turn.canvas.width * scale, height: turn.canvas.height * scale)
        }
        // Laid out face on; turning, it reaches past that, where nothing else is.
        .offset(x: (turn.canvas.width / 2 - turn.rest.midX) * scale, y: (turn.canvas.height / 2 - turn.rest.midY) * scale)
        .frame(width: Self.width(turn, height: height), height: height)
        .onAppear { start = .now }
    }
}

/// How the Dynamic Island's activities come and go, measured frame by frame from it, for everything
/// the closed notch shows: its wings open with a touch of bounce and fold without, what they show
/// riding in and out with their ends; it fades in out of a blur as they open, sharpening as it comes,
/// and fades away into one at once as they fold. With Reduce Motion on, the wings open without their
/// bounce, as they fold, and nothing blurs.
enum IslandMotion {
    static var open: Animation { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? fold : opening }
    static let fold = Animation.spring(response: 0.315, dampingFraction: 1.18)
    private static let opening = Animation.spring(response: 0.55, dampingFraction: 0.8)
    /// What comes and goes with the wings, as `islandFade` shows and hides it.
    static let fade = AnyTransition(IslandFade())
}

private struct IslandFade: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content.islandFade(phase.isIdentity)
    }
}

extension View {
    /// Shown or hidden in place, coming and going as the Dynamic Island's activities do, whatever
    /// else changes with it: everything in the notch, closed or open. SwiftUI's own blur and opacity,
    /// each on its own curve: the notch draws a fade of one's own only once it's done.
    func islandFade(_ shown: Bool) -> some View {
        modifier(IslandFadeModifier(shown: shown))
    }
}

private struct IslandFadeModifier: ViewModifier {
    let shown: Bool
    @Environment(\.closedNotch) private var closed
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        // Hidden, blurred by the closed notch's height, as the Dynamic Island's activities are by its
        // own; with Reduce Motion on, only faded.
        content
            .animation(.init(IslandCurve(shown ? .blurIn : .blurOut))) {
                $0.blur(radius: shown || reduceMotion ? 0 : closed.height * IslandCurve.blur)
            }
            .animation(.init(IslandCurve(shown ? .opacityIn : .opacityOut))) {
                $0.opacity(shown ? 1 : 0)
            }
    }
}

/// The fade's curves, measured frame by frame from the iPhone's AirPods arriving and leaving, with
/// what its island's resting shape hides taken out, since the notch's own hides what rides under it
/// just as much: from when the wings start to move, how far along it is.
private struct IslandCurve: CustomAnimation {
    enum Part: Hashable { case blurIn, opacityIn, blurOut, opacityOut, ringIn, ringOut }
    /// Hidden, blurred by this much of the height.
    static let blur: CGFloat = 0.16
    let part: Part

    init(_ part: Part) { self.part = part }

    /// Seconds, and how far along.
    private static let curves: [Part: [(Double, Double)]] = [
        // Half there while it's still all but under the resting shape, then the rest as it rides out.
        .opacityIn: [
            (0.050, 0), (0.074, 0.15), (0.090, 0.30), (0.107, 0.42), (0.124, 0.48), (0.140, 0.52), (0.157, 0.56),
            (0.174, 0.60), (0.190, 0.64), (0.207, 0.68), (0.224, 0.70), (0.240, 0.72), (0.257, 0.745), (0.274, 0.78),
            (0.290, 0.81), (0.307, 0.85), (0.324, 0.88), (0.340, 0.91), (0.357, 0.94), (0.374, 0.96), (0.390, 0.97),
            (0.407, 0.99), (0.424, 1),
        ],
        .blurIn: [
            (0.134, 0), (0.167, 0.125), (0.184, 0.25), (0.200, 0.34), (0.217, 0.46), (0.234, 0.59), (0.251, 0.69),
            (0.267, 0.76), (0.284, 0.825), (0.300, 0.875), (0.317, 0.925), (0.350, 0.96), (0.434, 1),
        ],
        .opacityOut: [
            (0, 0), (0.013, 0.09), (0.030, 0.21), (0.046, 0.35), (0.063, 0.60), (0.080, 0.73), (0.096, 0.86),
            (0.113, 0.94), (0.130, 0.97), (0.146, 0.99), (0.163, 1),
        ],
        // Blurring on past where it rests hidden while it's still seen; it's gone by the time it's back.
        .blurOut: [
            (0, 0), (0.013, 0.10), (0.030, 0.28), (0.046, 0.55), (0.063, 0.88), (0.080, 1.05), (0.096, 1.12), (0.113, 1.15),
            (0.163, 1.15),
        ],
        // Of what's arrived, how much of a battery's ring shows: it comes in a little after, and goes
        // a little ahead.
        .ringIn: [
            (0.124, 0), (0.150, 0.25), (0.167, 0.42), (0.184, 0.55), (0.200, 0.65), (0.217, 0.72), (0.234, 0.78),
            (0.251, 0.83), (0.267, 0.87), (0.284, 0.90), (0.301, 0.93), (0.317, 0.95), (0.334, 0.98), (0.351, 0.99),
            (0.367, 1),
        ],
        .ringOut: [(0, 0), (0.013, 0.07), (0.030, 0.16), (0.046, 0.24), (0.063, 0.31), (0.080, 0.36), (0.096, 0.44), (0.113, 0.5), (0.163, 1)],
    ]

    func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
        let curve = Self.curves[part]!
        guard let last = curve.last, time < last.0 else { return nil }
        var done = 0.0
        if let after = curve.firstIndex(where: { $0.0 > time }) {
            if after > 0 {
                let (t0, v0) = curve[after - 1], (t1, v1) = curve[after]
                done = v0 + (v1 - v0) * (time - t0) / (t1 - t0)
            }
        }
        return value.scaled(by: done)
    }
}

/// A battery's ring arriving a moment after its device, and leaving a little ahead of it, as the
/// iPhone's does beside AirPods.
private struct RingArrival: ViewModifier {
    let leaving: Bool
    @State private var arrived = false

    func body(content: Content) -> some View {
        let shown = arrived && !leaving
        content
            .animation(.init(IslandCurve(shown ? .ringIn : .ringOut))) { $0.opacity(shown ? 1 : 0) }
            .onAppear { arrived = true }
    }
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
            .font(.system(size: side * 0.8, weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.white)
            .frame(width: side, height: side)
            .rotation3DEffect(.degrees(reduceMotion ? 0 : turn), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            .scaleEffect(shown || reduceMotion ? 1 : 0.6)
            .opacity(shown ? 1 : 0)
            .onAppear {
                withAnimation(.easeOut(duration: 0.25).delay(0.15)) { shown = true }
                withAnimation(.spring(response: 1.1, dampingFraction: 0.72).delay(0.15)) { turn = 0 }
            }
    }
}

/// Headphones arriving as macOS pictures them, AirPods Max, or AirPods when their 3D model can't
/// be drawn: turning in together as one, then settling face on.
private struct TurningPictures: View {
    let images: [NSImage]
    let height: CGFloat
    @State private var arrived = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The earbuds overlap a little, as they're pictured side by side.
    static func overlap(_ height: CGFloat) -> CGFloat { height * 0.1 }

    static func width(_ images: [NSImage], height: CGFloat) -> CGFloat {
        let widths = images.map { $0.size.height > 0 ? $0.size.width / $0.size.height * height : height }
        return widths.reduce(0, +) - overlap(height) * CGFloat(max(images.count - 1, 0))
    }

    var body: some View {
        HStack(spacing: -Self.overlap(height)) {
            ForEach(images.indices, id: \.self) { index in
                Image(nsImage: images[index])
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(height: height)
            }
        }
        .rotation3DEffect(.degrees(arrived || reduceMotion ? 0 : -200), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
        .scaleEffect(arrived || reduceMotion ? 1 : 0.6)
        .opacity(arrived ? 1 : 0)
        .animation(.spring(response: 1.1, dampingFraction: 0.72).delay(0.15), value: arrived)
        .onAppear { arrived = true }
    }
}

/// A battery as a ring, as AirPods' is in the Dynamic Island: green, or red at 20% and below,
/// already at its level as it fades in.
struct BatteryRing: View {
    let percent: Int
    let diameter: CGFloat
    /// The iPhone's, as it shows AirPods' battery.
    static let green = Color(red: 68 / 255, green: 231 / 255, blue: 114 / 255)

    static func color(for percent: Int) -> Color { percent <= 20 ? .red : green }

    var body: some View {
        // As thick as the iPhone's: an eighth of the ring across.
        let line = max(diameter * 0.12, 2)
        let color = Self.color(for: percent)
        ZStack {
            Circle().stroke(color.opacity(0.3), lineWidth: line)
            Circle()
                .trim(from: 0, to: CGFloat(percent) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(line / 2)
        .frame(width: diameter, height: diameter)
        .accessibilityLabel("\(percent) percent")
    }
}

/// A state's symbol in its color, bouncing in as the iPhone's do; a timer that's done, shaking until
/// it's stopped. With Reduce Motion on, it does neither.
struct ArrivingSymbol: View {
    let symbol: String
    let color: Color
    let size: CGFloat
    let side: CGFloat
    var shakes = false
    @State private var arrived = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: side, height: side)
            .symbolEffect(.bounce, value: arrived && !reduceMotion)
            .symbolEffect(.wiggle, options: .repeat(.continuous), isActive: shakes && !reduceMotion)
            .onAppear { arrived = true }
    }
}

extension NotchTimer.State {
    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}

/// A battery, as the iPhone draws one beside its level in the Dynamic Island: its body filled faintly
/// in its color, as far as it's charged brightly, its cap apart, measured from it.
struct BatteryGlyph: View {
    let level: BatteryLevel
    let color: Color
    let height: CGFloat

    /// Its height, and the space before it, by the notch's.
    static let height: CGFloat = 0.473
    static let gap: CGFloat = 0.173
    /// The body, the space before the cap and the cap, by its own height.
    private static let main: CGFloat = 1.88
    private static let space: CGFloat = 0.074
    private static let cap: CGFloat = 0.127

    static func width(height: CGFloat) -> CGFloat { height * (main + space + cap) }

    var body: some View {
        let width = height * Self.main, radius = height * 0.3
        HStack(spacing: height * Self.space) {
            ZStack(alignment: .leading) {
                Rectangle().fill(color.opacity(0.45))
                Rectangle()
                    .fill(color)
                    .frame(width: max(width * CGFloat(level.percent) / 100, height * 0.3))
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            RoundedRectangle(cornerRadius: height * Self.cap / 2, style: .continuous)
                .fill(color.opacity(0.45))
                .frame(width: height * Self.cap, height: height * 0.4)
        }
        .frame(width: Self.width(height: height), height: height)
        .accessibilityLabel("\(level.percent) percent\(level.charging ? ", charging" : "")")
    }
}
