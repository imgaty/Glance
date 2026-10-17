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
            if let alert, case .device(let symbol, let model, let pictures, let battery) = alert.content {
                device(symbol: symbol, model: model, pictures: pictures, battery: battery, size: size)
                    .id(alert.id)
                    .transition(Self.announce)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(alert.spoken)
            } else if let alert {
                HStack(spacing: 0) {
                    leading(alert.content, side: side, size: size)
                        .frame(width: lane, alignment: .leading)
                    Spacer(minLength: 0)
                    trailing(alert.content, side: side, size: size)
                        .frame(width: lane, alignment: .trailing)
                }
                .padding(.horizontal, edge)
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
                .padding(.horizontal, edge)
                .transition(Self.announce)
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxHeight: .infinity)
    }

    /// A device arriving, laid out as the Dynamic Island lays out AirPods, by the notch's height: the
    /// device a little under half of it tall, in from the end; its battery's ring a little over half
    /// of it across, its circle concentric with the notch's rounded end.
    private func device(symbol: String, model: Headphones?, pictures: [String], battery: Int?, size: CGFloat) -> some View {
        let layout = DeviceLayout(height: restingHeight)
        return HStack(spacing: 0) {
            Group {
                if let model, let turn = DeviceTurn.cached(model) {
                    TurningDevice(turn: turn, height: layout.picture)
                } else if let images = DevicePictures.images(pictures) {
                    TurningPictures(images: images, height: layout.picture)
                } else {
                    TurningSymbol(symbol: symbol, side: layout.picture)
                }
            }
            .padding(.leading, layout.leading)
            Spacer(minLength: 0)
            Group {
                if let battery {
                    BatteryRing(percent: battery, diameter: layout.ring)
                        .padding(.trailing, layout.trailing)
                } else {
                    Text("Connected")
                        .font(.system(size: size, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                        .padding(.trailing, layout.leading)
                }
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
        case .timerDone:
            ArrivingSymbol(symbol: "timer", color: .orange, size: size + 2, side: side, shakes: true)
        }
    }

    @ViewBuilder private func trailing(_ content: NotchAlert.Content, side: CGFloat, size: CGFloat) -> some View {
        switch content {
        case .device:
            EmptyView()
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
    @MainActor
    static func wing(for alert: NotchAlert, restingHeight: CGFloat, island: Bool) -> CGFloat {
        let edge = LiveActivityView.edgeInset(island: island, restingHeight: restingHeight)
        let size = LiveActivityView.textSize(for: restingHeight)
        let side = side(restingHeight, island)
        let gap = LiveActivityView.cameraGap
        let (left, right): (CGFloat, CGFloat) =
            switch alert.content {
            case .device(_, let model, let pictures, let battery):
                {
                    let layout = DeviceLayout(height: restingHeight)
                    let device =
                        model.flatMap(DeviceTurn.cached).map { TurningDevice.width($0, height: layout.picture) }
                        ?? DevicePictures.images(pictures).map { TurningPictures.width($0, height: layout.picture) } ?? layout.picture
                    let end = battery == nil ? width("Connected", size, .semibold) + layout.leading : layout.ring + layout.trailing
                    return (layout.leading + device + gap, gap + end)
                }()
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

    /// As the Dynamic Island brings an activity in, measured from it: as the wings open, it fades in
    /// from a heavy blur, sharpening last; as they start to fold, it blurs away at once,
    /// riding in with their ends under the notch, which stays sharp over it.
    private static let announce = AnyTransition.asymmetric(
        insertion: .modifier(active: BlurFade(shown: false, arriving: true), identity: BlurFade(shown: true, arriving: true))
            .animation(.linear(duration: 0.22).delay(0.1)),
        removal: .modifier(active: BlurFade(shown: false, arriving: false), identity: BlurFade(shown: true, arriving: false))
            .animation(.linear(duration: 0.12)))
}

/// Where a device arriving sits, by the notch's height, measured from the iPhone's AirPods in the
/// Dynamic Island, which stands no taller for them: the device 46% of the height tall, 40% of it in
/// from the end; the ring 54% of it across, as far from the end as from the top and bottom.
struct DeviceLayout {
    let height: CGFloat
    var picture: CGFloat { (height * 0.46).rounded() }
    var ring: CGFloat { (height * 0.54).rounded() }
    var leading: CGFloat { (height * 0.4).rounded() }
    var trailing: CGFloat { ((height - ring) / 2).rounded() }
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

    /// About a turn every six seconds, measured from the iPhone.
    static let degreesPerSecond = 62.0

    /// The pair's width, face on.
    static func width(_ turn: DeviceTurn, height: CGFloat) -> CGFloat { turn.rest.width * height / turn.rest.height }

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

/// Coming and going through a blur, as the Dynamic Island's activities do, measured from it, over a
/// steady `progress`. Arriving, it comes in solid quickly out of a heavy blur that clears more
/// slowly, so it sharpens last. Leaving, it blurs at once and fades.
struct BlurFade: ViewModifier, Animatable {
    var progress: Double
    let arriving: Bool

    init(shown: Bool, arriving: Bool = true) {
        progress = shown ? 1 : 0
        self.arriving = arriving
    }

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let p = min(max(progress, 0), 1)
        content
            .blur(radius: arriving ? 8 * pow(1 - p, 2) : 9 * pow(1 - p, 0.7))
            .opacity(arriving ? 1 - pow(1 - p, 2.5) : p)
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
            .scaleEffect(shown ? 1 : 0.6)
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
        .scaleEffect(arrived ? 1 : 0.6)
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

    var body: some View {
        // As thick as the iPhone's: an eighth of the ring across.
        let line = max(diameter * 0.12, 2)
        let color: Color = percent <= 20 ? .red : .green
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
