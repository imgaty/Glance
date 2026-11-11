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

    /// As the iPhone pictured a caller without a picture: the name's first letter, one even for a
    /// name of three words, or none for a number, which shows a person's outline.
    var initials: String {
        guard let first = name.first(where: { !$0.isWhitespace }), first.isLetter else { return "" }
        return String(first).uppercased()
    }
    var rings: Bool { phase == .ringing }
    /// Over FaceTime or Phone, whose callers show as the iPhone shows them, in a colored circle; other
    /// apps' show no picture.
    var throughApple: Bool { app == CallAudio.faceTime || app == CallAudio.phone }
    var isConnected: Bool {
        if case .connected = phase { return true }
        return false
    }
}

/// How a call looks, measured from screenshots of the user's own iPhone on a call: a bright green
/// phone and its time on one side, on the other a waveform, the other person on the left, green, and
/// you on the right, orange, every bar yellow in its middle, so it's yellow dots while nobody speaks.
/// Opened, a FaceTime or Phone caller's initial in a colored circle, their name and the time, and the
/// iPhone's five buttons. The colors are the iPhone's own, in Display P3, which the green and yellow
/// are just outside sRGB in.
enum CallLook {
    static let green = Color(.displayP3, red: 0x7F / 255, green: 0xFB / 255, blue: 0x7F / 255)
    static let handset = Color(red: 0x8F / 255, green: 0x8F / 255, blue: 0x91 / 255)
    static let accept = Color(red: 0x67 / 255, green: 0xCD / 255, blue: 0x67 / 255)
    /// With Increase Contrast, a green the white phone reads on at 4.4 to 1, rather than 2.0: Apple's
    /// own green for it.
    static let acceptContrast = Color(red: 0x24 / 255, green: 0x8A / 255, blue: 0x3D / 255)
    static func accept(_ contrast: ColorSchemeContrast) -> Color { contrast == .increased ? acceptContrast : accept }
    static let decline = Color(red: 0xE9 / 255, green: 0x56 / 255, blue: 0x45 / 255)
    static let end = Color(red: 0xFE / 255, green: 0x44 / 255, blue: 0x44 / 255)
    static let speaker = Color(red: 0x2C / 255, green: 0x2C / 255, blue: 0x2E / 255)
    /// A FaceTime or Phone caller's circle, as the iPhone pictures one, top to bottom, and its serif
    /// initials, half the circle's size, which gives the iPhone's cap height of 0.353 of it.
    static let pictureTop = Color(.displayP3, red: 0x94 / 255, green: 0x60 / 255, blue: 0xF0 / 255)
    static let pictureMiddle = Color(.displayP3, red: 0x7C / 255, green: 0x9D / 255, blue: 0xE2 / 255)
    static let pictureBottom = Color(.displayP3, red: 0x78 / 255, green: 0xDD / 255, blue: 0xD5 / 255)
    static let pictureInitials: CGFloat = 0.5

    /// The waveform's bars, half the other person's and half yours, and their measures, the iPhone's
    /// for the notch's height.
    static let bars = 14
    static let barWidth: CGFloat = 1.5
    static let barGap: CGFloat = 1.05
    static var waveWidth: CGFloat { CGFloat(bars) * (barWidth + barGap) - barGap }
    /// As shares of the notch's height: the waveform at its tallest, every bar's yellow middle, which
    /// is all a quiet one is, the phone, the circle, the handset.
    static let waveHeight: CGFloat = 0.45
    static let core: CGFloat = 0.115
    static let phone: CGFloat = 0.384
    /// The caller's circle and the handset as large as every other activity's mark beside the camera.
    static let avatar: CGFloat = TimerLayout.ring
    static let handsetSize: CGFloat = 0.49
    /// Between the phone and its time.
    static let timeGap: CGFloat = 1.5
    /// The iPhone's handset stands more upright than the symbol, by this much.
    static let phoneTilt: Double = 15
    /// From the ends, by the notch's height, for the phone's ink and the waveform's to be as far in
    /// as the iPhone's, 0.264 and 0.291: the tilted symbol inks 0.078 inside its bounds.
    static let phoneEdge: CGFloat = 0.186
    static let waveEdge: CGFloat = 0.291

    /// Inside the round buttons, the symbol's size for the button's, as on the iPhone: its cross a
    /// third across, the speaker three fifths, the phone two fifths.
    static let endGlyph: CGFloat = 0.4
    /// The cross heavier than the rest, measured on the iPhone: 0.35 across, its strokes 0.08.
    static let crossGlyph: CGFloat = 0.45
    static let acceptGlyph: CGFloat = 0.42
    static let speakerGlyph: CGFloat = 0.42
    /// Opened on a call, its buttons as the iPhone's, each symbol's size by the button for its ink to
    /// match: the speaker, video off, the microphone, more, and ending it. Video is darker and its
    /// symbol dim, as it is on a voice call.
    static let speakerSymbol: CGFloat = 0.465
    static let videoSymbol: CGFloat = 0.44
    static let micSymbol: CGFloat = 0.463
    static let moreSymbol: CGFloat = 0.44
    static let endSymbol: CGFloat = 0.458
    static let videoFill = Color(.displayP3, red: 0x1D / 255, green: 0x1D / 255, blue: 0x1F / 255)
    static let videoGlyph = Color(.displayP3, red: 0x61 / 255, green: 0x60 / 255, blue: 0x65 / 255)
    /// Opened on a call, the name by the notch's height, and how far in it starts.
    static let name: CGFloat = 0.215
    static let nameEdge: CGFloat = 0.246
    /// Opened, as far apart as on the user's phone, by the buttons' size, measured at 3x on their
    /// screenshot: 150 pixel buttons, 63 between them, and 50 between the caller's circle and them.
    static let buttonSpacing: CGFloat = 63.0 / 150
    static let rowSpacing: CGFloat = 50.0 / 150

    /// A voice's color where it's the louder: the other person's green, yours orange; and the yellow
    /// where both overlap, about the two together. All three measured on the iPhone, in Display P3.
    static func voice(theirs: Bool) -> NSColor {
        theirs
            ? NSColor(displayP3Red: 0x77 / 255, green: 0xF8 / 255, blue: 0x4C / 255, alpha: 1)
            : NSColor(displayP3Red: 0xF8 / 255, green: 0xC6 / 255, blue: 0x47 / 255, alpha: 1)
    }
    static let yellow = NSColor(displayP3Red: 0xFE / 255, green: 0xFF / 255, blue: 0x56 / 255, alpha: 1)

    /// Where a bar goes, for a level from 0 to 1, in a space this tall, and its yellow middle `core`
    /// tall: quiet, the bar is its middle alone.
    static func barFrame(_ index: Int, level: CGFloat, height: CGFloat, core: CGFloat) -> CGRect {
        let tall = max(level * height, core)
        return CGRect(x: CGFloat(index) * (barWidth + barGap), y: (height - tall) / 2, width: barWidth, height: tall)
    }

    /// How strong a voice still is at the far side, having crossed the waveform from its own: it
    /// fades evenly on the way, rather than stopping at the middle. Measured from the user's iPhone,
    /// whose middle bars are little more than dots while those at the ends are up to three times as
    /// tall: about 0.4 of a voice by the middle, so 0.15 at the far side.
    static let farthest: CGFloat = 0.15

    /// How tall a bar's yellow is, in points: a quiet bar all yellow, a dot; the taller a bar, the
    /// thinner its yellow, down to 0.6 of a dot at the tallest, as the iPhone's, whose tall bars
    /// are yellow for 7 to 9 of their 45 pixels; and wider where the quieter voice overlaps more.
    static func yellowHeight(louder: CGFloat, overlap: CGFloat, core: CGFloat, height: CGFloat) -> CGFloat {
        let grown = min(max((louder - core) / max(height - core, 1), 0), 1)
        return min(max(core * (1 - 0.4 * grown), overlap), louder)
    }

    /// A bar's yellow, on its middle.
    static func yellowFrame(of bar: CGRect, overlap: CGFloat, core: CGFloat, height: CGFloat) -> CGRect {
        let tall = yellowHeight(louder: bar.height, overlap: overlap * height, core: core, height: height)
        return CGRect(x: bar.minX, y: bar.midY - tall / 2, width: bar.width, height: tall)
    }

    /// A voice's strength `across` the waveform from its own side, 0 there to 1 at the far side.
    static func fade(across: CGFloat) -> CGFloat { pow(farthest, min(max(across, 0), 1)) }

    /// A bar's two voices, overlapping, as the user's iPhone draws them: the louder in its own color,
    /// and where the quieter overlaps it, yellow, the two colors together. So a bar near the left is
    /// green past a yellow middle, near the right orange, in the middle where both are as loud
    /// nearly all yellow, and with nobody speaking, a yellow dot.
    static func layers(_ bar: CallBar) -> (louder: CGFloat, theirs: Bool, overlap: CGFloat) {
        (max(bar.theirs, bar.yours), bar.theirs >= bar.yours, min(bar.theirs, bar.yours))
    }
}

/// A bar of the call's waveform: how loud each voice draws it, from 0 to 1.
struct CallBar: Equatable, Sendable {
    var theirs: CGFloat = 0
    var yours: CGFloat = 0
}

enum CallLayout {
    /// Opened, each wing only as wide as the first line of words or the buttons need, whichever's
    /// wider: the second line runs on under the camera, as far as the buttons.
    @MainActor
    static func openWing(firstLine: CGFloat, buttons: CGFloat, picture: Bool = true, restingHeight h: CGFloat) -> CGFloat {
        let left = roundEdge(h) + (picture ? round(h) + wordsGap(h) : 0) + firstLine + LiveActivityView.cameraGap
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
            // The time changes once a second, but this is asked on every move of the pointer, more
            // than once: what the second's time measures is kept for the rest of it.
            let seconds = max(Int(date.timeIntervalSince(since)), 0)
            if let kept = measured, kept.seconds == seconds, kept.height == h { return kept.wing }
            let time = ClockText.of(seconds)
            let words = SystemActivityView.digitsWidth(time, LiveActivityView.textSize(for: h), .semibold)
            let wing = max(
                h * CallLook.phoneEdge + h * CallLook.phone * 1.15 + CallLook.timeGap + words + gap, gap + CallLook.waveWidth + h * CallLook.waveEdge)
            measured = (seconds, h, wing)
            return wing
        }
    }

    /// The connected call's wing, as last measured, for its second and the notch's height.
    nonisolated(unsafe) private static var measured: (seconds: Int, height: CGFloat, wing: CGFloat)?
}

/// A FaceTime or Phone caller: their photo from Contacts, or for a contact without one, their
/// initials in serif, white, on purple going to blue and teal, or for a number, a person's outline.
/// Other apps' callers have no picture.
struct CallAvatar: View {
    let call: CallShown
    let side: CGFloat
    @ObservedObject var photos = CallPhotos.shared

    var body: some View {
        Group {
            if let photo = photos.photo(for: call) {
                Image(nsImage: photo)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [CallLook.pictureTop, CallLook.pictureMiddle, CallLook.pictureBottom], startPoint: .top, endPoint: .bottom)
                    )
                    .overlay {
                        if call.initials.isEmpty {
                            Image(systemName: "person.fill")
                                .font(.system(size: side * 0.6))
                                .foregroundStyle(.white)
                        } else {
                            Text(call.initials)
                                .font(.system(size: side * CallLook.pictureInitials, weight: .regular, design: .serif))
                                .foregroundStyle(.white)
                        }
                    }
            }
        }
        .frame(width: side, height: side)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

/// How long the call has been going, a second at a time.
struct CallTime: View {
    let since: Date
    var bubble = false

    var body: some View {
        TimelineView(.periodic(from: since, by: 1)) { context in
            let seconds = max(Int(context.date.timeIntervalSince(since)), 0)
            Text(bubble ? CallBubbleMark.text(seconds) : ClockText.of(seconds))
                .monospacedDigit()
        }
    }
}

/// A call in the bubble, off the notch's end, when another activity started first: its time, as large
/// as the notch's time beside the camera when it fits, smaller when it doesn't, never under the Mac's
/// smallest text; and the green phone before it, only where both fit (the user, 2026-11-08: "it
/// should show the time, and if it fits the phone icon"). Measured at a 32 point notch: m:ss is 29.5
/// points at the notch's 13.6 point text and the circle holds about 28, so it's drawn a little
/// smaller; mm:ss fits at about 10; with the phone, even m:ss would need 31 at 10, so the phone doesn't
/// show at 32 or 37 points. Past an hour it goes on counting minutes, as h:mm:ss can't fit at 10.
/// Ringing or going out, it's the phone alone, as large as any mark in the bubble.
struct CallBubbleMark: View {
    let call: CallShown
    let restingHeight: CGFloat

    var body: some View {
        let h = restingHeight
        switch call.phase {
        case .connected(let since):
            TimelineView(.periodic(from: since, by: 1)) { context in
                let text = Self.text(max(Int(context.date.timeIntervalSince(since)), 0))
                let fit = Self.fit(text, restingHeight: h)
                HStack(spacing: fit.size * Self.gap) {
                    if fit.phone {
                        Image(systemName: "phone.fill")
                            .font(.system(size: fit.size * Self.phone, weight: .medium))
                            .rotationEffect(.degrees(CallLook.phoneTilt))
                    }
                    Text(text)
                        .font(.system(size: fit.size, weight: .semibold).monospacedDigit())
                        .fixedSize()
                }
                .foregroundStyle(CallLook.green)
            }
        case .ringing, .calling:
            Image(systemName: "phone.fill")
                .font(.system(size: h * Self.mark, weight: .medium))
                .foregroundStyle(CallLook.green)
                .rotationEffect(.degrees(CallLook.phoneTilt))
        }
    }

    /// The phone's size beside the time, as beside the camera; the gap between them, both as shares of
    /// the text's size; alone, as wide as the timer's ring by its ink.
    static let phone: CGFloat = CallLook.phone / 0.426
    static let gap: CGFloat = CallLook.timeGap / (32 * 0.426)
    static let mark: CGFloat = TimerLayout.ring / 0.936
    /// How far in from the circle's edge the time keeps, as a share of the notch's height.
    static let margin: CGFloat = 0.05

    /// The time as the bubble shows it: minutes and seconds, past 59 minutes too, as h:mm:ss can't fit
    /// and h:mm would read as minutes; hours and minutes only from 100 minutes, which can't fit either.
    static func text(_ seconds: Int) -> String {
        seconds < 100 * 60 ? String(format: "%d:%02d", seconds / 60, seconds % 60) : String(format: "%d:%02d", seconds / 3600, seconds / 60 % 60)
    }

    /// The time's size and whether the phone shows: the largest that fits across the circle at the
    /// text's height, the notch's size at most and the Mac's smallest at least, the phone only if it
    /// fits there too.
    static func fit(_ text: String, restingHeight h: CGFloat) -> (size: CGFloat, phone: Bool) {
        let most = LiveActivityView.textSize(for: h), least = StopwatchReading.smallest
        func width(_ size: CGFloat, phone: Bool) -> CGFloat {
            let digits = text.replacingOccurrences(of: "[0-9]", with: "0", options: .regularExpression)
            let font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .semibold)
            var width = (digits as NSString).size(withAttributes: [.font: font]).width
            if phone,
                let symbol = NSImage(systemSymbolName: "phone.fill", accessibilityDescription: nil)?
                    .withSymbolConfiguration(.init(pointSize: size * Self.phone, weight: .medium))
            {
                width += symbol.size.width + size * Self.gap
            }
            return width
        }
        func room(_ size: CGFloat) -> CGFloat {
            // Across the circle where the digits' tops and bottoms reach, less the margin each side.
            let half = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .semibold).capHeight / 2
            let r = h / 2
            return 2 * (r * r - half * half).squareRoot() - 2 * h * Self.margin
        }
        func largest(phone: Bool) -> CGFloat? {
            var size = most
            while size >= least {
                if width(size, phone: phone) <= room(size) { return size }
                size -= 0.25
            }
            return nil
        }
        if let size = largest(phone: true) { return (size, true) }
        return (largest(phone: false) ?? least, false)
    }
}

/// The waveform beside the camera on a call: the other person's voice from the left, yours from the
/// right, each crossing the whole of it and fading on the way, yellow where they overlap.
struct CallWaveform: View {
    let height: CGFloat
    /// Each bar's yellow middle.
    let core: CGFloat
    @Environment(\.notchOnScreen) private var onScreen

    var body: some View {
        Group {
            if onScreen {
                LiveCallBars(core: core)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { _ in
                    let bars = CallVoices.shared.bars
                    Canvas { context, size in
                        for (index, voices) in bars.enumerated() {
                            let parts = CallLook.layers(voices)
                            let louder = CallLook.barFrame(index, level: parts.louder, height: size.height, core: core)
                            let overlap = CallLook.yellowFrame(of: louder, overlap: parts.overlap, core: core, height: size.height)
                            context.fill(
                                Path(roundedRect: louder, cornerRadius: louder.width / 2), with: .color(Color(nsColor: CallLook.voice(theirs: parts.theirs))))
                            context.fill(Path(roundedRect: overlap, cornerRadius: overlap.width / 2), with: .color(Color(nsColor: CallLook.yellow)))
                        }
                    }
                }
            }
        }
        .frame(width: CallLook.waveWidth, height: height)
        .accessibilityHidden(true)
    }
}

/// The bars on the notch on the screen, drawn by Core Animation: through SwiftUI each change would
/// redraw the whole notch.
private struct LiveCallBars: NSViewRepresentable {
    let core: CGFloat
    func makeNSView(context: Context) -> CallBarsView { CallBarsView(core: core) }
    func updateNSView(_ view: CallBarsView, context: Context) {}
}

final class CallBarsView: NSView {
    /// Each bar: the louder voice in its color, and where the quieter overlaps it, yellow.
    private var backs: [CALayer] = []
    private var fronts: [CALayer] = []
    private let core: CGFloat
    private var hearing: AnyCancellable?

    init(core: CGFloat) {
        self.core = core
        super.init(frame: .zero)
        wantsLayer = true
        for _ in 0..<CallLook.bars {
            let back = CALayer()
            let front = CALayer()
            front.backgroundColor = CallLook.yellow.cgColor
            for part in [back, front] { layer?.addSublayer(part) }
            backs.append(back)
            fronts.append(front)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    /// The notch around it takes the clicks.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        hearing =
            window == nil
            ? nil
            : CallVoices.shared.$bars.sink { [weak self] bars in
                MainActor.assumeIsolated { self?.draw(bars) }
            }
    }

    override func layout() {
        super.layout()
        draw(CallVoices.shared.bars)
    }

    private func draw(_ bars: [CallBar]) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, voices) in bars.enumerated() where index < backs.count {
            let parts = CallLook.layers(voices)
            let louder = CallLook.barFrame(index, level: parts.louder, height: bounds.height, core: core)
            let overlap = CallLook.yellowFrame(of: louder, overlap: parts.overlap, core: core, height: bounds.height)
            backs[index].frame = louder
            backs[index].cornerRadius = louder.width / 2
            backs[index].backgroundColor = CallLook.voice(theirs: parts.theirs).cgColor
            fronts[index].frame = overlap
            fronts[index].cornerRadius = overlap.width / 2
        }
        CATransaction.commit()
    }
}

/// A call beside the camera. Ringing, once its popup is swiped away: the caller and a gray handset.
/// Connected: the green phone and the time, and the waveform. Before that, going out: the phone.
struct CallMark: View {
    let call: CallShown
    let restingHeight: CGFloat
    /// Its leading side alone, with another activity detached in its trailing side's place (see
    /// `SystemActivityView.leadingOnly`).
    var leadingOnly = false

    var body: some View {
        let h = restingHeight
        HStack(spacing: 0) {
            switch call.phase {
            case .ringing:
                if call.throughApple { CallAvatar(call: call, side: h * CallLook.avatar) }
                Spacer(minLength: 0)
                Image(systemName: "phone.down.fill")
                    .font(.system(size: h * CallLook.handsetSize, weight: .medium))
                    .foregroundStyle(CallLook.handset)
                    .islandFade(!leadingOnly)
            case .calling:
                Image(systemName: "phone.fill")
                    .font(.system(size: h * CallLook.phone, weight: .medium))
                    .foregroundStyle(CallLook.green)
                    .rotationEffect(.degrees(CallLook.phoneTilt))
                Spacer(minLength: 0)
            case .connected(let since):
                Image(systemName: "phone.fill")
                    .font(.system(size: h * CallLook.phone, weight: .medium))
                    .foregroundStyle(CallLook.green)
                    .rotationEffect(.degrees(CallLook.phoneTilt))
                    .padding(.trailing, CallLook.timeGap)
                CallTime(since: since)
                    .font(.system(size: LiveActivityView.textSize(for: h), weight: .semibold))
                    .foregroundStyle(CallLook.green)
                Spacer(minLength: 0)
                CallWaveform(height: h * CallLook.waveHeight, core: h * CallLook.core)
                    .islandFade(!leadingOnly)
            }
        }
        .padding(.leading, call.rings ? CallLayout.edge(h) : h * CallLook.phoneEdge)
        .padding(.trailing, call.isConnected ? h * CallLook.waveEdge : CallLayout.edge(h))
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
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let h = restingHeight
        let side = CallLayout.round(h)
        HStack(spacing: CallLayout.wordsGap(h)) {
            if call.throughApple { CallAvatar(call: call, side: side) }
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
                button("phone.fill", CallLook.accept(contrast), side, CallLook.acceptGlyph, hovered == .accept)
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
        return CallLayout.openWing(firstLine: first, buttons: call.canDecline ? 2 : 1, picture: call.throughApple, restingHeight: h)
    }
}

/// Opened, a call shows as a phone shows it. Connected over FaceTime or Phone, laid out as the
/// player, the same padding all around: the caller's photo or initial up in the corner beside the
/// camera, their name and the call's time beside it; under them, spread end to end, the speaker,
/// video, off, the microphone, more, which goes to the call's app, and, where its popup's own can be
/// pressed, a red button to end it. Connected in another app, one row as tall as the Alarm: the name,
/// the speaker and, where the app's own can be pressed, a red cross to end it. Coming in or going
/// out, as tall as the Alarm: the caller, what it's over, and buttons to decline or accept it.
/// Clicked, the caller goes to the app it's in.
struct ExpandedCallView: View {
    let call: CallShown
    let restingHeight: CGFloat
    let width: CGFloat
    var revealed = true
    /// How wide the notch is closed, if it shows beside the camera there, for what's there to grow out of.
    var closedWidth: CGFloat? = nil
    /// How far below its middle at rest the closed notch's middle was, swollen under the pointer.
    var closedDrop: CGFloat = 0
    @Environment(\.activityBubbleCenter) private var bubbleCenter
    @Environment(\.playerKeys) private var keys
    @Environment(\.colorSchemeContrast) private var contrast
    @ObservedObject private var microphone = CallMicrophone.shared

    var body: some View {
        Group {
            if case .connected(let since) = call.phase {
                if call.throughApple { connected(since: since) } else { inline }
            } else {
                coming
            }
        }
        .accessibilityElement(children: .contain)
        .onChange(of: revealed) { _, visible in
            if visible { microphone.refresh() }
        }
    }

    /// A FaceTime or Phone call: the caller's picture up in the corner beside the camera, as the
    /// player's cover; beside it, their name and the call's time, the time's digits on the circle's
    /// bottom edge; under them, the buttons, spread end to end.
    private func connected(since: Date) -> some View {
        let h = restingHeight
        let side = CallLayout.round(h)
        let edge = CallLayout.roundEdge(h)
        let out = revealed
        let words = edge + side + CallLayout.wordsGap(h)
        let detail = NSFont.systemFont(ofSize: NotchType.size)
        // The time grows out of where it shows beside the camera, going from green to gray as it comes.
        let spread = ((closedWidth ?? width) - width) / 2
        let timeBaseline = edge + side
        let bubbleText = CallBubbleMark.text(max(Int(Date.now.timeIntervalSince(since)), 0))
        let fit = CallBubbleMark.fit(bubbleText, restingHeight: h)
        let compactSize = bubbleCenter == nil ? LiveActivityView.textSize(for: h) : fit.size
        let compactWidth = (bubbleText as NSString).size(withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: compactSize, weight: .semibold)]).width
        let timeFrom = CGSize(
            width: bubbleCenter.map { $0 + width / 2 - words - compactWidth / 2 + (fit.phone ? fit.size * (CallBubbleMark.phone + CallBubbleMark.gap) / 2 : 0) }
                ?? (h * CallLook.phoneEdge + h * CallLook.phone * 1.15 + CallLook.timeGap - words - spread),
            height: h / 2 + closedDrop - (timeBaseline - detail.capHeight / 2))
        let count = CGFloat(3 + (microphone.available ? 1 : 0) + (call.canEnd ? 1 : 0))
        return VStack(alignment: .leading, spacing: Self.rowGap(restingHeight: h)) {
            Button {
                CallWatch.shared.goToApp()
            } label: {
                // The time's baseline on the circle's bottom edge, the name above it.
                ZStack(alignment: .bottomLeading) {
                    CallAvatar(call: call, side: side)
                        .modifier(IslandReveal(hidden: !revealed))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(call.name)
                            .font(NotchType.title)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .modifier(IslandReveal(hidden: !revealed))
                        CallTime(since: since, bubble: bubbleCenter != nil)
                            .font(NotchType.detail)
                            .foregroundStyle(out || closedWidth == nil && bubbleCenter == nil ? NotchType.detailColor : CallLook.green)
                            .modifier(
                                GrowsOut(
                                    out: out || closedWidth == nil && bubbleCenter == nil, scale: compactSize / NotchType.size, anchor: .leading,
                                    from: timeFrom)
                            )
                            .modifier(GrownFade(shown: revealed, grows: closedWidth != nil || bubbleCenter != nil))
                    }
                    .padding(.leading, side + CallLayout.wordsGap(h))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .alignmentGuide(.bottom) { $0[.lastTextBaseline] }
                }
                .frame(height: side, alignment: .topLeading)
                .contentShape(Rectangle())
            }
            // Clicked, it goes to the app, and doesn't sink in as a button does.
            .buttonStyle(StillPress())
            .notchControl()
            .help(String(localized: "Show in \(call.over)"))
            .accessibilityLabel(String(localized: "\(call.name), on a call"))
            .accessibilityHint(String(localized: "Show in \(call.over)"))
            // Spread from end to end, as the player's controls, at least as far apart as on a phone.
            HStack(spacing: max(side * CallLook.buttonSpacing, (width - edge * 2 - side * count) / max(count - 1, 1))) { buttons(h) }
                .modifier(IslandReveal(hidden: !revealed))
        }
        .padding([.top, .horizontal], edge)
        .frame(width: width, height: Self.height(for: call, restingHeight: h), alignment: .top)
    }

    /// Another app's call, in one row as tall as the Alarm: the name alone, large, running on under
    /// the camera, and the buttons at the other end. Its caller has no picture.
    private var inline: some View {
        let h = restingHeight
        return HStack(spacing: CallLayout.wordsGap(h)) {
            Button {
                CallWatch.shared.goToApp()
            } label: {
                Text(call.name)
                    .font(.system(size: TimerLayout.tallHeight(h) * CallLook.name, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.leading, TimerLayout.tallHeight(h) * CallLook.nameEdge - CallLayout.roundEdge(h))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .modifier(IslandReveal(hidden: !revealed))
            }
            .buttonStyle(StillPress())
            .notchControl()
            .help(String(localized: "Show in \(call.over)"))
            .accessibilityLabel(String(localized: "\(call.name), on a call"))
            .accessibilityHint(String(localized: "Show in \(call.over)"))
            HStack(spacing: CallLayout.roundGap(h)) { inlineButtons(h) }
                .modifier(IslandReveal(hidden: !revealed))
        }
        .padding(.horizontal, CallLayout.roundEdge(h))
        .frame(width: width, height: TimerLayout.tallHeight(h))
    }

    /// The sound output, and a red cross to end it where the app's own button can be pressed.
    @ViewBuilder private func inlineButtons(_ h: CGFloat) -> some View {
        let side = CallLayout.round(h)
        IslandCircleButton(control: .activityFirst, height: h, tint: .white, label: String(localized: "Sound Output"), fill: CallLook.speaker, side: side) {
            let fromKeys = NSApp.currentEvent?.type == .keyDown
            AudioOutput.shared.showMenu(at: fromKeys ? keys?.focusFrame.flatMap { keys?.screenPoint?($0) } : nil, withVolume: false, outputsOnly: true)
        } glyph: {
            glyph("speaker.wave.3.fill", CallLook.speakerGlyph, side)
        }
        if call.canEnd {
            IslandCircleButton(control: .activityFourth, height: h, tint: .white, label: String(localized: "End"), fill: CallLook.end, side: side) {
                CallWatch.shared.end()
            } glyph: {
                glyph("xmark", CallLook.crossGlyph, side, weight: .heavy)
            }
        }
    }

    /// Coming in or going out: the caller, what it's over and the name, and the buttons, in one row.
    private var coming: some View {
        let h = restingHeight
        let side = CallLayout.round(h)
        let out = revealed
        let spread = ((closedWidth ?? width) - width) / 2
        let rise = (h - TimerLayout.tallHeight(h)) / 2 + closedDrop
        let avatarFrom = CGSize(width: CallLayout.edge(h) - CallLayout.roundEdge(h) - spread, height: rise)
        return HStack(spacing: CallLayout.wordsGap(h)) {
            Button {
                CallWatch.shared.goToApp()
            } label: {
                HStack(spacing: CallLayout.wordsGap(h)) {
                    if call.throughApple {
                        CallAvatar(call: call, side: side)
                            .modifier(
                                GrowsOut(out: out || closedWidth == nil || !call.rings, scale: h * CallLook.avatar / side, anchor: .leading, from: avatarFrom)
                            )
                            .modifier(GrownFade(shown: revealed, grows: closedWidth != nil && call.rings))
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(call.line ?? call.over)
                            .font(NotchType.detail)
                            .foregroundStyle(NotchType.detailColor)
                        Text(call.name)
                            .font(NotchType.title)
                            .foregroundStyle(.white)
                    }
                    .modifier(IslandReveal(hidden: !revealed))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(StillPress())
            .notchControl()
            .help(String(localized: "Show in \(call.over)"))
            .accessibilityLabel(!call.rings ? String(localized: "\(call.name), on a call") : String(localized: "\(call.name), incoming call"))
            .accessibilityHint(String(localized: "Show in \(call.over)"))
            HStack(spacing: CallLayout.roundGap(h)) { buttons(h) }
                .modifier(IslandReveal(hidden: !revealed))
        }
        .padding(.horizontal, CallLayout.roundEdge(h))
        .frame(width: width, height: TimerLayout.tallHeight(h))
    }

    @ViewBuilder private func buttons(_ h: CGFloat) -> some View {
        let side = CallLayout.round(h)
        if call.isConnected {
            IslandCircleButton(control: .activityFirst, height: h, tint: .white, label: String(localized: "Sound Output"), fill: CallLook.speaker, side: side) {
                // From the keyboard the pointer can be anywhere: the menu opens under the button.
                let fromKeys = NSApp.currentEvent?.type == .keyDown
                AudioOutput.shared.showMenu(at: fromKeys ? keys?.focusFrame.flatMap { keys?.screenPoint?($0) } : nil, withVolume: false, outputsOnly: true)
            } glyph: {
                glyph("speaker.wave.3.fill", CallLook.speakerSymbol, side, weight: .regular)
            }
            // Video, off, as the iPhone shows it on a voice call: the Mac can't add it to one.
            IslandCircle(height: h, tint: .white, highlighted: false, fill: CallLook.videoFill, side: side) {
                Image(systemName: "video.slash.fill")
                    .font(.system(size: side * CallLook.videoSymbol, weight: .semibold))
                    .foregroundStyle(CallLook.videoGlyph)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "Video"))
            .accessibilityValue(String(localized: "Off"))
            if microphone.available {
                // Live, white with a dark microphone, as on the iPhone; muted, dark, struck through.
                IslandCircleButton(
                    control: .activitySecond, height: h, tint: .white, label: microphone.muted ? String(localized: "Unmute") : String(localized: "Mute"),
                    fill: microphone.muted ? CallLook.speaker : .white, side: side
                ) {
                    microphone.toggle()
                } glyph: {
                    Image(systemName: microphone.muted ? "mic.slash.fill" : "mic.fill")
                        .font(.system(size: side * CallLook.micSymbol, weight: .medium))
                        .foregroundStyle(microphone.muted ? .white : .black)
                }
            }
            IslandCircleButton(control: .activityThird, height: h, tint: .white, label: String(localized: "Show in \(call.over)"), fill: CallLook.speaker, side: side) {
                CallWatch.shared.goToApp()
            } glyph: {
                glyph("ellipsis", CallLook.moreSymbol, side)
            }
            if call.canEnd {
                IslandCircleButton(control: .activityFourth, height: h, tint: .white, label: String(localized: "End"), fill: CallLook.end, side: side) {
                    CallWatch.shared.end()
                } glyph: {
                    glyph("phone.down.fill", CallLook.endSymbol, side, weight: .bold)
                }
            }
        } else if call.rings {
            if call.canDecline {
                IslandCircleButton(control: .activityFirst, height: h, tint: .white, label: String(localized: "Decline"), fill: CallLook.decline, side: side) {
                    CallWatch.shared.decline()
                } glyph: {
                    glyph("phone.down.fill", CallLook.endGlyph, side)
                }
            }
            IslandCircleButton(control: .activitySecond, height: h, tint: .white, label: String(localized: "Accept"), fill: CallLook.accept(contrast), side: side) {
                CallWatch.shared.accept()
            } glyph: {
                glyph("phone.fill", CallLook.acceptGlyph, side)
            }
        } else if call.canEnd {
            IslandCircleButton(control: .activityFirst, height: h, tint: .white, label: String(localized: "End"), fill: CallLook.end, side: side) {
                CallWatch.shared.end()
            } glyph: {
                glyph("phone.down.fill", CallLook.endSymbol, side, weight: .bold)
            }
        }
    }

    private func glyph(_ symbol: String, _ share: CGFloat, _ side: CGFloat, weight: Font.Weight = .semibold) -> some View {
        Image(systemName: symbol)
            .font(.system(size: side * share, weight: weight))
            .foregroundStyle(.white)
    }

    /// How many round buttons a connected call has. FaceTime and Phone: the speaker, video, the
    /// microphone where it can be muted, more, and ending it where that can be done. Another app: the
    /// speaker, and ending it where that can be done.
    @MainActor
    static func connectedButtons(for call: CallShown) -> Int {
        guard call.throughApple else { return 1 + (call.canEnd ? 1 : 0) }
        return 3 + (CallMicrophone.canMute ? 1 : 0) + (call.canEnd ? 1 : 0)
    }

    /// Each side of the camera. Connected over FaceTime or Phone, as the player's: wide enough for the
    /// caller's circle, up in the corner, to stay clear of the camera, and for the row of buttons as
    /// far apart as on a phone, at least as wide as the camera with its gaps. Another app's, and
    /// otherwise, as wide as the wider of the first line and the buttons, each from its end.
    @MainActor
    static func wing(for call: CallShown, restingHeight h: CGFloat, closedWidth: CGFloat = 185) -> CGFloat {
        if call.isConnected, !call.throughApple {
            // The name runs on under the camera as far as the buttons, and never widens it.
            return CallLayout.openWing(firstLine: 0, buttons: CGFloat(connectedButtons(for: call)), picture: false, restingHeight: h)
        }
        guard call.isConnected else {
            if call.rings { return IncomingCallView.wing(for: call, restingHeight: h) }
            // Going out: the caller and what it's over, and ending it where that can be done.
            let first = ceil(((call.line ?? call.over) as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: NotchType.size)]).width)
            return CallLayout.openWing(firstLine: first, buttons: call.canEnd ? 1 : 0, picture: call.throughApple, restingHeight: h)
        }
        let buttons = CGFloat(connectedButtons(for: call))
        let row = CallLayout.roundEdge(h) * 2 + CallLayout.round(h) * buttons + CallLayout.round(h) * CallLook.buttonSpacing * (buttons - 1)
        let circle = call.throughApple ? CallLayout.roundEdge(h) + CallLayout.round(h) + PlayerLayout.besideCamera : 0
        return max((row - closedWidth) / 2, circle, LiveActivityView.cameraGap)
    }

    @MainActor
    static func width(for call: CallShown, restingHeight h: CGFloat, closedWidth: CGFloat) -> CGFloat {
        closedWidth + wing(for: call, restingHeight: h, closedWidth: closedWidth) * 2
    }

    /// Between the caller's row and the buttons, as on a phone, to a whole point, so the padding
    /// under them is the same as above.
    static func rowGap(restingHeight h: CGFloat) -> CGFloat { (CallLayout.round(h) * CallLook.rowSpacing).rounded() }

    /// Connected over FaceTime or Phone, the padding all around, the caller's row, as tall as the
    /// circle, and the buttons' with a gap between; otherwise as tall as the Alarm.
    static func height(for call: CallShown, restingHeight h: CGFloat) -> CGFloat {
        guard call.isConnected, call.throughApple else { return TimerLayout.tallHeight(h) }
        return CallLayout.roundEdge(h) * 2 + CallLayout.round(h) + rowGap(restingHeight: h) + CallLayout.round(h)
    }
}

/// The Mac's microphone, which a call's Mute button mutes: the default input device's own mute, so
/// the call hears nothing, nor does anything else listening. What Glance mutes it unmutes as the
/// call ends. At the bench it's only said.
@MainActor
final class CallMicrophone: ObservableObject {
    static let shared = CallMicrophone(fakes: ActivityBench.scene != nil)
    @Published private(set) var muted = false
    @Published private(set) var available = CallMicrophone.canMute
    /// Muted from the notch, to be unmuted as the call ends.
    private(set) var mutedHere = false
    /// At the bench and in tests, the real microphone is never touched.
    private let fakes: Bool

    init(fakes: Bool) {
        self.fakes = fakes
        if fakes { available = true }
    }

    private static var muteAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
    }

    /// The default input device, if its mute can be set.
    private static var device: AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr, device != 0 else { return nil }
        var mute = muteAddress
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(device, &mute), AudioObjectIsPropertySettable(device, &mute, &settable) == noErr, settable.boolValue else { return nil }
        return device
    }

    static var canMute: Bool { ActivityBench.scene != nil || device != nil }

    /// Reads it again, as the call opens.
    func refresh() {
        guard !fakes else { return }
        available = Self.canMute
        guard let device = Self.device else { return }
        var mute = Self.muteAddress
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectGetPropertyData(device, &mute, 0, nil, &size, &value) == noErr { muted = value != 0 }
    }

    func toggle() {
        set(!muted)
        mutedHere = muted
    }

    /// The call's over: the microphone back on, if it was muted here.
    func callEnded() {
        guard mutedHere else { return }
        mutedHere = false
        set(false)
    }

    private func set(_ on: Bool) {
        guard !fakes else { return muted = on }
        guard let device = Self.device else { return }
        var mute = Self.muteAddress
        var value: UInt32 = on ? 1 : 0
        if AudioObjectSetPropertyData(device, &mute, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr { muted = on }
    }
}

// MARK: - Voices

/// How loud each voice on the call is, for the waveform. On a phone or FaceTime call, read off macOS's
/// own popup's bars, with nothing listened to: the other person's on its left, yours on its right.
/// Otherwise, the other person from the sound the call's app makes, through the same process tap as
/// the music's waveform, and you from the microphone, once it's allowed. Nothing is recorded or
/// kept. It runs only during a call.
@MainActor
final class CallVoices: ObservableObject {
    static let shared = CallVoices()

    /// What the waveform draws, left to right: each bar's two voices, the other person's newest at
    /// the left end, yours at the right.
    @Published private(set) var bars = [CallBar](repeating: CallBar(), count: CallLook.bars)
    private var seenAt: Date?
    private var theirs: CGFloat = 0
    private var yours: CGFloat = 0
    /// What's drawn of each voice, easing towards what's heard: quickly up, more slowly down.
    private var shownTheirs: CGFloat = 0
    private var shownYours: CGFloat = 0
    /// How loud each voice has been, a thirtieth of a second at a time, newest first: as many as
    /// there are bars, as each voice crosses them all.
    private var theirHistory = [CGFloat](repeating: 0, count: CallLook.bars)
    private var yourHistory = [CGFloat](repeating: 0, count: CallLook.bars)
    private var pipeline: TapPipeline?
    private var engine: AVAudioEngine?
    private var clock: Timer?
    /// At the bench: both voices made up, turn about, with nothing listened to.
    var madeUp = false

    /// How loud each voice is in the popup's bars just now.
    func saw(theirs: CGFloat, yours: CGFloat) {
        guard clock != nil else { return }
        seenAt = .now
        self.theirs = theirs
        self.yours = yours
    }

    func start(listeningTo pid: pid_t?, microphone: Bool) {
        guard clock == nil else { return }
        if !madeUp, microphone, let pid, pid > 0, Permissions.audioCapture == .granted {
            pipeline = TapPipeline(target: .player(pid)) { [weak self] reading in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        // As loud as the waveform's bars, on average, once stood with this sound.
                        self?.theirs = min(CGFloat(reading.loudness) * 1.1, 1)
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
        seenAt = nil
        theirHistory = theirHistory.map { _ in 0 }
        yourHistory = yourHistory.map { _ in 0 }
        bars = bars.map { _ in CallBar() }
    }

    private func tick() {
        let t = Date.now.timeIntervalSinceReferenceDate
        if madeUp {
            // They speak, you speak, both, neither.
            let turn = Int(t / 2.5) % 4
            let voice = 0.9 * CGFloat(DJGlyph.flap(at: t))
            theirs = turn == 0 || turn == 2 ? voice : 0
            yours = turn == 1 || turn == 2 ? voice : 0
        } else if let seenAt, Date.now.timeIntervalSince(seenAt) > 1 {
            // The popup sends its bars only as they change: unchanged a while, nobody's speaking.
            theirs = 0
            yours = 0
        }
        shownTheirs = Self.eased(shownTheirs, towards: theirs)
        shownYours = Self.eased(shownYours, towards: yours)
        theirHistory = [shownTheirs] + theirHistory.dropLast()
        yourHistory = [shownYours] + yourHistory.dropLast()
        // Each bar's flicker is the waveform's own motion, not the voices', so Reduce Motion stops it.
        let ripples =
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? [] : (0..<CallLook.bars).map { (theirs: Self.ripple($0, theirs: true, at: t), yours: Self.ripple($0, theirs: false, at: t)) }
        let next = Self.shaped(theirs: theirHistory, yours: yourHistory, ripples: ripples)
        if next != bars { bars = next }
    }

    /// A step of easing, thirty times a second.
    nonisolated static func eased(_ shown: CGFloat, towards heard: CGFloat) -> CGFloat {
        shown + (heard - shown) * (heard > shown ? 0.55 : 0.18)
    }

    /// The bars, left to right, from how loud each voice has just been: the other person's newest at
    /// the left end and older to the right, yours newest at the right end and older to the left,
    /// each fading as it crosses, so they overlap rather than meet in the middle. Nothing's made up:
    /// each part of a bar is a moment of that voice.
    nonisolated static func shaped(theirs: [CGFloat], yours: [CGFloat], ripples: [(theirs: CGFloat, yours: CGFloat)] = []) -> [CallBar] {
        let count = CallLook.bars
        return (0..<count).map { index in
            let across = CGFloat(index) / CGFloat(max(count - 1, 1))
            let their = index < theirs.count ? theirs[index] : 0
            let your = count - 1 - index < yours.count ? yours[count - 1 - index] : 0
            let ripple = index < ripples.count ? ripples[index] : (theirs: 1, yours: 1)
            return CallBar(
                theirs: min(max(their, 0), 1) * CallLook.fade(across: across) * ripple.theirs,
                yours: min(max(your, 0), 1) * CallLook.fade(across: 1 - across) * ripple.yours)
        }
    }

    /// The least of a voice a bar shows while it speaks.
    static let rippleFloor: CGFloat = 0.55

    /// How much of a voice a bar shows just now. The island's bars aren't an even ramp: in the
    /// user's screenshots each stands taller or shorter than its neighbours, within the voice's
    /// shape. So each flickers on its own, a couple of times a second, from `rippleFloor` to all of
    /// the voice; with nobody speaking it's still a dot.
    nonisolated static func ripple(_ index: Int, theirs: Bool, at time: Double) -> CGFloat {
        let seed = Double(index * 7 + (theirs ? 3 : 11))
        let slow = sin(time * (9 + seed.truncatingRemainder(dividingBy: 5) * 1.7) + seed * 1.3)
        let fast = sin(time * (14 + seed.truncatingRemainder(dividingBy: 3) * 2.3) + seed * 0.7)
        return rippleFloor + (1 - rippleFloor) * CGFloat((slow + fast) / 4 + 0.5)
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
    /// When the popup's call started.
    private var since: Date?
    /// When a call in another app started: by its own time, where it shows one, as Discord does.
    private var clock = CallClock()
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
        // Once a second: which calling app has the microphone, asked off the notch's thread.
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                CallBanners.shared.follow()
                CallAudio.appOnMicrophone { app in
                    self?.microphone = app
                    self?.refresh()
                    self?.refitAsTimeGrows()
                }
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
            // Discord says who it's with and for how long. Its time is waited for a moment, as
            // its window fills in, as after Glance opens, rather than counted from nothing.
            let isDiscord = microphone.bundle.hasPrefix(DiscordCall.bundle)
            let discord = isDiscord ? DiscordCall.shared.read() : nil
            if let name = discord?.name { who = name }
            guard let started = clock.going(shown: discord?.elapsed, at: .now, waitsForTime: isDiscord) else { return }
            show(
                CallShown(
                    name: discord?.name ?? who ?? app.name, over: app.name, app: app.bundle, phase: .connected(since: started),
                    canEnd: DiscordCall.shared.canEnd))
        } else {
            who = nil
            since = nil
            clock.ended(at: .now)
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
        // A FaceTime or Phone caller's photo, looked up again as the popup's picture of them is read.
        if let next, next.throughApple { CallPhotos.shared.look(for: next, face: popup?.face) } else if next == nil { CallPhotos.shared.forget() }
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
        if next == nil { CallMicrophone.shared.callEnded() }
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

/// When a call in an app other than FaceTime or Phone started, as near as can be known: by the app's
/// own time wherever it shows one, which always wins; without one, what was known is kept, so a
/// reading missed, Glance opened again, or the call gone a moment never starts it from nothing.
struct CallClock: Equatable {
    /// When a time read started: in the second before that many seconds ago, a little either side
    /// for the app drawing it late. Each reading that agrees narrows it down.
    struct Span: Equatable {
        var earliest: Date
        var latest: Date

        init(seconds: Int, at now: Date) {
            earliest = now.addingTimeInterval(-TimeInterval(seconds) - 1.2)
            latest = now.addingTimeInterval(-TimeInterval(seconds) + 0.1)
        }

        init(earliest: Date, latest: Date) {
            self.earliest = earliest
            self.latest = latest
        }

        /// What both leave, if they agree.
        func meeting(_ other: Span) -> Span? {
            let from = max(earliest, other.earliest)
            let to = min(latest, other.latest)
            return from <= to ? Span(earliest: from, latest: to) : nil
        }

        var middle: Date { earliest.addingTimeInterval(latest.timeIntervalSince(earliest) / 2) }
    }

    /// When the call started, by its own time.
    private(set) var span: Span?
    /// A reading that disagreed, and the time it said: it's only believed once the app's time is
    /// seen to move on from it. An app whose window is out of sight, as behind a full-screen app,
    /// can stop drawing and go on showing the same second, which read a second later disagrees.
    private(set) var disagreeing: Span?
    private(set) var disagreeingSeconds: Int?
    /// Without a time of its own, when the call was first heard.
    private(set) var heard: Date?
    /// When it was last gone, for a call that comes straight back.
    private(set) var gone: Date?

    /// How long its own time is waited for, and how long a call that's gone is remembered.
    static let wait: TimeInterval = 3
    static let keep: TimeInterval = 10

    /// When it started, by its own time: the middle of what the readings leave.
    var shown: Date? { span?.middle }

    /// When the call started, given the time its app shows now, if it shows one; nil while that
    /// time is still worth waiting for.
    mutating func going(shown seconds: Int?, at now: Date, waitsForTime: Bool) -> Date? {
        gone = nil
        if let seconds { read(seconds, at: now) }
        if let shown { return shown }
        let heard = self.heard ?? now
        self.heard = heard
        if waitsForTime, now.timeIntervalSince(heard) < Self.wait { return nil }
        return heard
    }

    private mutating func read(_ seconds: Int, at now: Date) {
        let reading = Span(seconds: seconds, at: now)
        guard let known = span else {
            span = reading
            return
        }
        if let both = known.meeting(reading) {
            span = both
            disagreeing = nil
            disagreeingSeconds = nil
        } else if let waiting = disagreeing, let both = waiting.meeting(reading) {
            if seconds != disagreeingSeconds {
                // It's moving, and not with the time known: another call, or the app's own moved.
                span = both
                disagreeing = nil
                disagreeingSeconds = nil
            } else {
                disagreeing = both
            }
        } else {
            disagreeing = reading
            disagreeingSeconds = seconds
        }
    }

    /// The call's gone: remembered a while, in case it's back.
    mutating func ended(at now: Date) {
        let gone = self.gone ?? now
        if now.timeIntervalSince(gone) > Self.keep {
            self = CallClock()
        } else {
            self.gone = gone
        }
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
    /// The way down to the link from Discord's windows, as indexes: Discord redraws the link every
    /// second as its time ticks, so the element found goes stale, but the way to it stays, and
    /// following it costs a few reads where looking through the whole window cost about a quarter
    /// of a second, every second, on the thread that draws the notch.
    private var linkPath: [Int]?
    /// When the whole window was last looked through for a call coming in, which needn't be
    /// every second: only when Discord's window says one rings, or every few seconds otherwise.
    private var lookedForRinging = Date.distantPast
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
        // What was found last, if it still says something; Discord redraws it as its time ticks, and
        // then it's found again the same way down; failing that, looked for afresh.
        if let link, let found = Self.reading(link) { return found }
        if let linkPath, let followed = Self.follow(linkPath, in: element), Self.isCallLink(followed), let found = Self.reading(followed) {
            if link == nil || !CFEqual(link, followed) {
                link = followed
                leave = Self.leaveButton(beside: followed)
            }
            return found
        }
        let found = Self.findLink(in: element)
        link = found?.element
        linkPath = found?.path
        leave = link.flatMap(Self.leaveButton(beside:))
        if let link { return Self.reading(link) }
        // Not joined yet: a call coming in shows in the list of messages, by who it's from. Its
        // window says so in its title first, so looking through it all waits for that, or a while.
        guard ringingAsked || Date.now.timeIntervalSince(lookedForRinging) > 5 else { return nil }
        lookedForRinging = .now
        join = Self.findJoin(in: element)
        return Self.ringingName(in: element).map { Reading(name: $0, ringing: true) }
    }

    /// Set while `ringing()` asks, as Discord's window says a call is coming in.
    private var ringingAsked = false

    /// The element at the end of a way down from the app's windows.
    private static func follow(_ path: [Int], in app: AXUIElement) -> AXUIElement? {
        guard let first = path.first, let windows = SystemNotices.value(app, kAXWindowsAttribute) as? [AXUIElement], first < windows.count else {
            return nil
        }
        var element = windows[first]
        for index in path.dropFirst() {
            guard let children = SystemNotices.value(element, kAXChildrenAttribute) as? [AXUIElement], index < children.count else { return nil }
            element = children[index]
        }
        return element
    }

    /// A link whose words end in a running time: the call's.
    private static func isCallLink(_ element: AXUIElement) -> Bool {
        SystemNotices.value(element, kAXRoleAttribute) as? String == "AXLink"
            && CallPopup.elapsed(in: SystemNotices.value(element, kAXDescriptionAttribute) as? String) != nil
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
        shared.ringingAsked = true
        defer { shared.ringingAsked = false }
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
        linkPath = nil
        leave = nil
        join = nil
    }

    /// The name, and the time when there's one, which comes as minutes and seconds.
    nonisolated static func reading(name: String?, time: String?) -> Reading? {
        guard let name = name?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }
        return Reading(name: name, elapsed: CallPopup.elapsed(in: time))
    }

    /// The call's link, and the way down to it: the first link whose words end in a running time,
    /// looking no further once it's found.
    private static func findLink(in app: AXUIElement) -> (element: AXUIElement, path: [Int])? {
        var seen = 0
        func walk(_ element: AXUIElement, _ path: [Int]) -> (element: AXUIElement, path: [Int])? {
            seen += 1
            guard path.count < 80, seen < 20_000 else { return nil }
            if isCallLink(element) { return (element, path) }
            for (index, child) in (SystemNotices.value(element, kAXChildrenAttribute) as? [AXUIElement] ?? []).enumerated() {
                if let found = walk(child, path + [index]) { return found }
            }
            return nil
        }
        for (index, window) in (SystemNotices.value(app, kAXWindowsAttribute) as? [AXUIElement] ?? []).enumerated() {
            if let found = walk(window, [index]) { return found }
        }
        return nil
    }

    /// Its words, in order: the status first, in a group of its own; then who it's with; the time
    /// last. A call with one person has their name on its own; a group's has its names in one line,
    /// in the same group as the time.
    private static func parts(of link: AXUIElement) -> (name: String?, time: String?) {
        func texts(in element: AXUIElement) -> [String] {
            SystemNotices.findAll(in: element) { SystemNotices.value($0, kAXRoleAttribute) as? String == kAXStaticTextRole }
                .compactMap { SystemNotices.value($0, kAXValueAttribute) as? String }
        }
        let first = (SystemNotices.value(link, kAXChildrenAttribute) as? [AXUIElement])?.first
        let status = first.map { SystemNotices.value($0, kAXRoleAttribute) as? String == kAXGroupRole ? texts(in: $0).count : 0 } ?? 0
        return words(afterStatus: status, in: texts(in: link))
    }

    /// Who it's with and how long, from the link's words in order, past as many as its status has.
    nonisolated static func words(afterStatus status: Int, in texts: [String]) -> (name: String?, time: String?) {
        var rest = Array(texts.dropFirst(status))
        let time = rest.last.flatMap { CallPopup.elapsed(in: $0) != nil ? $0 : nil }
        if time != nil { rest.removeLast() }
        let name = rest.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: ", ")
        return (name.isEmpty ? nil : name, time)
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
        processIDs().compactMap { id in
            guard let pid = pid(of: id), let bundle = bundle(of: id) else { return nil }
            return Process(
                pid: pid, bundle: bundle, input: flag(id, kAudioProcessPropertyIsRunningInput), output: flag(id, kAudioProcessPropertyIsRunningOutput))
        }
    }

    /// Every process Core Audio knows of. Each question about one waits on macOS's sound service.
    private static func processIDs() -> [AudioObjectID] {
        var address = AudioProperty.address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioProperty.system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioProperty.system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func flag(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Bool {
        var address = AudioProperty.address(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr && value != 0
    }

    private static func pid(of id: AudioObjectID) -> pid_t? {
        var pid: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        var address = AudioProperty.address(kAudioProcessPropertyPID)
        return AudioObjectGetPropertyData(id, &address, 0, nil, &size, &pid) == noErr ? pid : nil
    }

    private static func bundle(of id: AudioObjectID) -> String? {
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var address = AudioProperty.address(kAudioProcessPropertyBundleID)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == noErr else { return nil }
        return name?.takeRetainedValue() as String?
    }

    /// A calling app using the microphone now: each process asked only whether it's recording,
    /// and only those that are, what they are.
    static func appOnMicrophone() -> App? {
        for id in processIDs() where flag(id, kAudioProcessPropertyIsRunningInput) {
            if let bundle = bundle(of: id), let app = callApp(of: bundle) { return app }
        }
        return nil
    }

    /// Every app using the microphone now, by its bundle: each process asked only whether it's
    /// recording, and only those that are, what they are.
    static func bundlesOnMicrophone() -> [String] {
        processIDs().filter { flag($0, kAudioProcessPropertyIsRunningInput) }.compactMap(bundle(of:))
    }

    static let asking = DispatchQueue(label: "Glance.CallAudio", qos: .userInitiated)

    /// The same, asked away from the thread that draws the notch, which would otherwise wait on
    /// macOS's sound service every second; the answer comes back on it.
    static func appOnMicrophone(then answer: @escaping @MainActor (App?) -> Void) {
        asking.async {
            let app = appOnMicrophone()
            DispatchQueue.main.async { MainActor.assumeIsolated { answer(app) } }
        }
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
    private lazy var wave = CallPopupWave { theirs, yours in
        DispatchQueue.main.async { MainActor.assumeIsolated { CallVoices.shared.saw(theirs: theirs, yours: yours) } }
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
        var ticks = CallPopup.Ticks(last: shown, at: .now)
        let giveUp = Date.now.addingTimeInterval(3)
        while Date.now < giveUp, found != nil, !pressing {
            guard let current = frame(of: found?.banner), let image = await CallPopupCamera.picture(of: current, in: window) else { return }
            let seen = await Task.detached(priority: .userInitiated) { CallPopup.read(image, accurate: false) }.value
            if let started = ticks.saw(seen.elapsed, at: .now) {
                popup?.detail = seen.detail
                popup?.started = started
                changed?(popup)
                return
            }
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
