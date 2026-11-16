//
//  ShortcutViews.swift
//  Glance
//
//  Created by Gaty on 14/11/2026.
//

import AppKit
import SwiftUI

/// A shortcut running beside the camera: its state at the left end, a word for it at the right.
struct ShortcutRunMark: View {
    let shown: ShortcutShown
    let restingHeight: CGFloat
    var leadingOnly = false

    @MainActor
    static func wing(for shown: ShortcutShown, restingHeight: CGFloat) -> CGFloat {
        CompactActivityLayout.wing(caption: ShortcutRunGlyph.caption(for: shown.run.state), restingHeight: restingHeight)
    }

    var body: some View {
        CompactActivityMark(caption: ShortcutRunGlyph.caption(for: shown.run.state), restingHeight: restingHeight, leadingOnly: leadingOnly) {
            ShortcutRunGlyph(state: shown.run.state, restingHeight: restingHeight)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(shown.spoken)
        .help(shown.spoken)
    }
}

/// The same mark beside the camera and in the bubble. The spinner means only that the run is going
/// on; it doesn't pretend to know how far the shortcut has got.
struct ShortcutRunGlyph: View {
    let state: ShortcutRun.State
    var minimal = false
    var restingHeight: CGFloat = 32
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static func symbol(for state: ShortcutRun.State) -> String {
        switch state {
        case .starting: "hourglass"
        case .running: "bolt.fill"
        case .stopping: "stop.circle"
        case .stopDelayed: "exclamationmark.triangle.fill"
        case .completed: "checkmark.circle.fill"
        case .stopped: "stop.circle.fill"
        case .endedAfterStop: "minus.circle"
        case .failed: "xmark.circle.fill"
        }
    }

    static func caption(for state: ShortcutRun.State) -> String {
        switch state {
        case .starting: String(localized: "Starting…")
        case .running: String(localized: "Running")
        case .stopping: String(localized: "Stopping…")
        case .stopDelayed: String(localized: "Still Running")
        case .completed: String(localized: "Complete")
        case .stopped: String(localized: "Stopped")
        case .endedAfterStop: String(localized: "Run Ended")
        case .failed: String(localized: "Failed")
        }
    }

    var body: some View {
        Group {
            if state == .running, !minimal, !reduceMotion {
                ProgressView().controlSize(.small).tint(.white)
            } else {
                Image(systemName: Self.symbol(for: state))
                    .font(.system(size: minimal ? restingHeight * 0.5 : LiveActivityView.textSize(for: restingHeight) + 2, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .accessibilityHidden(true)
    }
}

/// A shortcut run from Glance's menu, opened in one row: Shortcuts at the left end, which it opens;
/// the shortcut's name beside the camera and its state under it; at the right end, Stop while it
/// runs, and once it's over its result and Done.
struct ShortcutRunView: View {
    let shown: ShortcutShown
    let restingHeight: CGFloat
    let camera: CGFloat
    var revealed = true
    var stop: () -> Void = {}
    var dismiss: () -> Void = {}
    var openShortcuts: () -> Void = {}
    var showResult: () -> Void = {}

    static func detail(for shown: ShortcutShown) -> String { ShortcutRunGlyph.caption(for: shown.run.state) }

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

    private static func buttons(for shown: ShortcutShown) -> Int {
        shown.run.state.active ? 1 : (shown.run.exit?.output != nil ? 2 : 1)
    }

    @MainActor
    static func width(for shown: ShortcutShown, restingHeight h: CGFloat, camera: CGFloat) -> CGFloat {
        ActivityRowLayout.width(title: shown.run.shortcut.name, detail: detail(for: shown), buttons: buttons(for: shown), restingHeight: h, camera: camera)
    }

    static func height(restingHeight h: CGFloat) -> CGFloat { TimerLayout.tallHeight(h) }

    /// In the order they stand: Shortcuts at the left, then the result, then Stop or Done.
    static func controls(for shown: ShortcutShown) -> [PlayerControl] {
        [.activityFirst] + (shown.run.exit?.output != nil ? [.activityThird] : [])
            + (shown.run.canStop || !shown.run.state.active ? [.activitySecond] : [])
    }

    var body: some View {
        let h = restingHeight
        ActivityRow(
            restingHeight: h, camera: camera, width: Self.width(for: shown, restingHeight: h, camera: camera),
            title: shown.run.shortcut.name, detail: Self.detail(for: shown), explanation: Self.explanation(for: shown),
            buttons: Self.buttons(for: shown), revealed: revealed
        ) {
            ActivityRowPicture(restingHeight: h, label: String(localized: "Open Shortcuts"), open: openShortcuts) {
                Image(systemName: "square.2.layers.3d.fill")
                    .font(.system(size: h * 0.55, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityIdentifier("open-shortcuts")
        } trailing: {
            if shown.run.state.active {
                IslandCircleButton(
                    control: .activitySecond, height: h, tint: .white,
                    label: shown.run.state == .stopDelayed ? String(localized: "Try Stopping Again") : String(localized: "Stop Shortcut"), action: stop
                ) {
                    RoundedRectangle(cornerRadius: h * 0.06, style: .continuous)
                        .fill(.white)
                        .frame(width: h * 0.42, height: h * 0.42)
                }
                .disabled(!shown.run.canStop)
                .opacity(shown.run.canStop ? 1 : 0.45)
                .accessibilityIdentifier("stop-shortcut")
            } else {
                if shown.run.exit?.output != nil {
                    IslandCircleButton(control: .activityThird, height: h, tint: .white, label: String(localized: "Show Result"), action: showResult) {
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: h * 0.55, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .accessibilityIdentifier("show-shortcut-result")
                }
                IslandCircleButton(control: .activitySecond, height: h, tint: .white, label: String(localized: "Done"), action: dismiss) {
                    CrossGlyph(height: h)
                }
                .accessibilityIdentifier("dismiss-shortcut")
            }
        }
        .accessibilityLabel(shown.spoken)
    }
}
