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
    /// As an unknown caller shows, in a gray circle.
    var initial: String { name.first.map { String($0).uppercased() } ?? "" }
    var rings: Bool { phase == .ringing }
    var isConnected: Bool {
        if case .connected = phase { return true }
        return false
    }
}

/// How a call looks, measured from real calls: a green phone and its time on one side, on the other
/// a waveform in both voices at once, orange into green, as macOS's own popup draws it. Ringing, the
/// caller's initial in a gray circle, and a gray handset.
enum CallLook {
    static let green = Color(red: 0x9A / 255, green: 0xEE / 255, blue: 0x9C / 255)
    /// Along the waveform, by the share of its width, from a real call's popup on a P3 display.
    static let voices: [(at: Double, red: Double, green: Double, blue: Double)] = [
        (0, 0xFF, 0xA0, 0x25), (0.39, 0xFF, 0xAE, 0x29), (0.46, 0xFF, 0xFF, 0x9E), (0.5, 0xFF, 0xFF, 0xB5), (0.55, 0x6E, 0xFF, 0x7C), (1, 0x5E, 0xFF, 0x7A),
    ]
    /// The color at a share of the waveform's width.
    static func voice(at share: Double) -> Color {
        let after = voices.firstIndex { $0.at >= share } ?? voices.count - 1
        let end = voices[after]
        let start = voices[max(after - 1, 0)]
        let part = end.at > start.at ? (share - start.at) / (end.at - start.at) : 0
        func mix(_ a: Double, _ b: Double) -> Double { (a + (b - a) * part) / 255 }
        return Color(.displayP3, red: mix(start.red, end.red), green: mix(start.green, end.green), blue: mix(start.blue, end.blue))
    }
    static let handset = Color(red: 0x8F / 255, green: 0x8F / 255, blue: 0x91 / 255)
    static let accept = Color(red: 0x34 / 255, green: 0xC7 / 255, blue: 0x59 / 255)
    static let decline = Color(red: 0xFF / 255, green: 0x3B / 255, blue: 0x30 / 255)

    /// The waveform's bars, as many as show at once, and their measures.
    static let bars = 16
    static let barWidth: CGFloat = 1.25
    static let barGap: CGFloat = 1.25
    static var waveWidth: CGFloat { CGFloat(bars) * (barWidth + barGap) - barGap }
    /// As shares of the notch's height: the tallest bar, the phone, the circle, the handset.
    static let barHeight: CGFloat = 0.36
    static let phone: CGFloat = 0.42
    static let avatar: CGFloat = 0.68
    static let handsetSize: CGFloat = 0.52
    /// Between the phone and its time.
    static let timeGap: CGFloat = 5
}

enum CallLayout {
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

/// The caller, as a contact without a picture shows: their initial in a gray circle.
struct CallAvatar: View {
    let call: CallShown
    let side: CGFloat

    var body: some View {
        Circle()
            .fill(LinearGradient(colors: [Color(white: 0.62), Color(white: 0.45)], startPoint: .top, endPoint: .bottom))
            .overlay {
                Text(call.initial)
                    .font(.system(size: side * 0.48, weight: .semibold))
                    .foregroundStyle(.white)
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

/// The waveform beside the camera on a call: both voices at once, a half each, each bar lit from its
/// middle as it is in macOS's popup.
struct CallWaveform: View {
    let height: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12, paused: reduceMotion)) { _ in
            // Read out here, so the drawing is new each time and is drawn again.
            let bars = CallVoices.shared.bars
            Canvas { context, size in
                let pitch = CallLook.barWidth + CallLook.barGap
                for (index, level) in bars.enumerated() {
                    let bar = max(level * size.height, CallLook.barWidth)
                    let rect = CGRect(x: CGFloat(index) * pitch, y: (size.height - bar) / 2, width: CallLook.barWidth, height: bar)
                    let color = CallLook.voice(at: (Double(index) + 0.5) / Double(max(bars.count, 1)))
                    context.fill(Path(roundedRect: rect, cornerRadius: CallLook.barWidth / 2), with: .color(color))
                }
            }
        }
        .frame(width: CallLook.waveWidth, height: height)
        .accessibilityHidden(true)
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
                CallAvatar(call: call, side: h * CallLook.avatar)
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
                CallWaveform(height: h * CallLook.barHeight)
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
/// it, red and green.
struct IncomingCallView: View {
    let call: CallShown
    let restingHeight: CGFloat
    /// Which button the pointer is on.
    let hovered: AlertButton?

    /// Between the caller's circle and the words.
    static let gap: CGFloat = 0.3
    /// As long as a name goes before it's cut short, as a share of the notch's height.
    static let nameLimit: CGFloat = 6

    var body: some View {
        let h = restingHeight
        let side = TimerLayout.content(h)
        ZStack {
            HStack(spacing: h * Self.gap) {
                CallAvatar(call: call, side: side)
                VStack(alignment: .leading, spacing: 0) {
                    Text(call.over)
                        .font(NotchType.detail)
                        .foregroundStyle(NotchType.detailColor)
                    Text(call.name)
                        .font(NotchType.title)
                        .foregroundStyle(.white)
                }
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: h * Self.nameLimit, alignment: .leading)
            }
            .padding(.leading, TimerLayout.buttonEdge(h))
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: h * TimerLayout.buttonGap) {
                button("phone.down.fill", CallLook.decline, side, hovered == .decline)
                    .reportsFrame(.decline)
                    .spokenButton(String(localized: "Decline")) { CallWatch.shared.decline() }
                button("phone.fill", CallLook.accept, side, hovered == .accept)
                    .reportsFrame(.accept)
                    .spokenButton(String(localized: "Accept")) { CallWatch.shared.accept() }
            }
            .padding(.trailing, TimerLayout.buttonEdge(h))
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(maxHeight: .infinity)
    }

    private func button(_ symbol: String, _ color: Color, _ side: CGFloat, _ highlighted: Bool) -> some View {
        Circle()
            .fill(color)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: side * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .brightness(highlighted ? 0.08 : 0)
            .frame(width: side, height: side)
    }

    /// Each wing: as wide as the wider side, the caller or the buttons, each from its end.
    @MainActor
    static func wing(for call: CallShown, restingHeight h: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: NotchType.size, weight: .semibold)
        let words = min(
            ceil(max((call.name as NSString).size(withAttributes: [.font: font]).width, (call.over as NSString).size(withAttributes: [.font: font]).width)),
            h * nameLimit)
        let side = TimerLayout.content(h)
        let left = TimerLayout.buttonEdge(h) + side + h * gap + words + LiveActivityView.cameraGap
        let right = LiveActivityView.cameraGap + side * 2 + h * TimerLayout.buttonGap + TimerLayout.buttonEdge(h)
        return max(left, right)
    }
}

/// Opened, a call shows as its popup does, as tall as one coming in: the caller, and while it rings,
/// what it's over and buttons to decline or accept it; once connected, its time, a button for the
/// sound output and, where its popup's own can be pressed, one to end it. Clicked anywhere else, it
/// goes to the app it's in.
struct ExpandedCallView: View {
    let call: CallShown
    let restingHeight: CGFloat
    let width: CGFloat
    var revealed = true
    @Environment(\.playerKeys) private var keys

    var body: some View {
        let h = restingHeight
        ZStack {
            Button {
                CallWatch.shared.goToApp()
            } label: {
                HStack(spacing: h * IncomingCallView.gap) {
                    CallAvatar(call: call, side: TimerLayout.content(h))
                    VStack(alignment: .leading, spacing: 0) {
                        if case .connected(let since) = call.phase {
                            CallTime(since: since)
                                .font(NotchType.detail)
                                .foregroundStyle(CallLook.green)
                        } else {
                            Text(call.over)
                                .font(NotchType.detail)
                                .foregroundStyle(NotchType.detailColor)
                        }
                        Text(call.name)
                            .font(NotchType.title)
                            .foregroundStyle(.white)
                    }
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: h * IncomingCallView.nameLimit, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(IslandPress(highlight: false, contactSize: nil))
            .notchControl()
            .help(String(localized: "Show in \(call.over)"))
            .accessibilityLabel(!call.rings ? String(localized: "\(call.name), on a call") : String(localized: "\(call.name), incoming call"))
            .accessibilityHint(String(localized: "Show in \(call.over)"))
            .padding(.leading, TimerLayout.buttonEdge(h))
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: h * TimerLayout.buttonGap) { buttons(h) }
                .padding(.trailing, TimerLayout.buttonEdge(h))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .modifier(PageFade(hidden: !revealed))
        .frame(width: width, height: TimerLayout.tallHeight(h))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func buttons(_ h: CGFloat) -> some View {
        if !call.rings {
            IslandCircleButton(control: .activityFirst, height: h, tint: .white, label: String(localized: "Sound Output")) {
                // From the keyboard the pointer can be anywhere: the menu opens under the button.
                let fromKeys = NSApp.currentEvent?.type == .keyDown
                AudioOutput.shared.showMenu(at: fromKeys ? keys?.focusFrame.flatMap { keys?.screenPoint?($0) } : nil, withVolume: false)
            } glyph: {
                glyph("speaker.wave.2.fill", h)
            }
            if call.canEnd {
                IslandCircleButton(control: .activitySecond, height: h, tint: .white, label: String(localized: "End"), fill: CallLook.decline) {
                    CallWatch.shared.end()
                } glyph: {
                    glyph("phone.down.fill", h)
                }
            }
        } else {
            IslandCircleButton(control: .activityFirst, height: h, tint: .white, label: String(localized: "Decline"), fill: CallLook.decline) {
                CallWatch.shared.decline()
            } glyph: {
                glyph("phone.down.fill", h)
            }
            IslandCircleButton(control: .activitySecond, height: h, tint: .white, label: String(localized: "Accept"), fill: CallLook.accept) {
                CallWatch.shared.accept()
            } glyph: {
                glyph("phone.fill", h)
            }
        }
    }

    private func glyph(_ symbol: String, _ h: CGFloat) -> some View {
        Image(systemName: symbol)
            .font(.system(size: TimerLayout.content(h) * 0.42, weight: .semibold))
            .foregroundStyle(.white)
    }

    /// Each side of the camera: as wide as the wider of the caller and the buttons, each from its end.
    @MainActor
    static func wing(for call: CallShown, restingHeight h: CGFloat, at date: Date = .now) -> CGFloat {
        guard case .connected(let since) = call.phase else { return IncomingCallView.wing(for: call, restingHeight: h) }
        let font = NSFont.systemFont(ofSize: NotchType.size, weight: .semibold)
        let name = ceil((call.name as NSString).size(withAttributes: [.font: font]).width)
        let time = SystemActivityView.digitsWidth(ClockText.of(max(Int(date.timeIntervalSince(since)), 0)), NotchType.size, .regular)
        let side = TimerLayout.content(h)
        let left = TimerLayout.buttonEdge(h) + side + h * IncomingCallView.gap + min(max(name, time), h * IncomingCallView.nameLimit) + LiveActivityView.cameraGap
        let buttons: CGFloat = call.canEnd ? 2 : 1
        let right = LiveActivityView.cameraGap + side * buttons + h * TimerLayout.buttonGap * (buttons - 1) + TimerLayout.buttonEdge(h)
        return max(left, right)
    }

    @MainActor
    static func width(for call: CallShown, restingHeight h: CGFloat, closedWidth: CGFloat) -> CGFloat {
        closedWidth + wing(for: call, restingHeight: h) * 2
    }
}

// MARK: - Voices

/// How each voice on the call moves, for the waveform: half for you and half for the other person.
/// On a phone or FaceTime call, those are the bars of macOS's own popup, with nothing listened to.
/// Otherwise, the other person from the sound the call's app makes, through the same process tap as
/// the music's waveform, and you from the microphone, once it's allowed. Nothing is recorded or
/// kept. It runs only during a call.
@MainActor
final class CallVoices {
    static let shared = CallVoices()

    /// What the waveform draws, left to right.
    private(set) var bars = [CGFloat](repeating: 0, count: CallLook.bars)
    private var yourLevels = [CGFloat](repeating: 0, count: CallLook.bars / 2)
    private var theirLevels = [CGFloat](repeating: 0, count: CallLook.bars / 2)
    private var theirs: CGFloat = 0
    private var yours: CGFloat = 0
    private var seenAt: Date?
    private var pipeline: TapPipeline?
    private var engine: AVAudioEngine?
    private var clock: Timer?
    /// At the bench: both voices made up, turn about, with nothing listened to.
    var madeUp = false

    /// The popup's own bars, as they just showed. They're sent only when they've changed.
    func saw(_ popup: [CGFloat]) {
        guard clock != nil else { return }
        seenAt = .now
        bars = CallPopup.fold(popup, into: CallLook.bars)
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
        let timer = Timer(timeInterval: 1.0 / 12, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        clock = timer
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
        seenAt = nil
        yourLevels = yourLevels.map { _ in 0 }
        theirLevels = theirLevels.map { _ in 0 }
        bars = bars.map { _ in 0 }
    }

    private func tick() {
        // The popup's unchanged only while there's nothing to hear, and then it's flat anyway.
        if let seenAt, Date.now.timeIntervalSince(seenAt) < 1 { return }
        let t = Date.now.timeIntervalSinceReferenceDate
        if madeUp {
            let theirTurn = Int(t / 2.5) % 2 == 0
            theirs = theirTurn ? 0.9 * CGFloat(DJGlyph.flap(at: t)) : 0.1
            yours = theirTurn ? 0.1 : 0.9 * CGFloat(DJGlyph.flap(at: t))
        }
        bars = Self.running(&yourLevels, &theirLevels, yours: yours, theirs: theirs)
    }

    /// Each voice runs along its own half, its newest moment in the middle.
    nonisolated static func running(_ yourLevels: inout [CGFloat], _ theirLevels: inout [CGFloat], yours: CGFloat, theirs: CGFloat) -> [CGFloat] {
        yourLevels.removeFirst()
        yourLevels.append(min(yours, 1))
        theirLevels.removeLast()
        theirLevels.insert(min(theirs, 1), at: 0)
        return yourLevels + theirLevels
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
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                CallBanners.shared.follow()
                self?.microphone = CallAudio.appOnMicrophone()
                self?.refresh()
            }
        }
        timer.tolerance = 1.5
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
                show(CallShown(name: name, over: app.name, app: app.bundle, phase: .ringing))
            } else {
                show(CallShown(name: name, over: app.name, app: app.bundle, phase: .calling, canEnd: popup.red != nil))
            }
        } else if let microphone {
            let apple = microphone.bundle == CallAudio.appleService
            let app = apple ? Self.appleApp(detail: nil, phoneRunning: Self.phoneRunning) : (name: microphone.name, bundle: microphone.bundle)
            let started = since ?? .now
            since = started
            show(CallShown(name: who ?? app.name, over: app.name, app: app.bundle, phase: .connected(since: started)))
        } else {
            who = nil
            since = nil
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
        CallBanners.shared.press(.green)
    }

    func decline() {
        Activities.shared.dismiss(.incomingCall)
        end()
    }

    /// Ends it, with the popup's own End button.
    func end() {
        CallBanners.shared.press(.red)
    }

    /// To the call, in its app.
    func goToApp() {
        let bundle = call?.app ?? CallAudio.faceTime
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    /// At the bench: made up, the real one left alone.
    func bench(_ made: CallShown?) {
        CallVoices.shared.madeUp = true
        show(made)
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
/// Once the notch can offer the same, that window is moved up until only its last row of points is
/// on screen, which has nothing in it: the popup's out of sight and can still be read. Until then,
/// or without Screen Recording, it's left alone. Every other notification hides with it, until the
/// call's over. Without Accessibility, nothing's found and it shows as before.
@MainActor
final class CallBanners {
    static let shared = CallBanners()

    static let center = "com.apple.notificationcenterui"
    /// The process drawing the popup, which runs only around a call.
    private static let popupProcess = "com.apple.FaceTime.FaceTimeNotificationExtension"
    /// Where the window belongs while it's moved, kept in case Glance doesn't get to put it back.
    private static let homeKey = "callPopupWindowHome"

    enum Button {
        case red, green
    }

    var changed: ((CallPopup?) -> Void)?
    var hides = true {
        didSet {
            guard hides != oldValue, !hides else { return }
            reveal()
            scan()
        }
    }

    private var centerPID: pid_t = 0
    private var observer: AXObserver?
    private var timer: Timer?
    private var found: (banner: AXUIElement, window: AXUIElement)?
    private var popup: CallPopup?
    private var home: CGPoint?
    private var reading = false
    private var pressing = false
    private var readCarefully = false
    private var mustRead = false
    private var checkedAt: Date?
    private var askedForScreen = false
    private lazy var wave = CallPopupWave { bars in
        DispatchQueue.main.async { MainActor.assumeIsolated { CallVoices.shared.saw(bars) } }
    }

    /// Follows Notification Center, as soon as Accessibility is allowed, and again if it's restarted.
    func follow() {
        guard AXIsProcessTrusted(),
            let pid = NSRunningApplication.runningApplications(withBundleIdentifier: Self.center).first?.processIdentifier
        else { return }
        if timer == nil {
            putBackLeftOver(in: pid)
            NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { CallBanners.shared.reveal() }
            }
            let made = Timer(timeInterval: 1, repeats: true) { _ in
                MainActor.assumeIsolated { CallBanners.shared.scan() }
            }
            made.tolerance = 0.2
            RunLoop.main.add(made, forMode: .common)
            timer = made
        }
        guard pid != centerPID else { return }
        var made: AXObserver?
        let told: AXObserverCallback = { _, _, _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { CallBanners.shared.scan() } }
        }
        guard AXObserverCreate(pid, told, &made) == .success, let made else { return }
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode) }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        AXObserverAddNotification(made, app, kAXCreatedNotification as CFString, nil)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(made), .defaultMode)
        centerPID = pid
        observer = made
    }

    /// If Glance stopped with the window moved, it goes back, or no notification would ever show.
    private func putBackLeftOver(in pid: pid_t) {
        guard let left = UserDefaults.standard.string(forKey: Self.homeKey) else { return }
        let app = AXUIElementCreateApplication(pid)
        var place = NSPointFromString(left)
        for window in SystemNotices.value(app, kAXWindowsAttribute) as? [AXUIElement] ?? [] {
            if let back = AXValueCreate(.cgPoint, &place) { AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, back) }
        }
        UserDefaults.standard.removeObject(forKey: Self.homeKey)
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
        // macOS puts its window back by itself now and then.
        if let home, let place = position(of: now.window), place == home {
            self.home = nil
            conceal()
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

    private func position(of element: AXUIElement) -> CGPoint? {
        guard let value = SystemNotices.value(element, kAXPositionAttribute) else { return nil }
        var place = CGPoint.zero
        return AXValueGetValue(value as! AXValue, .cgPoint, &place) ? place : nil
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
        guard hides, !pressing, home == nil, popup?.readable == true, let found else { return }
        guard let place = position(of: found.window), let size = frame(of: found.window)?.height else { return }
        var away = CGPoint(x: place.x, y: place.y - size + 1)
        guard let value = AXValueCreate(.cgPoint, &away), AXUIElementSetAttributeValue(found.window, kAXPositionAttribute as CFString, value) == .success
        else { return }
        home = place
        UserDefaults.standard.set(NSStringFromPoint(place), forKey: Self.homeKey)
        guard !wave.running, let rect = frame(of: found.banner) else { return }
        Task {
            guard let window = await CallPopupCamera.window() else { return }
            await wave.start(window: window, popup: rect)
        }
    }

    private func reveal() {
        guard var place = home, let window = found?.window, let back = AXValueCreate(.cgPoint, &place) else { return }
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, back)
        home = nil
        UserDefaults.standard.removeObject(forKey: Self.homeKey)
    }

    /// It's gone: Notification Center's window goes back where it was, for every notification after.
    private func give() {
        wave.stop()
        reveal()
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
            reveal()
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
