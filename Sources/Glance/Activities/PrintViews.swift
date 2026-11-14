//
//  PrintViews.swift
//  Glance
//
//  Created by Gaty on 14/11/2026.
//

import SwiftUI

/// Print state beside the camera. The containing activity supplies its opening action.
struct PrintJobMark: View {
    let shown: PrintShown
    let restingHeight: CGFloat
    var leadingOnly = false
    static let wing: CGFloat = 96

    var body: some View {
        ZStack {
            Image(systemName: "printer.fill")
                .accessibilityHidden(true)
                .frame(width: max(restingHeight - LiveActivityView.inset * 2, 0))
                .frame(maxWidth: .infinity, alignment: .leading)
            if !leadingOnly {
                Text(shown.job.displayPrinter)
                    .lineLimit(1)
                    .frame(width: Self.wing - LiveActivityView.inset * 2, alignment: .trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, LiveActivityView.inset)
        .font(.body)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(shown.spoken)
    }
}

/// The queue's actual state and its two supported actions, using macOS controls throughout.
struct PrintJobView: View {
    let shown: PrintShown
    var cancel: () -> Void = {}
    var openPrintCenter: () -> Void = {}
    var refresh: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static func width(camera: CGFloat) -> CGFloat { max(400, camera + PlayerLayout.padding * 2) }
    static func height(restingHeight: CGFloat) -> CGFloat { restingHeight + LiveActivityView.cameraGap + 230 }

    static func controls(for shown: PrintShown) -> [PlayerControl] {
        [.activityFirst] + (!shown.sourceAvailable || shown.canCancel ? [.activitySecond] : [])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(shown.status, systemImage: "printer.fill")
                .font(.headline)
                .accessibilityIdentifier("print-status")

            VStack(alignment: .leading, spacing: 4) {
                Text(shown.job.title)
                    .font(.body)
                    .lineLimit(2)
                    .help(shown.job.title)
                Text(shown.job.displayPrinter)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(shown.job.displayPrinter)
            }

            if shown.sourceAvailable, shown.cancellation == .idle {
                if let progress = shown.job.progress {
                    ProgressView(value: progress.fraction)
                        .progressViewStyle(.linear)
                        .accessibilityLabel("Printing progress")
                } else if shown.job.state == .printing, !reduceMotion {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Printing")
                }
            }

            if shown.additionalJobs > 0 {
                Text(shown.additionalJobs == 1 ? String(localized: "1 More Print Job") : String(localized: "\(shown.additionalJobs) More Print Jobs"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Open Print Center", action: openPrintCenter)
                    .notchControl()
                    .keyControl(.activityFirst, in: RoundedRectangle(cornerRadius: 6), spoken: String(localized: "Open Print Center"), action: openPrintCenter)
                    .accessibilityIdentifier("open-print-center")
                Spacer(minLength: 8)
                if !shown.sourceAvailable {
                    Button("Try Again", action: refresh)
                        .notchControl()
                        .keyControl(.activitySecond, in: RoundedRectangle(cornerRadius: 6), spoken: String(localized: "Refresh print status"), action: refresh)
                        .help("Refresh print status")
                        .accessibilityIdentifier("refresh-print-status")
                } else {
                    Button(shown.cancellation == .failed ? String(localized: "Try Again") : String(localized: "Cancel Print Job"), role: .destructive, action: cancel)
                        .notchControl()
                        .keyControl(.activitySecond, in: RoundedRectangle(cornerRadius: 6), spoken: String(localized: "Cancel Print Job"), action: cancel)
                        .disabled(!shown.canCancel)
                        .help(shown.cancellation == .failed ? String(localized: "Try canceling this print job again") : String(localized: "Cancel this print job"))
                        .accessibilityIdentifier("cancel-print-job")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(shown.spoken)
    }
}
