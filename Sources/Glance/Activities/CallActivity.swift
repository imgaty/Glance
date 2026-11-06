//
//  CallActivity.swift
//  Glance
//
//  Created by Gaty on 05/11/2026.
//

import AVFoundation
import AppKit
import ApplicationServices
import Combine
import CoreAudio
import SwiftUI

/// A call, as the notch shows it.
struct CallShown: Equatable {
    enum Phase: Equatable {
        /// Coming in, and it can be answered from the notch.
        case ringing
        /// Going out, or coming in without a way to answer it from the notch.
        case calling
        case connected(since: Date)
    }

    /// Who it's with, or the app, where the app doesn't say.
    var name: String
    /// What it's over: FaceTime, Phone, Discord.
    var over: String
    /// The app it's in, to go to.
    var app: String?
    var phase: Phase
    /// Its popup shows a button to end it that Glance can press.
    var canEnd = false
    /// The line over the name while it rings, as its popup words it.
    var line: String?
    /// It can be declined from the notch; Discord's own window has no button for that.
    var canDecline = true

    /// As a contact without a picture shows, in a gray circle: the first letters of their first and
    /// last names, or none for a number, which shows a person's outline.
    var initials: String {
        let words = name.split(whereSeparator: \.isWhitespace)
        guard let first = words.first?.first, first.isLetter else { return "" }
        let last = words.count > 1 ? words.last?.first : nil
        return [first, last].compactMap { $0.map { String($0).uppercased() } }.joined()
    }
    var rings: Bool { phase == .ringing }
    var isConnected: Bool {
        if case .connected = phase { return true }
        return false
    }
}

/// How a call looks, measured from published screenshots of real iPhone calls and from macOS's own
/// popup: a green phone and its time on one side, on the other a waveform in both voices at once.
/// Ringing, the caller's initials in a gray circle, and a gray handset.
enum CallLook {
    static let green = Color(red: 0x9A / 255, green: 0xEE / 255, blue: 0x9C / 255)
    static let handset = Color(red: 0x8F / 255, green: 0x8F / 255, blue: 0x91 / 255)
    static let accept = Color(red: 0x67 / 255, green: 0xCD / 255, blue: 0x67 / 255)
    static let decline = Color(red: 0xE9 / 255, green: 0x56 / 255, blue: 0x45 / 255)
    static let speaker = Color(red: 0x2C / 255, green: 0x2C / 255, blue: 0x2E / 255)
    static let avatarTop = Color(red: 0xA4 / 255, green: 0xA8 / 255, blue: 0xB4 / 255)
    static let avatarBottom = Color(red: 0x89 / 255, green: 0x8D / 255, blue: 0x96 / 255)

    /// How much room the waveform takes beside the camera: half the width of macOS's popup's, so its
    /// bars stay sharp, and shorter by less, so they're as tall as they can be.
    static let waveWidth: CGFloat = 45
    /// As shares of the notch's height: the waveform, the phone, the circle, the handset.
    static let waveHeight: CGFloat = 0.6
    static let phone: CGFloat = 0.42
    /// The caller's circle and the handset as large as every other activity's mark beside the camera.
    static let avatar: CGFloat = TimerLayout.ring
    static let handsetSize: CGFloat = 0.49
    /// Between the phone and its time.
    static let timeGap: CGFloat = 5

    /// Inside the round buttons, the symbol's size for the button's, so each is as large in it as
    /// Apple's is, measured from screenshots of real iPhone calls: the handset half as wide as its
    /// button, the phone two fifths, the speaker a little over half.
    static let initials: CGFloat = 0.32
    static let smallInitials: CGFloat = 0.48
    static let endGlyph: CGFloat = 0.4
    static let acceptGlyph: CGFloat = 0.42
    static let speakerGlyph: CGFloat = 0.39

    /// A waveform drawn as macOS's popup draws its own, for a call that has no popup to show it, and
    /// for trying it: the same bars twice over, the other person's darker and stronger to the left,
    /// yours lighter and on top, stronger to the right. In the same size as the popup's picture.
    nonisolated static func drawnWave(theirs: [CGFloat], yours: [CGFloat]) -> CGImage? {
        let width = 180
        let height = 36
        guard let space = CGColorSpace(name: CGColorSpace.displayP3),
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        func color(_ rgb: (CGFloat, CGFloat, CGFloat)) -> CGColor { CGColor(colorSpace: space, components: [rgb.0 / 255, rgb.1 / 255, rgb.2 / 255, 1])! }
        func bar(_ index: Int, _ tall: CGFloat, _ fill: CGColor, _ glow: CGColor) {
            let rect = CGRect(x: CGFloat(index) * 6 + 1, y: (CGFloat(height) - tall) / 2, width: 4, height: tall)
            context.setShadow(offset: .zero, blur: 3, color: glow)
            context.setFillColor(fill)
            context.addPath(CGPath(roundedRect: rect, cornerWidth: 2, cornerHeight: min(2, tall / 2), transform: nil))
            context.fillPath()
        }
        for (index, level) in theirs.enumerated() where level > 0.02 {
            bar(index, max(level * 27, 5), color((0xFF, 0xAF, 0x28)), color((0xE8, 0x93, 0x3E)))
        }
        for (index, level) in yours.enumerated() {
            // Dots of pale yellow with nothing to hear, going green as they get taller.
            let part = min(max((level - 0.15) / 0.35, 0), 1)
            let fill = (0xFF + (0x9C - 0xFF) * part, 0xFF as CGFloat, 0xB5 + (0x91 - 0xB5) * part)
            bar(index, max(level * 27, 5), color(fill), color((0xCC + (0x78 - 0xCC) * part, 0xCB + (0xDB - 0xCB) * part, 0x75)))
        }
        return context.makeImage()
    }
}

enum CallLayout {
    /// Opened, each wing only as wide as the first line of words or the buttons need, whichever's
    /// wider: the second line runs on under the camera, as far as the buttons.
    @MainActor
    static func openWing(firstLine: CGFloat, buttons: CGFloat, restingHeight h: CGFloat) -> CGFloat {
        let left = roundEdge(h) + round(h) + wordsGap(h) + firstLine + LiveActivityView.cameraGap
        let right = LiveActivityView.cameraGap + round(h) * buttons + roundGap(h) * (buttons - 1) + roundEdge(h)
        return max(left, right)
    }

    /// Opened, round things are as large as every other activity's, at the same distance from the
    /// ends and from each other, and the words as far from the caller as AirDrop's from its file.
    static func round(_ h: CGFloat) -> CGFloat { TimerLayout.content(h) }
    static func roundEdge(_ h: CGFloat) -> CGFloat { TimerLayout.buttonEdge(h) }
    static func roundGap(_ h: CGFloat) -> CGFloat { h * TimerLayout.buttonGap }
    static func wordsGap(_ h: CGFloat) -> CGFloat { h * AirDropLayout.gap }

    /// How far in from a wing's end: as far as from the top and bottom, concentric with it.
    static func edge(_ h: CGFloat) -> CGFloat { LiveActivityView.textEdge(restingHeight: h) }

    /// Each wing: as wide as the wider side, against the camera.
    static func wing(for call: CallShown, restingHeight h: CGFloat, at date: Date = .now) -> CGFloat {
        let gap = LiveActivityView.cameraGap
        switch call.phase {
        case .ringing, .calling:
            return max(edge(h) + h * CallLook.avatar + gap, gap + h * CallLook.handsetSize * 1.5 + edge(h))
        case .connected(let since):
            let time = ClockText.of(max(Int(date.timeIntervalSince(since)), 0))
            let words = SystemActivityView.digitsWidth(time, LiveActivityView.textSize(for: h), .semibold)
            return max(edge(h) + h * CallLook.phone * 1.15 + CallLook.timeGap + words + gap, gap + CallLook.waveWidth + edge(h))
        }
    }
}

/// The caller, as a contact without a picture shows: their initials in a gray circle, or for a
/// number, a person's outline.
struct CallAvatar: View {
    let call: CallShown
    let side: CGFloat
    /// Beside the camera, its letters are larger and bolder for the size.
    var small = false

    var body: some View {
        Circle()
            .fill(LinearGradient(colors: [CallLook.avatarTop, CallLook.avatarBottom], startPoint: .top, endPoint: .bottom))
            .overlay {
                if call.initials.isEmpty {
                    Image(systemName: "person.fill")
                        .font(.system(size: side * 0.6))
                        .foregroundStyle(.white)
                } else {
                    Text(call.initials)
                        .font(.system(size: side * (small ? CallLook.smallInitials : CallLook.initials), weight: small ? .semibold : .medium))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: side, height: side)
    }
}

/// How long the call has been going, a second at a time.
struct CallTime: View {
    let since: Date

    var body: some View {
        TimelineView(.periodic(from: since, by: 1)) { context in
            Text(ClockText.of(max(Int(context.date.timeIntervalSince(since)), 0)))
                .monospacedDigit()
        }
    }
}

/// The waveform beside the camera on a call: macOS's popup's own, or for a call without one, drawn
/// as it draws it: both voices over the same width at once.
struct CallWaveform: View {
    let height: CGFloat
    @Environment(\.notchOnScreen) private var onScreen

    var body: some View {
        Group {
            if onScreen {
                LiveCallWave()
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 12)) { _ in
                    if let picture = CallVoices.shared.picture {
                        Image(decorative: picture, scale: 1).resizable()
                    }
                }
            }
        }
        .frame(width: CallLook.waveWidth, height: height)
        .accessibilityHidden(true)
    }
}

/// The waveform on the notch on the screen, shown by Core Animation: through SwiftUI each new picture
/// would redraw the whole notch.
private struct LiveCallWave: NSViewRepresentable {
    func makeNSView(context: Context) -> CallWaveView { CallWaveView() }
    func updateNSView(_ view: CallWaveView, context: Context) {}
}

final class CallWaveView: NSView {
    private var hearing: AnyCancellable?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.contentsGravity = .resize
        layer?.minificationFilter = .linear
    }

    required init?(coder: NSCoder) { fatalError() }

    /// The notch around it takes the clicks.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        hearing =
            window == nil
            ? nil
            : CallVoices.shared.$picture.sink { [weak self] picture in
                MainActor.assumeIsolated {
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    self?.layer?.contents = picture
                    CATransaction.commit()
                }
            }
    }
}

/// A call beside the camera. Ringing, once its popup is swiped away: the caller and a gray handset.
/// Connected: the green phone and the time, and the waveform. Before that, going out: the phone.
struct CallMark: View {
    let call: CallShown
    let restingHeight: CGFloat

    var body: some View {
        let h = restingHeight
        HStack(spacing: 0) {
            switch call.phase {
            case .ringing:
                CallAvatar(call: call, side: h * CallLook.avatar, small: true)
                Spacer(minLength: 0)
                Image(systemName: "phone.down.fill")
                    .font(.system(size: h * CallLook.handsetSize, weight: .medium))
                    .foregroundStyle(CallLook.handset)
            case .calling:
                Image(systemName: "phone.fill")
                    .font(.system(size: h * CallLook.phone, weight: .medium))
                    .foregroundStyle(CallLook.green)
                Spacer(minLength: 0)
            case .connected(let since):
                Image(systemName: "phone.fill")
                    .font(.system(size: h * CallLook.phone, weight: .medium))
                    .foregroundStyle(CallLook.green)
                    .padding(.trailing, CallLook.timeGap)
                CallTime(since: since)
                    .font(.system(size: LiveActivityView.textSize(for: h), weight: .semibold))
                    .foregroundStyle(CallLook.green)
                Spacer(minLength: 0)
                CallWaveform(height: h * CallLook.waveHeight)
            }
        }
        .padding(.horizontal, CallLayout.edge(h))
        .frame(maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            !call.rings ? String(localized: "\(call.name), on a call") : String(localized: "\(call.name), incoming call"))
    }
}

/// A call coming in, as tall as the Alarm: the caller and what it's over, and to decline or accept
/// it, red and green. What it's over stops at the camera; the caller, below it, runs on underneath.
struct IncomingCallView: View {
    let call: CallShown
    let restingHeight: CGFloat
    /// Which button the pointer is on.
    let hovered: AlertButton?

    var body: some View {
        let h = restingHeight
        let side = CallLayout.round(h)
        HStack(spacing: CallLayout.wordsGap(h)) {
            CallAvatar(call: call, side: side)
            VStack(alignment: .leading, spacing: 0) {
                Text(call.line ?? call.over)
                    .font(NotchType.detail)
                    .foregroundStyle(NotchType.detailColor)
                Text(call.name)
                    .font(NotchType.title)
                    .foregroundStyle(.white)
            }
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: CallLayout.roundGap(h)) {
                if call.canDecline {
                    button("phone.down.fill", CallLook.decline, side, CallLook.endGlyph, hovered == .decline)
                        .reportsFrame(.decline)
                        .spokenButton(String(localized: "Decline")) { CallWatch.shared.decline() }
                }
                button("phone.fill", CallLook.accept, side, CallLook.acceptGlyph, hovered == .accept)
                    .reportsFrame(.accept)
                    .spokenButton(String(localized: "Accept")) { CallWatch.shared.accept() }
            }
        }
        .padding(.horizontal, CallLayout.roundEdge(h))
        .frame(maxHeight: .infinity)
    }

    private func button(_ symbol: String, _ color: Color, _ side: CGFloat, _ glyph: CGFloat, _ highlighted: Bool) -> some View {
        Circle()
            .fill(color)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: side * glyph, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .brightness(highlighted ? 0.08 : 0)
            .frame(width: side, height: side)
    }

    /// Each wing: as wide as the wider side, what it's over or the buttons, each from its end.
    @MainActor
    static func wing(for call: CallShown, restingHeight h: CGFloat) -> CGFloat {
        let first = ceil(((call.line ?? call.over) as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: NotchType.size)]).width)
        return CallLayout.openWing(firstLine: first, buttons: call.canDecline ? 2 : 1, restingHeight: h)
    }
}

/// Opened, a call shows as its popup does, as tall as one coming in: the caller, and while it rings,
/// what it's over and buttons to decline or accept it; once connected, its time, a button for the
/// sound output and, where its popup's own can be pressed, one to end it. The first line stops at the
/// camera; the caller, below it, runs on underneath. Clicked anywhere else, it goes to the app it's in.
struct ExpandedCallView: View {
    let call: CallShown
    let restingHeight: CGFloat
    let width: CGFloat
    var revealed = true
    /// How wide the notch is closed, if it shows beside the camera there, for what's there to grow out of.
    var closedWidth: CGFloat? = nil
    @Environment(\.playerKeys) private var keys
    @State private var arrived = false

    var body: some View {
        let h = restingHeight
        let side = CallLayout.round(h)
        // What shows beside the camera grows out of there, as the Timer's does: the caller while it
        // rings, the time once it's going. The rest fades in.
        let out = revealed && arrived
        let spread = ((closedWidth ?? width) - width) / 2
        let rise = (h - TimerLayout.tallHeight(h)) / 2
        let avatarFrom = CGSize(width: CallLayout.edge(h) - CallLayout.roundEdge(h) - spread, height: rise)
        let line = NSLayoutManager().defaultLineHeight(for: NSFont.systemFont(ofSize: NotchType.size))
        let words = CallLayout.roundEdge(h) + side + CallLayout.wordsGap(h)
        let timeFrom = CGSize(
            width: CallLayout.edge(h) + h * CallLook.phone * 1.15 + CallLook.timeGap - words - spread, height: rise + line / 2)
        HStack(spacing: CallLayout.wordsGap(h)) {
            Button {
                CallWatch.shared.goToApp()
            } label: {
                HStack(spacing: CallLayout.wordsGap(h)) {
                    CallAvatar(call: call, side: side)
                        .modifier(
                            GrowsOut(out: out || closedWidth == nil || !call.rings, scale: h * CallLook.avatar / side, anchor: .leading, from: avatarFrom)
                        )
                        .modifier(GrownFade(shown: revealed, grows: closedWidth != nil && call.rings))
                    VStack(alignment: .leading, spacing: 0) {
                        if case .connected(let since) = call.phase {
                            CallTime(since: since)
                                .font(NotchType.detail)
                                .foregroundStyle(CallLook.green)
                                .modifier(
                                    GrowsOut(
                                        out: out || closedWidth == nil, scale: LiveActivityView.textSize(for: h) / NotchType.size, anchor: .leading,
                                        from: timeFrom)
                                )
                                .modifier(GrownFade(shown: revealed, grows: closedWidth != nil))
                        } else {
                            Text(call.line ?? call.over)
                                .font(NotchType.detail)
                                .foregroundStyle(NotchType.detailColor)
                                .modifier(PageFade(hidden: !revealed))
                        }
                        Text(call.name)
                            .font(NotchType.title)
                            .foregroundStyle(.white)
                            .modifier(PageFade(hidden: !revealed))
                    }
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            // Clicked, it goes to the app, and doesn't sink in as a button does.
            .buttonStyle(StillPress())
            .notchControl()
            .help(String(localized: "Show in \(call.over)"))
            .accessibilityLabel(!call.rings ? String(localized: "\(call.name), on a call") : String(localized: "\(call.name), incoming call"))
            .accessibilityHint(String(localized: "Show in \(call.over)"))
            HStack(spacing: CallLayout.roundGap(h)) { buttons(h) }
                .modifier(PageFade(hidden: !revealed))
        }
        .padding(.horizontal, CallLayout.roundEdge(h))
        .frame(width: width, height: TimerLayout.tallHeight(h))
        .accessibilityElement(children: .contain)
        .onAppear { withAnimation(NotchMotion.expand) { arrived = true } }
    }

    @ViewBuilder private func buttons(_ h: CGFloat) -> some View {
        let side = CallLayout.round(h)
        if !call.rings {
            IslandCircleButton(control: .activityFirst, height: h, tint: .white, label: String(localized: "Sound Output"), fill: CallLook.speaker, side: side) {
                // From the keyboard the pointer can be anywhere: the menu opens under the button.
                let fromKeys = NSApp.currentEvent?.type == .keyDown
                AudioOutput.shared.showMenu(at: fromKeys ? keys?.focusFrame.flatMap { keys?.screenPoint?($0) } : nil, withVolume: false, outputsOnly: true)
            } glyph: {
                glyph("speaker.wave.3.fill", CallLook.speakerGlyph, side)
            }
            if call.canEnd {
                IslandCircleButton(control: .activitySecond, height: h, tint: .white, label: String(localized: "End"), fill: CallLook.decline, side: side) {
                    CallWatch.shared.end()
                } glyph: {
                    glyph("phone.down.fill", CallLook.endGlyph, side)
                }
            }
        } else {
            if call.canDecline {
                IslandCircleButton(control: .activityFirst, height: h, tint: .white, label: String(localized: "Decline"), fill: CallLook.decline, side: side) {
                    CallWatch.shared.decline()
                } glyph: {
                    glyph("phone.down.fill", CallLook.endGlyph, side)
                }
            }
            IslandCircleButton(control: .activitySecond, height: h, tint: .white, label: String(localized: "Accept"), fill: CallLook.accept, side: side) {
                CallWatch.shared.accept()
            } glyph: {
                glyph("phone.fill", CallLook.acceptGlyph, side)
            }
        }
    }

    private func glyph(_ symbol: String, _ share: CGFloat, _ side: CGFloat) -> some View {
        Image(systemName: symbol)
            .font(.system(size: side * share, weight: .semibold))
            .foregroundStyle(.white)
    }

    /// Each side of the camera: as wide as the wider of the first line and the buttons, each from its end.
    @MainActor
    static func wing(for call: CallShown, restingHeight h: CGFloat, at date: Date = .now) -> CGFloat {
        guard case .connected(let since) = call.phase else { return IncomingCallView.wing(for: call, restingHeight: h) }
        let time = SystemActivityView.digitsWidth(ClockText.of(max(Int(date.timeIntervalSince(since)), 0)), NotchType.size, .regular)
        return CallLayout.openWing(firstLine: time, buttons: call.canEnd ? 2 : 1, restingHeight: h)
    }

    @MainActor
    static func width(for call: CallShown, restingHeight h: CGFloat, closedWidth: CGFloat) -> CGFloat {
        closedWidth + wing(for: call, restingHeight: h) * 2
    }
}

// MARK: - Voices

/// The waveform's picture during a call. On a phone or FaceTime call, it's macOS's popup's own, as it
/// shows, with nothing listened to. Otherwise, it's drawn the same way: the other person from the
/// sound the call's app makes, through the same process tap as the music's waveform, and you from
/// the microphone, once it's allowed. Nothing is recorded or kept. It runs only during a call.
@MainActor
final class CallVoices: ObservableObject {
    static let shared = CallVoices()

    @Published private(set) var picture: CGImage?
    private var seen = false
    private var theirs: CGFloat = 0
    private var yours: CGFloat = 0
    /// What's drawn of each voice, easing towards what's heard: quickly up, more slowly down, as
    /// the popup's bars do.
    private var shownTheirs: CGFloat = 0
    private var shownYours: CGFloat = 0
    /// How loud each voice has been, a thirtieth of a second at a time, newest first.
    private var theirHistory = [CGFloat](repeating: 0, count: 30)
    private var yourHistory = [CGFloat](repeating: 0, count: 30)
    private var pipeline: TapPipeline?
    private var engine: AVAudioEngine?
    private var clock: Timer?
    /// At the bench: both voices made up, turn about, with nothing listened to.
    var madeUp = false

    /// The popup's own, as it just showed: sent only when it changes, so a call gone quiet stays on
    /// its last, which is flat.
    func saw(_ popup: CGImage) {
        guard clock != nil else { return }
        seen = true
        picture = popup
    }

    func start(listeningTo pid: pid_t?, microphone: Bool) {
        guard clock == nil else { return }
        if !madeUp, let pid, pid > 0, Permissions.audioCapture == .granted {
            pipeline = TapPipeline(target: .player(pid)) { [weak self] reading in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        let loud = Double(reading.levels.reduce(0, +)) / Double(max(reading.levels.count, 1))
                        self?.theirs = min(CGFloat(loud) * 2.4, 1)
                    }
                }
            }
        }
        if !madeUp, microphone { startMicrophone() }
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        clock = timer
        tick()
    }

    func stop() {
        clock?.invalidate()
        clock = nil
        pipeline?.stop()
        pipeline = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        theirs = 0
        yours = 0
        shownTheirs = 0
        shownYours = 0
        theirHistory = theirHistory.map { _ in 0 }
        yourHistory = yourHistory.map { _ in 0 }
        seen = false
        picture = nil
    }

    private func tick() {
        guard !seen else { return }
        let t = Date.now.timeIntervalSinceReferenceDate
        if madeUp {
            // They speak, you speak, both, neither.
            let turn = Int(t / 2.5) % 4
            let voice = 0.9 * CGFloat(DJGlyph.flap(at: t))
            theirs = turn == 0 || turn == 2 ? voice : 0
            yours = turn == 1 || turn == 2 ? voice : 0
        }
        shownTheirs = Self.eased(shownTheirs, towards: theirs)
        shownYours = Self.eased(shownYours, towards: yours)
        theirHistory = [shownTheirs] + theirHistory.dropLast()
        yourHistory = [shownYours] + yourHistory.dropLast()
        let bars = Self.shaped(theirs: theirHistory, yours: yourHistory)
        picture = CallLook.drawnWave(theirs: bars.theirs, yours: bars.yours)
    }

    /// A step of easing, thirty times a second.
    nonisolated static func eased(_ shown: CGFloat, towards heard: CGFloat) -> CGFloat {
        shown + (heard - shown) * (heard > shown ? 0.55 : 0.18)
    }

    /// The bars of each voice from how loud it's just been, over the same width, as the popup's: the
    /// other person's newest at the left, running right and dying away, yours mirrored from the right.
    /// Nothing's made up: a bar is a moment of that voice.
    nonisolated static func shaped(theirs: [CGFloat], yours: [CGFloat]) -> (theirs: [CGFloat], yours: [CGFloat]) {
        let count = min(theirs.count, yours.count)
        func fading(_ place: Double) -> CGFloat { CGFloat(min(max((0.62 - place) / 0.22, 0), 1)) }
        let them = (0..<count).map { bar in min(theirs[bar] * fading((Double(bar) + 0.5) / Double(count)), 1) }
        let you = (0..<count).map { bar in min(yours[count - 1 - bar] * fading(1 - (Double(bar) + 0.5) / Double(count)), 1) }
        return (them, you)
    }

    private func startMicrophone() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            listenToMicrophone()
        case .notDetermined:
            Task { [weak self] in
                guard await AVCaptureDevice.requestAccess(for: .audio), self?.clock != nil else { return }
                self?.listenToMicrophone()
            }
        default:
            break
        }
    }

    private func listenToMicrophone() {
        guard engine == nil else { return }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { [weak self] buffer, _ in
            guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
            let count = Int(buffer.frameLength)
            var sum: Float = 0
            for index in 0..<count { sum += channel[index] * channel[index] }
            let level = CGFloat(min((sum / Float(count)).squareRoot() * 7, 1))
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.yours = level }
            }
        }
        do {
            try engine.start()
            self.engine = engine
        } catch {
            input.removeTap(onBus: 0)
        }
    }
}

// MARK: - Which calls

/// The calls there are: a phone or FaceTime call from macOS's own popup for it, and apps like Zoom
/// and Discord, which tell the system nothing on a Mac, from one of them using the microphone.
@MainActor
final class CallWatch: ObservableObject {
    static let shared = CallWatch()

    @Published private(set) var call: CallShown?
    /// Counted a minute at a time during a call, so the notch refits as its time gains a digit.
    @Published private(set) var minutes = 0

    private var microphone: CallAudio.App?
    private var popup: CallPopup?
    /// Who the call is with, kept from its popup in case that's closed during it.
    private var who: String?
    private var since: Date?
    private var watch: Timer?
    private var minuteTimer: Timer?
    private var showing: CallShown?

    func start() {
        guard ActivityBench.scene == nil else { return }
        CallBanners.shared.changed = { [weak self] popup in
            self?.popup = popup
            if let name = popup?.name { self?.who = name }
            self?.refresh()
        }
        // Reading whether the microphone's in use costs next to nothing; it's read rarely.
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                CallBanners.shared.follow()
                self?.microphone = CallAudio.appOnMicrophone()
                self?.refresh()
                self?.refitAsTimeGrows()
            }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        watch = timer
        CallBanners.shared.follow()
        refresh()
    }

    private var turnedOn: Bool {
        let defaults = UserDefaults.standard
        return defaults.bool(forKey: Preferences.activityCalls) && defaults.bool(forKey: Preferences.notchEnabled)
    }

    private func refresh() {
        CallBanners.shared.hides = turnedOn
        guard turnedOn else { return show(nil) }
        if let popup {
            let app = Self.appleApp(detail: popup.detail, phoneRunning: Self.phoneRunning)
            let name = popup.name ?? who ?? app.name
            if Self.connected(popup, microphone: microphone != nil) {
                // Until its popup's time is settled, as near as can be known.
                let started = popup.started ?? since ?? popup.elapsed.map { .now - TimeInterval($0) } ?? .now
                since = started
                show(CallShown(name: name, over: app.name, app: app.bundle, phase: .connected(since: started), canEnd: popup.red != nil))
            } else if popup.readable, popup.green != nil {
                show(CallShown(name: name, over: app.name, app: app.bundle, phase: .ringing, line: popup.detail))
            } else {
                show(CallShown(name: name, over: app.name, app: app.bundle, phase: .calling, canEnd: popup.red != nil))
            }
        } else if let ringing = DiscordCall.ringing(), microphone == nil {
            // Discord tells of a call coming in only in its own window.
            show(CallShown(name: ringing.name, over: "Discord", app: DiscordCall.bundle, phase: .ringing, canDecline: false))
        } else if let microphone {
            let apple = microphone.bundle == CallAudio.appleService
            let app = apple ? Self.appleApp(detail: nil, phoneRunning: Self.phoneRunning) : (name: microphone.name, bundle: microphone.bundle)
            // Discord says who it's with and for how long.
            let discord = microphone.bundle.hasPrefix(DiscordCall.bundle) ? DiscordCall.shared.read() : nil
            if let elapsed = discord?.elapsed {
                let shown = Date.now - TimeInterval(elapsed)
                if since.map({ abs($0.timeIntervalSince(shown)) > 1.5 }) ?? true { since = shown }
            }
            let started = since ?? .now
            since = started
            if let name = discord?.name { who = name }
            show(
                CallShown(
                    name: discord?.name ?? who ?? app.name, over: app.name, app: app.bundle, phase: .connected(since: started),
                    canEnd: DiscordCall.shared.canEnd))
        } else {
            who = nil
            since = nil
            DiscordCall.shared.forget()
            show(nil)
        }
    }

    /// It's connected once it shows a time. Before it can be read, a call service using the
    /// microphone says so, as long as there's no button to accept it.
    nonisolated static func connected(_ popup: CallPopup, microphone: Bool) -> Bool {
        popup.elapsed != nil || (microphone && popup.green == nil)
    }

    private static var phoneRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: CallAudio.phone).isEmpty
    }

    /// Which of Apple's apps the call is in. Both go through the same popup, which names FaceTime
    /// when it's FaceTime; Phone starts only for a phone call.
    nonisolated static func appleApp(detail: String?, phoneRunning: Bool) -> (name: String, bundle: String) {
        if detail?.contains("FaceTime") == true || !phoneRunning { return ("FaceTime", CallAudio.faceTime) }
        return ("Phone", CallAudio.phone)
    }

    private func show(_ next: CallShown?) {
        guard next != showing else { return }
        let before = showing
        showing = next
        call = next
        // A call coming in shows as tall as the Alarm, until it's answered, swiped away or over.
        if next?.rings == true, before?.rings != true, let next {
            Activities.shared.post(
                NotchAlert(
                    kind: .incomingCall, content: .incomingCall(next), spoken: String(localized: "\(next.name), incoming call"), stays: true))
        } else if next?.rings != true {
            Activities.shared.dismiss(.incomingCall)
        }
        if next?.isConnected == true {
            // The popup's waveform has both voices; without one, they're listened to.
            CallVoices.shared.start(listeningTo: popup?.readable == true ? nil : CallAudio.pid(ofCallIn: microphone?.bundle), microphone: popup?.readable != true)
            if minuteTimer == nil {
                let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.minutes += 1 }
                }
                RunLoop.main.add(timer, forMode: .common)
                minuteTimer = timer
            }
        } else {
            CallVoices.shared.stop()
            minuteTimer?.invalidate()
            minuteTimer = nil
        }
    }

    func accept() {
        Activities.shared.dismiss(.incomingCall)
        guard ActivityBench.scene == nil else { return ActivityBench.shared.answered() }
        if popup == nil, call?.app == DiscordCall.bundle { return DiscordCall.shared.accept() }
        CallBanners.shared.press(.green)
    }

    /// The notch refits as soon as the time gains a digit, at 10:00 or 1:00:00, not a minute after.
    private var timeLength = 0
    private func refitAsTimeGrows() {
        guard case .connected(let since) = call?.phase else { return timeLength = 0 }
        let length = ClockText.of(max(Int(Date.now.timeIntervalSince(since)), 0)).count
        if length != timeLength {
            timeLength = length
            minutes += 1
        }
    }

    func decline() {
        Activities.shared.dismiss(.incomingCall)
        end()
    }

    /// Ends it, with the popup's own End button, or in Discord, with its own.
    func end() {
        guard ActivityBench.scene == nil else { return ActivityBench.shared.stopped(.call) }
        if popup == nil, microphone?.bundle.hasPrefix(DiscordCall.bundle) == true { return DiscordCall.shared.end() }
        CallBanners.shared.press(.red)
    }

    /// To the call, in its app.
    func goToApp() {
        guard ActivityBench.scene == nil else { return }
        let bundle = CallAudio.appBundle(of: call?.app ?? CallAudio.faceTime)
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    /// At the bench: made up, the real one left alone.
    func bench(_ made: CallShown?) {
        CallVoices.shared.madeUp = true
        show(made)
    }
}

/// Discord's own window, read through Accessibility, which Discord lets Glance turn on for it as an
/// Electron app: its "Voice Connected" link names the call and shows its time, whatever language
/// Discord is in, and the button beside it leaves the call. Only read during a call in Discord,
/// and turned off again after.
@MainActor
final class DiscordCall {
    static let shared = DiscordCall()
    static let bundle = "com.hnc.Discord"

    struct Reading: Equatable {
        var name: String
        var elapsed: Int?
        /// Coming in, not yet joined.
        var ringing = false
    }

    private var askedPID: pid_t = 0
    private var link: AXUIElement?
    private var leave: AXUIElement?
    private var join: AXUIElement?

    var canAnswer: Bool { join != nil }

    var canEnd: Bool { leave != nil }

    /// Who the call is with and how long it's been going, as Discord shows them now.
    func read() -> Reading? {
        guard AXIsProcessTrusted(), let app = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundle).first else {
            forget()
            return nil
        }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.3)
        if askedPID != app.processIdentifier {
            AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            askedPID = app.processIdentifier
            link = nil
        }
        // What was found last, if it still says something; Discord redraws it, renamed say, and
        // then it's looked for afresh.
        if let link, let found = Self.reading(link) { return found }
        link = Self.findLink(in: element)
        leave = link.flatMap(Self.leaveButton(beside:))
        if let link { return Self.reading(link) }
        // Not joined yet: a call coming in shows in the list of messages, by who it's from.
        join = Self.findJoin(in: element)
        return Self.ringingName(in: element).map { Reading(name: $0, ringing: true) }
    }

    private static func reading(_ link: AXUIElement) -> Reading? {
        let parts = parts(of: link)
        return reading(name: parts.name, time: parts.time)
    }

    /// Answers it, as Discord's own Join Voice Call does.
    func accept() {
        guard let join else { return }
        AXUIElementPerformAction(join, kAXPressAction as CFString)
    }

    /// Who a call coming in is from: the message list says "Name (direct message), Incoming Call".
    nonisolated static func ringingName(from words: String) -> String? {
        guard words.contains("Incoming Call"), let end = words.range(of: " (direct message)") else { return nil }
        let name = words[..<end.lowerBound].replacingOccurrences(of: "unread, ", with: "")
        return name.isEmpty ? nil : name
    }

    private static func ringingName(in app: AXUIElement) -> String? {
        for window in SystemNotices.value(app, kAXWindowsAttribute) as? [AXUIElement] ?? [] {
            let links = SystemNotices.findAll(in: window) { SystemNotices.value($0, kAXRoleAttribute) as? String == "AXLink" }
            for link in links {
                if let name = ringingName(from: SystemNotices.value(link, kAXDescriptionAttribute) as? String ?? "") { return name }
            }
        }
        return nil
    }

    private static func findJoin(in app: AXUIElement) -> AXUIElement? {
        for window in SystemNotices.value(app, kAXWindowsAttribute) as? [AXUIElement] ?? [] {
            let buttons = SystemNotices.findAll(in: window) {
                SystemNotices.value($0, kAXRoleAttribute) as? String == kAXButtonRole
                    && ["Join Voice Call", "Join Call"].contains(SystemNotices.value($0, kAXDescriptionAttribute) as? String ?? "")
            }
            if let first = buttons.first { return first }
        }
        return nil
    }

    /// A call coming in: Discord's window takes the title "Incoming Call" every other second while
    /// it rings, which shows without asking Discord for anything; only then is its window read, for
    /// who it's from.
    static func ringing() -> Reading? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first else { return nil }
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let titled = windows.contains {
            ($0[kCGWindowOwnerPID as String] as? pid_t) == app.processIdentifier
                && ($0[kCGWindowName as String] as? String)?.hasPrefix("Incoming Call") == true
        }
        if titled { ringingSeen = .now }
        guard let seen = ringingSeen, Date.now.timeIntervalSince(seen) < 3 else { return nil }
        guard let reading = shared.read(), reading.ringing else { return nil }
        return reading
    }

    private static var ringingSeen: Date?

    /// Leaves the call, as Discord's own button does.
    func end() {
        guard let leave else { return }
        AXUIElementPerformAction(leave, kAXPressAction as CFString)
    }

    /// The call's over: Discord's accessibility goes back to how it was.
    func forget() {
        if askedPID != 0, let app = NSRunningApplication(processIdentifier: askedPID) {
            AXUIElementSetAttributeValue(AXUIElementCreateApplication(app.processIdentifier), "AXManualAccessibility" as CFString, kCFBooleanFalse)
        }
        askedPID = 0
        link = nil
        leave = nil
        join = nil
    }

    /// The name, and the time when there's one, which comes as minutes and seconds.
    nonisolated static func reading(name: String?, time: String?) -> Reading? {
        guard let name = name?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }
        return Reading(name: name, elapsed: CallPopup.elapsed(in: time))
    }

    /// A link whose words end in a running time.
    private static func findLink(in app: AXUIElement) -> AXUIElement? {
        for window in SystemNotices.value(app, kAXWindowsAttribute) as? [AXUIElement] ?? [] {
            let links = SystemNotices.findAll(in: window) { element in
                SystemNotices.value(element, kAXRoleAttribute) as? String == "AXLink"
                    && CallPopup.elapsed(in: SystemNotices.value(element, kAXDescriptionAttribute) as? String) != nil
            }
            if let first = links.first { return first }
        }
        return nil
    }

    /// Its words: the status in a group of its own, the name on its own, the time last in a group.
    private static func parts(of link: AXUIElement) -> (name: String?, time: String?) {
        let children = SystemNotices.value(link, kAXChildrenAttribute) as? [AXUIElement] ?? []
        let name = children.first { SystemNotices.value($0, kAXRoleAttribute) as? String == kAXStaticTextRole }
            .flatMap { SystemNotices.value($0, kAXValueAttribute) as? String }
        let time = children.last.flatMap { group in
            SystemNotices.findAll(in: group) { SystemNotices.value($0, kAXRoleAttribute) as? String == kAXStaticTextRole }.last
        }
        .flatMap { SystemNotices.value($0, kAXValueAttribute) as? String }
        return (name, time)
    }

    /// The button to leave, among the call's controls beside the link: named so in English, or else
    /// the one just before the camera's switch, where Discord keeps it in every language.
    private static func leaveButton(beside link: AXUIElement) -> AXUIElement? {
        guard let parent = SystemNotices.value(link, kAXParentAttribute), let row = SystemNotices.value(parent as! AXUIElement, kAXParentAttribute)
        else { return nil }
        let controls = SystemNotices.value(row as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement] ?? []
        if let named = controls.first(where: { SystemNotices.value($0, kAXDescriptionAttribute) as? String == "Disconnect" }) { return named }
        guard let camera = controls.firstIndex(where: { SystemNotices.value($0, kAXRoleAttribute) as? String == kAXCheckBoxRole }), camera > 0,
            SystemNotices.value(controls[camera - 1], kAXRoleAttribute) as? String == kAXButtonRole
        else { return nil }
        return controls[camera - 1]
    }
}

/// Who's using the microphone and making sound, from Core Audio's list of processes.
enum CallAudio {
    static let faceTime = "com.apple.FaceTime"
    static let phone = "com.apple.mobilephone"
    /// Apple's calls use the microphone through this.
    static let appleService = "com.apple.avconferenced"

    struct App: Equatable {
        var bundle: String
        var name: String
    }

    /// Apps that call, by the start of their bundle ID, which their helpers share. Apple's calls go
    /// through a service of their own.
    static let callApps: [(prefix: String, name: String)] = [
        ("com.apple.FaceTime", "FaceTime"), ("com.apple.mobilephone", "Phone"), ("com.apple.avconferenced", "FaceTime"),
        ("com.apple.TelephonyUtilities", "Phone"), ("us.zoom.xos", "Zoom"), ("com.hnc.Discord", "Discord"),
        ("net.whatsapp.WhatsApp", "WhatsApp"), ("desktop.WhatsApp", "WhatsApp"), ("com.microsoft.teams", "Microsoft Teams"),
        ("com.tinyspeck.slackmacgap", "Slack"), ("ru.keepcoder.Telegram", "Telegram"), ("org.telegram", "Telegram"),
        ("org.whispersystems.signal-desktop", "Signal"), ("com.skype", "Skype"), ("Cisco-Systems.Spark", "Webex"),
        ("com.webex", "Webex"), ("com.ringcentral", "RingCentral"), ("com.loom", "Loom"),
    ]

    /// The app itself, for one of its helpers, which can't be opened: Discord's sound comes from
    /// "com.hnc.Discord.helper.Renderer", whose app is "com.hnc.Discord".
    nonisolated static func appBundle(of bundle: String) -> String {
        callApps.first { bundle.hasPrefix($0.prefix) && $0.prefix.contains(".") && !$0.prefix.hasSuffix(".") }
            .map { bundle.hasPrefix($0.prefix + ".helper") || bundle.hasPrefix($0.prefix + ".Helper") ? $0.prefix : bundle } ?? bundle
    }

    /// The calling app a bundle ID belongs to.
    static func callApp(of bundle: String) -> App? {
        callApps.first { bundle.hasPrefix($0.prefix) }.map { App(bundle: bundle, name: $0.name) }
    }

    private struct Process {
        var pid: pid_t
        var bundle: String
        var input: Bool
        var output: Bool
    }

    private static func processes() -> [Process] {
        var address = AudioProperty.address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioProperty.system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioProperty.system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            func flag(_ selector: AudioObjectPropertySelector) -> Bool {
                var address = AudioProperty.address(selector)
                var value: UInt32 = 0
                var size = UInt32(MemoryLayout<UInt32>.size)
                return AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr && value != 0
            }
            var pid: pid_t = 0
            var pidSize = UInt32(MemoryLayout<pid_t>.size)
            var pidAddress = AudioProperty.address(kAudioProcessPropertyPID)
            guard AudioObjectGetPropertyData(id, &pidAddress, 0, nil, &pidSize, &pid) == noErr else { return nil }
            var name: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            var nameAddress = AudioProperty.address(kAudioProcessPropertyBundleID)
            guard AudioObjectGetPropertyData(id, &nameAddress, 0, nil, &nameSize, &name) == noErr, let bundle = name?.takeRetainedValue() as String?
            else { return nil }
            return Process(
                pid: pid, bundle: bundle, input: flag(kAudioProcessPropertyIsRunningInput), output: flag(kAudioProcessPropertyIsRunningOutput))
        }
    }

    /// A calling app using the microphone now.
    static func appOnMicrophone() -> App? {
        processes().lazy.filter(\.input).compactMap { callApp(of: $0.bundle) }.first
    }

    /// The process making the call's sound: of the app, or of any calling app.
    static func pid(ofCallIn bundle: String?) -> pid_t? {
        let all = processes().filter { callApp(of: $0.bundle) != nil }
        let same = bundle.flatMap { wanted in callApp(of: wanted).map { app in all.filter { callApp(of: $0.bundle)?.name == app.name } } } ?? all
        return (same.first(where: \.output) ?? same.first(where: \.input) ?? same.first)?.pid
    }
}

/// macOS's popup for a phone or FaceTime call, at the top right of the screen, in Notification
/// Center's window, for the whole of the call. Accessibility finds it but can't see into it, so
/// it's read from its picture (see `CallPopup`), and its buttons are clicked where they show.
///
/// Once the notch can offer the same, that window is held out of sight (see `NotificationWindow`).
/// Until then, or without Screen Recording, it's left alone. Without Accessibility, nothing's found
/// and it shows as before.
@MainActor
final class CallBanners {
    static let shared = CallBanners()

    static let center = NotificationWindow.center
    /// The process drawing the popup, which runs only around a call.
    private static let popupProcess = "com.apple.FaceTime.FaceTimeNotificationExtension"

    enum Button {
        case red, green
    }

    var changed: ((CallPopup?) -> Void)?
    var hides = true {
        didSet {
            guard hides != oldValue, !hides else { return }
            NotificationWindow.shared.letGo(.call)
            scan()
        }
    }

    private var centerPID: pid_t = 0
    private var observer: AXObserver?
    private var timer: Timer?
    private var found: (banner: AXUIElement, window: AXUIElement)?
    private var popup: CallPopup?
    private var reading = false
    private var pressing = false
    private var readCarefully = false
    private var mustRead = false
    private var checkedAt: Date?
    private var askedForScreen = false
    private lazy var wave = CallPopupWave { picture in
        nonisolated(unsafe) let picture = picture
        DispatchQueue.main.async { MainActor.assumeIsolated { CallVoices.shared.saw(picture) } }
    }

    /// Follows Notification Center, as soon as Accessibility is allowed, and again if it's restarted.
    func follow() {
        guard AXIsProcessTrusted(),
            let pid = NSRunningApplication.runningApplications(withBundleIdentifier: Self.center).first?.processIdentifier
        else { return }
        if timer == nil {
            NotificationWindow.shared.start()
            // As well as when it's told: a real notification can't be made to show, to prove it always is.
            let made = Timer(timeInterval: 1, repeats: true) { _ in
                MainActor.assumeIsolated {
                    SystemNotices.sweep()
                    CallBanners.shared.scan()
                }
            }
            made.tolerance = 0.2
            RunLoop.main.add(made, forMode: .common)
            timer = made
        }
        guard pid != centerPID else { return }
        var made: AXObserver?
        // Anything Notification Center shows: a call's popup, or something the notch says already.
        let told: AXObserverCallback = { _, _, _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    NotificationWindow.shared.check()
                    SystemNotices.sweep()
                    CallBanners.shared.scan()
                }
            }
        }
        guard AXObserverCreate(pid, told, &made) == .success, let made else { return }
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode) }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        AXObserverAddNotification(made, app, kAXWindowCreatedNotification as CFString, nil)
        AXObserverAddNotification(made, app, kAXCreatedNotification as CFString, nil)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(made), .defaultMode)
        centerPID = pid
        observer = made
    }

    private func scan() {
        guard centerPID != 0, !pressing else { return }
        guard hides else {
            if found != nil { give() }
            return
        }
        // Nothing's asked of Notification Center unless a call might be up.
        guard found != nil || !NSRunningApplication.runningApplications(withBundleIdentifier: Self.popupProcess).isEmpty else { return }
        guard let now = findPopup() else {
            if found != nil { give() }
            return
        }
        found = now
        if popup == nil {
            popup = CallPopup()
            changed?(popup)
        }
        // Once it's connected and read, there's nothing new to read until a button's pressed, but
        // for checking its time now and then, in case the Mac slept.
        if popup?.readable != true || popup?.elapsed == nil || mustRead || popup?.started == nil || checkedAt.map({ Date.now.timeIntervalSince($0) > 60 }) ?? true {
            read()
        }
    }

    private func findPopup() -> (banner: AXUIElement, window: AXUIElement)? {
        let app = AXUIElementCreateApplication(centerPID)
        AXUIElementSetMessagingTimeout(app, 0.5)
        for window in SystemNotices.value(app, kAXWindowsAttribute) as? [AXUIElement] ?? [] {
            let banners = SystemNotices.findAll(in: window) {
                (SystemNotices.value($0, kAXIdentifierAttribute) as? String ?? "").contains("FACETIME")
            }
            if let banner = banners.first { return (banner, window) }
        }
        return nil
    }

    private func frame(of element: AXUIElement?) -> CGRect? {
        guard let element, let value = SystemNotices.value(element, "AXFrame") else { return nil }
        var rect = CGRect.zero
        return AXValueGetValue(value as! AXValue, .cgRect, &rect) ? rect : nil
    }

    /// Takes a picture of it and reads that, off the main thread, then hides it if that's all that
    /// was missing.
    private func read() {
        guard !reading, let found, let rect = frame(of: found.banner) else { return }
        guard CGPreflightScreenCaptureAccess() else {
            if !askedForScreen {
                askedForScreen = true
                CGRequestScreenCaptureAccess()
            }
            return
        }
        reading = true
        Task {
            await readNow(rect)
            mustRead = false
            checkedAt = .now
            conceal()
            await settleTime(rect)
            reading = false
        }
    }

    /// Its time only changes once a second, so it's read over and over until it does, which says
    /// when it started to within a tenth of a second or so. It's done again if it's ever a second out.
    private func settleTime(_ rect: CGRect) async {
        guard let shown = popup?.elapsed else { return }
        if let started = popup?.started, abs(Date.now.timeIntervalSince(started) - TimeInterval(shown)) < 1.5 { return }
        guard let window = await CallPopupCamera.window() else { return }
        var before = Date.now
        var last = shown
        let giveUp = Date.now.addingTimeInterval(3)
        while Date.now < giveUp, found != nil, !pressing {
            guard let current = frame(of: found?.banner), let image = await CallPopupCamera.picture(of: current, in: window) else { return }
            let seen = await Task.detached(priority: .userInitiated) { CallPopup.read(image, accurate: false) }.value
            let after = Date.now
            guard let time = seen.elapsed else { continue }
            if time != last {
                popup?.detail = seen.detail
                popup?.started = CallPopup.started(changedBetween: before, and: after, to: time)
                changed?(popup)
                return
            }
            last = time
            before = after
        }
    }

    private func readNow(_ rect: CGRect) async {
        guard let window = await CallPopupCamera.window(), let image = await CallPopupCamera.picture(of: rect, in: window) else { return }
        let seen = await Task.detached(priority: .userInitiated) { CallPopup.read(image, accurate: false) }.value
        guard found != nil else { return }
        update(with: seen)
        // Names read at once are in Latin letters only: the slower reading covers the Mac's languages.
        if seen.name != nil, !readCarefully {
            readCarefully = true
            Task {
                let careful = await Task.detached(priority: .utility) { CallPopup.read(image, accurate: true) }.value
                if found != nil, let name = careful.name, name != popup?.name, popup != nil {
                    popup?.name = name
                    changed?(popup)
                }
            }
        }
    }

    private func update(with seen: CallPopup) {
        var next = seen
        if readCarefully, let name = popup?.name { next.name = name }
        next.name = next.name ?? popup?.name
        next.started = popup?.started
        guard next != popup else { return }
        popup = next
        changed?(next)
    }

    /// Out of sight, if the notch has everything it needs to stand in for it.
    private func conceal() {
        guard hides, !pressing, popup?.readable == true, let found else { return }
        NotificationWindow.shared.hold(.call)
        guard !wave.running, let rect = frame(of: found.banner) else { return }
        Task {
            guard let window = await CallPopupCamera.window() else { return }
            await wave.start(window: window, popup: rect)
        }
    }

    /// It's gone: Notification Center's window goes back where it was, for every notification after.
    private func give() {
        wave.stop()
        NotificationWindow.shared.letGo(.call)
        found = nil
        popup = nil
        readCarefully = false
        mustRead = false
        checkedAt = nil
        changed?(nil)
    }

    /// Clicks one of its buttons, where it shows right now, with the pointer put back after. The
    /// popup comes back for that moment, as only what's on screen can be clicked; if the button
    /// can't be found, it stays, for a person to press.
    func press(_ button: Button) {
        guard !pressing, let found else { return }
        pressing = true
        Task {
            defer { pressing = false }
            if let rect = frame(of: found.banner) { await readNow(rect) }
            let spot = button == .green ? popup?.green : popup?.red
            NotificationWindow.shared.letGo(.call)
            NotificationWindow.shared.bringBack()
            guard let spot else { return }
            try? await Task.sleep(for: .milliseconds(120))
            guard let rect = frame(of: found.banner) else { return }
            await Self.click(at: CGPoint(x: rect.minX + rect.width * spot.x, y: rect.minY + rect.height * spot.y))
            try? await Task.sleep(for: .milliseconds(300))
            // Answered, its buttons have moved, so it's read again before it hides.
            mustRead = true
        }
    }

    private static func click(at point: CGPoint) async {
        let source = CGEventSource(stateID: .hidSystemState)
        let back = CGEvent(source: nil)?.location
        func post(_ type: CGEventType) {
            CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        }
        post(.mouseMoved)
        try? await Task.sleep(for: .milliseconds(60))
        post(.leftMouseDown)
        try? await Task.sleep(for: .milliseconds(30))
        post(.leftMouseUp)
        try? await Task.sleep(for: .milliseconds(30))
        if let back { CGWarpMouseCursorPosition(back) }
    }
}

/// A button that doesn't change as it's pressed.
private struct StillPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
}
