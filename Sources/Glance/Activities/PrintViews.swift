//
//  PrintViews.swift
//  Glance
//
//  Created by Gaty on 14/11/2026.
//

import AppKit
import SwiftUI

/// A print job beside the camera: how far it's got at the left end, as a ring, and at the right end
/// the share printed, or what's become of it.
struct PrintJobMark: View {
    let shown: PrintShown
    let restingHeight: CGFloat
    var leadingOnly = false

    @MainActor
    static func wing(for shown: PrintShown, restingHeight: CGFloat) -> CGFloat {
        CompactActivityLayout.wing(caption: PrintJobGlyph.caption(for: shown), restingHeight: restingHeight)
    }

    var body: some View {
        CompactActivityMark(caption: PrintJobGlyph.caption(for: shown), restingHeight: restingHeight, leadingOnly: leadingOnly) {
            PrintJobGlyph(shown: shown, restingHeight: restingHeight)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(shown.spoken)
        .help(shown.spoken)
    }
}

/// The same mark beside the camera and in the bubble: a ring filling as the pages print, a spinner
/// while it prints with nothing to count, or a symbol for what's become of it.
struct PrintJobGlyph: View {
    let shown: PrintShown
    var minimal = false
    var restingHeight: CGFloat = 32
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static func symbol(for shown: PrintShown) -> String {
        if !shown.sourceAvailable { return "questionmark.circle" }
        if shown.cancellation == .pending { return "stop.circle" }
        if shown.cancellation == .unconfirmed { return "questionmark.circle" }
        if shown.cancellation == .failed || shown.openFailed { return "exclamationmark.triangle.fill" }
        switch shown.job.state {
        case .queued: return "clock"
        case .held: return "pause.circle.fill"
        case .printing: return "printer.fill"
        case .stopped: return "stop.circle.fill"
        case .canceled: return "minus.circle"
        case .failed: return "xmark.circle.fill"
        case .completed: return "checkmark.circle.fill"
        }
    }

    /// Printing with a count, the share done; otherwise a word for its state.
    static func caption(for shown: PrintShown) -> String {
        if let progress = counting(shown) { return progress.fraction.formatted(.percent.precision(.fractionLength(0))) }
        return word(for: shown)
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

    /// The pages printed of how many, while it prints and nothing's gone wrong.
    static func counting(_ shown: PrintShown) -> PrintJob.Progress? {
        guard shown.sourceAvailable, shown.cancellation == .idle, !shown.openFailed, shown.job.state == .printing else { return nil }
        return shown.job.progress
    }

    var body: some View {
        let h = restingHeight
        Group {
            if let progress = Self.counting(shown) {
                ProgressRing(fraction: progress.fraction, diameter: h * TimerLayout.ring, line: h * AirDropLayout.ringLine)
            } else if Self.counting(shown) == nil, shown.sourceAvailable, shown.cancellation == .idle, !shown.openFailed,
                shown.job.state == .printing, !reduceMotion
            {
                ProgressView().controlSize(.small).tint(.white)
            } else {
                Image(systemName: Self.symbol(for: shown))
                    .font(.system(size: minimal ? h * 0.5 : LiveActivityView.textSize(for: h) + 2, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .accessibilityHidden(true)
    }
}

/// A print job opened, in one row: the printer at the left end opens Print Center; the job's name
/// beside the camera and what's happening to it under that; at the right end, the ✕ that cancels it,
/// in the ring of how far it's got, as AirDrop's stop is.
struct PrintJobView: View {
    let shown: PrintShown
    let restingHeight: CGFloat
    let camera: CGFloat
    var revealed = true
    var cancel: () -> Void = {}
    var openPrintCenter: () -> Void = {}
    var refresh: () -> Void = {}

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

    /// Something at the right end: a button, or the ring alone when the job can't be canceled.
    private static func buttons(for shown: PrintShown) -> Int {
        !shown.sourceAvailable || shown.job.canCancel || shown.cancellation != .idle || shown.job.progress != nil ? 1 : 0
    }

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
            ActivityRowPicture(restingHeight: h, label: String(localized: "Open Print Center"), open: openPrintCenter) {
                Image(systemName: "printer.fill")
                    .font(.system(size: h * 0.55, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityIdentifier("open-print-center")
        } trailing: {
            trailing(h)
        }
        .accessibilityLabel(shown.spoken)
    }

    @ViewBuilder private func trailing(_ h: CGFloat) -> some View {
        let side = TimerLayout.content(h)
        if !shown.sourceAvailable {
            IslandCircleButton(control: .activitySecond, height: h, tint: .white, label: String(localized: "Try Again"), action: refresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: h * 0.55, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityIdentifier("refresh-print-status")
        } else if shown.canRetryCancellation, shown.canCancel {
            IslandCircleButton(control: .activitySecond, height: h, tint: .white, label: String(localized: "Try Canceling Again"), action: cancel) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: h * 0.55, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityIdentifier("cancel-print-job")
        } else if shown.job.canCancel || shown.cancellation == .pending {
            IslandCircleButton(control: .activitySecond, height: h, tint: .white, label: String(localized: "Cancel Print Job"), action: cancel) {
                ZStack {
                    if let progress = shown.job.progress {
                        ProgressRing(fraction: progress.fraction, diameter: side, line: h * AirDropLayout.bigRingLine)
                    }
                    CrossGlyph(height: h)
                }
            }
            .disabled(!shown.canCancel)
            .opacity(shown.canCancel ? 1 : 0.45)
            .accessibilityValue(shown.job.progress.map { $0.fraction.formatted(.percent.precision(.fractionLength(0))) } ?? "")
            .accessibilityIdentifier("cancel-print-job")
        } else if let progress = shown.job.progress {
            ProgressRing(fraction: progress.fraction, diameter: side, line: h * AirDropLayout.bigRingLine)
        }
    }
}
