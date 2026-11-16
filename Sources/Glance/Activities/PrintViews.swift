//
//  PrintViews.swift
//  Glance
//
//  Created by Gaty on 14/11/2026.
//

import AppKit
import SwiftUI

/// A print job beside the camera, as Apple's progress activity: Print Center's icon at the left end,
/// and at the right the ring of how far it's got, or how it ended.
struct PrintJobMark: View {
    let shown: PrintShown
    let restingHeight: CGFloat
    var leadingOnly = false

    static func wing(for shown: PrintShown, restingHeight: CGFloat) -> CGFloat {
        TaskCompactMark<EmptyView>.wing(restingHeight: restingHeight)
    }

    var body: some View {
        TaskCompactMark(status: PrintJobGlyph.status(for: shown), restingHeight: restingHeight, leadingOnly: leadingOnly) {
            TaskAppIcon(bundleID: PrintJobView.app, fallback: "printer.fill", side: SystemActivityView.side(restingHeight))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(shown.spoken)
        .help(shown.spoken)
    }
}

/// The job's ring, as beside the camera, alone in the bubble.
struct PrintJobGlyph: View {
    let shown: PrintShown
    var minimal = false
    var restingHeight: CGFloat = 32

    /// The pages printed, filling the ring; an arc going round while it waits or prints with nothing
    /// to count; a check once printed, an exclamation mark if it failed or its status can't be read.
    /// On hold or stopped, the ring stands still where it got to.
    static func status(for shown: PrintShown) -> TaskStatus {
        let fraction = shown.job.progress?.fraction
        if !shown.sourceAvailable { return TaskStatus(outcome: .failed, fraction: fraction) }
        switch shown.job.state {
        case .queued: return .working
        case .printing: return fraction.map(TaskStatus.counting) ?? .working
        case .held, .stopped: return .counting(fraction ?? 0)
        case .completed: return .done
        case .failed: return TaskStatus(outcome: .failed, fraction: fraction)
        case .canceled: return .stopped
        }
    }

    /// A word or two for its state, short enough for beside the camera.
    static func word(for shown: PrintShown) -> String {
        if shown.cancellation == .unconfirmed { return String(localized: "Unconfirmed") }
        if !shown.sourceAvailable { return String(localized: "Unavailable") }
        if shown.cancellation == .pending { return String(localized: "Canceling…") }
        if shown.cancellation == .failed { return String(localized: "Cancel Failed") }
        if shown.openFailed { return String(localized: "Open Failed") }
        switch shown.job.state {
        case .queued: return String(localized: "Waiting")
        case .held: return String(localized: "On Hold")
        case .printing: return String(localized: "Printing")
        case .stopped: return String(localized: "Stopped")
        case .canceled: return String(localized: "Canceled")
        case .failed: return String(localized: "Failed")
        case .completed: return String(localized: "Complete")
        }
    }

    var body: some View {
        TaskRing(status: Self.status(for: shown), diameter: restingHeight * TimerLayout.ring)
    }
}

/// A print job opened, in one row, as Apple's progress activity: Print Center's icon at the left
/// end, which opens it; the job's name beside the camera and what's happening to it under that; at
/// the right end the ring, with the square inside it that cancels the job.
struct PrintJobView: View {
    let shown: PrintShown
    let restingHeight: CGFloat
    let camera: CGFloat
    var revealed = true
    var cancel: () -> Void = {}
    var openPrintCenter: () -> Void = {}
    var refresh: () -> Void = {}

    /// Print Center, whose icon the job shows.
    static let app = "com.apple.printcenter"

    static func detail(for shown: PrintShown) -> String { "\(PrintJobGlyph.word(for: shown)) · \(shown.job.displayPrinter)" }

    /// The whole status, and how many more jobs are waiting.
    static func explanation(for shown: PrintShown) -> String {
        var lines = [shown.job.title, "\(shown.status) · \(shown.job.displayPrinter)"]
        if shown.additionalJobs == 1 {
            lines.append(String(localized: "1 More Print Job"))
        } else if shown.additionalJobs > 1 {
            lines.append(String(localized: "\(shown.additionalJobs) More Print Jobs"))
        }
        return lines.joined(separator: "\n")
    }

    /// The ring at the right end, and Try Again before it while the queue can't be read.
    private static func buttons(for shown: PrintShown) -> Int { shown.sourceAvailable ? 1 : 2 }

    @MainActor
    static func width(for shown: PrintShown, restingHeight h: CGFloat, camera: CGFloat) -> CGFloat {
        ActivityRowLayout.width(title: shown.job.title, detail: detail(for: shown), buttons: buttons(for: shown), restingHeight: h, camera: camera)
    }

    static func height(restingHeight h: CGFloat) -> CGFloat { TimerLayout.tallHeight(h) }

    static func controls(for shown: PrintShown) -> [PlayerControl] {
        [.activityFirst] + (!shown.sourceAvailable || shown.canCancel ? [.activitySecond] : [])
    }

    var body: some View {
        let h = restingHeight
        ActivityRow(
            restingHeight: h, camera: camera, width: Self.width(for: shown, restingHeight: h, camera: camera),
            title: shown.job.title, detail: Self.detail(for: shown), explanation: Self.explanation(for: shown),
            buttons: Self.buttons(for: shown), revealed: revealed
        ) {
            TaskAppButton(bundleID: Self.app, fallback: "printer.fill", restingHeight: h, label: String(localized: "Open Print Center"), open: openPrintCenter)
                .accessibilityIdentifier("open-print-center")
        } trailing: {
            trailing(h)
        }
        .accessibilityLabel(shown.spoken)
    }

    @ViewBuilder private func trailing(_ h: CGFloat) -> some View {
        if !shown.sourceAvailable {
            IslandCircleButton(control: .activitySecond, height: h, tint: .white, label: String(localized: "Try Again"), action: refresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: h * 0.55, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityIdentifier("refresh-print-status")
        }
        // Cancels the job while it can be; otherwise, as once it's printed, only how it stands.
        TaskRingButton(
            status: PrintJobGlyph.status(for: shown), control: .activitySecond, height: h,
            label: shown.canRetryCancellation ? String(localized: "Try Canceling Again") : String(localized: "Cancel Print Job"),
            held: shown.cancellation == .pending, interactive: shown.sourceAvailable && (shown.job.canCancel || shown.cancellation == .pending),
            action: cancel
        )
        .disabled(!shown.canCancel)
        .accessibilityIdentifier("cancel-print-job")
    }
}
