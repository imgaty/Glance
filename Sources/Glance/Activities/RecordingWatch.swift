//
//  RecordingWatch.swift
//  Glance
//
//  Created by Gaty on 07/11/2026.
//

import AVFoundation
import AppKit

/// How loud the microphone is while a voice memo records, for its waveform: the loudest of each
/// tenth of a second, newest last. Heard as the call's voice is (see `CallVoices`), once the
/// microphone is allowed; nothing is recorded or kept. It runs only while a voice memo records.
@MainActor
final class RecordingLevels: ObservableObject {
    static let shared = RecordingLevels()

    /// From 0 to 1, as many as the open waveform shows.
    @Published private(set) var levels: [CGFloat] = []
    private var loudest: CGFloat = 0
    private var engine: AVAudioEngine?
    private var clock: Timer?
    /// At the bench: made up, with nothing listened to.
    var madeUp = false
    private var madeUpAt = 0

    static let kept = RecordingLook.openRecorded

    func start() {
        guard clock == nil else { return }
        if !madeUp { startMicrophone() }
        let timer = Timer(timeInterval: RecordingLook.barTime, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        clock = timer
    }

    /// Paused: the waveform stays as it is.
    func pause() {
        clock?.invalidate()
        clock = nil
        stopMicrophone()
    }

    func stop() {
        pause()
        loudest = 0
        levels = []
    }

    private func tick() {
        let level = madeUp ? Self.madeUpLevel(madeUpAt) : loudest
        madeUpAt += 1
        loudest = 0
        levels = Array((levels + [level]).suffix(Self.kept))
    }

    /// A voice, as near as made up: about three syllables a second, each rising and falling over a
    /// few bars, the phrase louder and quieter, with a breath every couple of seconds.
    nonisolated static func madeUpLevel(_ step: Int) -> CGFloat {
        let t = Double(step) * RecordingLook.barTime
        if t.truncatingRemainder(dividingBy: 2.6) > 2.1 { return 0 }
        let syllable = pow(abs(sin(t * .pi * 3.1)), 0.7)
        let phrase = 0.6 + 0.4 * sin(t * 1.7)
        let grain = 0.85 + 0.15 * sin(t * 13.7)
        return CGFloat(min(max(syllable * phrase * grain, 0), 1))
    }

    /// A sound's loudness as the waveform shows it: by its decibels, from very quiet to a raised
    /// voice.
    nonisolated static func level(rms: Float) -> CGFloat {
        guard rms > 0 else { return 0 }
        let decibels = 20 * log10(rms)
        return CGFloat(min(max((decibels + 50) / 40, 0), 1))
    }

    private func startMicrophone() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            listen()
        case .notDetermined:
            Task { [weak self] in
                guard await AVCaptureDevice.requestAccess(for: .audio), self?.clock != nil else { return }
                self?.listen()
            }
        default:
            break
        }
    }

    private func listen() {
        guard engine == nil else { return }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { [weak self] buffer, _ in
            guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
            let count = Int(buffer.frameLength)
            var sum: Float = 0
            for index in 0..<count { sum += channel[index] * channel[index] }
            let level = Self.level(rms: (sum / Float(count)).squareRoot())
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.loudest = max(self.loudest, level)
                }
            }
        }
        do {
            try engine.start()
            self.engine = engine
        } catch {
            input.removeTap(onBus: 0)
        }
    }

    private func stopMicrophone() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
    }
}

/// A voice memo being recorded in Voice Memos, as the iPhone's own shows in the Dynamic Island: from
/// when it starts until it's done, its waveform and its time; opened, a button to stop it. Voice
/// Memos tells other apps nothing of it, so it's known by Voice Memos using the microphone, as a
/// call in another app is (see `CallAudio`), and told apart from paused by its own Resume button,
/// found by the name Voice Memos gives it in the Mac's language.
@MainActor
final class VoiceMemoWatch: ObservableObject {
    static let shared = VoiceMemoWatch()

    @Published private(set) var memo: VoiceMemo? {
        didSet { follow(memo) }
    }
    /// At the bench: made up.
    private var benching = false
    private var clock: Timer?
    private var asking = false

    static let bundle = "com.apple.VoiceMemos"
    /// What records for it, as Core Audio names them: the app, and its service.
    nonisolated static let recorders = ["com.apple.VoiceMemos", "com.apple.voicememod"]
    static let app = URL(fileURLWithPath: "/System/Applications/VoiceMemos.app")

    /// Looks once a second, while Voice Memos is open.
    func start() {
        guard clock == nil, ActivityBench.scene == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.look() }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        clock = timer
    }

    private static var enabled: Bool {
        let defaults = UserDefaults.standard
        return defaults.bool(forKey: Preferences.activityVoiceMemos) && defaults.bool(forKey: Preferences.notchEnabled)
    }

    private func look() {
        guard Self.enabled, let app = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundle).first else {
            if memo != nil { memo = nil }
            return
        }
        guard !asking else { return }
        asking = true
        // Asked away from the thread that draws the notch, as Core Audio's answers wait on macOS's
        // sound service.
        CallAudio.asking.async {
            let recording = CallAudio.bundlesOnMicrophone().contains { bundle in Self.recorders.contains { bundle.hasPrefix($0) } }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.asking = false
                    self.heard(recording: recording, app: app)
                }
            }
        }
    }

    private func heard(recording: Bool, app: NSRunningApplication) {
        let now = Date.now
        switch (recording, memo) {
        case (true, .recording?):
            break
        case (true, .paused(let length)?):
            memo = .recording(since: now - length)
        case (true, nil):
            memo = .recording(since: now)
        case (false, .recording(let since)?):
            // Paused, if its Resume button shows; otherwise it's done.
            memo = Self.button(Self.resume, in: app) != nil ? .paused(length: now.timeIntervalSince(since)) : nil
        case (false, .paused?):
            if Self.button(Self.resume, in: app) == nil { memo = nil }
        case (false, nil):
            break
        }
    }

    /// Voice Memos' own buttons' names, in the Mac's language.
    static var resume: String { SystemNotices.words("AX_RESUME", table: "Localizable", of: app) }
    static var done: String { SystemNotices.words("AX_DONE_BUTTON", table: "Localizable", of: app) }

    /// One of Voice Memos' buttons, by its name.
    static func button(_ name: String, in app: NSRunningApplication) -> AXUIElement? {
        guard AXIsProcessTrusted() else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.3)
        let windows = SystemNotices.value(element, kAXWindowsAttribute) as? [AXUIElement] ?? []
        for window in windows {
            let found = SystemNotices.findAll(in: window) { element in
                guard SystemNotices.value(element, kAXRoleAttribute) as? String == kAXButtonRole else { return false }
                return [kAXDescriptionAttribute, kAXTitleAttribute].contains { SystemNotices.value(element, $0) as? String == name }
            }
            if let button = found.first { return button }
        }
        return nil
    }

    /// Stops it, as Voice Memos' own Done button does, which keeps it.
    func stop() {
        if benching { return ActivityBench.shared.stopped(.voiceMemo) }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundle).first,
            let done = Self.button(Self.done, in: app)
        else { return }
        AXUIElementPerformAction(done, kAXPressAction as CFString)
    }

    /// A made-up one, at the bench, or none.
    func bench(_ memo: VoiceMemo?) {
        benching = true
        RecordingLevels.shared.madeUp = true
        self.memo = memo
    }

    /// The waveform listens while it records, holds while it's paused, and stops with it.
    private func follow(_ memo: VoiceMemo?) {
        RecordingLevels.shared.madeUp = benching
        switch memo {
        case .recording?: RecordingLevels.shared.start()
        case .paused?: RecordingLevels.shared.pause()
        case nil: RecordingLevels.shared.stop()
        }
    }
}

/// The screen being recorded, as the iPhone's own shows it in the Dynamic Island: its countdown, its
/// red dot while it records, a spinner while it's saved, then where it went. macOS's Screenshot
/// records it, from its toolbar, Control Center or QuickTime Player, and tells other apps nothing,
/// so it's known by its stop button in the menu bar, which shows for as long as it records; and
/// once it's stopped, by its file, as Spotlight finds it.
@MainActor
final class ScreenRecordingWatch: ObservableObject {
    static let shared = ScreenRecordingWatch()

    @Published private(set) var recording: ScreenRecording?
    /// The last one saved, which the notch opens.
    private(set) var saved: URL?
    /// At the bench: made up.
    private var benching = false
    private var clock: Timer?
    private var observers: [NSObjectProtocol] = []
    private var startedAt = Date.distantPast
    private var savingSince = Date.distantPast
    private var files: NSMetadataQuery?

    nonisolated static let capture = "com.apple.screencaptureui"
    /// Longest it waits for the file once stopped, before it lets it go unsaid.
    static let savingLimit: TimeInterval = 20

    /// Looks twice a second while Screenshot is open, as it is only while capturing.
    func start() {
        guard observers.isEmpty, ActivityBench.scene == nil else { return }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                    let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                    guard app?.bundleIdentifier == Self.capture else { return }
                    MainActor.assumeIsolated { self?.follow() }
                })
        }
        follow()
    }

    private static var enabled: Bool {
        let defaults = UserDefaults.standard
        return defaults.bool(forKey: Preferences.activityScreenRecording) && defaults.bool(forKey: Preferences.notchEnabled)
    }

    private var captureApp: NSRunningApplication? { NSRunningApplication.runningApplications(withBundleIdentifier: Self.capture).first }

    /// Looking while Screenshot is open, or a recording is being saved.
    private func follow() {
        let wanted = captureApp != nil || recording != nil
        if wanted, clock == nil {
            let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.look() }
            }
            timer.tolerance = 0.1
            RunLoop.main.add(timer, forMode: .common)
            clock = timer
            look()
        } else if !wanted {
            clock?.invalidate()
            clock = nil
        }
    }

    private func look() {
        guard Self.enabled else {
            recording = nil
            return follow()
        }
        let now = Date.now
        let item = Self.stopItem()
        switch (item.map(Self.words), recording) {
        case (let words?, let shown):
            // Waiting to start, it counts down the seconds left; recording, it's a stop button.
            if let seconds = Self.countdown(in: words) {
                if case .countdown(let from, _)? = shown {
                    recording = .countdown(from: max(from, seconds), until: now + Double(seconds))
                } else {
                    recording = .countdown(from: seconds, until: now + Double(seconds))
                }
            } else if case .recording? = shown {
                break
            } else {
                startedAt = now
                recording = .recording(since: now)
            }
        case (nil, .recording(let since)?):
            // Stopped: saved once its file shows up.
            savingSince = now
            recording = .saving(length: now.timeIntervalSince(since))
            findFile()
        case (nil, .saving?):
            if now.timeIntervalSince(savingSince) > Self.savingLimit { done(nil) }
        case (nil, .saved?):
            break
        case (nil, .countdown?):
            // Cancelled before it started.
            recording = nil
        case (nil, nil):
            break
        }
        follow()
    }

    /// The menu bar's button that stops it, while there's one: in Screenshot's own menu bar items,
    /// or among the menu bar's, by its identifier.
    static func stopItem() -> AXUIElement? {
        guard AXIsProcessTrusted() else { return nil }
        for bundle in [capture, "com.apple.MenuBarAgent"] {
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first else { continue }
            let element = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(element, 0.1)
            guard let bar = SystemNotices.value(element, kAXExtrasMenuBarAttribute) else { continue }
            let items = SystemNotices.findAll(in: bar as! AXUIElement) { SystemNotices.value($0, kAXRoleAttribute) as? String == kAXMenuBarItemRole }
            if bundle == capture, let first = items.first { return first }
            if let item = items.first(where: { isRecordingItem(SystemNotices.value($0, kAXIdentifierAttribute) as? String) }) { return item }
        }
        return nil
    }

    /// A menu bar item that's screen recording's, by its identifier.
    nonisolated static func isRecordingItem(_ identifier: String?) -> Bool {
        guard let identifier = identifier?.lowercased() else { return false }
        return ["screencapture", "screenrecording", "screen-recording", "screenshot"].contains { identifier.contains($0) }
    }

    /// What a menu bar item says.
    static func words(_ item: AXUIElement) -> String {
        [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute].compactMap { SystemNotices.value(item, $0) as? String }.joined(separator: " ")
    }

    /// The seconds left before it starts, as Screenshot counts them down: "5s", or a number alone.
    nonisolated static func countdown(in words: String) -> Int? {
        let trimmed = words.trimmingCharacters(in: .whitespaces)
        guard let match = trimmed.firstMatch(of: #/^(\d{1,2})\s?s?$/#) else { return nil }
        return Int(match.1)
    }

    /// Looks for the file it's saved as, as Spotlight finds a new screen recording.
    private func findFile() {
        files?.stop()
        let query = NSMetadataQuery()
        query.predicate = NSPredicate(format: "kMDItemIsScreenRecording == 1 && kMDItemContentCreationDate >= %@", startedAt.addingTimeInterval(-2) as NSDate)
        query.searchScopes = [NSMetadataQueryUserHomeScope]
        NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidUpdate, object: query, queue: .main) { [weak self] note in
            let added = note.userInfo?[NSMetadataQueryUpdateAddedItemsKey] as? [NSMetadataItem] ?? []
            let path = added.compactMap { $0.value(forAttribute: NSMetadataItemPathKey) as? String }.first
            MainActor.assumeIsolated {
                guard let path, case .saving? = self?.recording else { return }
                self?.done(URL(fileURLWithPath: path))
            }
        }
        query.start()
        files = query
    }

    /// Saved, it says where, its square growing into its first picture, for a moment; or, never
    /// found, it just goes.
    private func done(_ file: URL?) {
        files?.stop()
        files = nil
        guard case .saving(let length)? = recording else { return }
        guard let file else {
            recording = nil
            return follow()
        }
        saved = file
        let folder = FileManager.default.displayName(atPath: file.deletingLastPathComponent().path)
        Task {
            let preview = await Self.firstPicture(of: file)
            guard case .saving? = self.recording else { return }
            self.recording = .saved(length: length, folder: folder, preview: preview)
            try? await Task.sleep(for: .seconds(Self.savedFor))
            if case .saved? = self.recording { self.recording = nil }
            self.follow()
        }
    }

    /// How long it says where it was saved.
    static let savedFor: TimeInterval = 4

    /// Its first picture, as its thumbnail.
    static func firstPicture(of file: URL) async -> NSImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: file))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 240, height: 240)
        guard let picture = try? await generator.image(at: .zero).image else { return nil }
        return NSImage(cgImage: picture, size: .zero)
    }

    /// Stops it, as macOS's own button in the menu bar does.
    func stop() {
        if benching { return ActivityBench.shared.stopped(.screenRecording) }
        guard let item = Self.stopItem() else { return }
        AXUIElementPerformAction(item, kAXPressAction as CFString)
    }

    /// Opens the one just saved, in the app that opens it.
    func openSaved() {
        guard let saved else { return }
        NSWorkspace.shared.open(saved)
    }

    /// A made-up one, at the bench, or none.
    func bench(_ recording: ScreenRecording?) {
        benching = true
        self.recording = recording
    }

}
