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
/// By the Mac's island's measures, for its height: a circle as wide as the island is tall, level
/// with it, 0.217 of that off its end, a timer's ring, the stopwatch's symbol or AirDrop's ring in
/// it as beside the camera, or a call's time. It leaves the notch's end as a drop of water does: the
/// end draws back from it on a neck that thins until it parts, and it runs back into the end as it
/// goes. Opened from the notch, the notch's end takes it in at once and grows from there; opened
/// from the bubble, it runs into the notch, which folds to the housing first. The pointer resting on
/// it swells its outline and leans it toward the pointer, with what's in it staying where it is.
/// With Reduce Motion on, it fades in and out where it rests. VoiceOver names it, and opens it as a
/// click does.
struct IslandBubble: View {
    /// Out of the notch; in it, it's hidden in its end.
    let shown: Bool
    /// The timer or stopwatch it shows, and the timer's name, as VoiceOver says it.
    let clock: ClockShown?
    /// Or AirDrop, by its ring.
    var airdrop: AirDropShown? = nil
    var alarm: AlarmShown? = nil
    var recognition: MusicRecognitionActivity.State? = nil
    var shortcut: ShortcutShown? = nil
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
    /// How much further out than its gap it rests: beside an open view, past the flare its top
    /// corner reaches out to the screen's edge with, coming out of the view's body under it.
    var travel: CGFloat = 0
    /// The notch is open over it: nothing of the bubble shows over its glass.
    let hidden: Bool
    /// How far its outline reaches past its circle under the pointer (see `IslandSwell`).
    var swell = IslandSwell.zero
    var toolMotion = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.islandExpansionMotion) private var expansionMotion
    /// What it showed, kept on as it runs back into the notch, so it fades as it goes rather than
    /// vanishing.
    @State private var kept: ClockShown?
    @State private var keptAirDrop: AirDropShown?
    @State private var keptAlarm: AlarmShown?
    @State private var keptRecognition: MusicRecognitionActivity.State?
    @State private var keptShortcut: ShortcutShown?
    @State private var keptRecording: Recording?
    @State private var keptCall: CallShown?
    @State private var keptMusic = false
    @State private var keptArtwork: NSImage?
    /// Counted, so what's kept goes only if nothing has come since.
    @State private var changes = (clock: 0, airdrop: 0, music: 0, recording: 0, call: 0, recognition: 0, alarm: 0, shortcut: 0)

    /// Off the notch's end, by its height: 7.5 points off a 34.5 point island.
    static let gap: CGFloat = 0.217
    /// How long it keeps what it showed as it runs back into the notch, at the notch's pace.
    private static var keeping: Duration { SystemActivityView.folding * (1 / max(NotchMotion.pace, 0.01)) }

    /// On the same expansion or collapse motion as the notch's end, so the two part evenly.
    private var motion: Animation { toolMotion ? (shown ? ToolMotion.bubble : ToolMotion.close) : (shown ? expansionMotion : IslandMotion.fold) }

    var body: some View {
        let h = restingHeight
        // With Reduce Motion on, it stays where it rests, and only fades.
        let out: CGFloat = shown || reduceMotion ? 1 : 0
        let span = h * (1 + Self.gap) + travel
        ZStack(alignment: .leading) {
            if !reduceMotion {
                BubbleBlend(out: out, span: span / h)
                    .animation(motion, value: out)
            }
            ZStack {
                Circle().fill(.black)
                    // Its outline swollen and leaning toward the pointer; its top, the screen's edge,
                    // stays put.
                    .background(alignment: .top) {
                        Ellipse().fill(.black)
                            .frame(width: h + swell.across, height: h + swell.bottom)
                            .offset(x: (swell.trailing - swell.leading) / 2)
                            .animation(NotchMotion.hover, value: swell)
                    }
                ZStack {
                    switch kept {
                    case .timer(let timer): TimerRing(state: timer, height: h)
                    case .stopwatch(let watch): StopwatchMark(watch: watch, height: h)
                    case nil:
                        if keptMusic {
                            // As the cover beside the camera: its size, its corners, dimmed while paused.
                            let side = LiveActivityView.coverSide(h)
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
                        } else if let keptAlarm {
                            AlarmCompactView(shown: keptAlarm, minimal: true, restingHeight: h)
                        } else if let keptShortcut {
                            ShortcutRunGlyph(run: keptShortcut.run, look: keptShortcut.shownLook, restingHeight: h)
                        } else if let keptRecognition {
                            MusicRecognitionCompactView(state: keptRecognition, minimal: true, restingHeight: h)
                        }
                    }
                }
                .modifier(BubbleGlyph(out: reduceMotion ? 1 : out))
                .animation(motion, value: out)
                .animation(Animation.easeOut(duration: 0.1).paced) { $0.opacity(hidden ? 0 : 1) }
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
                } else if shown, !hidden, let alarm {
                    Color.clear
                        .accessibilityElement()
                        .accessibilityLabel(alarm.spoken)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction(.default, open)
                } else if shown, !hidden, let shortcut {
                    Color.clear
                        .accessibilityElement()
                        .accessibilityLabel(shortcut.spoken)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction(.default, open)
                } else if shown, !hidden, let recognition {
                    Color.clear
                        .accessibilityElement()
                        .accessibilityLabel(String(localized: "Music recognition, \(recognition.title)"))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction(.default, open)
                } else if shown, !hidden, music {
                    Color.clear
                        .accessibilityElement()
                        .accessibilityLabel(name)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction(.default, open)
                }
            }
            .animation(.easeInOut(duration: 0.25)) { $0.opacity(reduceMotion && !shown ? 0 : 1) }
            .offset(x: span * out)
            .animation(motion, value: out)
        }
        // From inside the notch's end, where it comes out of, to where it rests.
        .frame(width: h + span, height: h, alignment: .leading)
        // Stepped as the notch's own frame is, so the two keep one clock even when a frame comes late.
        .modifier(SteppedOffset(x: notchEnd - h + (h + span) / 2))
        // Solid until the opening notch has covered it, or it's run all the way into the notch's end,
        // and back before the closing notch uncovers it, as anything fading here would show as a pale
        // circle beside the notch.
        .animation((hidden ? Animation.linear(duration: 0.01).delay(0.2) : .linear(duration: 0.01)).paced) {
            $0.opacity(hidden ? 0 : 1)
        }
        // With nothing to show or running back, it isn't there at all, to show past the notch's end.
        .animation(.linear(duration: 0.01)) {
            $0.opacity(
                shown || kept != nil || keptAirDrop != nil || keptRecording != nil || keptCall != nil || keptAlarm != nil || keptRecognition != nil
                    || keptShortcut != nil || keptMusic
                    ? 1 : 0)
        }
        .allowsHitTesting(false)
        .onChange(of: clock, initial: true) { _, new in
            changes.clock += 1
            if let new { return kept = new }
            let change = changes.clock
            Task { @MainActor in
                try? await Task.sleep(for: Self.keeping)
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
                try? await Task.sleep(for: Self.keeping)
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
                try? await Task.sleep(for: Self.keeping)
                if changes.airdrop == change { keptAirDrop = nil }
            }
        }
        .onChange(of: recording, initial: true) { _, new in
            changes.recording += 1
            if let new { return keptRecording = new }
            let change = changes.recording
            Task { @MainActor in
                try? await Task.sleep(for: Self.keeping)
                if changes.recording == change { keptRecording = nil }
            }
        }
        .onChange(of: call, initial: true) { _, new in
            changes.call += 1
            if let new { return keptCall = new }
            let change = changes.call
            Task { @MainActor in
                try? await Task.sleep(for: Self.keeping)
                if changes.call == change { keptCall = nil }
            }
        }
        .onChange(of: alarm, initial: true) { _, new in
            changes.alarm += 1
            if let new { return keptAlarm = new }
            let change = changes.alarm
            Task { @MainActor in
                try? await Task.sleep(for: Self.keeping)
                if changes.alarm == change { keptAlarm = nil }
            }
        }
        .onChange(of: shortcut, initial: true) { _, new in
            changes.shortcut += 1
            if let new { return keptShortcut = new }
            let change = changes.shortcut
            Task { @MainActor in
                try? await Task.sleep(for: Self.keeping)
                if changes.shortcut == change { keptShortcut = nil }
            }
        }
        .onChange(of: recognition, initial: true) { _, new in
            changes.recognition += 1
            if let new { return keptRecognition = new }
            let change = changes.recognition
            Task { @MainActor in
                try? await Task.sleep(for: Self.keeping)
                if changes.recognition == change { keptRecognition = nil }
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
    /// How far it rests from the circle in the notch's end, by the height.
    var span: CGFloat = 1 + IslandBubble.gap

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
                let bubble = h * span * out
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
