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
    /// A variable symbol keeps its full canvas while its layers draw to the new value.
    var symbolValue: Double? = nil
    var color: Color = .white
    /// Struck through, for an option that's off; the slash draws across, and back, as it changes.
    var slashed = false
    /// Counts saves: each new value plays the save effect once.
    var burst = 0
    /// Only the side currently assigned Favorite plays the shared save count.
    var burstEnabled = true
    var burstColor: Color = .white
    /// What VoiceOver and Voice Control call it, and its state, when the symbol's own name isn't
    /// what it does.
    var label: String? = nil
    var value: String? = nil
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let glyph = size, glowColor = burstColor
        let drawBurst = burstEnabled, scaleBurst = burstEnabled && !reduceMotion
        Button(action: action) {
            VariableControlSymbol(symbol: symbol, value: symbolValue ?? 1)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(color)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: symbol)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: symbolValue)
                .modifier(Slashed(progress: slashed ? 1 : 0, color: color, weight: size * 0.075))
                .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.9), value: slashed)
                // Saving: the star swells once, slowly and smoothly, with a soft glow in the accent
                // color behind it, then settles back with no overshoot. With Reduce Motion on, only
                // the glow.
                .keyframeAnimator(initialValue: SaveEffect(), trigger: burst) { icon, effect in
                    icon
                        .scaleEffect(scaleBurst ? effect.scale : 1)
                        .background {
                            Circle()
                                .fill(glowColor)
                                .frame(width: glyph * 2, height: glyph * 2)
                                .blur(radius: glyph * 0.5)
                                .opacity(drawBurst ? effect.glow : 0)
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
        .modifier(SpokenAs(label: label, value: value))
    }
}

/// Interpolates volume inside one symbol and uses the native transition when its name changes.
struct VariableControlSymbol: View, Animatable {
    let symbol: String
    var value: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Image(systemName: symbol, variableValue: value)
            .symbolVariableValueMode(.draw)
            .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace.magic(fallback: .replace)))
    }
}

/// A control's name, and its state, for VoiceOver and Voice Control, where it has one of its own.
struct SpokenAs: ViewModifier {
    let label: String?
    var value: String? = nil

    func body(content: Content) -> some View {
        if let label {
            content.accessibilityLabel(label).accessibilityValue(value ?? "").help(label)
        } else {
            content
        }
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
        IslandPressBody(label: configuration.label, pressed: configuration.isPressed, highlight: highlight, contactSize: contactSize)
    }
}

private struct IslandPressBody<Label: View>: View {
    let label: Label
    let pressed: Bool
    let highlight: Bool
    let contactSize: CGFloat?
    @State private var hovered = false
    @State private var frame = CGRect.zero
    @Environment(\.demoPointer) private var demoPointer

    var body: some View {
        IslandPressFeedback(label: label, pressed: pressed, hovered: hovered || frame.holds(demoPointer), highlight: highlight, contactSize: contactSize)
            .onHover { hovered = $0 }
            .onGeometryChange(for: CGRect.self) {
                $0.frame(in: .named(NotchView.bodySpace))
            } action: {
                frame = $0
            }
    }
}

/// The contact area stays fixed as the symbol responds. Shared by native button events and the
/// isolated design previews, which can show each state without moving the real pointer.
struct IslandPressFeedback<Label: View>: View {
    let label: Label
    let pressed: Bool
    let hovered: Bool
    var highlight = true
    var contactSize: CGFloat? = NowPlayingView.hitbox
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let down = enabled && pressed
        let over = enabled && hovered
        label
            .scaleEffect(down && !reduceMotion ? 0.85 : 1)
            .opacity(down && !highlight ? 0.75 : 1)
            .animation(reduceMotion ? nil : NotchMotion.spring(response: 0.3, dampingFraction: 0.7), value: down)
            .frame(width: contactSize, height: contactSize)
            .background {
                Circle()
                    .fill(.white.opacity(highlight ? (down ? 0.14 : over ? 0.08 : 0) : 0))
                    .animation(.easeOut(duration: 0.15), value: down)
                    .animation(.easeOut(duration: 0.15), value: over)
            }
            .contentShape(Rectangle())
    }
}

/// A progress bar you can drag to seek. It thickens a little under the pointer.
struct Scrubber: View {
    let fraction: Double
    let color: Color
    /// Where the song is, in words, and how far one step of VoiceOver's adjusting moves it.
    var spoken = ""
    var step = 0.05
    let onScrub: (Double) -> Void
    let onCommit: (Double) -> Void
    @State private var hovering = false
    @Environment(\.demoPointer) private var demoPointer

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let clamp = { (x: CGFloat) in Double(min(max(x / max(width, 1), 0), 1)) }
            let pointed = proxy.frame(in: .named(NotchView.bodySpace)).holds(demoPointer)
            // One bar, its played part and the rest side by side within its shape, rather than a second
            // bar laid over the first: the played part ends in a straight edge, however short, and the
            // gray never shows through it.
            let played = width * min(max(fraction, 0), 1)
            HStack(spacing: 0) {
                Rectangle().fill(color).frame(width: played)
                Rectangle().fill(.white.opacity(0.2))
            }
            .frame(height: 6)
            .clipShape(Capsule())
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
        // To VoiceOver, a slider: where the song is, and a step back or ahead.
        .accessibilityElement()
        .accessibilityLabel("Track Position")
        .accessibilityValue(spoken)
        .accessibilityAdjustableAction { direction in
            let moved = direction == .increment ? fraction + step : fraction - step
            onCommit(min(max(moved, 0), 1))
        }
    }
}
