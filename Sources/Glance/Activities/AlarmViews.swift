//
//  AlarmViews.swift
//  Glance
//
//  Created by Gaty on 14/11/2026.
//

import SwiftUI

struct AlarmCompactView: View {
    let shown: AlarmShown
    var minimal = false
    var leadingOnly = false
    var restingHeight: CGFloat = 32
    static let wing: CGFloat = 104

    var body: some View {
        Group {
            if minimal {
                Image(systemName: "alarm.fill")
            } else {
                ZStack {
                    Image(systemName: "alarm.fill")
                        .frame(width: max(restingHeight - LiveActivityView.inset * 2, 0))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !leadingOnly {
                        Text(shown.alarm.title)
                            .lineLimit(1)
                            .frame(width: Self.wing - LiveActivityView.inset * 2, alignment: .trailing)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .padding(.horizontal, LiveActivityView.inset)
            }
        }
        .font(.body)
        .foregroundStyle(shown.sourceAvailable ? .primary : .secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(shown.spoken)
    }
}

/// Pure presentation plus supplied actions: Settings previews cannot command the live alarm.
struct AlarmActivityView: View {
    let shown: AlarmShown
    var perform: (AlarmActivity.Action, String) -> Void = { _, _ in }
    var openClock: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static func width(camera: CGFloat) -> CGFloat { max(400, camera + PlayerLayout.padding * 2) }
    static func height(restingHeight: CGFloat) -> CGFloat { restingHeight + LiveActivityView.cameraGap + 200 }

    static func controls(for shown: AlarmShown) -> [PlayerControl] {
        (shown.canPerform(.snooze) ? [.activityFirst] : [])
            + (shown.canPerform(.stop) ? [.activitySecond] : []) + [.activityThird]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text(shown.alarm.title)
                        .font(.headline)
                        .lineLimit(2)
                        .help(shown.alarm.title)
                    Text(shown.sourceAvailable ? String(localized: "Alarm") : String(localized: "Alarm status unavailable"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "alarm.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            if let pending = shown.pending {
                if reduceMotion {
                    Text(pending.progress).font(.callout).foregroundStyle(.secondary)
                } else {
                    ProgressView(pending.progress).controlSize(.small)
                }
            } else if let failure = shown.failure {
                Text(failure)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if shown.alarm.actions.contains(.snooze) {
                    Button("Snooze", systemImage: "zzz") { perform(.snooze, shown.alarm.id) }
                        .buttonStyle(.borderedProminent)
                        .notchControl()
                        .keyControl(.activityFirst, in: RoundedRectangle(cornerRadius: 6), spoken: String(localized: "Snooze Alarm")) { perform(.snooze, shown.alarm.id) }
                        .disabled(!shown.canPerform(.snooze))
                        .accessibilityIdentifier("snooze-alarm")
                }
                if shown.alarm.actions.contains(.stop) {
                    Button("Stop", systemImage: "stop.fill") { perform(.stop, shown.alarm.id) }
                        .buttonStyle(.bordered)
                        .notchControl()
                        .keyControl(.activitySecond, in: RoundedRectangle(cornerRadius: 6), spoken: String(localized: "Stop Alarm")) { perform(.stop, shown.alarm.id) }
                        .disabled(!shown.canPerform(.stop))
                        .accessibilityIdentifier("stop-alarm")
                }
                Spacer(minLength: 8)
                Button("Open Clock", systemImage: "arrow.up.forward.app", action: openClock)
                    .buttonStyle(.bordered)
                    .notchControl()
                    .keyControl(.activityThird, in: RoundedRectangle(cornerRadius: 6), spoken: String(localized: "Open Clock"), action: openClock)
                    .accessibilityIdentifier("open-alarm-clock")
            }
            .controlSize(.regular)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(shown.spoken)
    }
}
