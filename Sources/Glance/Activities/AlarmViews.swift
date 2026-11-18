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
    /// The time's and the name's baselines, measured on iOS 27's ringing alarm.
    static let timeBaseline: CGFloat = 49.3 / alert
    static let nameBaseline: CGFloat = 68.7 / alert
    /// The zz's share of its circle.
    static let snoozeGlyph: CGFloat = 25.5 / 50

    /// The clock's ink at the alert's height `h`, as tall as `glyphHeight` of it.
    static func glyphInk(_ h: CGFloat) -> CGFloat { TimerLayout.tallHeight(h) * glyphHeight }
}

/// The alarm clock Clock rings in the Dynamic Island, which isn't `alarm.fill`: a fuller face with
/// thicker hands at nine o'clock, short legs, and two bells apart from the face. Measured from iOS 27
/// in units where the face is 22.45 across its radius, its middle at 0 and up positive. Ringing, as
/// Clock's own does: the whole clock rocks 1.5° either way about a point 28.1 under the face's middle,
/// and each bell slides 2 either way along its own edge, a little blurred, all together, 0.06 seconds
/// each way, eased.
struct AlarmClockGlyph: View {
    /// As tall as its ink, from the higher bell's top to the feet.
    let height: CGFloat
    var tint: Color = AlarmLook.ink
    var ringing = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let face: CGFloat = 22.45
    /// The ink at rest, around the face's middle.
    private static let inkLeft: CGFloat = -22.45, inkRight: CGFloat = 23.55
    private static let inkTop: CGFloat = 27.42, inkBottom: CGFloat = -23.06
    private static var inkHeight: CGFloat { inkTop - inkBottom }
    /// How wide it is for a height.
    static func width(forHeight height: CGFloat) -> CGFloat { height * (inkRight - inkLeft) / inkHeight }

    private static let pivot = CGPoint(x: 0.49, y: -28.11)
    private static let tilt = 1.5 * Double.pi / 180
    private static let swing: TimeInterval = 0.06
    /// Each bell's middle at rest, the way it slides, and the side its flat edge faces.
    private static let bells: [(rest: CGPoint, slide: CGVector, facing: CGVector)] = [
        (CGPoint(x: -15.45, y: 20.73), CGVector(dx: 0.807, dy: 0.5905), CGVector(dx: 0.578, dy: -0.816)),
        (CGPoint(x: 16.86, y: 19.68), CGVector(dx: 0.807, dy: -0.5905), CGVector(dx: -0.578, dy: -0.816)),
    ]
    private static let bellRadius: CGFloat = 6.686
    /// The flat edge, this far past the bell's middle toward the face.
    private static let bellCut: CGFloat = 0.446

    var body: some View {
        let shaking = ringing && !reduceMotion
        TimelineView(.animation(paused: !shaking)) { context in
            // Clock's ease each way: 0 to 1 and back.
            let phase = shaking ? context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.swing * 2) / Self.swing : 0.5
            let u = phase < 1 ? phase : 2 - phase
            let eased = u * u * (3 - 2 * u)
            // Drawn with room around its ink, as the bells slide and blur past where they rest.
            Canvas { canvas, _ in
                draw(in: &canvas, angle: shaking ? Self.tilt * (1 - 2 * eased) : 0, slide: shaking ? CGFloat(4 * eased - 2) : 0, blur: shaking)
            }
            .padding(-Self.margin * height / Self.inkHeight)
        }
        .frame(width: Self.width(forHeight: height), height: height)
        .accessibilityHidden(true)
    }

    /// Room beyond the ink at rest, in the drawing's units.
    private static let margin: CGFloat = 6

    private func draw(in canvas: inout GraphicsContext, angle: Double, slide: CGFloat, blur: Bool) {
        let k = height / Self.inkHeight
        let m = Self.margin
        func at(_ p: CGPoint) -> CGPoint { CGPoint(x: (p.x - Self.inkLeft + m) * k, y: (Self.inkTop - p.y + m) * k) }
        // The whole clock rocks about the point under its feet; drawn upside down from its units, so
        // its turn the other way round.
        let pivot = at(Self.pivot)
        canvas.translateBy(x: pivot.x, y: pivot.y)
        canvas.rotate(by: .radians(-angle))
        canvas.translateBy(x: -pivot.x, y: -pivot.y)
        let shading = GraphicsContext.Shading.color(tint)

        canvas.drawLayer { body in
            let middle = at(.zero)
            let r = Self.face * k
            body.fill(Path(ellipseIn: CGRect(x: middle.x - r, y: middle.y - r, width: 2 * r, height: 2 * r)), with: shading)
            var legs = Path()
            legs.move(to: at(CGPoint(x: -10.13, y: -12.8)))
            legs.addLine(to: at(CGPoint(x: -18.14, y: -20.81)))
            legs.move(to: at(CGPoint(x: 10.1, y: -12.8)))
            legs.addLine(to: at(CGPoint(x: 18.11, y: -20.81)))
            body.stroke(legs, with: shading, style: StrokeStyle(lineWidth: 4.5 * k, lineCap: .round))
            // The hands, cut out at nine o'clock, meeting a little under the middle.
            var hands = Path()
            hands.move(to: at(CGPoint(x: -9.47, y: -1.2)))
            hands.addLine(to: at(CGPoint(x: 0, y: -1.2)))
            hands.move(to: at(CGPoint(x: 0, y: -1.2)))
            hands.addLine(to: at(CGPoint(x: 0, y: 11.54)))
            body.blendMode = .destinationOut
            body.stroke(hands, with: .color(.black), style: StrokeStyle(lineWidth: 4.05 * k, lineCap: .round))
        }

        canvas.drawLayer { bells in
            if blur { bells.addFilter(.blur(radius: k)) }
            for bell in Self.bells {
                let middle = CGPoint(x: bell.rest.x + bell.slide.dx * slide, y: bell.rest.y + bell.slide.dy * slide)
                // A round bell cut flat on the side facing the face, a little past its middle.
                let along = CGVector(dx: -bell.facing.dy, dy: bell.facing.dx)
                let half = sqrt(Self.bellRadius * Self.bellRadius - Self.bellCut * Self.bellCut)
                let cut = CGPoint(x: middle.x + bell.facing.dx * Self.bellCut, y: middle.y + bell.facing.dy * Self.bellCut)
                let from = CGPoint(x: cut.x + along.dx * half, y: cut.y + along.dy * half)
                let to = CGPoint(x: cut.x - along.dx * half, y: cut.y - along.dy * half)
                var path = Path()
                let steps = 40
                let a0 = atan2(from.y - middle.y, from.x - middle.x)
                let a1 = atan2(to.y - middle.y, to.x - middle.x)
                // Round the side away from the face: counterclockwise if that passes it, else the
                // other way.
                let away = atan2(-bell.facing.dy, -bell.facing.dx)
                func turn(_ x: Double) -> Double { let r = x.truncatingRemainder(dividingBy: 2 * .pi); return r < 0 ? r + 2 * .pi : r }
                let sweep = turn(away - a0) <= turn(a1 - a0) ? turn(a1 - a0) : turn(a1 - a0) - 2 * .pi
                for i in 0...steps {
                    let a = a0 + sweep * Double(i) / Double(steps)
                    let p = at(CGPoint(x: middle.x + Self.bellRadius * cos(a), y: middle.y + Self.bellRadius * sin(a)))
                    if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
                }
                path.closeSubpath()
                bells.fill(path, with: shading)
            }
        }
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
                AlarmClockGlyph(height: restingHeight * 0.5, tint: tint, ringing: shown.pending == nil)
            } else {
                CompactActivityMark(caption: shown.alarm.title, captionColor: tint, restingHeight: restingHeight, leadingOnly: leadingOnly) {
                    AlarmClockGlyph(height: LiveActivityView.textSize(for: restingHeight) + 2, tint: tint, ringing: shown.pending == nil)
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

    /// What shows above the name: what's happening to it, or the time it rang; and the name, or Alarm
    /// for one without, whose title is its time.
    static func lines(for shown: AlarmShown, rangAt: Date) -> (top: String, name: String) {
        let status: String? =
            if !shown.sourceAvailable { String(localized: "Status unavailable") }
            else if let pending = shown.pending { pending.progress }
            else if shown.failure != nil { String(localized: "Not confirmed") }
            else { nil }
        let titleIsTime = shown.alarm.title.range(of: #"^\d{1,2}[:.h]\d{2}"#, options: .regularExpression) != nil
        let time = shown.alarm.time ?? (titleIsTime ? shown.alarm.title : rangAt.formatted(date: .omitted, time: .shortened))
        return (status ?? time, titleIsTime ? String(localized: "Alarm") : shown.alarm.title)
    }

    @MainActor
    private static func textWidth(_ text: String, size: CGFloat, weight: NSFont.Weight) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight)]).width) + 1
    }

    private static func buttonsWidth(_ h: CGFloat) -> CGFloat { TimerLayout.circle(h) * 2 + TimerLayout.circleGap(h) }

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
        let left = tall * AlarmLook.glyphEdge + AlarmClockGlyph.width(forHeight: AlarmLook.glyphInk(h)) + gap
        let right = gap + buttonsWidth(h) + TimerLayout.circleEdge(h)
        let across = tall * AlarmLook.wordsStart + words + TimerLayout.circleGap(h) + buttonsWidth(h) + TimerLayout.circleEdge(h)
        return max(left, right, (across - closedWidth) / 2)
    }

    var body: some View {
        let h = restingHeight
        let tall = TimerLayout.tallHeight(h)
        let lines = Self.lines(for: shown, rangAt: rangAt)
        ZStack(alignment: .topLeading) {
            glyph(h)
                .padding(.leading, tall * AlarmLook.glyphEdge)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            // Each line on the iPhone's baseline, from the row's top, running on under the camera up
            // to the buttons.
            Color.clear
                .frame(width: max(width - tall * AlarmLook.wordsStart - TimerLayout.circleGap(h) - Self.buttonsWidth(h) - TimerLayout.circleEdge(h), 0), height: tall)
                .overlay(alignment: .topLeading) {
                    Text(lines.top)
                        .font(.system(size: tall * AlarmLook.timeSize))
                        .foregroundStyle(AlarmLook.ink.opacity(0.5))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .alignmentGuide(.top) { $0[.firstTextBaseline] - tall * AlarmLook.timeBaseline }
                }
                .overlay(alignment: .topLeading) {
                    Text(lines.name)
                        .font(.system(size: tall * AlarmLook.titleSize, weight: .medium))
                        .foregroundStyle(AlarmLook.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .alignmentGuide(.top) { $0[.firstTextBaseline] - tall * AlarmLook.nameBaseline }
                }
            .padding(.leading, tall * AlarmLook.wordsStart)
            .help(shown.failure ?? shown.spoken)
            .accessibilityElement(children: .combine)
            .accessibilityHint(shown.failure ?? "")
            buttons(h)
                .padding(.trailing, TimerLayout.circleEdge(h))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        }
        .frame(width: width, height: tall)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(shown.spoken)
    }

    @ViewBuilder private func glyph(_ h: CGFloat) -> some View {
        let symbol = AlarmClockGlyph(height: AlarmLook.glyphInk(h), ringing: shown.pending == nil)
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
            .font(.system(size: TimerLayout.circle(h) * AlarmLook.snoozeGlyph, weight: .semibold))
            .foregroundStyle(AlarmLook.ink)
    }

    @ViewBuilder private func buttons(_ h: CGFloat) -> some View {
        let snoozes = shown.alarm.actions.contains(.snooze), stops = shown.alarm.actions.contains(.stop)
        HStack(spacing: TimerLayout.circleGap(h)) {
            switch mode {
            case .alert(let hovered):
                if snoozes {
                    IslandCircle(height: h, tint: AlarmLook.ink, highlighted: hovered == .snooze && shown.canPerform(.snooze), side: TimerLayout.circle(h)) { snoozeGlyph(h) }
                        .reportsFrame(.snooze)
                        .spokenButton(String(localized: "Snooze")) { AlarmActivity.shared.perform(.snooze, expectedID: shown.alarm.id) }
                        .opacity(shown.canPerform(.snooze) ? 1 : 0.45)
                }
                if stops {
                    IslandCircle(height: h, tint: .white, highlighted: hovered == .alarmStop && shown.canPerform(.stop), side: TimerLayout.circle(h)) { CrossGlyph(height: h) }
                        .reportsFrame(.alarmStop)
                        .spokenButton(String(localized: "Stop")) { AlarmActivity.shared.perform(.stop, expectedID: shown.alarm.id) }
                        .opacity(shown.canPerform(.stop) ? 1 : 0.45)
                }
            case .open(let perform, _):
                if snoozes {
                    IslandCircleButton(control: .activitySecond, height: h, tint: AlarmLook.ink, label: String(localized: "Snooze"), side: TimerLayout.circle(h)) {
                        perform(.snooze, shown.alarm.id)
                    } glyph: {
                        snoozeGlyph(h)
                    }
                    .disabled(!shown.canPerform(.snooze))
                    .opacity(shown.canPerform(.snooze) ? 1 : 0.45)
                    .accessibilityIdentifier("snooze-alarm")
                }
                if stops {
                    IslandCircleButton(control: .activityThird, height: h, tint: .white, label: String(localized: "Stop"), side: TimerLayout.circle(h)) {
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
