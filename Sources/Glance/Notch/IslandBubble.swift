//
//  IslandBubble.swift
//  Glance
//
//  Created by Gaty on 23/10/2026.
//

import AppKit
import SwiftUI

/// The second activity, detached, as the Dynamic Island's minimal presentation shows one beside
/// another: only ever off the notch's trailing end, the first staying attached at its leading end.
/// By Apple's measures, for the island's height: a circle as wide as the island is tall, level with
/// it, 0.175 of that off its end, a timer's ring, the stopwatch's symbol, AirDrop's ring or AirPlay's
/// symbol in it as beside the camera. It leaves the notch's end as a drop of water does, stretching
/// on a neck that thins until it parts, past where it rests and back, and runs back into it as it
/// goes; as the notch opens it stays where it
/// rests, and the notch comes out over it. With Reduce Motion on, it fades in and out where it rests.
/// VoiceOver names it, and opens it as a click does.
struct IslandBubble: View {
    /// Out of the notch; in it, it's hidden in its end.
    let shown: Bool
    /// The timer or stopwatch it shows, and the timer's name, as VoiceOver says it.
    let clock: ClockShown?
    /// Or AirPlay, by its symbol alone, in its blue; or AirDrop, by its ring.
    var route: AirPlayRoute? = nil
    var airdrop: AirDropShown? = nil
    let name: String
    /// Opens it, as a click on it does.
    let open: () -> Void
    let restingHeight: CGFloat
    /// How far from the notch's middle its trailing end is, which the bubble sits off.
    let notchEnd: CGFloat
    /// The notch is open: nothing of the bubble shows over its glass.
    let hidden: Bool
    let hovered: Bool
    let pressed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// What it showed, kept on as it runs back into the notch, so it fades as it goes rather than
    /// vanishing.
    @State private var kept: ClockShown?
    @State private var keptRoute: AirPlayRoute?
    @State private var keptAirDrop: AirDropShown?
    /// Counted, so what's kept goes only if nothing has come since.
    @State private var changes = (clock: 0, route: 0, airdrop: 0)

    /// Off the notch's end, by its height.
    static let gap: CGFloat = 0.175

    /// Out with a little overshoot, as a drop that's let go; back in, straight.
    private var motion: Animation {
        shown ? .spring(response: 0.62, dampingFraction: 0.6) : .spring(response: 0.38, dampingFraction: 1)
    }

    var body: some View {
        let h = restingHeight
        // With Reduce Motion on, it stays where it rests, and only fades.
        let out: CGFloat = shown || reduceMotion ? 1 : 0
        ZStack(alignment: .leading) {
            if !reduceMotion {
                BubbleNeck(out: out).fill(.black)
                    .animation(motion, value: out)
            }
            ZStack {
                Circle().fill(.black)
                ZStack {
                    switch kept {
                    case .timer(let timer): TimerRing(state: timer, height: h)
                    case .stopwatch(let watch): StopwatchMark(watch: watch, height: h)
                    case nil:
                        if let keptAirDrop {
                            AirDropRing(fraction: keptAirDrop.fraction, diameter: h * AirDropLayout.ring, line: h * AirDropLayout.ringLine)
                        } else if keptRoute != nil {
                            Image(systemName: "airplay.audio")
                                .font(.system(size: h * 0.5, weight: .semibold))
                                .foregroundStyle(AirPlayLayout.tint)
                        }
                    }
                }
                .islandFade(shown && !hidden)
            }
            .frame(width: h, height: h)
            // What it shows, in words, and a click's opening.
            .overlay {
                if shown, !hidden, let clock {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Color.clear
                            .accessibilityElement()
                            .accessibilityLabel(SystemActivityView.spoken(clock, name: name, at: context.date))
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction(.default, open)
                    }
                } else if shown, !hidden, let airdrop {
                    Color.clear
                        .accessibilityElement()
                        .accessibilityLabel(ExpandedAirDropView.spoken(airdrop))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction(.default, open)
                } else if shown, !hidden, let route {
                    Color.clear
                        .accessibilityElement()
                        .accessibilityLabel("AirPlay, playing on \(route.name)")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction(.default, open)
                }
            }
            .scaleEffect(reduceMotion ? 1 : pressed ? 0.94 : hovered ? 1.06 : 1)
            .animation(.easeInOut(duration: 0.25)) { $0.opacity(reduceMotion && !shown ? 0 : 1) }
            .modifier(BubbleDrop(out: out, distance: h * (1 + Self.gap)))
            .animation(motion, value: out)
        }
        // From inside the notch's end, where it comes out of, to where it rests.
        .frame(width: h * (2 + Self.gap), height: h, alignment: .leading)
        .offset(x: notchEnd - h + h * (2 + Self.gap) / 2)
        // Solid until the opening notch has covered it, and back before the closing notch uncovers it,
        // as anything fading here would show as a pale circle beside the notch.
        .animation(hidden ? .linear(duration: 0.01).delay(0.2) : .linear(duration: 0.01)) { $0.opacity(hidden ? 0 : 1) }
        // With nothing to show or running back, it isn't there at all, to show past the notch's end.
        .animation(.linear(duration: 0.01)) { $0.opacity(shown || kept != nil || keptRoute != nil || keptAirDrop != nil ? 1 : 0) }
        .allowsHitTesting(false)
        .onChange(of: clock, initial: true) { _, new in
            changes.clock += 1
            if let new { return kept = new }
            let change = changes.clock
            Task { @MainActor in
                try? await Task.sleep(for: SystemActivityView.folding)
                if changes.clock == change { kept = nil }
            }
        }
        .onChange(of: airdrop, initial: true) { _, new in
            changes.airdrop += 1
            if let new { return keptAirDrop = new }
            let change = changes.airdrop
            Task { @MainActor in
                try? await Task.sleep(for: SystemActivityView.folding)
                if changes.airdrop == change { keptAirDrop = nil }
            }
        }
        .onChange(of: route, initial: true) { _, new in
            changes.route += 1
            if let new { return keptRoute = new }
            let change = changes.route
            Task { @MainActor in
                try? await Task.sleep(for: SystemActivityView.folding)
                if changes.route == change { keptRoute = nil }
            }
        }
    }
}

/// The bubble on its way, at each step of it: longest halfway out, as a drop is, and round where it
/// starts and where it rests.
private struct BubbleDrop: ViewModifier, Animatable {
    var out: CGFloat
    let distance: CGFloat

    /// How much longer than it's wide it gets, and how much of that it loses in height.
    private static let stretch: CGFloat = 0.14
    private static let thinning: CGFloat = 0.5

    var animatableData: CGFloat {
        get { out }
        set { out = newValue }
    }

    func body(content: Content) -> some View {
        let along = sin(min(max(out, 0), 1) * .pi) * Self.stretch
        content
            .scaleEffect(x: 1 + along, y: 1 - along * Self.thinning)
            .offset(x: distance * out)
    }
}

/// The bridge between the notch's end and the bubble while they're near, as between two drops
/// running together or apart: between two circles as tall as the notch, one in the notch's end and
/// the bubble, curves that pinch in as they part, until it breaks a little before the bubble rests.
/// Drawn as metaballs are, with the curves drawn in to the line between the circles' middles as
/// they part, so it thins away rather than snapping.
struct BubbleNeck: Shape {
    /// 0 with the bubble in the notch's end, 1 where it rests.
    var out: CGFloat

    var animatableData: CGFloat {
        get { out }
        set { out = newValue }
    }

    /// How far past touching the bridge breaks, by the circles' radius: just before the bubble rests,
    /// 0.35 past.
    static let reach: CGFloat = 0.32

    func path(in rect: CGRect) -> Path {
        let r = rect.height / 2
        let d = rect.height * (1 + IslandBubble.gap) * out
        let apart = d - 2 * r
        guard d > 1, apart < r * Self.reach else { return Path() }
        let spread = apart <= 0 ? 0.5 : 0.5 * (1 - apart / (r * Self.reach))
        // Overlapping, the curves start where the circles cross.
        let u = d < 2 * r ? acos(d / (2 * r)) : 0
        let a1 = u + (.pi / 2 - u) * spread
        let a3 = .pi - u - (.pi / 2 - u) * spread
        let a = CGPoint(x: r, y: r), b = CGPoint(x: r + d, y: r)
        func on(_ c: CGPoint, _ angle: CGFloat, _ length: CGFloat) -> CGPoint {
            CGPoint(x: c.x + cos(angle) * length, y: c.y + sin(angle) * length)
        }
        let p1 = on(a, a1, r), p2 = on(a, -a1, r), p3 = on(b, a3, r), p4 = on(b, -a3, r)
        let handle = r * min(spread * 2.4, hypot(p3.x - p1.x, p3.y - p1.y) / (2 * r)) * min(1, d / r)
        var path = Path()
        path.move(to: p1)
        path.addCurve(to: p3, control1: on(p1, a1 - .pi / 2, handle), control2: on(p3, a3 + .pi / 2, handle))
        path.addLine(to: p4)
        path.addCurve(to: p2, control1: on(p4, -a3 - .pi / 2, handle), control2: on(p2, -a1 + .pi / 2, handle))
        path.closeSubpath()
        return path
    }
}
