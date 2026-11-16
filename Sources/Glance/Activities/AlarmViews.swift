//
//  AlarmViews.swift
//  Glance
//
//  Created by Gaty on 14/11/2026.
//

import AppKit
import SwiftUI

/// A ringing alarm, as iOS 27's Clock draws it in the Dynamic Island, measured from the iPhone 18 Pro
/// simulator ringing a Clock alarm over another app: an 87.7 point alert, the clock 45.7 tall in Clock's
/// orange and shaking, 25.7 in from the end; the time, 13.5 point in the orange at half, above the
/// alarm's name, 16.5 point, both 83 in; Snooze, the orange at 0.35 with its zz half the circle, and
/// Stop, white at 0.2 with a white ✕, at the other end. Everything here is by the alert's height, so it
/// keeps those proportions at the notch's.
enum AlarmLook {
    /// Clock's orange as iOS 27 draws its alarm, #FF9230 (sRGB).
    static let ink = Color(.sRGB, red: 1, green: 146 / 255, blue: 48 / 255)
    private static let alert: CGFloat = 87.7
    /// The clock's ink, as tall as this share of the alert, and as far in from its end.
    static let glyphHeight: CGFloat = 45.7 / alert
    static let glyphEdge: CGFloat = 25.7 / alert
    /// Where the words start, from the end.
    static let wordsStart: CGFloat = 83 / alert
    static let timeSize: CGFloat = 13.5 / alert
    static let titleSize: CGFloat = 16.5 / alert
    /// The time's capitals start this far down.
    static let timeTop: CGFloat = 39 / alert
    /// The zz's share of its circle.
    static let snoozeGlyph: CGFloat = 25.5 / 50
    /// `alarm.fill`'s ink is a little taller and narrower than its point size.
    static let glyphInkPerPoint: (width: CGFloat, height: CGFloat) = (0.93, 1.005)

    static func glyphSize(_ h: CGFloat) -> CGFloat { TimerLayout.tallHeight(h) * glyphHeight / glyphInkPerPoint.height }

    /// The room the symbol keeps either side of its ink, so the ink, not the symbol's box, sits at
    /// `glyphEdge`.
    @MainActor
    static func glyphBearing(_ h: CGFloat) -> CGFloat {
        let size = glyphSize(h)
        guard let image = NSImage(systemSymbolName: "alarm.fill", accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: size, weight: .regular))
        else { return 0 }
        return max((image.size.width - size * glyphInkPerPoint.width) / 2, 0)
    }
}

/// A ringing alarm beside the camera, in Clock's orange: the alarm at the left end, its name at the
/// right; in the bubble, the alarm alone. macOS 27.3's menu bar shows it the same way.
struct AlarmCompactView: View {
    let shown: AlarmShown
    var minimal = false
    var leadingOnly = false
    var restingHeight: CGFloat = 32

    private var tint: Color { shown.sourceAvailable ? AlarmLook.ink : NotchType.detailColor }

    @MainActor
    static func wing(for shown: AlarmShown, restingHeight: CGFloat) -> CGFloat {
        CompactActivityLayout.wing(caption: shown.alarm.title, restingHeight: restingHeight)
    }

    var body: some View {
        Group {
            if minimal {
                Image(systemName: "alarm.fill")
                    .font(.system(size: restingHeight * 0.5, weight: .semibold))
                    .foregroundStyle(tint)
            } else {
                CompactActivityMark(caption: shown.alarm.title, captionColor: tint, restingHeight: restingHeight, leadingOnly: leadingOnly) {
                    Image(systemName: "alarm.fill")
                        .font(.system(size: LiveActivityView.textSize(for: restingHeight) + 2, weight: .semibold))
                        .foregroundStyle(tint)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(shown.spoken)
    }
}

/// The ringing alarm itself (see `AlarmLook`), the same in the closed notch, where it comes in by
/// itself as the iPhone's does, and in the open notch. Closed, its buttons are pressed where they
/// are, as a done timer's are; open, they're buttons the keys reach, and the clock opens Clock.
struct AlarmRingingView: View {
    enum Mode {
        case alert(hovered: AlertButton?)
        case open(perform: (AlarmActivity.Action, String) -> Void, openClock: () -> Void)
    }

    let shown: AlarmShown
    let restingHeight: CGFloat
    let width: CGFloat
    let mode: Mode
    /// When it started ringing, which the time above its name says.
    var rangAt: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// What shows above the name: what's happening to it, or the time it rang; and the name, or Alarm
    /// for one without, whose title is its time.
    static func lines(for shown: AlarmShown, rangAt: Date) -> (top: String, name: String) {
        let status: String? =
            if !shown.sourceAvailable { String(localized: "Status unavailable") }
            else if let pending = shown.pending { pending.progress }
            else if shown.failure != nil { String(localized: "Not confirmed") }
            else { nil }
        let titleIsTime = shown.alarm.title.range(of: #"^\d{1,2}[:.h]\d{2}"#, options: .regularExpression) != nil
        let time = titleIsTime ? shown.alarm.title : rangAt.formatted(date: .omitted, time: .shortened)
        return (status ?? time, titleIsTime ? String(localized: "Alarm") : shown.alarm.title)
    }

    @MainActor
    private static func textWidth(_ text: String, size: CGFloat, weight: NSFont.Weight) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight)]).width) + 1
    }

    private static func buttonsWidth(_ h: CGFloat) -> CGFloat { TimerLayout.content(h) * 2 + h * TimerLayout.buttonGap }

    /// Each side of the camera: room for the clock beside it on the left and the two buttons on the
    /// right, each from its end, and for the words under it to reach the buttons.
    @MainActor
    static func wing(for shown: AlarmShown, rangAt: Date = .now, restingHeight h: CGFloat, closedWidth: CGFloat) -> CGFloat {
        let tall = TimerLayout.tallHeight(h)
        let gap = LiveActivityView.cameraGap
        let lines = lines(for: shown, rangAt: rangAt)
        let words = min(
            max(textWidth(lines.top, size: tall * AlarmLook.timeSize, weight: .regular), textWidth(lines.name, size: tall * AlarmLook.titleSize, weight: .medium)),
            h * TimerLayout.titleLimit)
        let left = tall * AlarmLook.glyphEdge + AlarmLook.glyphSize(h) * AlarmLook.glyphInkPerPoint.width + gap
        let right = gap + buttonsWidth(h) + TimerLayout.buttonEdge(h)
        let across = tall * AlarmLook.wordsStart + words + h * TimerLayout.buttonGap + buttonsWidth(h) + TimerLayout.buttonEdge(h)
        return max(left, right, (across - closedWidth) / 2)
    }

    var body: some View {
        let h = restingHeight
        let tall = TimerLayout.tallHeight(h)
        let lines = Self.lines(for: shown, rangAt: rangAt)
        let timeFont = NSFont.systemFont(ofSize: tall * AlarmLook.timeSize)
        // The time's line starts above its capitals by the font's ascent over them.
        let wordsTop = tall * AlarmLook.timeTop - (timeFont.ascender - timeFont.capHeight)
        ZStack(alignment: .topLeading) {
            glyph(h)
                .padding(.leading, tall * AlarmLook.glyphEdge - AlarmLook.glyphBearing(h))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
                Text(lines.top)
                    .font(.system(size: tall * AlarmLook.timeSize))
                    .foregroundStyle(AlarmLook.ink.opacity(0.5))
                Text(lines.name)
                    .font(.system(size: tall * AlarmLook.titleSize, weight: .medium))
                    .foregroundStyle(AlarmLook.ink)
            }
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: max(width - tall * AlarmLook.wordsStart - h * TimerLayout.buttonGap - Self.buttonsWidth(h) - TimerLayout.buttonEdge(h), 0), alignment: .leading)
            .padding(.leading, tall * AlarmLook.wordsStart)
            .padding(.top, wordsTop)
            .help(shown.failure ?? shown.spoken)
            .accessibilityElement(children: .combine)
            .accessibilityHint(shown.failure ?? "")
            buttons(h)
                .padding(.trailing, TimerLayout.buttonEdge(h))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        }
        .frame(width: width, height: tall)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(shown.spoken)
    }

    @ViewBuilder private func glyph(_ h: CGFloat) -> some View {
        let symbol = Image(systemName: "alarm.fill")
            .font(.system(size: AlarmLook.glyphSize(h)))
            .foregroundStyle(AlarmLook.ink)
            .symbolEffect(.wiggle, options: .repeat(.continuous), isActive: !reduceMotion && shown.pending == nil)
        switch mode {
        case .alert:
            symbol.accessibilityHidden(true)
        case .open(_, let openClock):
            Button(action: openClock) { symbol.contentShape(Rectangle()) }
                .buttonStyle(IslandPress(highlight: false, contactSize: nil))
                .notchControl()
                .keyControl(.activityFirst, in: Circle(), outset: CGSize(width: 3, height: 3), spoken: String(localized: "Open Clock"), action: openClock)
                .help(String(localized: "Open Clock"))
                .accessibilityLabel(String(localized: "Open Clock"))
                .accessibilityIdentifier("open-alarm-clock")
        }
    }

    private func snoozeGlyph(_ h: CGFloat) -> some View {
        Image(systemName: "zzz")
            .font(.system(size: TimerLayout.content(h) * AlarmLook.snoozeGlyph, weight: .semibold))
            .foregroundStyle(AlarmLook.ink)
    }

    @ViewBuilder private func buttons(_ h: CGFloat) -> some View {
        let snoozes = shown.alarm.actions.contains(.snooze), stops = shown.alarm.actions.contains(.stop)
        HStack(spacing: h * TimerLayout.buttonGap) {
            switch mode {
            case .alert(let hovered):
                if snoozes {
                    IslandCircle(height: h, tint: AlarmLook.ink, highlighted: hovered == .snooze && shown.canPerform(.snooze)) { snoozeGlyph(h) }
                        .reportsFrame(.snooze)
                        .spokenButton(String(localized: "Snooze")) { AlarmActivity.shared.perform(.snooze, expectedID: shown.alarm.id) }
                        .opacity(shown.canPerform(.snooze) ? 1 : 0.45)
                }
                if stops {
                    IslandCircle(height: h, tint: .white, highlighted: hovered == .alarmStop && shown.canPerform(.stop)) { CrossGlyph(height: h) }
                        .reportsFrame(.alarmStop)
                        .spokenButton(String(localized: "Stop")) { AlarmActivity.shared.perform(.stop, expectedID: shown.alarm.id) }
                        .opacity(shown.canPerform(.stop) ? 1 : 0.45)
                }
            case .open(let perform, _):
                if snoozes {
                    IslandCircleButton(control: .activitySecond, height: h, tint: AlarmLook.ink, label: String(localized: "Snooze")) {
                        perform(.snooze, shown.alarm.id)
                    } glyph: {
                        snoozeGlyph(h)
                    }
                    .disabled(!shown.canPerform(.snooze))
                    .opacity(shown.canPerform(.snooze) ? 1 : 0.45)
                    .accessibilityIdentifier("snooze-alarm")
                }
                if stops {
                    IslandCircleButton(control: .activityThird, height: h, tint: .white, label: String(localized: "Stop")) {
                        perform(.stop, shown.alarm.id)
                    } glyph: {
                        CrossGlyph(height: h)
                    }
                    .disabled(!shown.canPerform(.stop))
                    .opacity(shown.canPerform(.stop) ? 1 : 0.45)
                    .accessibilityIdentifier("stop-alarm")
                }
            }
        }
    }
}

/// A ringing alarm in the open notch: the same alert, as wide and as tall, so opening onto it changes
/// nothing but what the keys reach. Pure presentation plus supplied actions, so Settings' previews
/// can't command the real alarm.
struct AlarmActivityView: View {
    let shown: AlarmShown
    let restingHeight: CGFloat
    let camera: CGFloat
    var revealed = true
    var perform: (AlarmActivity.Action, String) -> Void = { _, _ in }
    var openClock: () -> Void = {}
    @State private var rangAt = Date.now

    static func detail(for shown: AlarmShown) -> String {
        if !shown.sourceAvailable { return String(localized: "Status unavailable") }
        if let pending = shown.pending { return pending.progress }
        if shown.failure != nil { return String(localized: "Not confirmed") }
        return String(localized: "Alarm")
    }

    @MainActor
    static func width(for shown: AlarmShown, restingHeight h: CGFloat, camera: CGFloat) -> CGFloat {
        camera + 2 * AlarmRingingView.wing(for: shown, restingHeight: h, closedWidth: camera)
    }

    static func height(restingHeight h: CGFloat) -> CGFloat { TimerLayout.tallHeight(h) }

    /// In the order they stand: Clock at the left, then Snooze and Stop.
    static func controls(for shown: AlarmShown) -> [PlayerControl] {
        [.activityFirst] + (shown.canPerform(.snooze) ? [.activitySecond] : []) + (shown.canPerform(.stop) ? [.activityThird] : [])
    }

    var body: some View {
        AlarmRingingView(
            shown: shown, restingHeight: restingHeight, width: Self.width(for: shown, restingHeight: restingHeight, camera: camera),
            mode: .open(perform: perform, openClock: openClock), rangAt: shown.rangAt ?? rangAt
        )
        .modifier(IslandReveal(hidden: !revealed))
    }
}
