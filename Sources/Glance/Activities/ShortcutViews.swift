//
//  ShortcutViews.swift
//  Glance
//
//  Created by Gaty on 14/11/2026.
//

import AppKit
import SwiftUI

/// A shortcut running, measured from iOS 27's Shortcuts in the Dynamic Island, by the island's
/// height. Beside the camera, the shortcut's own icon at the left, in further from the end than
/// from the top and bottom, and the ring in its color at the right. Opened, its icon laid flat as
/// a diamond on a dark one, as Shortcuts' own layers, its name, and the ring.
enum ShortcutRunLook {
    static let icon: CGFloat = 0.636
    static let iconEdge: CGFloat = 0.273
    static let ring: CGFloat = 0.645
    static let ringEdge: CGFloat = 0.2
    /// Opened, by the opened height: the diamond's width as it shows, its height by its width, and
    /// how far the dark one lies under it, by the opened height.
    static let diamond: CGFloat = 0.55
    static let flat: CGFloat = 0.8
    static let under: CGFloat = 0.219
    /// The dark one: the shortcut's color at a quarter, as the ring's track.
    static let underShade: Double = 0.25
}

/// A shortcut running beside the camera: its icon at the left end, and at the right the ring in its
/// color, filling as it goes, or how it ended.
struct ShortcutRunMark: View {
    let shown: ShortcutShown
    let restingHeight: CGFloat
    var leadingOnly = false

    static func wing(for shown: ShortcutShown, restingHeight h: CGFloat) -> CGFloat {
        let gap = LiveActivityView.cameraGap
        let left = h * (ShortcutRunLook.iconEdge + ShortcutRunLook.icon) + gap
        let right = gap + h * (ShortcutRunLook.ring + ShortcutRunLook.ringEdge)
        return max(left, right)
    }

    var body: some View {
        let h = restingHeight
        ZStack {
            ShortcutTile(look: shown.look, side: h * ShortcutRunLook.icon)
                .padding(.leading, h * ShortcutRunLook.iconEdge)
                .frame(maxWidth: .infinity, alignment: .leading)
            TaskRing(status: ShortcutRunGlyph.status(for: shown.run.state), diameter: h * ShortcutRunLook.ring, tint: shown.look?.tint)
                .padding(.trailing, h * ShortcutRunLook.ringEdge)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .islandFade(!leadingOnly)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(shown.spoken)
        .help(shown.spoken)
    }
}

/// A shortcut's icon, as Shortcuts draws it: its rounded square in its color with its glyph. Without
/// it, Shortcuts' layers on the shortcut's color, or faint white.
struct ShortcutTile: View {
    let look: ShortcutLook?
    let side: CGFloat

    var body: some View {
        Group {
            if let icon = look?.icon {
                Image(nsImage: icon).resizable().interpolation(.high)
            } else {
                RoundedRectangle(cornerRadius: side * TaskAppIcon.corner, style: .continuous)
                    .fill(look?.tint ?? .white.opacity(0.2))
                    .overlay {
                        Image(systemName: "square.2.layers.3d.fill")
                            .font(.system(size: side * 0.62, weight: .semibold))
                            .foregroundStyle(.white)
                    }
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

/// The shortcut's icon opened, as the iPhone lays it: flat, as a diamond, on a dark copy of itself
/// half a diamond lower, as Shortcuts' layers are drawn.
struct ShortcutStack: View {
    let look: ShortcutLook?
    /// The opened height.
    let height: CGFloat

    var body: some View {
        let width = height * ShortcutRunLook.diamond
        // Its corners round off the diamond's points: the square that shows that wide across.
        let side = width / (2.squareRoot() - 2 * TaskAppIcon.corner * (2.squareRoot() - 1))
        let lower = height * ShortcutRunLook.under
        ZStack {
            RoundedRectangle(cornerRadius: side * TaskAppIcon.corner, style: .continuous)
                .fill((look?.tint ?? .white).opacity(ShortcutRunLook.underShade))
                .frame(width: side, height: side)
                .rotationEffect(.degrees(45))
                .scaleEffect(x: 1, y: ShortcutRunLook.flat)
                .offset(y: lower / 2)
            ShortcutTile(look: look, side: side)
                .rotationEffect(.degrees(45))
                .scaleEffect(x: 1, y: ShortcutRunLook.flat)
                .offset(y: -lower / 2)
        }
        .frame(width: width, height: width * ShortcutRunLook.flat + lower)
        .accessibilityHidden(true)
    }
}

/// The run's ring, as beside the camera, alone in the bubble.
struct ShortcutRunGlyph: View {
    let state: ShortcutRun.State
    var look: ShortcutLook? = nil
    var minimal = false
    var restingHeight: CGFloat = 32

    /// Filling as it runs (Shortcuts' own runs tell how far they've got; one started from Glance
    /// doesn't, so it goes round); a check when it's done, an exclamation mark when it couldn't
    /// finish, and the stop square when you stopped it.
    static func status(for state: ShortcutRun.State) -> TaskStatus {
        switch state {
        case .starting, .running, .stopping, .stopDelayed: .working
        case .completed: .done
        case .failed: .failed
        case .stopped, .endedAfterStop: .stopped
        }
    }

    var body: some View {
        TaskRing(status: Self.status(for: state), diameter: restingHeight * TimerLayout.ring, tint: look?.tint)
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
                ShortcutStack(look: shown.look, height: metrics.height)
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
                status: ShortcutRunGlyph.status(for: shown.run.state), control: .activitySecond, height: h,
                label: active
                    ? (shown.run.state == .stopDelayed ? String(localized: "Try Stopping Again") : String(localized: "Stop Shortcut"))
                    : String(localized: "Done"),
                held: shown.run.state == .stopping, tint: shown.look?.tint, side: metrics.buttonSide, action: active ? stop : dismiss
            )
            .disabled(active && !shown.run.canStop)
            .accessibilityIdentifier(active ? "stop-shortcut" : "dismiss-shortcut")
        }
        .accessibilityLabel(shown.spoken)
    }
}
