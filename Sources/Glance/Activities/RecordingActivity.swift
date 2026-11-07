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
    /// Recording, beside the camera, the dot fades to this and back, a slow, faint pulse, and
    /// takes this long; opened, the dot and the time fade further, a little faster (the user,
    /// 2026-11-07, from their iPhone, twice: the closed one fainter, the opened one faster).
    static let pulseDim: Double = 0.75
    static let pulse: Double = 2
    static let openDim: Double = 0.35
    static let openPulse: Double = 1.5

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
    static let memoTime: CGFloat = 1.16
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

    /// Opened to Voice Memos: as wide, for its height, as the iPhone's island, and wider if need be for
    /// the bars recorded so far to end beside the camera housing, as the iPhone's end beside its
    /// camera: under the housing they'd rise out of sight, and only the dots still to come, low in
    /// the middle, pass beneath it.
    static func memoWidth(restingHeight h: CGFloat, camera: CGFloat) -> CGFloat {
        let tall = TimerLayout.tallHeight(h)
        let recorded = tall * (openPitch * CGFloat(openRecorded - 1) + openBarWidth)
        let beside = PlayerLayout.padding + recorded + LiveActivityView.cameraGap
        return max(tall * openWidth, camera + 2 * beside).rounded(.up)
    }

    /// Opened to the screen recording: the dot and the time beside the camera, its name running on
    /// under it, and on the other side, the same room for the button.
    @MainActor
    static func screenWidth(restingHeight h: CGFloat, camera: CGFloat, at date: Date = .now, length: TimeInterval = 0) -> CGFloat {
        let gap = LiveActivityView.cameraGap
        let left = PlayerLayout.padding + firstLineWidth(length) + gap
        let right = gap + TimerLayout.content(h) + TimerLayout.buttonEdge(h)
        return camera + max(left, right) * 2
    }

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
        let tall = TimerLayout.tallHeight(h)
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
        let h = restingHeight
        let text = LiveActivityView.textSize(for: h)
        ZStack {
            switch recording {
            case .voiceMemo(let memo):
                MemoWaveform(slots: RecordingLook.bars, recorded: RecordingLook.bars, height: h * RecordingLook.barMost, scale: h, open: false, live: memo.isRecording)
                    .padding(.leading, h * RecordingLook.waveEdge)
                    .frame(maxWidth: .infinity, alignment: .leading)
                RecordingTime(memo: memo)
                    .font(.system(size: text, weight: .semibold).monospacedDigit())
                    .foregroundStyle(RecordingLook.memoRed)
                    .fixedSize()
                    .padding(.trailing, LiveActivityView.textEdge(restingHeight: h))
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
                    .font(.system(size: text * RecordingLook.countdown, weight: .regular).monospacedDigit())
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(recording.spoken())
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

        /// The recorded places from the newest levels, oldest first, the newest last; the rest
        /// dots.
        func frames(_ levels: [CGFloat]) -> [CGRect] {
            let newest = Array(levels.suffix(recorded))
            let quiet = recorded - newest.count
            return (0..<slots).map { index in
                let level: CGFloat = index < quiet || index >= recorded ? 0 : newest[index - quiet]
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
    /// The recorded bars, which scroll, clipped to their places; and the dots still to come, which
    /// stay.
    private let recorded = CALayer()
    private let later = CALayer()
    private let spec: MemoBars.Spec
    private var hearing: Any?

    init(spec: MemoBars.Spec) {
        self.spec = spec
        super.init(frame: .zero)
        wantsLayer = true
        recorded.masksToBounds = true
        layer?.addSublayer(recorded)
        layer?.addSublayer(later)
        for index in 0..<spec.slots {
            let bar = CALayer()
            bar.backgroundColor = (index < spec.recorded ? RecordingLook.memoRedNS : RecordingLook.laterNS).cgColor
            (index < spec.recorded ? recorded : later).addSublayer(bar)
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
        recorded.frame = CGRect(x: 0, y: 0, width: spec.pitch * CGFloat(spec.recorded - 1) + spec.barWidth, height: bounds.height)
        later.frame = bounds
        CATransaction.commit()
        draw(RecordingLevels.shared.levels, scrolls: false)
    }

    /// Each new level takes the newest place and every bar moves on one; drawn there at once, the
    /// bars are slid back a place and glide into it over the time the next takes to come, so the
    /// waveform scrolls along as the iPhone's does rather than stepping. With Reduce Motion on, it
    /// steps.
    private func draw(_ levels: [CGFloat], scrolls: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Laid out from the top, as SwiftUI's own.
        for (bar, frame) in zip(bars, spec.frames(levels)) {
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
        recorded.add(glide, forKey: "glide")
    }
}

// MARK: - Opened

/// Opened to a recording, as the iPhone's expands. Voice Memos: the waveform from the left end, the
/// red time and the button to stop it at the right. The screen: its red dot and time beside the
/// camera, its name under them, running on under the camera, and the button to stop it. What shows
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
    @State private var arrived = false
    @Environment(\.trailingGrows) private var trailingGrows

    var body: some View {
        let h = restingHeight
        let tall = TimerLayout.tallHeight(h)
        let out = revealed && arrived
        let rise = (h - tall) / 2 + closedDrop
        let spread = ((closedWidth ?? width) - width) / 2
        let grows = out || closedWidth == nil
        ZStack {
            switch recording {
            case .voiceMemo(let memo):
                memoRow(memo, h: h, tall: tall, grows: grows, rise: rise, spread: spread)
            case .screen(let screen):
                screenRow(screen, h: h, grows: grows, rise: rise, spread: spread)
            }
        }
        .frame(width: width, height: tall)
        .onAppear { withAnimation(NotchMotion.expand) { arrived = true } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(recording.spoken())
    }

    @ViewBuilder
    private func memoRow(_ memo: VoiceMemo, h: CGFloat, tall: CGFloat, grows: Bool, rise: CGFloat, spread: CGFloat) -> some View {
        let edge = PlayerLayout.padding
        let open = MemoBars.Spec(slots: RecordingLook.openBars, recorded: RecordingLook.openRecorded, height: tall * RecordingLook.openBarMost, scale: tall, open: true)
        let closed = MemoBars.Spec(slots: RecordingLook.bars, recorded: RecordingLook.bars, height: h * RecordingLook.barMost, scale: h, open: false)
        let waveFrom = CGSize(width: h * RecordingLook.waveEdge - edge - spread, height: rise)
        let text = LiveActivityView.textSize(for: h)
        let size = NotchType.size * RecordingLook.memoTime
        let timeFrom = CGSize(width: spread - LiveActivityView.textEdge(restingHeight: h) + Self.memoTimeEdge(h), height: rise)
        MemoWaveform(slots: open.slots, recorded: open.recorded, height: open.height, scale: tall, open: true, live: memo.isRecording)
            .modifier(GrowsOut(out: grows, scale: closed.pitch / open.pitch, anchor: .leading, from: waveFrom))
            .modifier(GrownFade(shown: revealed, grows: closedWidth != nil))
            .padding(.leading, edge)
            .frame(maxWidth: .infinity, alignment: .leading)
        RecordingTime(memo: memo)
            .font(.system(size: size, weight: .semibold).monospacedDigit())
            .foregroundStyle(RecordingLook.memoRed)
            .fixedSize()
            .modifier(GrowsOut(out: grows || !trailingGrows, scale: text / size, anchor: .trailing, from: timeFrom))
            .modifier(GrownFade(shown: revealed, grows: closedWidth != nil && trailingGrows))
            .padding(.trailing, Self.memoTimeEdge(h))
            .frame(maxWidth: .infinity, alignment: .trailing)
        StopRecordingButton(memo: true, h: h) { VoiceMemoWatch.shared.stop() }
            .modifier(IslandReveal(hidden: !revealed))
            .padding(.trailing, TimerLayout.buttonEdge(h))
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    /// From the right end to Voice Memos' time: past the button.
    static func memoTimeEdge(_ h: CGFloat) -> CGFloat {
        TimerLayout.buttonEdge(h) + TimerLayout.content(h) + TimerLayout.tallHeight(h) * RecordingLook.openTimeGap
    }

    @ViewBuilder
    private func screenRow(_ screen: ScreenRecording, h: CGFloat, grows: Bool, rise: CGFloat, spread: CGFloat) -> some View {
        let edge = PlayerLayout.padding
        let dot = NotchType.size * RecordingLook.openDot
        let closedDot = h * RecordingLook.dot
        // The dot slides out from beside the camera to before the time, the same size: down from
        // the first line to the closed notch's middle.
        let dotFrom = CGSize(width: LiveActivityView.concentric(closedDot, in: h) - edge - spread, height: rise + Self.firstLineRise(h))
        VStack(alignment: .leading, spacing: 0) {
            // Recording, the dot and the time fade and come back together, as on the iPhone.
            HStack(spacing: NotchType.size * RecordingLook.openDotGap) {
                Circle().fill(RecordingLook.screenRed)
                    .frame(width: dot, height: dot)
                    .modifier(GrowsOut(out: grows, scale: closedDot / dot, anchor: .leading, from: dotFrom))
                    .modifier(GrownFade(shown: revealed, grows: closedWidth != nil))
                ScreenTime(screen: screen)
                    .font(NotchType.title.monospacedDigit())
                    .foregroundStyle(RecordingLook.screenRed)
                    .modifier(IslandReveal(hidden: !revealed))
            }
            .modifier(RecordingBlink(recording: screen.isRecording, faded: !screen.isRecording && !screen.isSaved, shown: revealed))
            Text(screen.title)
                .font(NotchType.title)
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.middle)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.3), value: screen.title)
                .padding(.top, RecordingLook.lineGap)
                .modifier(IslandReveal(hidden: !revealed))
        }
        .fixedSize()
        .padding(.leading, edge)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Being saved, the spinner beside the camera grows into the ring around the square.
        let ringFrom = CGSize(width: spread - SystemActivityView.ringEdge(h) + TimerLayout.buttonEdge(h), height: rise)
        ScreenRecordingButton(screen: screen, h: h)
            .modifier(
                GrowsOut(
                    out: grows || !screen.isSaving || !trailingGrows, scale: h * TimerLayout.ring / TimerLayout.content(h), anchor: .trailing,
                    from: ringFrom)
            )
            .modifier(IslandReveal(hidden: !revealed))
            .padding(.trailing, TimerLayout.buttonEdge(h))
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    /// How far above the open notch's middle the first line's middle is.
    static func firstLineRise(_ h: CGFloat) -> CGFloat { NotchType.size * RecordingLook.lines / 2 }
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
            .opacity(faded ? RecordingLook.dim : pulsed ? RecordingLook.openDim : 1)
            .animation(.easeInOut(duration: 0.3), value: faded)
            .onChange(of: recording && shown && !reduceMotion, initial: true) { _, blinks in
                if blinks {
                    withAnimation(.easeInOut(duration: RecordingLook.openPulse / 2).repeatForever(autoreverses: true)) { pulsed = true }
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

/// The button that stops a recording, as the iPhone's: a white ring around a red square with round
/// corners. No light under the pointer, as the iPhone has none.
struct StopRecordingButton: View {
    /// Voice Memos', whose square is a little larger and ring heavier than the screen recording's.
    let memo: Bool
    let h: CGFloat
    let action: () -> Void

    var body: some View {
        let side = TimerLayout.content(h)
        let square = side * (memo ? RecordingLook.memoSquare : RecordingLook.screenSquare)
        let ring = side * (memo ? RecordingLook.memoRing : RecordingLook.screenRing)
        Button(action: action) {
            ZStack {
                Circle().strokeBorder(.white, lineWidth: ring)
                RoundedRectangle(cornerRadius: square * RecordingLook.squareCorner, style: .continuous)
                    .fill(RecordingLook.red(memo: memo))
                    .frame(width: square, height: square)
            }
            .frame(width: side, height: side)
            .contentShape(Circle())
        }
        .buttonStyle(IslandPress(highlight: false, contactSize: nil))
        .notchControl()
        .keyControl(.activityFirst, outset: CGSize(width: 3, height: 3), spoken: String(localized: "Stop Recording"), action: action)
        .accessibilityLabel(String(localized: "Stop Recording"))
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

    var body: some View {
        let side = TimerLayout.content(h)
        let square = side * RecordingLook.screenSquare
        let line = side * RecordingLook.screenRing
        let saved = screen.isSaved
        let picture = saved ? side : square
        let corner = saved ? side * PlayerLayout.thumbnailCorner : square * RecordingLook.squareCorner
        let preview: NSImage? = { if case .saved(_, _, let preview) = screen { preview } else { nil } }()
        let label = saved ? String(localized: "Open Recording") : String(localized: "Stop Recording")
        Button(action: press) {
            ZStack {
                Circle().strokeBorder(.white, lineWidth: line)
                    .opacity(screen.isSaving || saved ? 0 : 1)
                SavingSpinner(diameter: side, line: line)
                    .opacity(screen.isSaving ? 1 : 0)
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(RecordingLook.screenRed)
                    .overlay {
                        if let preview {
                            Image(nsImage: preview).resizable().aspectRatio(contentMode: .fill)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                    .frame(width: picture, height: picture)
            }
            .frame(width: side, height: side)
            .contentShape(Circle())
            .animation(NotchMotion.expand, value: saved)
            .animation(.easeOut(duration: 0.3), value: screen.isSaving)
        }
        .buttonStyle(IslandPress(highlight: false, contactSize: nil))
        .disabled(screen.isSaving)
        .notchControl(enabled: !screen.isSaving)
        .keyControl(.activityFirst, outset: CGSize(width: 3, height: 3), spoken: label, action: press)
        .accessibilityLabel(label)
    }

    private func press() {
        switch screen {
        case .countdown, .recording: ScreenRecordingWatch.shared.stop()
        case .saved: ScreenRecordingWatch.shared.openSaved()
        case .saving: break
        }
    }
}
