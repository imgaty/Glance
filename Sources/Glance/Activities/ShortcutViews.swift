//
//  ShortcutViews.swift
//  Glance
//
//  Created by Gaty on 14/11/2026.
//

import AppKit
import SwiftUI

/// A shortcut running, as iOS 27's ShortcutsUI draws it in the Dynamic Island, by the island's
/// height. Beside the camera, the shortcut's own icon at the left and the ring in its color at the
/// right; opened, the icon laid flat on a dark platter, its name, and the ring.
enum ShortcutRunLook {
    static let icon: CGFloat = 0.636
    static let iconEdge: CGFloat = 0.273
    static let ring: CGFloat = 0.645
    static let ringEdge: CGFloat = 0.2
    /// The icon's corners, by its side (`WFApertureIconView`'s image view).
    static let corner: CGFloat = 0.26
    /// Its shadow, in the iPhone's points: 35% black, 6 across, 3 up.
    static let shadowOpacity: Double = 0.35
    static let shadowRadius: CGFloat = 6
    static let shadowLift: CGFloat = 3
    /// Opened, `-[WFApertureIconView setMode:animated:]`: the icon scaled to 0.76, turned 45° the
    /// other way from a clock's hands and squashed to 0.8 tall, lifted 0.17 of its side, the platter
    /// as far below; they spring there 0.17 seconds after it opens, in 0.45, with no bounce.
    static let laidScale: CGFloat = 0.76
    static let laidTurn: Double = -45
    static let laidSquash: CGFloat = 0.8
    static let laidLift: CGFloat = 0.17
    static let laidDelay: TimeInterval = 0.17
    static let laidSpring: TimeInterval = 0.45

    /// How much of the ring shows for how far the run has got, from the top round as a clock's hands
    /// go: a dot before it starts, almost all of it at the end, a little more opened
    /// (`-[WFProgressAccessoryView updateProgressWithValue:]`).
    static func arc(_ fraction: Double, opened: Bool) -> Double { 0.001 + min(max(fraction, 0), 1) * (opened ? 0.98 : 0.97) }
    /// Beside the camera the ring waits this long for the run's first progress before it shows, then
    /// fades in (`setProgressSuppressionState:`, `setMicaViewHidden:animated:`).
    static let ringWait: TimeInterval = 1
    static let ringFade: TimeInterval = 0.4
}

/// A shortcut running beside the camera: its icon at the left end, and at the right the ring in its
/// color, filling as it goes, or how it ended.
struct ShortcutRunMark: View {
    let shown: ShortcutShown
    let restingHeight: CGFloat
    var leadingOnly = false
    @State private var waited = false

    static func wing(for shown: ShortcutShown, restingHeight h: CGFloat) -> CGFloat {
        let gap = LiveActivityView.cameraGap
        let left = h * (ShortcutRunLook.iconEdge + ShortcutRunLook.icon) + gap
        let right = gap + h * (ShortcutRunLook.ring + ShortcutRunLook.ringEdge)
        return max(left, right)
    }

    var body: some View {
        let h = restingHeight
        let run = shown.run
        let ringShown = !run.state.active || (run.progress ?? 0) > 0 || waited
        ZStack {
            ShortcutTile(look: shown.shownLook, side: h * ShortcutRunLook.icon, restingHeight: h)
                .padding(.leading, h * ShortcutRunLook.iconEdge)
                .frame(maxWidth: .infinity, alignment: .leading)
            TaskRing(status: ShortcutRunGlyph.status(for: run), diameter: h * ShortcutRunLook.ring, tint: shown.shownLook.tint)
                .opacity(ringShown ? 1 : 0)
                .animation(.easeInOut(duration: ShortcutRunLook.ringFade), value: ringShown)
                .padding(.trailing, h * ShortcutRunLook.ringEdge)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .islandFade(!leadingOnly)
        }
        .task(id: run.id) {
            let wait = ShortcutRunLook.ringWait - Date.now.timeIntervalSince(run.startedAt)
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            waited = true
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(shown.spoken)
        .help(shown.spoken)
    }
}

/// A shortcut's icon as the island shows it: Shortcuts' own drawing of it, or its drawer's in the
/// shortcut's color, its corners rounded to a quarter and a bit of its side, with a soft shadow.
struct ShortcutTile: View {
    let look: ShortcutLook
    let side: CGFloat
    /// The island's height, which the shadow is measured by.
    var restingHeight: CGFloat = 32

    var body: some View {
        let k = restingHeight / 36.7
        ShortcutTileImage(look: look, side: side)
            .shadow(
                color: .black.opacity(ShortcutRunLook.shadowOpacity), radius: ShortcutRunLook.shadowRadius * k, x: 0,
                y: -ShortcutRunLook.shadowLift * k
            )
            .accessibilityHidden(true)
    }
}

/// The icon alone, rounded as the island rounds it.
private struct ShortcutTileImage: View {
    let look: ShortcutLook
    let side: CGFloat

    var body: some View {
        Group {
            if let tile = look.tile {
                Image(nsImage: tile).resizable().interpolation(.high)
            } else {
                Rectangle().fill(look.tint ?? .white.opacity(0.2))
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: side * ShortcutRunLook.corner, style: .continuous))
    }
}

/// The shortcut's icon opened, as iOS 27 lays it: turned and squashed flat, lifted over a dark
/// platter of the same shape, which `iconStackPlatterColorForImage:` colors.
struct ShortcutStack: View {
    let look: ShortcutLook
    /// The icon view's side, 50 points on the iPhone.
    let side: CGFloat
    /// The island's height, which the shadow is measured by.
    var restingHeight: CGFloat = 32
    /// Laid flat, as opened; otherwise upright, as beside the camera, before it springs flat.
    var laid = true

    var body: some View {
        let lift = laid ? side * ShortcutRunLook.laidLift : 0
        ZStack {
            RoundedRectangle(cornerRadius: side * ShortcutRunLook.corner, style: .continuous)
                .fill(look.platter)
                .frame(width: side, height: side)
                .modifier(ShortcutLaid(laid: laid))
                .offset(y: lift)
            ShortcutTile(look: look, side: side, restingHeight: restingHeight)
                .modifier(ShortcutLaid(laid: laid))
                .offset(y: -lift)
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

/// Scaled, turned and squashed, in that order, as `CATransform3DConcat` puts them together.
private struct ShortcutLaid: ViewModifier {
    let laid: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(laid ? ShortcutRunLook.laidScale : 1)
            .rotationEffect(.degrees(laid ? ShortcutRunLook.laidTurn : 0))
            .scaleEffect(x: 1, y: laid ? ShortcutRunLook.laidSquash : 1)
    }
}

/// The run alone in the bubble: its icon, as iOS 27's minimal view is the icon view.
struct ShortcutRunGlyph: View {
    let run: ShortcutRun
    var look: ShortcutLook = .newShortcut
    var restingHeight: CGFloat = 32

    /// The ring filling as Shortcuts says the run goes, a dot at the top until it does; a check when
    /// it's done, an exclamation mark when it couldn't finish, and the stop square when you stopped it.
    static func status(for run: ShortcutRun, opened: Bool = false) -> TaskStatus {
        switch run.state {
        case .starting, .running, .stopping, .stopDelayed: .counting(ShortcutRunLook.arc(run.progress ?? 0, opened: opened))
        case .completed: .done
        case .failed: .failed
        case .stopped, .endedAfterStop: .stopped
        }
    }

    var body: some View {
        ShortcutTile(look: look, side: restingHeight * ShortcutRunLook.icon, restingHeight: restingHeight)
    }
}

/// A shortcut run from Glance's menu, opened, as the iPhone's: its icon laid flat at the left end,
/// which opens Shortcuts; its name beside the camera; at the right end the ring in its color, with
/// the square inside it that stops the run. Once it's over the ring turns white with how it ended,
/// and the run goes by itself, unless it has a result to show or it failed; then the ring closes
/// it, as Done, its result before it.
struct ShortcutRunView: View {
    let shown: ShortcutShown
    let restingHeight: CGFloat
    let camera: CGFloat
    var revealed = true
    var stop: () -> Void = {}
    var dismiss: () -> Void = {}
    var openShortcuts: () -> Void = {}
    @State private var laid = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Shortcuts, whose icon the run shows.
    static let app = "com.apple.shortcuts"

    /// What the line has no room for: why it ended, or what to do while it runs.
    static func explanation(for shown: ShortcutShown) -> String {
        var lines = [shown.status]
        if shown.run.state == .stopDelayed {
            lines.append(String(localized: "The shortcut hasn't stopped yet. Try again, or stop it in Shortcuts."))
        } else if let message = shown.run.message, !message.isEmpty {
            lines.append(message)
        } else if shown.run.state.active {
            lines.append(String(localized: "If the shortcut asks for anything, answer it in Shortcuts."))
        }
        if shown.additionalRuns > 0 { lines.append(String(localized: "Other runs are in the Run Shortcut menu.")) }
        return lines.joined(separator: "\n")
    }

    @MainActor
    static func width(for shown: ShortcutShown, restingHeight h: CGFloat, camera: CGFloat) -> CGFloat {
        ActivityRowLayout.width(title: shown.run.shortcut.name, detail: "", buttons: 1, metrics: .shortcut(h), restingHeight: h, camera: camera)
    }

    static func height(restingHeight h: CGFloat) -> CGFloat { ActivityRowMetrics.shortcut(h).height }

    /// In the order they stand: Shortcuts at the left, then Stop, or Done once it's over.
    static func controls(for shown: ShortcutShown) -> [PlayerControl] {
        [.activityFirst] + (shown.run.canStop || !shown.run.state.active ? [.activitySecond] : [])
    }

    var body: some View {
        let h = restingHeight
        let metrics = ActivityRowMetrics.shortcut(h)
        ActivityRow(
            restingHeight: h, camera: camera, width: Self.width(for: shown, restingHeight: h, camera: camera), metrics: metrics,
            title: shown.run.shortcut.name, detail: "", explanation: Self.explanation(for: shown), buttons: 1, revealed: revealed
        ) {
            Button(action: openShortcuts) {
                ShortcutStack(look: shown.shownLook, side: metrics.pictureSide, restingHeight: h, laid: laid)
                    .frame(width: metrics.pictureSide, height: metrics.pictureSide)
                    .contentShape(Rectangle())
            }
            .buttonStyle(IslandPress(highlight: false, contactSize: nil))
            .notchControl()
            .keyControl(.activityFirst, in: Rectangle(), outset: CGSize(width: 3, height: 3), spoken: String(localized: "Open Shortcuts"), action: openShortcuts)
            .accessibilityLabel(String(localized: "Open Shortcuts"))
            .help(String(localized: "Open Shortcuts"))
            .accessibilityIdentifier("open-shortcuts")
        } trailing: {
            let active = shown.run.state.active
            // One ring all the way: Stop while it runs, Done once it's over.
            TaskRingButton(
                status: ShortcutRunGlyph.status(for: shown.run, opened: true), control: .activitySecond, height: h,
                label: active
                    ? (shown.run.state == .stopDelayed ? String(localized: "Try Stopping Again") : String(localized: "Stop Shortcut"))
                    : String(localized: "Done"),
                held: shown.run.state == .stopping, tint: shown.shownLook.tint, side: metrics.buttonSide, action: active ? stop : dismiss
            )
            .disabled(active && !shown.run.canStop)
            .accessibilityIdentifier(active ? "stop-shortcut" : "dismiss-shortcut")
        }
        .accessibilityLabel(shown.spoken)
        // Upright as it opens, then flat.
        .onChange(of: revealed, initial: true) { _, revealed in
            if reduceMotion {
                laid = true
            } else if revealed {
                laid = false
                withAnimation(.spring(duration: ShortcutRunLook.laidSpring, bounce: 0).delay(ShortcutRunLook.laidDelay)) { laid = true }
            } else {
                laid = false
            }
        }
    }
}
