//
//  ShortcutViews.swift
//  Glance
//
//  Created by Gaty on 14/11/2026.
//

import AppKit
import SwiftUI

/// A shortcut running beside the camera, as Apple's progress activity: Shortcuts' icon at the left
/// end, and at the right the ring, going round while it runs, or how it ended.
struct ShortcutRunMark: View {
    let shown: ShortcutShown
    let restingHeight: CGFloat
    var leadingOnly = false

    static func wing(for shown: ShortcutShown, restingHeight: CGFloat) -> CGFloat {
        TaskCompactMark<EmptyView>.wing(restingHeight: restingHeight)
    }

    var body: some View {
        TaskCompactMark(status: ShortcutRunGlyph.status(for: shown.run.state), restingHeight: restingHeight, leadingOnly: leadingOnly) {
            TaskAppIcon(bundleID: ShortcutRunView.app, fallback: "square.2.layers.3d.fill", side: SystemActivityView.side(restingHeight))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(shown.spoken)
        .help(shown.spoken)
    }
}

/// The run's ring, as beside the camera, alone in the bubble. It goes round only to say the run is
/// going on; it doesn't pretend to know how far the shortcut has got.
struct ShortcutRunGlyph: View {
    let state: ShortcutRun.State
    var minimal = false
    var restingHeight: CGFloat = 32

    /// Going round while it runs or stops; a check when it's done, an exclamation mark when it
    /// couldn't finish, and the stop square when you stopped it.
    static func status(for state: ShortcutRun.State) -> TaskStatus {
        switch state {
        case .starting, .running, .stopping, .stopDelayed: .working
        case .completed: .done
        case .failed: .failed
        case .stopped, .endedAfterStop: .stopped
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
        TaskRing(status: Self.status(for: state), diameter: restingHeight * TimerLayout.ring)
    }
}

/// A shortcut run from Glance's menu, opened in one row, as Apple's progress activity: Shortcuts'
/// icon at the left end, which opens it; the shortcut's name beside the camera and its state under
/// it; at the right end the ring, with the square inside it that stops the run. Once it's over the
/// ring shows how it ended and closes it, as Done, its result before it.
struct ShortcutRunView: View {
    let shown: ShortcutShown
    let restingHeight: CGFloat
    let camera: CGFloat
    var revealed = true
    var stop: () -> Void = {}
    var dismiss: () -> Void = {}
    var openShortcuts: () -> Void = {}
    var showResult: () -> Void = {}

    /// Shortcuts, whose icon the run shows.
    static let app = "com.apple.shortcuts"

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
            TaskAppButton(
                bundleID: Self.app, fallback: "square.2.layers.3d.fill", restingHeight: h, label: String(localized: "Open Shortcuts"), open: openShortcuts
            )
            .accessibilityIdentifier("open-shortcuts")
        } trailing: {
            let active = shown.run.state.active
            if !active, shown.run.exit?.output != nil {
                IslandCircleButton(control: .activityThird, height: h, tint: .white, label: String(localized: "Show Result"), action: showResult) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: h * 0.55, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .accessibilityIdentifier("show-shortcut-result")
            }
            // One ring all the way: Stop while it runs, Done once it's over.
            TaskRingButton(
                status: ShortcutRunGlyph.status(for: shown.run.state), control: .activitySecond, height: h,
                label: active
                    ? (shown.run.state == .stopDelayed ? String(localized: "Try Stopping Again") : String(localized: "Stop Shortcut"))
                    : String(localized: "Done"),
                held: shown.run.state == .stopping, action: active ? stop : dismiss
            )
            .disabled(active && !shown.run.canStop)
            .accessibilityIdentifier(active ? "stop-shortcut" : "dismiss-shortcut")
        }
        .accessibilityLabel(shown.spoken)
    }
}
