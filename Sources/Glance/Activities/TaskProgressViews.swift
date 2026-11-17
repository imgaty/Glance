//
//  TaskProgressViews.swift
//  Glance
//
//  Created by Gaty on 16/11/2026.
//

import AppKit
import SwiftUI

/// How a task stands, as iOS 27's system progress activity shows it, the one the iPhone puts up for
/// work an app goes on with in the background: a ring filling as it goes, or an arc going round when
/// there's nothing to count; a check when it's done, an exclamation mark when it failed. Glance adds
/// one Apple has no need of, as its activity closes when you stop it: the stop square, kept, once
/// you have.
struct TaskStatus: Equatable {
    enum Outcome: Equatable { case working, done, failed, stopped }

    var outcome: Outcome
    /// How far it's got, when that can be counted.
    var fraction: Double?

    static let working = TaskStatus(outcome: .working)
    static let done = TaskStatus(outcome: .done)
    static let failed = TaskStatus(outcome: .failed)
    static let stopped = TaskStatus(outcome: .stopped)
    static func counting(_ fraction: Double) -> TaskStatus { TaskStatus(outcome: .working, fraction: fraction) }

    var over: Bool { outcome != .working }
    /// Going on with nothing to count: the arc going round.
    var spinning: Bool { outcome == .working && fraction == nil }
}

/// The ring and its marks, measured from Apple's own drawing of them (`activity-progress.ca` in
/// iOS 27's ActivityProgressUI, a 50-point square), all by the ring's outside diameter beside the
/// camera. Opened, the line is thinner and a stop square sits inside it; once over, thinner still,
/// and the square blurs away as the check or the exclamation mark springs in.
enum TaskRingLook {
    /// The middle of the line, from the middle.
    static let radius: CGFloat = 0.4435
    static let line: CGFloat = 0.1149
    static let openLine: CGFloat = 0.0965
    static let overLine: CGFloat = 0.0781
    static let openOverLine: CGFloat = 0.0567
    /// The track, white at a fifth, as Apple's; in a task's own color, that color at 36.5%, as
    /// Shortcuts' ring measured in iOS 27's simulator, where it stays under the arc going round.
    static let track: Double = 0.2
    static let tintedTrack: Double = 0.365
    /// The arc going round: most of a turn, once every two seconds.
    static let arc: CGFloat = 0.78
    static let turn: TimeInterval = 2
    /// The stop square and its rounding.
    static let stop: CGFloat = 0.338
    static let stopCorner: CGFloat = 0.0915
    /// The check's line beside the camera and opened.
    static let checkLine: CGFloat = 0.0821
    static let openCheckLine: CGFloat = 0.0734
    /// How small the check and the exclamation mark start, and how blurred, as they spring in.
    static let markStart: CGFloat = 1 / 2.405
    static let checkBlur: CGFloat = 0.106
    static let exclamationBlur: CGFloat = 0.294
    static let stopBlur: CGFloat = 0.168
    /// Pressed, the ring shrinks to this and fades to half; the square more, to about a third.
    static let pressedRing: CGFloat = 0.842
    static let pressedRingOpacity: Double = 0.5
    static let pressedStop: CGFloat = 0.714
    static let pressedStopOpacity: Double = 0.357

    /// Apple's one spring for all of it: mass 2, stiffness 300, damping 50, settling without a bounce.
    static let settle = Animation.spring(response: 0.513, dampingFraction: 1)
    /// The check's and the exclamation mark's growing in: the same spring at damping 20, so it bounces.
    static let pop = Animation.spring(response: 0.513, dampingFraction: 0.408)
    /// The exclamation mark drawing down to its dot.
    static let draw = Animation.spring(response: 0.544, dampingFraction: 1)

    /// The check, from the ring's middle, by its outside diameter, y down: the short stroke down to
    /// a rounded corner, the long one up to the right.
    static let checkStart = CGPoint(x: -0.1963, y: 0.0215)
    static let checkCorner = CGPoint(x: -0.0947, y: 0.1521)
    static let checkBend = CGPoint(x: -0.0571, y: 0.1913)
    static let checkTurn = CGPoint(x: -0.022, y: 0.1391)
    static let checkEnd = CGPoint(x: 0.178, y: -0.17)

    /// The exclamation mark: a bar narrowing toward its dot, both ends round, and the dot a little
    /// wider than tall.
    static let barTop: CGFloat = -0.2473
    static let barBottom: CGFloat = 0.0741
    static let barTopWidth: CGFloat = 0.0948
    static let barBottomWidth: CGFloat = 0.0796
    static let dotMiddle: CGFloat = 0.1822
    static let dot = CGSize(width: 0.1015, height: 0.0944)
}

/// The ring, at its outside diameter: beside the camera and in the bubble its lines are heavier;
/// opened, it's the button that stops the task, the square inside it.
struct TaskRing: View {
    let status: TaskStatus
    let diameter: CGFloat
    var opened = false
    var pressed = false
    /// The task's own color, as Shortcuts gives each shortcut's: the ring, the arc and the square
    /// in it, the track the color at 36.5%, kept under the arc going round. Once over, white, as
    /// Apple's turns. Without it, white on a white track at a fifth, the track gone while it spins.
    var tint: Color? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let d = diameter
        let look = TaskRingLook.self
        let line = d * (status.over ? (opened ? look.openOverLine : look.overLine) : (opened ? look.openLine : look.line))
        let ring = 2 * d * look.radius
        let fill = status.outcome == .done ? 1 : status.fraction ?? 0
        let settle = reduceMotion ? nil : look.settle
        let ink = status.over ? Color.white : tint ?? .white
        let track = tint.map { $0.opacity(look.tintedTrack) } ?? .white.opacity(look.track)
        ZStack {
            ZStack {
                Circle().stroke(track, lineWidth: line)
                    .opacity(status.spinning && tint == nil ? 0 : 1)
                Circle()
                    .trim(from: 0, to: max(min(fill, 1), 0))
                    .stroke(ink, style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .opacity(status.spinning ? 0 : 1)
                    .animation(reduceMotion ? nil : .linear(duration: 0.15), value: fill)
                    .animation(settle, value: status.over)
                TaskSpinner(line: line, shown: status.spinning, ink: ink)
            }
            .frame(width: ring, height: ring)
            .animation(settle, value: line)
            .scaleEffect(pressed && !reduceMotion ? look.pressedRing : 1)
            .opacity(pressed ? look.pressedRingOpacity : 1)
            let square = opened && !(status.outcome == .done || status.outcome == .failed) || status.outcome == .stopped
            RoundedRectangle(cornerRadius: d * look.stopCorner, style: .continuous)
                .fill(status.outcome == .stopped ? .white : tint ?? .white)
                .frame(width: d * look.stop, height: d * look.stop)
                .scaleEffect(pressed && !reduceMotion ? look.pressedStop : 1)
                .opacity(pressed ? look.pressedStopOpacity : 1)
                .blur(radius: square || reduceMotion ? 0 : d * look.stopBlur)
                .opacity(square ? 1 : 0)
                .animation(settle, value: square)
            TaskCheck(diameter: d, line: d * (opened ? look.openCheckLine : look.checkLine), shown: status.outcome == .done)
            TaskExclamation(diameter: d, shown: status.outcome == .failed)
        }
        .animation(reduceMotion ? nil : look.settle, value: pressed)
        .frame(width: d, height: d)
        .accessibilityHidden(true)
    }
}

/// The arc going round while there's nothing to count.
private struct TaskSpinner: View {
    let line: CGFloat
    let shown: Bool
    var ink: Color = .white
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: !shown || reduceMotion)) { context in
            let turn = TaskRingLook.turn
            let angle = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: turn) / turn * 360
            Circle()
                .trim(from: 0, to: TaskRingLook.arc)
                .stroke(ink, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(180 + angle))
        }
        .opacity(shown ? 1 : 0)
        .animation(reduceMotion ? nil : TaskRingLook.settle, value: shown)
    }
}

/// The check, drawn out from its short end as it grows in with a bounce.
private struct TaskCheck: View {
    let diameter: CGFloat
    let line: CGFloat
    let shown: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let d = diameter
        let look = TaskRingLook.self
        let point = { (p: CGPoint) in CGPoint(x: d / 2 + p.x * d, y: d / 2 + p.y * d) }
        Path { path in
            path.move(to: point(look.checkStart))
            path.addLine(to: point(look.checkCorner))
            path.addQuadCurve(to: point(look.checkTurn), control: point(look.checkBend))
            path.addLine(to: point(look.checkEnd))
        }
        .trim(from: 0, to: shown || reduceMotion ? 1 : 0)
        .stroke(.white, style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round))
        .animation(reduceMotion ? nil : look.settle, value: shown)
        .scaleEffect(shown || reduceMotion ? 1 : look.markStart)
        .animation(reduceMotion ? nil : look.pop, value: shown)
        .blur(radius: shown || reduceMotion ? 0 : d * look.checkBlur)
        .opacity(shown ? 1 : 0)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : look.settle, value: shown)
        .animation(reduceMotion ? nil : look.settle, value: line)
        .frame(width: d, height: d)
    }
}

/// The exclamation mark, uncovered from its dot up as it grows in with a bounce.
private struct TaskExclamation: View {
    let diameter: CGFloat
    let shown: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let d = diameter
        let look = TaskRingLook.self
        let top = look.barTopWidth * d / 2, bottom = look.barBottomWidth * d / 2
        let middle = d / 2
        ZStack {
            Path { path in
                let upper = middle + look.barTop * d + top
                let lower = middle + look.barBottom * d - bottom
                path.addArc(center: CGPoint(x: middle, y: upper), radius: top, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
                path.addLine(to: CGPoint(x: middle + bottom, y: lower))
                path.addArc(center: CGPoint(x: middle, y: lower), radius: bottom, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
                path.closeSubpath()
            }
            .fill(.white)
            Ellipse()
                .fill(.white)
                .frame(width: look.dot.width * d, height: look.dot.height * d)
                .position(x: middle, y: middle + look.dotMiddle * d)
        }
        .mask(alignment: .bottom) {
            Rectangle()
                .frame(height: d)
                .scaleEffect(x: 1, y: shown || reduceMotion ? 1 : 0, anchor: .bottom)
                .animation(reduceMotion ? nil : look.draw, value: shown)
        }
        .scaleEffect(shown || reduceMotion ? 1 : look.markStart)
        .animation(reduceMotion ? nil : look.pop, value: shown)
        .blur(radius: shown || reduceMotion ? 0 : d * look.exclamationBlur)
        .opacity(shown ? 1 : 0)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : look.settle, value: shown)
        .frame(width: d, height: d)
    }
}

/// The ring opened, at the right end, as a button: Stop while the task goes on, and once it's over,
/// Done. Pressing it shrinks and dims the ring, and the square more, as Apple's does. Where there's
/// nothing for it to do it only shows how the task stands; it's the same ring either way, so what
/// changes in it, as the check springing in, is seen to change.
struct TaskRingButton: View {
    let status: TaskStatus
    let control: PlayerControl
    let height: CGFloat
    let label: String
    /// Held pressed while what pressing it asked for is under way, as stopping.
    var held = false
    var interactive = true
    var tint: Color? = nil
    /// Its own size, as the activity's row measures it, in place of the Timer's buttons'.
    var side: CGFloat? = nil
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) { Color.clear }
            .buttonStyle(TaskRingPress(status: status, side: side ?? TimerLayout.content(height), hovering: hovering, held: held, tint: tint))
            .onHover { hovering = $0 }
            .notchControl()
            .keyControl(control, outset: CGSize(width: 3, height: 3), spoken: label, action: action)
            .disabled(!interactive)
            .accessibilityHidden(!interactive)
            .accessibilityLabel(label)
            .accessibilityValue(status.fraction.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "")
            .help(interactive ? label : "")
    }
}

private struct TaskRingPress: ButtonStyle {
    let status: TaskStatus
    let side: CGFloat
    let hovering: Bool
    let held: Bool
    let tint: Color?

    func makeBody(configuration: Configuration) -> some View {
        TaskRingPressBody(status: status, side: side, hovering: hovering, pressed: configuration.isPressed || held, tint: tint)
    }
}

private struct TaskRingPressBody: View {
    let status: TaskStatus
    let side: CGFloat
    let hovering: Bool
    let pressed: Bool
    let tint: Color?
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        TaskRing(status: status, diameter: side, opened: true, pressed: pressed, tint: tint)
            .background(Circle().fill(.white.opacity(enabled && hovering ? 0.08 : 0)).animation(.easeOut(duration: 0.15), value: hovering))
            .contentShape(Circle())
    }
}

/// An app icon's shape: its corners, by its side, as macOS and Shortcuts round them.
enum TaskAppIcon {
    static let corner: CGFloat = 0.2237
}
