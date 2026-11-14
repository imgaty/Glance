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
/// it, 0.175 of that off its end, a timer's ring, the stopwatch's symbol, AirDrop's ring or
/// AirPlay's symbol in it as beside the camera, or a call's time. It leaves the notch's end as a
/// drop of water does: the end draws back from it on a neck that thins until it parts, and it runs
/// back into the end as it goes. Opened from the notch, it runs into the notch's end and rides on
/// it as the notch opens, until the end takes it in; opened from the bubble, it stays where it
/// rests, and the notch comes out over it. With Reduce Motion on, it fades in and out where it
/// rests. VoiceOver names it, and opens it as a click does.
struct IslandBubble: View {
    /// Out of the notch; in it, it's hidden in its end.
    let shown: Bool
    /// The timer or stopwatch it shows, and the timer's name, as VoiceOver says it.
    let clock: ClockShown?
    /// Or AirPlay, by its symbol alone, in its blue; or AirDrop, by its ring.
    var route: AirPlayRoute? = nil
    var airdrop: AirDropShown? = nil
    /// Or a recording: the screen's dot, or Voice Memos' waveform.
    var recording: Recording? = nil
    /// Or a call, by its time.
    var call: CallShown? = nil
    /// Or music, by its cover in a circle, or a note without one.
    var music = false
    var artwork: NSImage? = nil
    /// The music's paused: its cover dims, as beside the camera.
    var paused = false
    let name: String
    /// Opens it, as a click on it does.
    let open: () -> Void
    let restingHeight: CGFloat
    /// How far from the notch's middle its trailing end is, which the bubble sits off.
    let notchEnd: CGFloat
    /// The notch is open: nothing of the bubble shows over its glass.
    let hidden: Bool
    /// The notch opened from its own end, which the bubble goes on running into as it opens, riding
    /// with it: it's hidden only once it's all the way in.
    var runsIn = false
    /// Its glyph is carried by the expanded presentation until it returns here.
    var sharedGlyph = false
    let hovered: Bool
    let pressed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.islandExpansionMotion) private var expansionMotion
    /// What it showed, kept on as it runs back into the notch, so it fades as it goes rather than
    /// vanishing.
    @State private var kept: ClockShown?
    @State private var keptRoute: AirPlayRoute?
    @State private var keptAirDrop: AirDropShown?
    @State private var keptRecording: Recording?
    @State private var keptCall: CallShown?
    @State private var keptMusic = false
    @State private var keptArtwork: NSImage?
    /// Counted, so what's kept goes only if nothing has come since.
    @State private var changes = (clock: 0, route: 0, airdrop: 0, music: 0, recording: 0, call: 0)

    /// Off the notch's end, by its height.
    static let gap: CGFloat = 0.175
    /// The last part of the bubble disappears into the shell during its housing fold, so it
    /// cannot remain detached beside the bare camera housing.
    static let inBy: Double = 0.13

    /// On the same expansion or collapse motion as the notch's end, so the two part evenly.
    private var motion: Animation { shown ? expansionMotion : IslandMotion.fold }

    var body: some View {
        let h = restingHeight
        // With Reduce Motion on, it stays where it rests, and only fades.
        let out: CGFloat = shown || reduceMotion ? 1 : 0
        ZStack(alignment: .leading) {
            if !reduceMotion {
                BubbleBlend(out: out)
                    .animation(motion, value: out)
            }
            ZStack {
                Circle().fill(.black)
                    .overlay { Circle().fill(.white.opacity(hovered && !pressed ? 0.08 : 0)) }
                ZStack {
                    switch kept {
                    case .timer(let timer): TimerRing(state: timer, height: h)
                    case .stopwatch(let watch): StopwatchMark(watch: watch, height: h)
                    case nil:
                        if keptMusic {
                            // As the cover beside the camera: its size, its corners, dimmed while paused.
                            let side = h - LiveActivityView.inset * 2
                            Group {
                                if let keptArtwork {
                                    Image(nsImage: keptArtwork).resizable().aspectRatio(contentMode: .fill)
                                } else {
                                    Image(systemName: "music.note")
                                        .font(.system(size: side * 0.5, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.7))
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .background(.white.opacity(0.12))
                                }
                            }
                            .frame(width: side, height: side)
                            .overlay(Color.black.opacity(paused ? 1 - PausedLook.kept : 0))
                            .animation(.easeInOut(duration: 0.3), value: paused)
                            .clipShape(RoundedRectangle(cornerRadius: side * ArtworkShape.restingRadius, style: .continuous))
                        } else if let keptCall {
                            CallBubbleMark(call: keptCall, restingHeight: h)
                        } else if let keptRecording {
                            RecordingBubbleGlyph(recording: keptRecording, restingHeight: h)
                        } else if let keptAirDrop {
                            AirDropRing(fraction: keptAirDrop.fraction, diameter: h * AirDropLayout.ring, line: h * AirDropLayout.ringLine)
                        } else if keptRoute != nil {
                            Image(systemName: "airplay.audio")
                                .font(.system(size: h * 0.5, weight: .semibold))
                                .foregroundStyle(AirPlayLayout.tint)
                        }
                    }
                }
                .modifier(BubbleGlyph(out: reduceMotion ? 1 : out))
                .animation(motion, value: out)
                .modifier(BubbleContentHandoff(hidden: hidden, shared: sharedGlyph))
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
                } else if shown, !hidden, let recording {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Color.clear
                            .accessibilityElement()
                            .accessibilityLabel(recording.spoken(at: context.date))
                            .modifier(RecordingOpenAction(recording: recording, open: open))
                    }
                } else if shown, !hidden, let call {
                    Color.clear
                        .accessibilityElement()
                        .accessibilityLabel(call.rings ? String(localized: "\(call.name), incoming call") : String(localized: "\(call.name), on a call"))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction(.default, open)
                } else if shown, !hidden, let airdrop {
                    Color.clear
                        .accessibilityElement()
                        .accessibilityLabel(ExpandedAirDropView.spoken(airdrop))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction(.default, open)
                } else if shown, !hidden, music {
                    Color.clear
                        .accessibilityElement()
                        .accessibilityLabel(name)
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
            .scaleEffect(reduceMotion || !pressed ? 1 : 0.94)
            .animation(.easeInOut(duration: 0.25)) { $0.opacity(reduceMotion && !shown ? 0 : 1) }
            .offset(x: h * (1 + Self.gap) * out)
            .animation(motion, value: out)
        }
        // From inside the notch's end, where it comes out of, to where it rests.
        .frame(width: h * (2 + Self.gap), height: h, alignment: .leading)
        // Stepped as the notch's own frame is, so the two keep one clock even when a frame comes late.
        .modifier(SteppedOffset(x: notchEnd - h + h * (2 + Self.gap) / 2))
        // Solid until the opening notch has covered it, or it's run all the way into the notch's end,
        // and back before the closing notch uncovers it, as anything fading here would show as a pale
        // circle beside the notch.
        .animation((hidden ? Animation.linear(duration: 0.01).delay(runsIn ? Self.inBy : 0.2) : .linear(duration: 0.01)).paced) {
            $0.opacity(hidden ? 0 : 1)
        }
        // With nothing to show or running back, it isn't there at all, to show past the notch's end.
        .animation(.linear(duration: 0.01)) { $0.opacity(shown || kept != nil || keptRoute != nil || keptAirDrop != nil || keptRecording != nil || keptCall != nil || keptMusic ? 1 : 0) }
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
        .onChange(of: music, initial: true) { _, new in
            changes.music += 1
            if new {
                keptMusic = true
                keptArtwork = artwork
                return
            }
            let change = changes.music
            Task { @MainActor in
                try? await Task.sleep(for: SystemActivityView.folding)
                if changes.music == change {
                    keptMusic = false
                    keptArtwork = nil
                }
            }
        }
        .onChange(of: artwork.map(ObjectIdentifier.init), initial: true) { _, _ in
            // A track without a cover uses the note. Keep an old cover only while music is
            // leaving the bubble, so the outgoing image survives its fold back into the notch.
            if music { keptArtwork = artwork }
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
        .onChange(of: recording, initial: true) { _, new in
            changes.recording += 1
            if let new { return keptRecording = new }
            let change = changes.recording
            Task { @MainActor in
                try? await Task.sleep(for: SystemActivityView.folding)
                if changes.recording == change { keptRecording = nil }
            }
        }
        .onChange(of: call, initial: true) { _, new in
            changes.call += 1
            if let new { return keptCall = new }
            let change = changes.call
            Task { @MainActor in
                try? await Task.sleep(for: SystemActivityView.folding)
                if changes.call == change { keptCall = nil }
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

/// What the bubble shows, once it's all but out: no sooner, as anything in it would show as a tint on
/// the black while it's still one with the notch.
private struct BubbleGlyph: ViewModifier, Animatable {
    var out: CGFloat

    var animatableData: CGFloat {
        get { out }
        set { out = newValue }
    }

    func body(content: Content) -> some View {
        content.opacity(min(max((out - 0.8) / 0.2, 0), 1))
    }
}

/// Moved by an offset laid out afresh at every step as it animates, as the notch's frame is, rather
/// than one only its picture follows: a late frame delays both alike, and the bubble stays on the
/// notch's end.
private struct SteppedOffset: ViewModifier, Animatable {
    var x: CGFloat

    var animatableData: CGFloat {
        get { x }
        set { x = newValue }
    }

    func body(content: Content) -> some View {
        content.offset(x: x)
    }
}

/// The notch's end and the bubble running together as two drops do: two circles, one in the notch's
/// end, blurred and cut back to a hard edge, so that where they're near, their blurs add up past the
/// cut into a neck that thins and parts, as nothing drawn by hand does.
struct BubbleBlend: View, Animatable {
    /// 0 with the bubble in the notch's end, 1 where it rests.
    var out: CGFloat

    /// How much it's blurred, by the height: enough for them to part just before the bubble rests.
    static let blur: CGFloat = 0.11
    /// Room around them for the blur.
    private static let margin: CGFloat = 12
    /// Far enough out that the neck has parted, and the bubble is a circle.
    static let apart: CGFloat = 0.9

    var animatableData: CGFloat {
        get { out }
        set { out = newValue }
    }

    var body: some View {
        Canvas { context, size in
            let h = size.height - Self.margin * 2
            context.addFilter(.alphaThreshold(min: 0.5, color: .black))
            context.addFilter(.blur(radius: h * Self.blur))
            context.drawLayer { layer in
                let bubble = h * (1 + IslandBubble.gap) * out
                // One shape, so that where they overlap, in the notch's end, they don't add up past its edge.
                var circles = Path()
                for x in [0, bubble] {
                    circles.addEllipse(in: CGRect(x: Self.margin + x, y: Self.margin, width: h, height: h))
                }
                layer.fill(circles, with: .color(.black))
                // In the notch's end, the bubble's top is the notch's: square up to the screen's edge, as
                // the notch's other end is, rounding into a circle only as it leaves.
                let near = 1 - min(out / Self.apart, 1)
                if near > 0 {
                    layer.drawLayer { top in
                        top.clip(to: circles, options: .inverse)
                        top.fill(Path(CGRect(x: Self.margin + bubble, y: 0, width: h, height: Self.margin + h / 2)), with: .color(.black.opacity(near)))
                    }
                }
            }
        }
        .padding(-Self.margin)
    }
}

private struct BubbleContentHandoff: ViewModifier {
    let hidden: Bool
    let shared: Bool
    func body(content: Content) -> some View {
        if shared {
            content.modifier(GrownAway(grown: hidden))
        } else {
            content.animation(Animation.easeOut(duration: 0.1).paced) { $0.opacity(hidden ? 0 : 1) }
        }
    }
}
