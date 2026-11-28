//
//  RecordingActivity.swift
//  Glance
//
//  Created by Gaty on 07/11/2026.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A voice memo being recorded in Voice Memos: since when, less any time it was paused; or paused,
/// how long it is.
enum VoiceMemo: Equatable {
    case recording(since: Date)
    case paused(length: TimeInterval)

    var isRecording: Bool {
        if case .recording = self { return true }
        return false
    }

    func length(at date: Date = .now) -> TimeInterval {
        switch self {
        case .recording(let since): max(date.timeIntervalSince(since), 0)
        case .paused(let length): length
        }
    }
}

/// The screen being recorded, as macOS's Screenshot records it, from its toolbar or QuickTime
/// Player: counting down to the start when it's set to wait, recording, then being saved.
enum ScreenRecording: Equatable {
    /// Waiting this many seconds, until then.
    case countdown(from: Int, until: Date)
    case recording(since: Date)
    /// Stopped, its file being written: how long it is.
    case saving(length: TimeInterval)
    /// Saved, for a moment: how long it is, the folder it went to, as Finder names it, and its first
    /// picture.
    case saved(length: TimeInterval, folder: String, preview: NSImage?)

    func length(at date: Date = .now) -> TimeInterval {
        switch self {
        case .countdown: 0
        case .recording(let since): max(date.timeIntervalSince(since), 0)
        case .saving(let length), .saved(let length, _, _): length
        }
    }

    var isRecording: Bool {
        if case .recording = self { return true }
        return false
    }
    var isSaving: Bool {
        if case .saving = self { return true }
        return false
    }
    var isSaved: Bool {
        if case .saved = self { return true }
        return false
    }

    /// Its name under its time, opened: what it's doing.
    var title: String {
        switch self {
        case .countdown, .recording: String(localized: "Screen Recording")
        case .saving: String(localized: "Saving Recording…")
        case .saved(_, let folder, _): String(localized: "Recording Saved to \(folder)")
        }
    }

    /// The whole second the countdown shows: 3, then 2, then 1.
    static func step(from: Int, until: Date, at date: Date) -> Int {
        min(max(Int(until.timeIntervalSince(date).rounded(.up)), 0), from)
    }
}

/// Either recording, as one activity's views draw it.
enum Recording: Equatable {
    case voiceMemo(VoiceMemo)
    case screen(ScreenRecording)

    /// Its time as the iPhone's shows it: Voice Memos' as 0:14, the screen's as 00:08.
    static func reading(_ seconds: TimeInterval, memo: Bool) -> String {
        ClockText.of(Int(seconds.rounded(.down)), paddingMinutes: !memo)
    }

    /// In words, for VoiceOver.
    func spoken(at date: Date = .now) -> String {
        switch self {
        case .voiceMemo(let memo):
            let time = NotchTimer.words(memo.length(at: date).rounded(.down)) ?? Self.reading(memo.length(at: date), memo: true)
            return memo.isRecording ? String(localized: "Recording a voice memo, \(time)") : String(localized: "Voice memo paused, \(time)")
        case .screen(.countdown(let from, let until)):
            return String(localized: "Screen recording starts in \(ScreenRecording.step(from: from, until: until, at: date))")
        case .screen(.recording(let since)):
            let time = NotchTimer.words(max(date.timeIntervalSince(since), 0).rounded(.down)) ?? ""
            return String(localized: "Recording the screen, \(time)")
        case .screen(.saving):
            return String(localized: "Saving the screen recording")
        case .screen(.saved(let length, let folder, _)):
            let time = NotchTimer.words(length.rounded(.down)) ?? Self.reading(length, memo: false)
            return String(localized: "Screen recording saved to \(folder), \(time)")
        }
    }
}

/// The countdown is status only; the other recording presentations can open their controls.
struct RecordingOpenAction: ViewModifier {
    let recording: Recording
    let open: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if case .screen(.countdown) = recording {
            content
        } else {
            content
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(.default, open)
        }
    }
}

/// The recordings as the iPhone draws them in the Dynamic Island, measured from the user's own
/// screenshots (3x, Display P3), by the island's height: beside the camera, the screen's red dot,
/// its countdown's ring and its saving spinner, or Voice Memos' waveform and time; opened, the
/// screen's dot and time over its name, or the waveform running on in gray dots, and a button to
/// stop it.
enum RecordingLook {
    /// Voice Memos' red, and the screen recording's, a little more orange.
    static let memoRed = Color.p3(0xE8, 0x65, 0x5F)
    static let memoRedNS = NSColor(displayP3Red: 0xE8 / 255, green: 0x65 / 255, blue: 0x5F / 255, alpha: 1)
    static let screenRed = Color.p3(0xE9, 0x57, 0x46)
    /// The waveform's dots still to come, and the countdown ring's track.
    static let later = Color.p3(0x4B, 0x4B, 0x4B)
    static let laterNS = NSColor(displayP3Red: 0x4B / 255, green: 0x4B / 255, blue: 0x4B / 255, alpha: 1)
    static let track = Color.p3(0x4A, 0x4A, 0x4A)
    /// Counting down or being saved, the dot and the time are this faded, measured.
    static let dim: Double = 0.29
    /// Recording, the dot fades to this and back, a slow, faint pulse, and takes this long:
    /// beside the camera, and opened, where the time pulses with it, the same (the user,
    /// 2026-11-07, after a real recording).
    static let pulseDim: Double = 0.75
    static let pulse: Double = 2

    // Beside the camera.
    /// The screen's dot, by the notch's height, for the Timer's ring as the iPhone draws both.
    static let dot: CGFloat = TimerLayout.ring * 38 / 66
    /// The countdown's and the spinner's ring, its line by its size.
    static let ringLine: CGFloat = 0.139
    /// The countdown's number, by the size of the time beside the camera, and lighter.
    static let countdown: CGFloat = 1.16
    /// In the bubble, the countdown's ring, as large as a ring with a number in it is, and the
    /// number inside it.
    static let bubbleRing: CGFloat = 0.68
    static let bubbleNumber: CGFloat = 0.3
    /// The spinner's arc, of the circle.
    static let spinnerArc: CGFloat = 0.845
    /// Voice Memos' waveform beside the camera: so many bars, from its end, how far apart, how wide,
    /// least and most tall.
    static let bars = 15
    static let waveEdge: CGFloat = 0.174
    /// Beside the camera, how far in from the ends Voice Memos' bars and time stand: as far as the
    /// bars, at their tallest, from the top and bottom.
    static func memoEdge(_ h: CGFloat) -> CGFloat { LiveActivityView.concentric(h * barMost, in: h) }
    static let barPitch: CGFloat = 0.0757
    static let barWidth: CGFloat = 0.048
    static let barLeast: CGFloat = 0.091
    static let barMost: CGFloat = 0.53
    /// How long each bar holds: not measured, no video of it seen.
    static let barTime: Double = 0.1

    // Opened, by the iPhone's island, 84 points tall and 374 wide.
    static let island: CGFloat = 84
    static let openWidth: CGFloat = 374 / island
    /// The waveform opened: so many places, the first ones recorded, the rest dots still to come.
    static let openBars = 26
    static let openRecorded = 15
    static let openPitch: CGFloat = 6.453 / island
    static let openBarWidth: CGFloat = 4 / island
    static let openBarMost: CGFloat = 29.33 / island
    /// Between Voice Memos' time and its button.
    static let openTimeGap: CGFloat = 14.3 / island
    /// Voice Memos' time, by the size of the notch's words: larger than its title would be.
    /// The stop button: its square, its ring's line, by its size, and the square's corners.
    static let memoSquare: CGFloat = 0.432
    static let memoRing: CGFloat = 0.045
    static let screenSquare: CGFloat = 0.403
    static let screenRing: CGFloat = 0.04
    static let squareCorner: CGFloat = 0.25
    /// The screen recording opened: its dot, and the gap after it, by the words' size; between the
    /// lines, baseline to baseline.
    static let openDot: CGFloat = 0.755
    static let openDotGap: CGFloat = 0.4
    static let lines: CGFloat = 1.12

    static func red(memo: Bool) -> Color { memo ? memoRed : screenRed }

    /// What brings the second line's baseline as close under the first's as the iPhone's.
    static var lineGap: CGFloat { NotchType.size * lines - LiveActivityView.lineHeight(NotchType.size) }

    /// How tall it opens: the screen's, the iPhone's row, its two lines centered on it; Voice Memos',
    /// a little taller, for its bars and button to stand level with its time, as high as it goes
    /// under the camera (see `UnderCamera.oneLineHeight`).
    static func openHeight(_ recording: Recording, restingHeight h: CGFloat) -> CGFloat {
        switch recording {
        case .voiceMemo: UnderCamera.oneLineHeight(middle: memoMiddle(h), side: TimerLayout.content(h), edge: TimerLayout.buttonEdge(h))
        case .screen: TimerLayout.rowHeight(h)
        }
    }

    /// The middle of Voice Memos' time, as high as it goes under the camera: the bars and the button
    /// stand level with it.
    static func memoMiddle(_ h: CGFloat) -> CGFloat {
        UnderCamera.oneLineMiddle(font: .monospacedDigitSystemFont(ofSize: memoTimeSize(h), weight: .semibold), restingHeight: h)
    }

    /// Opened to Voice Memos: only as wide as the camera needs for the button beside it. The bars
    /// recorded so far end beside the camera housing, as the iPhone's end beside its camera: under
    /// the housing they'd rise out of sight, so only as many show as fit beside it, and the dots still
    /// to come, low in the middle, pass beneath it, then the time, as high as it goes under it.
    static func memoWidth(restingHeight h: CGFloat, camera: CGFloat) -> CGFloat {
        (camera + 2 * (LiveActivityView.cameraGap + TimerLayout.content(h) + TimerLayout.buttonEdge(h))).rounded(.up)
    }

    /// How many recorded bars show, opened: as many of the iPhone's 15 as fit beside the camera.
    static func memoRecorded(restingHeight h: CGFloat, camera: CGFloat) -> Int {
        let tall = TimerLayout.rowHeight(h)
        let room = (memoWidth(restingHeight: h, camera: camera) - camera) / 2 - TimerLayout.buttonEdge(h) - LiveActivityView.cameraGap
        let fits = Int(((room - tall * openBarWidth) / (tall * openPitch)).rounded(.down)) + 1
        return min(max(fits, 1), openRecorded)
    }

    /// Opened to the screen recording: as wide as the camera needs for the button on one side and,
    /// on the other, the dot and the time beside it, clear of it, however long the time reads; the
    /// name runs on under the camera.
    @MainActor
    static func screenWidth(restingHeight h: CGFloat, camera: CGFloat, at date: Date = .now, length: TimeInterval = 0) -> CGFloat {
        let gap = LiveActivityView.cameraGap
        let right = TimerLayout.content(h) + TimerLayout.buttonEdge(h)
        let left = TimerLayout.buttonEdge(h) + firstLineWidth(length) + gap
        return (camera + max(gap + right, left) * 2).rounded(.up)
    }

    /// Where the screen recording's first line, its time, stands: its two lines centered on the row,
    /// level with the button beside the camera (the user, 2026-11-27: "scoot the text up so its
    /// aligned center"), from the time's capitals to the name's baseline. The time stands beside the
    /// camera (see `screenWidth`), the name under it.
    static func screenBaseline(_ reading: String, restingHeight h: CGFloat) -> CGFloat {
        let reach = UnderCamera.reach([reading], font: .monospacedDigitSystemFont(ofSize: NotchType.size, weight: .semibold))
        return (TimerLayout.rowHeight(h) - reach - NotchType.size * lines) / 2 + reach
    }

    /// Where Voice Memos' time stands: as high as it goes under the camera.
    static func memoBaseline(_ reading: String, restingHeight h: CGFloat) -> CGFloat {
        UnderCamera.baseline([reading], font: .monospacedDigitSystemFont(ofSize: memoTimeSize(h), weight: .semibold), restingHeight: h)
    }

    /// Voice Memos' time opened, the iPhone's 21 points on its 84-point island.
    static func memoTimeSize(_ h: CGFloat) -> CGFloat { TimerLayout.rowHeight(h) * 21 / island }

    /// The dot and the time, as long as it reads then.
    @MainActor
    static func firstLineWidth(_ length: TimeInterval) -> CGFloat {
        let size = NotchType.size
        let reading = Recording.reading(length, memo: false).replacingOccurrences(of: "[0-9]", with: "0", options: .regularExpression)
        let font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .semibold)
        return size * (openDot + openDotGap) + ceil((reading as NSString).size(withAttributes: [.font: font]).width) + 1
    }

    /// The time beside the camera, as wide as it reads then.
    @MainActor
    static func timeWidth(_ text: String, size: CGFloat, weight: NSFont.Weight = .semibold) -> CGFloat {
        let reading = text.replacingOccurrences(of: "[0-9]", with: "0", options: .regularExpression)
        let font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
        return ceil((reading as NSString).size(withAttributes: [.font: font]).width) + 1
    }

    /// Each side of the camera beside it: the wider of what each end shows, each from its end, up
    /// to the camera.
    @MainActor
    static func wing(for recording: Recording, restingHeight h: CGFloat, at date: Date = .now) -> CGFloat {
        let gap = LiveActivityView.cameraGap
        let text = LiveActivityView.textSize(for: h)
        let words = LiveActivityView.textEdge(restingHeight: h)
        switch recording {
        case .voiceMemo(let memo):
            let wave = h * waveEdge + waveWidth(h) + gap
            let time = gap + timeWidth(Recording.reading(memo.length(at: date), memo: true), size: text) + words
            return max(wave, time)
        case .screen(.countdown(let from, _)):
            let ring = SystemActivityView.ringEdge(h) + h * TimerLayout.ring + gap
            let number = gap + timeWidth(String(from), size: text * countdown, weight: .regular) + words
            return max(ring, number)
        case .screen(.recording), .screen(.saved):
            return LiveActivityView.concentric(h * dot, in: h) + h * dot + gap
        case .screen(.saving):
            return SystemActivityView.ringEdge(h) + h * TimerLayout.ring + gap
        }
    }

    /// The waveform beside the camera, end to end.
    static func waveWidth(_ h: CGFloat) -> CGFloat { h * (barPitch * CGFloat(bars - 1) + barWidth) }
    /// Opened, end to end, dots still to come and all.
    static func openWaveWidth(_ h: CGFloat) -> CGFloat {
        let tall = TimerLayout.rowHeight(h)
        return tall * (openPitch * CGFloat(openBars - 1) + openBarWidth)
    }
}

// MARK: - Beside the camera

/// A recording beside the camera, as the iPhone's: the screen's red dot alone, fading and coming
/// back, its countdown's ring and number before it starts, and its dot dimmed beside a spinner as
/// it's saved; Voice Memos' waveform and its time.
struct RecordingMark: View {
    let recording: Recording
    let restingHeight: CGFloat
    /// Its leading side alone, with another activity detached in its trailing side's place.
    var leadingOnly = false

    var body: some View {
        // The visible countdown and elapsed time update inside their own timelines. Keep the
        // enclosing spoken status on the same seconds without replacing those visual views.
        TimelineView(.periodic(from: readingStart, by: 1)) { context in
            drawing
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(recording.spoken(at: context.date))
        }
    }

    private var readingStart: Date {
        switch recording {
        case .voiceMemo(.recording(let since)), .screen(.recording(let since)): since
        case .screen(.countdown(let from, let until)): until - Double(from)
        default: .now
        }
    }

    @ViewBuilder private var drawing: some View {
        let h = restingHeight
        let text = LiveActivityView.textSize(for: h)
        ZStack {
            switch recording {
            case .voiceMemo(let memo):
                // The bars and the time as far in from the ends as the bars, at their tallest, stand
                // from the top and bottom (the user, 2026-11-28: the padding "consistent all around").
                MemoWaveform(slots: RecordingLook.bars, recorded: RecordingLook.bars, height: h * RecordingLook.barMost, scale: h, open: false, live: memo.isRecording)
                    .padding(.leading, RecordingLook.memoEdge(h))
                    .frame(maxWidth: .infinity, alignment: .leading)
                RecordingTime(memo: memo)
                    .font(IslandType.font(text, weight: .semibold, restingHeight: h, digits: true))
                    .foregroundStyle(RecordingLook.memoRed)
                    .fixedSize()
                    .padding(.trailing, RecordingLook.memoEdge(h) - Ink.trail("0", font: .monospacedDigitSystemFont(ofSize: text, weight: .semibold)))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .islandFade(!leadingOnly)
            case .screen(.countdown(let from, let until)) where leadingOnly:
                // With another detached in its trailing side's place, its number inside its ring.
                CountdownWithNumber(from: from, until: until, h: h)
                    .padding(.leading, LiveActivityView.concentric(h * RecordingLook.bubbleRing, in: h))
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .screen(.countdown(let from, let until)):
                CountdownRing(from: from, until: until, diameter: h * TimerLayout.ring)
                    .padding(.leading, SystemActivityView.ringEdge(h))
                    .frame(maxWidth: .infinity, alignment: .leading)
                CountdownNumber(from: from, until: until)
                    .font(IslandType.font(text * RecordingLook.countdown, restingHeight: h, digits: true))
                    .foregroundStyle(.white)
                    .fixedSize()
                    .padding(.trailing, LiveActivityView.textEdge(restingHeight: h))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .islandFade(!leadingOnly)
            case .screen(.recording):
                RecordingDot(diameter: h * RecordingLook.dot, blinking: true)
                    .padding(.leading, LiveActivityView.concentric(h * RecordingLook.dot, in: h))
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .screen(.saved):
                RecordingDot(diameter: h * RecordingLook.dot, blinking: false)
                    .padding(.leading, LiveActivityView.concentric(h * RecordingLook.dot, in: h))
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .screen(.saving):
                RecordingDot(diameter: h * RecordingLook.dot, blinking: false)
                    .opacity(RecordingLook.dim)
                    .padding(.leading, LiveActivityView.concentric(h * RecordingLook.dot, in: h))
                    .frame(maxWidth: .infinity, alignment: .leading)
                SavingSpinner(diameter: h * TimerLayout.ring)
                    .padding(.trailing, SystemActivityView.ringEdge(h))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .islandFade(!leadingOnly)
            }
        }
        .frame(maxHeight: .infinity)
    }
}

/// Voice Memos' time, a second at a time while it records.
struct RecordingTime: View {
    let memo: VoiceMemo

    var body: some View {
        switch memo {
        case .recording(let since):
            TimelineView(.periodic(from: since, by: 1)) { context in
                Text(Recording.reading(memo.length(at: context.date), memo: true))
            }
        case .paused(let length):
            Text(Recording.reading(length, memo: true))
        }
    }
}

/// The screen recording's red dot. Recording, it fades and comes back, drawn by Core Animation on
/// the notch on screen, as anything that moves all the time is there; with Reduce Motion on, it
/// stays.
struct RecordingDot: View {
    let diameter: CGFloat
    let blinking: Bool
    @Environment(\.notchOnScreen) private var onScreen
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if blinking, !reduceMotion, onScreen {
                BlinkingDot()
            } else {
                Circle().fill(RecordingLook.screenRed)
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }
}

private struct BlinkingDot: NSViewRepresentable {
    func makeNSView(context: Context) -> BlinkingDotView { BlinkingDotView() }
    func updateNSView(_ view: BlinkingDotView, context: Context) {}
}

final class BlinkingDotView: NSView {
    private let dot = CALayer()

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        dot.backgroundColor = NSColor(displayP3Red: 0xE9 / 255, green: 0x57 / 255, blue: 0x46 / 255, alpha: 1).cgColor
        layer?.addSublayer(dot)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dot.frame = bounds
        dot.cornerRadius = min(bounds.width, bounds.height) / 2
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        dot.removeAllAnimations()
        guard window != nil else { return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = RecordingLook.pulseDim
        fade.duration = RecordingLook.pulse / 2
        fade.autoreverses = true
        fade.repeatCount = .infinity
        fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        dot.add(fade, forKey: "blink")
    }
}

/// The countdown before the screen recording starts, as the iPhone's: a white ring, full at the
/// start, that slides back a step each second and stops there, over a gray track.
struct CountdownRing: View {
    let from: Int
    let until: Date
    let diameter: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let line = diameter * RecordingLook.ringLine
        let start = until - Double(from)
        TimelineView(.explicit((0...from).map { start + Double($0) })) { context in
            let step = ScreenRecording.step(from: from, until: until, at: context.date)
            let left = from > 0 ? CGFloat(step) / CGFloat(from) : 0
            ZStack {
                Circle().stroke(RecordingLook.track, lineWidth: line)
                Circle()
                    .trim(from: 0, to: left)
                    .stroke(.white, style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    // Each step slides and stops.
                    .animation(reduceMotion ? nil : CountdownRing.slide, value: step)
            }
            .padding(line / 2)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }

    /// How a step slides: speeding up out of one mark and slowing into the next, over most of the
    /// second (the user, 2026-11-07, from their iPhone).
    static let slide = Animation.timingCurve(0.65, 0, 0.35, 1, duration: 0.8)
}

/// The countdown's number, which changes as its ring steps.
struct CountdownNumber: View {
    let from: Int
    let until: Date

    var body: some View {
        let start = until - Double(from)
        TimelineView(.explicit((0...from).map { start + Double($0) })) { context in
            let step = max(ScreenRecording.step(from: from, until: until, at: context.date), 1)
            // One number fades out as the next fades in, as the iPhone's do.
            ZStack {
                Text(String(step))
                    .id(step)
                    .transition(.opacity)
            }
            .animation(.easeInOut(duration: 0.35), value: step)
        }
    }
}

/// The countdown with its number inside its ring, as in the bubble, or beside a bubble.
struct CountdownWithNumber: View {
    let from: Int
    let until: Date
    let h: CGFloat

    var body: some View {
        ZStack {
            CountdownRing(from: from, until: until, diameter: h * RecordingLook.bubbleRing)
            CountdownNumber(from: from, until: until)
                .font(.system(size: h * RecordingLook.bubbleNumber, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
        }
    }
}

/// The screen recording being saved: a white arc going round.
struct SavingSpinner: View {
    let diameter: CGFloat
    /// Its line: as heavy as the countdown's ring beside the camera, unless given.
    var line: CGFloat? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var turned = false

    var body: some View {
        let line = line ?? diameter * RecordingLook.ringLine
        Circle()
            .trim(from: 0, to: RecordingLook.spinnerArc)
            .stroke(.white, style: StrokeStyle(lineWidth: line, lineCap: .round))
            .padding(line / 2)
            .rotationEffect(.degrees(turned ? 360 : 0))
            .frame(width: diameter, height: diameter)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) { turned = true }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Voice Memos' waveform

/// Voice Memos' waveform, as the iPhone's: red bars, the newest at the right, quiet ones as dots;
/// opened, gray dots run on after them, the places still to come. From the microphone, as the
/// call's is (see `RecordingLevels`), drawn by Core Animation on the notch on screen.
struct MemoWaveform: View {
    /// How many places, and how many of them recorded, the rest still to come.
    let slots: Int
    let recorded: Int
    /// The tallest a bar gets.
    let height: CGFloat
    /// What its measures are by: the notch's height beside the camera, the open notch's opened.
    let scale: CGFloat
    let open: Bool
    /// Still recording: it moves on.
    var live = true
    /// Future places belong only to the expanded presentation.
    var futureShown = true
    var compactRecorded: Int? = nil
    @Environment(\.notchOnScreen) private var onScreen

    var body: some View {
        let spec = MemoBars.Spec(slots: slots, recorded: recorded, height: height, scale: scale, open: open)
        Group {
            if onScreen {
                LiveMemoBars(spec: spec)
            } else {
                TimelineView(.animation(minimumInterval: RecordingLook.barTime, paused: !live)) { _ in
                    let levels = RecordingLevels.shared.levels
                    Canvas { context, _ in
                        for (index, bar) in spec.frames(levels).enumerated() {
                            let color = index < recorded ? RecordingLook.memoRed : RecordingLook.later
                            context.fill(Path(roundedRect: bar, cornerRadius: bar.width / 2), with: .color(color))
                        }
                    }
                }
            }
        }
        .frame(width: spec.width, height: height)
        .mask(alignment: .leading) {
            HStack(spacing: 0) {
                let older = spec.pitch * CGFloat(max(recorded - (compactRecorded ?? recorded), 0))
                Color.white.frame(width: older).islandFade(futureShown)
                Color.white.frame(width: spec.recordedWidth - older)
                Color.white.islandFade(futureShown)
            }
            .frame(width: spec.width, height: height)
        }
        .accessibilityHidden(true)
    }
}

/// Where each of the waveform's bars goes.
enum MemoBars {
    struct Spec: Equatable {
        let slots: Int
        let recorded: Int
        let height: CGFloat
        let scale: CGFloat
        let open: Bool

        var pitch: CGFloat { scale * (open ? RecordingLook.openPitch : RecordingLook.barPitch) }
        var barWidth: CGFloat { scale * (open ? RecordingLook.openBarWidth : RecordingLook.barWidth) }
        /// Quiet, a bar is a dot: as tall as it's wide opened, a little taller beside the camera.
        var least: CGFloat { open ? barWidth : scale * RecordingLook.barLeast }
        var width: CGFloat { pitch * CGFloat(slots - 1) + barWidth }
        var recordedWidth: CGFloat { min(width, pitch * CGFloat(recorded)) }

        /// The recorded places from the newest levels, oldest first, the newest last; the rest
        /// dots. From a place before the first, for one that's on its way out.
        func frames(_ levels: [CGFloat], from first: Int = 0) -> [CGRect] {
            let newest = Array(levels.suffix(recorded - first))
            let quiet = recorded - first - newest.count
            return (first..<slots).map { index in
                let place = index - first
                let level: CGFloat = place < quiet || index >= recorded ? 0 : newest[place - quiet]
                let tall = least + (height - least) * min(max(level, 0), 1)
                return CGRect(x: CGFloat(index) * pitch, y: (height - tall) / 2, width: barWidth, height: tall)
            }
        }
    }
}

private struct LiveMemoBars: NSViewRepresentable {
    let spec: MemoBars.Spec
    func makeNSView(context: Context) -> MemoBarsView { MemoBarsView(spec: spec) }
    func updateNSView(_ view: MemoBarsView, context: Context) {}
}

final class MemoBarsView: NSView {
    private var bars: [CALayer] = []
    /// Every bar on one strip that scrolls, the recorded ones and the dots still to come alike, as
    /// the iPhone's: the dots run on toward the recorded ones and turn red there. One more recorded
    /// bar than shows, on its way out at the left end.
    private let strip = CALayer()
    private let spec: MemoBars.Spec
    private var hearing: Any?

    init(spec: MemoBars.Spec) {
        self.spec = spec
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.addSublayer(strip)
        for index in -1..<spec.slots {
            let bar = CALayer()
            bar.backgroundColor = (index < spec.recorded ? RecordingLook.memoRedNS : RecordingLook.laterNS).cgColor
            strip.addSublayer(bar)
            bars.append(bar)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        hearing =
            window == nil
            ? nil
            : RecordingLevels.shared.$levels.sink { [weak self] levels in
                MainActor.assumeIsolated { self?.draw(levels, scrolls: true) }
            }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        strip.frame = bounds
        CATransaction.commit()
        draw(RecordingLevels.shared.levels, scrolls: false)
    }

    /// Each new level takes the newest place and every bar moves on one; drawn there at once, the
    /// strip is slid back a place and glides into it over the time the next takes to come, so the
    /// waveform scrolls along as the iPhone's does rather than stepping. Where the dots meet the
    /// recorded bars, the dot arriving turns red and grows to the level heard. With Reduce Motion
    /// on, it steps.
    private func draw(_ levels: [CGFloat], scrolls: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Laid out from the top, as SwiftUI's own.
        for (bar, frame) in zip(bars, spec.frames(levels, from: -1)) {
            bar.frame = CGRect(x: frame.minX, y: bounds.height - frame.maxY, width: frame.width, height: frame.height)
            bar.cornerRadius = frame.width / 2
        }
        CATransaction.commit()
        guard scrolls, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let glide = CABasicAnimation(keyPath: "sublayerTransform.translation.x")
        glide.fromValue = spec.pitch
        glide.toValue = 0
        glide.duration = RecordingLook.barTime
        glide.timingFunction = CAMediaTimingFunction(name: .linear)
        strip.add(glide, forKey: "glide")
        // The newest bar is where the first dot was: it turns red and grows from it.
        guard spec.recorded < spec.slots, let newest = bars.dropFirst(spec.recorded).first, newest.bounds.height > 0 else { return }
        let grow = CABasicAnimation(keyPath: "transform.scale.y")
        grow.fromValue = spec.least / newest.bounds.height
        grow.toValue = 1
        let redden = CABasicAnimation(keyPath: "backgroundColor")
        redden.fromValue = RecordingLook.laterNS.cgColor
        redden.toValue = RecordingLook.memoRedNS.cgColor
        let turn = CAAnimationGroup()
        turn.animations = [grow, redden]
        turn.duration = RecordingLook.barTime
        turn.timingFunction = CAMediaTimingFunction(name: .easeOut)
        newest.add(turn, forKey: "turn")
    }
}

// MARK: - Opened

/// Opened to a recording, as the iPhone's expands. Voice Memos: the waveform from the left end, the
/// red time, as high as it goes under the camera, and the button to stop it at the right. The
/// screen: its red dot and time, and its name under them, as high as they go under the camera,
/// running on beneath it, and the button to stop it. What shows
/// beside the camera slides out to its place here, as the Timer's does.
struct ExpandedRecordingView: View {
    let recording: Recording
    let restingHeight: CGFloat
    let camera: CGFloat
    let width: CGFloat
    var revealed = true
    /// How wide the notch is closed, if it shows beside the camera there, and grows out of that.
    var closedWidth: CGFloat? = nil
    var closedDrop: CGFloat = 0
    /// Review fixtures can show unavailable controls and use fake actions without system access.
    var controlPermissionOverride: Bool? = nil
    var savedFileStateOverride: ScreenRecordingWatch.SavedFileState? = nil
    var stopAction: (() -> Void)? = nil
    var openAction: (() -> Void)? = nil
    @ObservedObject private var memoWatch = VoiceMemoWatch.shared
    @ObservedObject private var screenWatch = ScreenRecordingWatch.shared
    @Environment(\.activityBubbleCenter) private var bubbleCenter
    @Environment(\.trailingGrows) private var trailingGrows

    var body: some View {
        TimelineView(.periodic(from: readingStart, by: 1)) { context in
            drawing
                .accessibilityElement(children: .contain)
                .accessibilityLabel(recording.spoken(at: context.date))
        }
    }

    private var readingStart: Date {
        switch recording {
        case .voiceMemo(.recording(let since)), .screen(.recording(let since)): since
        case .screen(.countdown(let from, let until)): until - Double(from)
        default: .now
        }
    }

    @ViewBuilder private var drawing: some View {
        let h = restingHeight
        let tall = TimerLayout.rowHeight(h)
        // Voice Memos' laid out twice as tall as its time's middle, so its bars and button, centered,
        // stand level with it; the notch ends sooner, under them.
        let row: CGFloat = if case .voiceMemo = recording { 2 * RecordingLook.memoMiddle(h) } else { RecordingLook.openHeight(recording, restingHeight: h) }
        let out = revealed
        let rise = (h - row) / 2 + closedDrop
        let spread = ((closedWidth ?? width) - width) / 2
        let grows = out || closedWidth == nil && bubbleCenter == nil
        ZStack {
            switch recording {
            case .voiceMemo(let memo):
                memoRow(memo, h: h, tall: tall, grows: grows, rise: rise, spread: spread)
            case .screen(let screen):
                screenRow(screen, h: h, grows: grows, rise: rise, spread: spread)
            }
        }
        .frame(width: width, height: row)
        .frame(height: RecordingLook.openHeight(recording, restingHeight: h), alignment: .top)
    }

    @ViewBuilder
    private func memoRow(_ memo: VoiceMemo, h: CGFloat, tall: CGFloat, grows: Bool, rise: CGFloat, spread: CGFloat) -> some View {
        let canControl = controlPermissionOverride ?? memoWatch.canControl
        let edge = TimerLayout.buttonEdge(h)
        let recorded = RecordingLook.memoRecorded(restingHeight: h, camera: camera)
        let open = MemoBars.Spec(slots: RecordingLook.openBars, recorded: recorded, height: tall * RecordingLook.openBarMost, scale: tall, open: true)
        let closed = MemoBars.Spec(slots: RecordingLook.bars, recorded: RecordingLook.bars, height: h * RecordingLook.barMost, scale: h, open: false)
        let waveFrom = CGSize(
            width: bubbleCenter.map { $0 + width / 2 - edge - closed.pitch * (CGFloat(open.recorded) - 2.5) }
                ?? (RecordingLook.memoEdge(h) - edge - spread), height: rise)
        let text = LiveActivityView.textSize(for: h)
        let size = RecordingLook.memoTimeSize(h)
        // The time as high as it goes under the camera, growing out of the closed notch's middle.
        let font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .semibold)
        let baseline = RecordingLook.memoBaseline(Recording.reading(memo.length(), memo: true), restingHeight: h)
        let timeMiddle = baseline - (font.ascender + font.descender) / 2
        let timeFrom = CGSize(width: spread - LiveActivityView.textEdge(restingHeight: h) + Self.memoTimeEdge(h), height: rise + RecordingLook.memoMiddle(h) - timeMiddle)
        Group {
            if canControl {
                MemoWaveform(
                    slots: open.slots, recorded: open.recorded, height: open.height, scale: tall, open: true, live: memo.isRecording, futureShown: revealed,
                    compactRecorded: bubbleCenter == nil ? nil : 5
                )
            } else {
                Text("Needs Accessibility")
                    .font(IslandType.title(restingHeight))
                    .foregroundStyle(.white)
                    .frame(width: open.width, height: open.height, alignment: .leading)
            }
        }
        .modifier(GrowsOut(out: grows, scale: closed.pitch / open.pitch, anchor: .leading, from: waveFrom))
        .modifier(GrownFade(shown: revealed, grows: closedWidth != nil || bubbleCenter != nil))
        .padding(.leading, edge)
        .frame(maxWidth: .infinity, alignment: .leading)
        RecordingTime(memo: memo)
            .font(IslandType.font(size, weight: .semibold, restingHeight: h, digits: true))
            .foregroundStyle(RecordingLook.memoRed)
            .fixedSize()
            .modifier(GrowsOut(out: grows || !trailingGrows, scale: text / size, anchor: .trailing, from: timeFrom))
            .modifier(GrownFade(shown: revealed, grows: closedWidth != nil && trailingGrows))
            .firstBaseline(baseline, alignment: .trailing)
            .padding(.trailing, Self.memoTimeEdge(h))
        StopRecordingButton(memo: true, h: h, canControl: canControl) {
            if let stopAction { stopAction() } else { memoWatch.stop() }
        }
        .modifier(IslandReveal(hidden: !revealed))
        .padding(.trailing, TimerLayout.buttonEdge(h))
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    /// From the right end to Voice Memos' time: past the button.
    static func memoTimeEdge(_ h: CGFloat) -> CGFloat {
        TimerLayout.buttonEdge(h) + TimerLayout.content(h) + TimerLayout.rowHeight(h) * RecordingLook.openTimeGap
    }

    @ViewBuilder
    private func screenRow(_ screen: ScreenRecording, h: CGFloat, grows: Bool, rise: CGFloat, spread: CGFloat) -> some View {
        let canControl = controlPermissionOverride ?? screenWatch.canControl
        let needsPermission = !canControl && !screen.isSaving && !screen.isSaved
        let savedFileState = savedFileStateOverride ?? screenWatch.savedFileState
        let title = ScreenRecordingButton.title(for: screen, needsPermission: needsPermission, savedFileState: savedFileState)
        let edge = TimerLayout.buttonEdge(h)
        // Keep the full folder name for accessibility while its visible line truncates before
        // the button, with the same inset between them as around the content.
        let wordsWidth = max(width - edge - TimerLayout.buttonEdge(h) - TimerLayout.content(h) - edge, 0)
        let dot = NotchType.size * RecordingLook.openDot
        let closedDot = h * RecordingLook.dot
        // The first line as high as it goes under the camera.
        let font = NSFont.monospacedDigitSystemFont(ofSize: NotchType.size, weight: .semibold)
        let baseline = RecordingLook.screenBaseline(Recording.reading(screen.length(), memo: false), restingHeight: h)
        let lineMiddle = baseline - (font.ascender + font.descender) / 2
        // The dot slides out from beside the camera to before the time, the same size: down from
        // the first line to the closed notch's middle.
        let dotFrom = CGSize(
            width: bubbleCenter.map { $0 + width / 2 - edge - closedDot / 2 }
                ?? (LiveActivityView.concentric(closedDot, in: h) - edge - spread), height: rise + TimerLayout.rowHeight(h) / 2 - lineMiddle)
        VStack(alignment: .leading, spacing: 0) {
            // Recording, the dot and the time fade and come back together, as on the iPhone. The dot
            // stands on the time's line, so the line is the time's, by its baseline.
            ScreenTime(screen: screen)
                .font(IslandType.title(restingHeight).monospacedDigit())
                .foregroundStyle(RecordingLook.screenRed)
                .modifier(IslandReveal(hidden: !revealed))
                .padding(.leading, dot + NotchType.size * RecordingLook.openDotGap)
                .overlay(alignment: .leading) {
                    Circle().fill(RecordingLook.screenRed)
                        .frame(width: dot, height: dot)
                        .modifier(GrowsOut(out: grows, scale: closedDot / dot, anchor: .leading, from: dotFrom))
                        .modifier(GrownFade(shown: revealed, grows: closedWidth != nil || bubbleCenter != nil))
                }
                .modifier(RecordingBlink(recording: screen.isRecording, faded: !screen.isRecording && !screen.isSaved, shown: revealed))
            Text(title)
                .font(IslandType.title(restingHeight))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.middle)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.3), value: screen.title)
                .padding(.top, RecordingLook.lineGap)
                .modifier(IslandReveal(hidden: !revealed))
        }
        .frame(width: wordsWidth, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .firstBaseline(baseline)
        .padding(.leading, edge)
        // Being saved, the spinner beside the camera grows into the ring around the square.
        let ringFrom = CGSize(width: spread - SystemActivityView.ringEdge(h) + TimerLayout.buttonEdge(h), height: rise)
        ScreenRecordingButton(
            screen: screen, h: h, revealed: revealed, canControl: canControl, savedFileState: savedFileState,
            stopAction: { if let stopAction { stopAction() } else { screenWatch.stop() } },
            openAction: { if let openAction { openAction() } else { screenWatch.openSaved() } }
        )
        .modifier(
            GrowsOut(
                out: grows || !screen.isSaving || !trailingGrows, scale: h * TimerLayout.ring / TimerLayout.content(h), anchor: .trailing,
                from: ringFrom)
        )
        .modifier(GrownFade(shown: revealed, grows: screen.isSaving && closedWidth != nil && trailingGrows))
        .padding(.trailing, TimerLayout.buttonEdge(h))
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

}

/// Recording, what it's on fades and comes back; counting down or being saved, it stays faded; saved,
/// it's whole. Only while it shows, as the open view stays, hidden, once the notch closes; with
/// Reduce Motion on, it stays.
private struct RecordingBlink: ViewModifier {
    let recording: Bool
    /// Faded, still: counting down or being saved.
    let faded: Bool
    let shown: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsed = false

    func body(content: Content) -> some View {
        content
            .opacity(faded ? RecordingLook.dim : pulsed ? RecordingLook.pulseDim : 1)
            .animation(.easeInOut(duration: 0.3), value: faded)
            .onChange(of: recording && shown && !reduceMotion, initial: true) { _, blinks in
                if blinks {
                    withAnimation(.easeInOut(duration: RecordingLook.pulse / 2).repeatForever(autoreverses: true)) { pulsed = true }
                } else {
                    var still = Transaction()
                    still.disablesAnimations = true
                    withTransaction(still) { pulsed = false }
                }
            }
    }
}

/// The screen recording's time, a second at a time while it records; nothing yet while it counts
/// down.
struct ScreenTime: View {
    let screen: ScreenRecording

    var body: some View {
        switch screen {
        case .recording(let since):
            TimelineView(.periodic(from: since, by: 1)) { context in
                Text(Recording.reading(screen.length(at: context.date), memo: false))
            }
        default:
            Text(Recording.reading(screen.length(), memo: false))
        }
    }
}

/// The button that stops a recording: a white ring around a red square with round corners.
/// Voice Memos uses the pressed-state proportions of its installed macOS platter asset.
struct StopRecordingButton: View {
    /// Voice Memos', whose square is a little larger and ring heavier than the screen recording's.
    let memo: Bool
    let h: CGFloat
    var canControl = true
    /// Isolated fixtures can show feedback without pointer events or invoking the action.
    var pressStateOverride: Bool? = nil
    var reduceMotionOverride: Bool? = nil
    let action: () -> Void

    var body: some View {
        let side = TimerLayout.content(h)
        let square = side * (memo ? RecordingLook.memoSquare : RecordingLook.screenSquare)
        let ring = side * (memo ? RecordingLook.memoRing : RecordingLook.screenRing)
        Button(action: action) {
            Group {
                if memo {
                    MemoStopGlyph(side: side, pressedOverride: pressStateOverride, reduceMotionOverride: reduceMotionOverride)
                } else {
                    ZStack {
                        Circle().strokeBorder(.white, lineWidth: ring)
                        RoundedRectangle(cornerRadius: square * RecordingLook.squareCorner, style: .continuous)
                            .fill(RecordingLook.red(memo: false))
                            .frame(width: square, height: square)
                    }
                }
            }
            .frame(width: side, height: side)
            .contentShape(Circle())
        }
        .buttonStyle(RecordingStopPress(memo: memo))
        .opacity(canControl ? 1 : 0.45)
        .notchControl()
        .keyControl(.activityFirst, outset: CGSize(width: 3, height: 3), spoken: String(localized: "Stop Recording"), action: action)
        .accessibilityLabel(String(localized: "Stop Recording"))
        .accessibilityHint(canControl ? "" : String(localized: "Needs Accessibility"))
        .help(canControl ? String(localized: "Stop Recording") : String(localized: "Needs Accessibility"))
    }
}

private struct MemoStopPressedKey: EnvironmentKey {
    static let defaultValue = false
}

private extension EnvironmentValues {
    var memoStopPressed: Bool {
        get { self[MemoStopPressedKey.self] }
        set { self[MemoStopPressedKey.self] = newValue }
    }
}

private struct RecordingStopPress: ButtonStyle {
    let memo: Bool

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        if memo {
            configuration.label.environment(\.memoStopPressed, configuration.isPressed)
        } else {
            IslandPress(highlight: false, contactSize: nil).makeBody(configuration: configuration)
        }
    }
}

/// Measured zoom/zoom-press model states in VoiceMemos.app/PlatterStopButton.ca. Preserve the
/// existing resting glyph and hit target; adapt only the native press endpoints and response.
private struct MemoStopGlyph: View {
    let side: CGFloat
    var pressedOverride: Bool? = nil
    var reduceMotionOverride: Bool? = nil
    @Environment(\.memoStopPressed) private var pressed
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let down = enabled && (pressedOverride ?? pressed)
        let reduced = reduceMotionOverride ?? reduceMotion
        let square = side * RecordingLook.memoSquare
        ZStack {
            Circle().strokeBorder(.white, lineWidth: side * RecordingLook.memoRing)
                .scaleEffect(down && !reduced ? 0.226 / 0.246 : 1)
            RoundedRectangle(cornerRadius: square * RecordingLook.squareCorner, style: .continuous)
                .fill(RecordingLook.memoRed)
                .frame(width: square, height: square)
                .scaleEffect(down && !reduced ? 1.095 / 1.149 : 1)
        }
        .frame(width: side, height: side)
        .opacity(down ? 0.2 : 1)
        .animation(
            reduced ? nil : .interpolatingSpring(mass: 2, stiffness: down ? 800 : 300, damping: down ? 100 : 50),
            value: down
        )
    }
}

// MARK: - Detached

/// A recording in the bubble off the notch's end: the screen's dot, its countdown's ring or its
/// spinner; Voice Memos' newest bars. Never seen on an iPhone: this is what each shows beside the
/// camera, at the bubble's size.
struct RecordingBubbleGlyph: View {
    let recording: Recording
    let restingHeight: CGFloat

    var body: some View {
        let h = restingHeight
        switch recording {
        case .voiceMemo(let memo):
            MemoWaveform(slots: 5, recorded: 5, height: h * RecordingLook.barMost, scale: h, open: false, live: memo.isRecording)
        case .screen(.countdown(let from, let until)):
            // Its number inside the ring, as the iPhone's in its bubble (the user, 2026-11-07).
            CountdownWithNumber(from: from, until: until, h: h)
        case .screen(.recording):
            RecordingDot(diameter: h * RecordingLook.dot, blinking: true)
        case .screen(.saved):
            RecordingDot(diameter: h * RecordingLook.dot, blinking: false)
        case .screen(.saving):
            SavingSpinner(diameter: h * TimerLayout.ring)
        }
    }
}

// MARK: - The screen recording's button

/// The screen recording's button, as the iPhone's: a ring around a red square that stops it. Being
/// saved, the ring turns into a spinner around the square, as large and as fine; saved, the spinner
/// fades and the square grows into the recording's first picture, which opens it (the user,
/// 2026-11-07, from their iPhone).
struct ScreenRecordingButton: View {
    let screen: ScreenRecording
    let h: CGFloat
    let revealed: Bool
    var canControl = true
    var savedFileState = ScreenRecordingWatch.SavedFileState.available
    var reduceMotionOverride: Bool? = nil
    var stopAction: () -> Void = { ScreenRecordingWatch.shared.stop() }
    var openAction: () -> Void = { ScreenRecordingWatch.shared.openSaved() }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let side = TimerLayout.content(h)
        let square = side * RecordingLook.screenSquare
        let line = side * RecordingLook.screenRing
        let saved = screen.isSaved
        let reduced = reduceMotionOverride ?? reduceMotion
        let picture = saved ? side : square
        let corner = saved ? side * PlayerLayout.thumbnailCorner : square * RecordingLook.squareCorner
        let preview: NSImage? = { if case .saved(_, _, let preview) = screen { preview } else { nil } }()
        let unavailable = saved && savedFileState == .unavailable
        let enabled = !screen.isSaving && !unavailable
        let label =
            saved
            ? (savedFileState == .openingFailed ? String(localized: "Try Again") : String(localized: "Open Recording"))
            : String(localized: "Stop Recording")
        let hint = unavailable ? String(localized: "Recording Unavailable") : canControl || saved || screen.isSaving ? "" : String(localized: "Needs Accessibility")
        Button(action: press) {
            ZStack {
                Circle().strokeBorder(.white, lineWidth: line)
                    .opacity(screen.isSaving || saved ? 0 : 1)
                    .animation(.easeOut(duration: 0.3), value: screen.isSaving || saved)
                SavingSpinner(diameter: side, line: line)
                    .opacity(screen.isSaving ? 1 : 0)
                    .animation(.easeOut(duration: 0.3), value: screen.isSaving)
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(saved && preview == nil ? Color.white.opacity(0.12) : RecordingLook.screenRed)
                    .overlay {
                        if let preview {
                            Image(nsImage: preview).resizable().aspectRatio(contentMode: .fill)
                        } else if saved {
                            Image(systemName: "play.rectangle")
                                .font(.system(size: side * 0.55, weight: .medium))
                                .foregroundStyle(.white)
                                .accessibilityHidden(true)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                    .frame(width: picture, height: picture)
                    .islandFade(revealed)
                    .animation(reduced ? nil : NotchMotion.expand, value: saved)
            }
            .frame(width: side, height: side)
            .contentShape(Circle())
        }
        .buttonStyle(IslandPress(highlight: false, contactSize: nil))
        .opacity(!unavailable && (canControl || saved || screen.isSaving) ? 1 : 0.45)
        .disabled(!enabled)
        .notchControl(enabled: enabled)
        .keyControl(.activityFirst, outset: CGSize(width: 3, height: 3), spoken: label, action: press)
        .accessibilityLabel(label)
        .accessibilityHint(hint)
        .help(hint.isEmpty ? label : hint)
    }

    private func press() {
        switch screen {
        case .countdown, .recording: stopAction()
        case .saved:
            guard savedFileState != .unavailable else { return }
            openAction()
        case .saving: break
        }
    }

    static func title(for screen: ScreenRecording, needsPermission: Bool, savedFileState: ScreenRecordingWatch.SavedFileState) -> String {
        if needsPermission { return String(localized: "Needs Accessibility") }
        if screen.isSaved {
            switch savedFileState {
            case .unavailable: return String(localized: "Recording Unavailable")
            case .openingFailed: return String(localized: "Couldn't Open Recording")
            case .available: break
            }
        }
        return screen.title
    }
}
