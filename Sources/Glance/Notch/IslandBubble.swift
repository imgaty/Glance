//
//  IslandBubble.swift
//  Glance
//
//  Created by Gaty on 23/10/2026.
//

import AppKit
import SwiftUI

/// An activity in a bubble of its own beside the notch, as the Dynamic Island shows one beside
/// another: the second off the notch's right end, the third off its left. Measured from the iPhone,
/// by the island's height: a circle as wide as the island is tall, level with it, 0.175 of that off
/// its end, a timer's ring, the stopwatch's symbol, AirDrop's ring or AirPlay's symbol in it as beside
/// the camera. It buds off the
/// notch's end as it comes, joined to it for a moment as two drops are, and runs back into it as it
/// goes, or as the notch opens; with Reduce Motion on, it fades in and out where it rests. VoiceOver
/// names it, and opens it as a click does.
struct IslandBubble: View {
    let side: NotchModel.Side
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
    /// How far the notch's top corners flare out past its body.
    let flare: CGFloat
    /// The notch is open: nothing of the bubble shows over its glass.
    let hidden: Bool
    let hovered: Bool
    let pressed: Bool
    /// A full-screen app covers the display: a thin ring in its activity's color circles it, as it
    /// rings the notch, just clear of its edge and fading toward the top.
    let fullScreen: Bool
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

    var body: some View {
        let h = restingHeight
        // With Reduce Motion on, it stays where it rests, and only fades.
        let out: CGFloat = shown || reduceMotion ? 1 : 0
        let line = h * KeyLine.width
        let trailing = side == .trailing
        // Away from the notch: right off its right end, left off its left.
        let away: CGFloat = trailing ? 1 : -1
        ZStack(alignment: trailing ? .leading : .trailing) {
            if !reduceMotion {
                BubbleNeck(out: out).fill(.black)
                    .scaleEffect(x: away)
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
                .islandFade(shown)
            }
            .frame(width: h, height: h)
            // Ringed just clear of it, fading toward the top, as the notch is.
            .overlay {
                let tint = kept == nil && (keptRoute != nil || keptAirDrop != nil) ? Color.blue : .orange
                KeyLine.ring(around: CGRect(x: 0, y: 0, width: h, height: h), width: line)
                    .fill(KeyLine.color(tint, height: h, in: h))
                    .frame(width: h, height: h)
                    .animation(fullScreen && shown ? .easeOut(duration: 0.3) : .easeOut(duration: 0.12)) { $0.opacity(fullScreen && shown ? 1 : 0) }
            }
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
            .offset(x: away * h * (1 + Self.gap) * out)
        }
        // From inside the notch's end, where it comes out of, to where it rests.
        .frame(width: h * (2 + Self.gap), height: h, alignment: trailing ? .leading : .trailing)
        .offset(x: away * (h * (1 + Self.gap) - flare))
        // Gone at once as the notch opens; back once it has all but closed, as its black is.
        .animation(hidden ? .easeOut(duration: 0.1) : .easeOut(duration: 0.1).delay(0.2)) { $0.opacity(hidden ? 0 : 1) }
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

/// The bridge between the notch's end and the bubble while they're near, as between two drops
/// running together or apart: between two circles as tall as the notch, one in the notch's end and
/// the bubble, curves that pinch in as they part, until it breaks a little before the bubble rests.
/// Drawn as metaballs are, with the curves drawn in to the line between the circles' middles as
/// they part, so it thins away rather than snapping. Drawn for the right end; mirrored for the left.
struct BubbleNeck: Shape {
    /// 0 with the bubble in the notch's end, 1 where it rests.
    var out: CGFloat

    var animatableData: CGFloat {
        get { out }
        set { out = newValue }
    }

    /// How far past touching the bridge breaks, by the circles' radius: before the bubble rests,
    /// 0.35 past.
    static let reach: CGFloat = 0.25

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
