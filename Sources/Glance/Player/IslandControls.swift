//
//  IslandControls.swift
//  Glance
//
//  Created by Gaty on 07/10/2026.
//

import AppKit
import SwiftUI

/// A borderless symbol button. Every one has the same contact area.
struct IslandButton: View {
    let symbol: String
    let size: CGFloat
    var color: Color = .white
    /// Struck through, for an option that's off; the slash draws across, and back, as it changes.
    var slashed = false
    /// Counts saves: each new value plays the save effect once.
    var burst = 0
    var burstColor: Color = .white
    let action: () -> Void

    var body: some View {
        let glyph = size, glowColor = burstColor
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(color)
                .contentTransition(.symbolEffect(.replace))
                .modifier(Slashed(progress: slashed ? 1 : 0, color: color, weight: size * 0.075))
                .animation(.spring(response: 0.32, dampingFraction: 0.9), value: slashed)
                // Saving: the star swells once, slowly and smoothly, with a soft glow in the accent
                // color behind it, then settles back with no overshoot.
                .keyframeAnimator(initialValue: SaveEffect(), trigger: burst) { icon, effect in
                    icon
                        .scaleEffect(effect.scale)
                        .background {
                            Circle()
                                .fill(glowColor)
                                .frame(width: glyph * 2, height: glyph * 2)
                                .blur(radius: glyph * 0.5)
                                .opacity(effect.glow)
                        }
                } keyframes: { _ in
                    KeyframeTrack(\.scale) {
                        CubicKeyframe(1.22, duration: 0.35)
                        CubicKeyframe(1.22, duration: 0.1)
                        CubicKeyframe(1, duration: 0.45)
                    }
                    KeyframeTrack(\.glow) {
                        CubicKeyframe(0.6, duration: 0.35)
                        CubicKeyframe(0.6, duration: 0.1)
                        CubicKeyframe(0, duration: 0.55)
                    }
                }
        }
        .buttonStyle(IslandPress())
        .notchControl()
    }
}

/// A slash across a symbol, from its top left toward its bottom right, as far as `progress` says,
/// with a gap cut along it, as SF Symbols' slashed symbols have.
private struct Slashed: ViewModifier, Animatable {
    var progress: CGFloat
    let color: Color
    let weight: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
            .mask {
                ZStack {
                    Rectangle()
                    SlashLine(progress: progress)
                        .stroke(style: StrokeStyle(lineWidth: weight * 2.8, lineCap: .round))
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
            }
            .overlay {
                SlashLine(progress: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: weight, lineCap: .round))
            }
    }
}

private struct SlashLine: Shape {
    var progress: CGFloat

    func path(in rect: CGRect) -> Path {
        guard progress > 0.001 else { return Path() }
        // Within the symbol, short of its corners.
        let inset = rect.insetBy(dx: rect.width * 0.14, dy: rect.height * 0.06)
        let start = CGPoint(x: inset.minX, y: inset.minY)
        let end = CGPoint(x: inset.maxX, y: inset.maxY)
        var path = Path()
        path.move(to: start)
        path.addLine(to: CGPoint(x: start.x + (end.x - start.x) * progress, y: start.y + (end.y - start.y) * progress))
        return path
    }
}

private struct SaveEffect {
    var scale: CGFloat = 1
    var glow: Double = 0
}

/// Pressing shrinks the icon and lights a soft circle behind it, as on the iPhone. The contact
/// area never changes size.
struct IslandPress: ButtonStyle {
    var highlight = true
    /// nil keeps the label's own size, for the app badge.
    var contactSize: CGFloat? = NowPlayingView.hitbox

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
            .frame(width: contactSize, height: contactSize)
            .background {
                Circle()
                    .fill(.white.opacity(highlight && configuration.isPressed ? 0.14 : 0))
                    .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
            }
            .contentShape(Rectangle())
    }
}

/// A progress bar you can drag to seek. It thickens a little under the pointer.
struct Scrubber: View {
    let fraction: Double
    let color: Color
    let onScrub: (Double) -> Void
    let onCommit: (Double) -> Void
    @State private var hovering = false
    @Environment(\.demoPointer) private var demoPointer

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let clamp = { (x: CGFloat) in Double(min(max(x / max(width, 1), 0), 1)) }
            let pointed = proxy.frame(in: .named(NotchView.bodySpace)).holds(demoPointer)
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.2))
                Capsule().fill(color).frame(width: width * min(max(fraction, 0), 1))
            }
            .frame(height: 6)
            // Thickened as a whole rather than laid out again, so it grows evenly.
            .scaleEffect(x: 1, y: hovering || pointed ? 1.35 : 1)
            .animation(.easeOut(duration: 0.18), value: pointed)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { onScrub(clamp($0.location.x)) }
                    .onEnded { onCommit(clamp($0.location.x)) })
        }
        .animation(.easeOut(duration: 0.18), value: hovering)
        .onHover { hovering = $0 }
        .notchControl()
    }
}
