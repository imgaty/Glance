//
//  IslandBubble.swift
//  Glance
//
//  Created by Gaty on 23/10/2026.
//

import AppKit
import SwiftUI

/// A second activity in a bubble of its own beside the notch, as the Dynamic Island shows one
/// beside another: music while a timer has the notch, or the timer while a new song is announced
/// there. Measured from the iPhone, by the island's height: a circle as wide as the island is tall,
/// level with it, 0.175 of that off its right end, with an app's own picture 0.76 of it across. It
/// buds off the notch's end as it comes, joined to it for a moment as two drops are, and runs back
/// into it as it goes, or as the notch opens.
struct IslandBubble: View {
    @EnvironmentObject private var nowPlaying: NowPlaying
    @AppStorage(Preferences.musicAccentSource) private var accentSource = AccentSource.artwork
    /// What it shows; nil while it's in the notch.
    let bubble: NotchModel.Bubble?
    let timer: NotchTimer.State?
    let restingHeight: CGFloat
    /// How far the notch's top corners flare out past its body.
    let flare: CGFloat
    /// The notch is open: nothing of the bubble shows over its glass.
    let hidden: Bool
    let hovered: Bool
    let pressed: Bool
    /// A full-screen app covers the display: a thin line in its activity's color outlines it, as
    /// it outlines the notch.
    let fullScreen: Bool
    /// What it showed, kept on as it runs back into the notch, so it fades as it goes rather than
    /// vanishing, and the timer it showed.
    @State private var kept: NotchModel.Bubble?
    @State private var keptTimer: NotchTimer.State?
    /// Counted, so what's kept goes only if nothing has come since.
    @State private var changes = 0

    /// Off the notch's end, by its height.
    static let gap: CGFloat = 0.175
    /// An app's own picture in it, by its height.
    static let content: CGFloat = 0.76

    var body: some View {
        let h = restingHeight
        let out: CGFloat = bubble == nil ? 0 : 1
        let line = h * KeyLine.width
        ZStack(alignment: .leading) {
            BubbleNeck(out: out).fill(.black)
            ZStack {
                Circle().fill(.black)
                ZStack {
                    switch kept {
                    case .music: cover(side: h * Self.content)
                    case .timer: if let keptTimer { TimerRing(state: keptTimer, height: h) }
                    case nil: EmptyView()
                    }
                }
                .id(kept)
                .transition(IslandMotion.fade)
                .islandFade(bubble != nil)
            }
            .frame(width: h, height: h)
            // Outside it, as around the notch, without making it any larger.
            .overlay {
                Circle()
                    .strokeBorder((kept == .timer ? .orange : nowPlaying.accent(from: accentSource)).opacity(0.18), lineWidth: line)
                    .frame(width: h + line * 2, height: h + line * 2)
                    .animation(.easeOut(duration: 0.3)) { $0.opacity(fullScreen && bubble != nil ? 1 : 0) }
            }
            .scaleEffect(pressed ? 0.94 : hovered ? 1.06 : 1)
            .offset(x: h * (1 + Self.gap) * out)
        }
        // From inside the notch's right end, where it comes out of, to where it rests.
        .frame(width: h * (2 + Self.gap), height: h, alignment: .leading)
        .offset(x: h * (1 + Self.gap) - flare)
        // Gone at once as the notch opens; back once it has all but closed, as its black is.
        .animation(hidden ? .easeOut(duration: 0.1) : .easeOut(duration: 0.1).delay(0.2)) { $0.opacity(hidden ? 0 : 1) }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: bubble, initial: true) { _, new in
            changes += 1
            if let new { return kept = new }
            let change = changes
            Task { @MainActor in
                try? await Task.sleep(for: SystemActivityView.folding)
                if changes == change { kept = nil }
            }
        }
        .onChange(of: timer, initial: true) { _, new in
            if let new { keptTimer = new }
        }
    }

    /// The cover, round, as the iPhone shows an app's own picture in a bubble.
    private func cover(side: CGFloat) -> some View {
        ZStack {
            if let artwork = nowPlaying.artwork {
                Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fill)
                    .id(ObjectIdentifier(artwork))
                    .transition(IslandMotion.fade)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: side * 0.42, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .frame(width: side, height: side)
        .clipShape(Circle())
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
