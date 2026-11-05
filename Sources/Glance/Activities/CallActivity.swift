//
//  CallActivity.swift
//  Glance
//
//  Created by Gaty on 05/11/2026.
//

import AVFoundation
import AppKit
import ApplicationServices
import CoreAudio
import SwiftUI

/// A call, as the notch shows it.
struct CallShown: Equatable {
    enum Phase: Equatable {
        case ringing
        case connected(since: Date)
    }

    /// Who it's with, or the app, where the app doesn't say.
    var name: String
    /// What it's over: FaceTime, Phone, Discord.
    var over: String
    /// The app it's in, to go to.
    var app: String?
    var phase: Phase
    /// Its app shows a button to end it that Glance can press.
    var canEnd = false

    /// As an unknown caller shows, in a gray circle.
    var initial: String { name.first.map { String($0).uppercased() } ?? "" }
    var isConnected: Bool { phase != .ringing }
}

/// How a call looks, measured from a screenshot of a real call: a green phone and its time on one
/// side, on the other a thin waveform that runs along, green where the other person speaks and a
/// paler yellow where you do. Ringing, the caller's initial in a gray circle, and a gray handset.
enum CallLook {
    static let green = Color(red: 0x9A / 255, green: 0xEE / 255, blue: 0x9C / 255)
    static let theirVoice = Color(red: 0xBD / 255, green: 0xF5 / 255, blue: 0x8F / 255)
    static let yourVoice = Color(red: 0xF5 / 255, green: 0xE6 / 255, blue: 0xA3 / 255)
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
        case .ringing:
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

/// The waveform beside the camera on a call, running along: each bar is a moment, the newest at the
/// right, in the color of whoever was speaking then.
struct CallWaveform: View {
    let height: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12, paused: reduceMotion)) { _ in
            // Read out here, so the drawing is new each time and is drawn again.
            let samples = CallVoices.shared.samples
            Canvas { context, size in
                let pitch = CallLook.barWidth + CallLook.barGap
                for (index, sample) in samples.enumerated() {
                    let bar = max(sample.level * size.height, CallLook.barWidth * 1.6)
                    let rect = CGRect(
                        x: CGFloat(index) * pitch, y: (size.height - bar) / 2, width: CallLook.barWidth, height: bar)
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: CallLook.barWidth / 2),
                        with: .color(sample.mine ? CallLook.yourVoice : CallLook.theirVoice))
                }
            }
        }
        .frame(width: CallLook.waveWidth, height: height)
        .accessibilityHidden(true)
    }
}

/// A call beside the camera. Ringing, once its popup is swiped away: the caller and a gray handset.
/// Connected: the green phone and the time, and the waveform.
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
            call.isConnected ? String(localized: "\(call.name), on a call") : String(localized: "\(call.name), incoming call"))
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
/// sound output and, where its app's own can be pressed, one to end it. Clicked anywhere else, it
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
            .accessibilityLabel(call.isConnected ? String(localized: "\(call.name), on a call") : String(localized: "\(call.name), incoming call"))
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
        if call.isConnected {
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

/// Who's speaking on the call, for the waveform: the other person from the sound the call's app
/// makes, through the same process tap as the music's waveform, and you from the microphone, once
/// it's allowed. Nothing is recorded or kept. It runs only during a call.
@MainActor
final class CallVoices {
    static let shared = CallVoices()

    struct Sample: Equatable {
        var level: CGFloat
        var mine: Bool
    }

    /// Oldest first.
    private(set) var samples = [Sample](repeating: Sample(level: 0, mine: false), count: CallLook.bars)
    private var theirs: CGFloat = 0
    private var yours: CGFloat = 0
    private var pipeline: TapPipeline?
    private var engine: AVAudioEngine?
    private var clock: Timer?
    /// At the bench: both voices made up, turn about, with nothing listened to.
    var madeUp = false

    /// One moment's bar: whoever's louder then, and how loud.
    nonisolated static func sample(theirs: CGFloat, yours: CGFloat) -> Sample {
        Sample(level: min(max(theirs, yours), 1), mine: yours > theirs)
    }

    func start(listeningTo pid: pid_t?) {
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
        if !madeUp { startMicrophone() }
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
        samples = [Sample](repeating: Sample(level: 0, mine: false), count: CallLook.bars)
    }

    private func tick() {
        let t = Date.now.timeIntervalSinceReferenceDate
        if madeUp {
            let theirTurn = Int(t / 2.5) % 2 == 0
            theirs = theirTurn ? 0.9 * CGFloat(DJGlyph.flap(at: t)) : 0
            yours = theirTurn ? 0 : 0.9 * CGFloat(DJGlyph.flap(at: t))
        }
        // With audio capture off there's nothing to hear of them, so it moves as a voice does.
        let heard = madeUp || Permissions.audioCapture == .granted ? theirs : 0.5 * CGFloat(DJGlyph.flap(at: t))
        samples.removeFirst()
        samples.append(Self.sample(theirs: heard, yours: yours))
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

/// The calls there are, from everything that can tell: the system's own list; macOS's popup for a
/// call coming in; and, for apps like Zoom and Discord that tell the system nothing on a Mac, one of
/// them using the microphone.
@MainActor
final class CallWatch: ObservableObject {
    static let shared = CallWatch()

    @Published private(set) var call: CallShown?
    /// Counted a minute at a time during a call, so the notch refits as its time gains a digit.
    @Published private(set) var minutes = 0

    private let system = SystemCalls()
    private var microphone: CallAudio.App?
    private var banner: CallBanners.Banner?
    /// Who the call is with, kept from its popup once that's gone.
    private var who: CallBanners.Banner?
    private var since: Date?
    private var watch: Timer?
    private var minuteTimer: Timer?
    private var showing: CallShown?

    func start() {
        guard ActivityBench.scene == nil else { return }
        system.changed = { [weak self] in self?.refresh() }
        system.start()
        CallBanners.shared.changed = { [weak self] banner in
            self?.banner = banner
            if let banner { self?.who = banner }
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
        let calls = system.calls
        let connected = microphone != nil || calls.contains(where: \.connected)
        let ringing = banner != nil || calls.contains { !$0.connected }
        let app = microphone?.bundle ?? who?.app
        let over = who?.over ?? microphone?.name ?? "FaceTime"
        let name = who?.name ?? microphone?.name ?? String(localized: "Call")
        if connected, banner == nil {
            let started = since ?? .now
            since = started
            show(CallShown(name: name, over: over, app: app, phase: .connected(since: started), canEnd: CallEnd.button() != nil))
        } else if ringing {
            show(CallShown(name: name, over: over, app: app, phase: .ringing))
        } else {
            who = nil
            since = nil
            show(nil)
        }
    }

    private func show(_ next: CallShown?) {
        guard next != showing else { return }
        let before = showing
        showing = next
        call = next
        // A call coming in shows as tall as the Alarm, until it's answered, swiped away or over.
        if next?.phase == .ringing, before?.phase != .ringing, let next {
            Activities.shared.post(
                NotchAlert(
                    kind: .incomingCall, content: .incomingCall(next), spoken: String(localized: "\(next.name), incoming call"), stays: true))
        } else if next?.phase != .ringing {
            Activities.shared.dismiss(.incomingCall)
        }
        if next?.isConnected == true {
            CallVoices.shared.start(listeningTo: CallAudio.pid(ofCallIn: microphone?.bundle))
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
        CallBanners.shared.press(CallBanners.acceptWords)
    }

    func decline() {
        Activities.shared.dismiss(.incomingCall)
        CallBanners.shared.press(CallBanners.declineWords)
    }

    /// Ends it, as its app's own End button does, pressed through Accessibility.
    func end() {
        CallEnd.press()
        refresh()
    }

    /// To the call, in its app.
    func goToApp() {
        let bundle = call?.app ?? "com.apple.FaceTime"
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    /// At the bench: made up, the real one left alone.
    func bench(_ made: CallShown?) {
        CallVoices.shared.madeUp = true
        show(made)
    }
}

/// The system's own list of calls. Its API is marked as for iOS and Mac Catalyst apps, but it's
/// there on the Mac and answers, so it's reached by name.
@MainActor
final class SystemCalls: NSObject {
    struct Call: Equatable {
        var connected: Bool
        var outgoing: Bool
    }

    var changed: (() -> Void)?
    private(set) var calls: [Call] = []
    private var observer: NSObject?

    func start() {
        _ = Bundle(path: "/System/Library/Frameworks/CallKit.framework")?.load()
        guard let kind = NSClassFromString("CXCallObserver") as? NSObject.Type else { return }
        let observer = kind.init()
        let setDelegate = NSSelectorFromString("setDelegate:queue:")
        guard observer.responds(to: setDelegate) else { return }
        observer.perform(setDelegate, with: self, with: nil)
        self.observer = observer
        read()
    }

    private func read() {
        let listed = observer?.value(forKey: "calls") as? [NSObject] ?? []
        calls = listed.compactMap { call in
            guard call.value(forKey: "hasEnded") as? Bool != true else { return nil }
            return Call(connected: call.value(forKey: "hasConnected") as? Bool == true, outgoing: call.value(forKey: "isOutgoing") as? Bool == true)
        }
    }

    @objc(callObserver:callChanged:)
    func callObserver(_ observer: NSObject, callChanged call: NSObject) {
        read()
        changed?()
    }
}

/// The End button macOS shows during a FaceTime or phone call, in FaceTime's or Phone's window or in
/// the call's notification, found by the words macOS itself gives it in the Mac's language, and
/// pressed through Accessibility. Other apps' calls have their own, which aren't looked for.
@MainActor
enum CallEnd {
    private static let apps = ["com.apple.FaceTime", "com.apple.mobilephone"]

    /// macOS's own names for it.
    static let words: Set<String> = {
        let kit = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/ConversationKit.framework")
        let found = ["DRAWER_END_AX", "IN_CALL_CONTROLS_END_LABEL", "AX_HANG_UP"].map { SystemNotices.words($0, table: "ConversationKit", of: kit) }
        let named = Set(found.filter { !$0.isEmpty && !$0.hasPrefix("DRAWER_") && !$0.hasPrefix("IN_CALL_") && !$0.hasPrefix("AX_") })
        return named.isEmpty ? ["End", "Hang Up"] : named
    }()

    /// Where it is: a button in a window, or a notification with it as one of its actions.
    enum Place {
        case button(AXUIElement)
        case action(AXUIElement, String)
    }

    static func button() -> Place? {
        guard AXIsProcessTrusted() else { return nil }
        for bundle in apps {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundle) {
                let element = AXUIElementCreateApplication(app.processIdentifier)
                AXUIElementSetMessagingTimeout(element, 0.5)
                for window in SystemNotices.value(element, kAXWindowsAttribute) as? [AXUIElement] ?? [] {
                    let found = SystemNotices.findAll(in: window) { item in
                        SystemNotices.value(item, kAXRoleAttribute) as? String == kAXButtonRole as String
                            && [kAXDescriptionAttribute, kAXTitleAttribute].contains { words.contains(SystemNotices.value(item, $0) as? String ?? "") }
                    }
                    if let first = found.first { return .button(first) }
                }
            }
        }
        let calls = ["FaceTime", "Phone"].map { SystemNotices.name(of: URL(fileURLWithPath: "/System/Applications/\($0).app")) }
        for notification in calls.flatMap(SystemNotices.showing(from:)) {
            var names: CFArray?
            AXUIElementCopyActionNames(notification, &names)
            if let action = (names as? [String] ?? []).first(where: { action in words.contains { action.hasPrefix("Name:" + $0 + "\n") || action == "Name:" + $0 } }) {
                return .action(notification, action)
            }
        }
        return nil
    }

    static func press() {
        switch button() {
        case .button(let button): AXUIElementPerformAction(button, kAXPressAction as CFString)
        case .action(let notification, let action): AXUIElementPerformAction(notification, action as CFString)
        case nil: break
        }
    }
}

/// Who's using the microphone and making sound, from Core Audio's list of processes.
enum CallAudio {
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

/// macOS's popup for a call coming in, at the top right of the screen, in Notification Center: read
/// through Accessibility, moved out of sight while the notch shows the same, and pressed from the
/// notch's buttons. Without Accessibility, it shows as before.
@MainActor
final class CallBanners {
    static let shared = CallBanners()

    struct Banner: Equatable {
        var name: String
        var over: String
        var app: String?
    }

    static let acceptWords = ["Accept", "Answer"]
    static let declineWords = ["Decline"]
    /// Past any arrangement of displays.
    private static let away = CGPoint(x: -20000, y: -20000)

    var changed: ((Banner?) -> Void)?
    var hides = true

    private var center: pid_t = 0
    private var observer: AXObserver?
    private var showing: (notification: AXUIElement, window: AXUIElement, place: CGPoint?, banner: Banner)?
    private var poll: Timer?

    /// Follows Notification Center, as soon as Accessibility is allowed, and again if it's restarted.
    func follow() {
        guard AXIsProcessTrusted(),
            let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").first?.processIdentifier,
            pid != center
        else { return }
        var made: AXObserver?
        let told: AXObserverCallback = { _, _, _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { CallBanners.shared.scan() } }
        }
        guard AXObserverCreate(pid, told, &made) == .success, let made else { return }
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode) }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        AXObserverAddNotification(made, app, kAXWindowCreatedNotification as CFString, nil)
        AXObserverAddNotification(made, app, kAXCreatedNotification as CFString, nil)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(made), .defaultMode)
        center = pid
        observer = made
    }

    /// What a notification tells of a call coming in, if it's one: its first words name the app,
    /// and it has a button to accept. The next words are who's calling.
    nonisolated static func call(description: String, actions: [String]) -> Banner? {
        let apps = ["FaceTime": "com.apple.FaceTime", "Phone": "com.apple.mobilephone"]
        let words = description.components(separatedBy: ", ")
        guard words.count >= 2, let app = apps[words[0]] else { return nil }
        guard actions.contains(where: { action in acceptWords.contains { action.hasPrefix("Name:" + $0) } }) else { return nil }
        return Banner(name: words[1], over: words[0], app: app)
    }

    private func scan() {
        guard center != 0 else { return }
        let app = AXUIElementCreateApplication(center)
        AXUIElementSetMessagingTimeout(app, 0.5)
        let subroles: Set<String> = ["AXNotificationCenterAlert", "AXNotificationCenterBanner"]
        for window in SystemNotices.value(app, kAXWindowsAttribute) as? [AXUIElement] ?? [] {
            let found = SystemNotices.findAll(in: window) { subroles.contains(SystemNotices.value($0, kAXSubroleAttribute) as? String ?? "") }
            for notification in found {
                var names: CFArray?
                AXUIElementCopyActionNames(notification, &names)
                guard
                    let banner = Self.call(
                        description: SystemNotices.words(of: notification), actions: names as? [String] ?? [])
                else { continue }
                if showing == nil || showing?.banner != banner { take(notification, in: window, banner) }
                return
            }
        }
        // It's gone: answered, declined or missed.
        if showing != nil { give() }
    }

    private func take(_ notification: AXUIElement, in window: AXUIElement, _ banner: Banner) {
        var place: CGPoint?
        if hides, let value = SystemNotices.value(window, kAXPositionAttribute) {
            var point = CGPoint.zero
            if AXValueGetValue(value as! AXValue, .cgPoint, &point) { place = point }
            var off = Self.away
            if let away = AXValueCreate(.cgPoint, &off) { AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, away) }
        }
        showing = (notification, window, place, banner)
        changed?(banner)
        poll?.invalidate()
        let timer = Timer(timeInterval: 0.5, repeats: true) { _ in
            MainActor.assumeIsolated { CallBanners.shared.scan() }
        }
        RunLoop.main.add(timer, forMode: .common)
        poll = timer
    }

    private func give() {
        poll?.invalidate()
        poll = nil
        showing = nil
        changed?(nil)
    }

    /// Presses one of the popup's buttons. If it hasn't one of these names, the popup comes back for
    /// a person to press.
    func press(_ words: [String]) {
        guard let showing else { return }
        var names: CFArray?
        AXUIElementCopyActionNames(showing.notification, &names)
        let actions = names as? [String] ?? []
        if let action = actions.first(where: { action in words.contains { action.hasPrefix("Name:" + $0) } }),
            AXUIElementPerformAction(showing.notification, action as CFString) == .success
        {
            return
        }
        if var place = showing.place, let back = AXValueCreate(.cgPoint, &place) {
            AXUIElementSetAttributeValue(showing.window, kAXPositionAttribute as CFString, back)
        }
    }
}
