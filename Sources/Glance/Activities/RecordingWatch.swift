//
//  RecordingWatch.swift
//  Glance
//
//  Created by Gaty on 07/11/2026.
//

import AVFoundation
import AppKit

/// Permission checks are separate from user-requested authorization so review fixtures never
/// need a system prompt or access to another app's interface.
struct RecordingAccess {
    var isGranted: () -> Bool
    var request: () -> Bool

    static let system = RecordingAccess(
        isGranted: { AXIsProcessTrusted() },
        request: { AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary) }
    )
}

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

    /// As many as the open waveform shows, and one more on its way out.
    static let kept = RecordingLook.openRecorded + 1

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

    @Published private(set) var canControl: Bool
    private let access: RecordingAccess
    private let finishRecording: () -> Void

    init(access: RecordingAccess = .system, finishRecording: (() -> Void)? = nil) {
        self.access = access
        canControl = access.isGranted()
        self.finishRecording =
            finishRecording ?? {
                guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundle).first,
                    let done = Self.button(Self.done, in: app)
                else { return }
                AXUIElementPerformAction(done, kAXPressAction as CFString)
            }
    }

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
        canControl = access.isGranted()
        // Its buttons are only looked for while one is going and the microphone has stopped.
        let looks = canControl && !recording && memo != nil
        let resume = looks && Self.button(Self.resume, in: app) != nil
        let done = looks && !resume && Self.button(Self.done, in: app) != nil
        let next = Self.next(after: memo, recording: recording, resume: resume, done: done, at: .now, controlsAvailable: canControl)
        if !recording && !canControl {
            // Losing access cannot tell us whether it paused or finished. Keep the last known
            // state, but don't keep listening to the microphone when Voice Memos isn't using it.
            RecordingLevels.shared.pause()
        }
        if next != memo {
            memo = next
        } else if recording {
            follow(memo)
        }
    }

    /// The voice memo now, from whether Voice Memos is using the microphone and which of its
    /// buttons show: paused while its Resume button does, and going on, paused or about to record
    /// again, for as long as its Done button does. Resumed, Voice Memos swaps Resume for Pause a
    /// moment before the microphone comes back, and that's not the end of it.
    nonisolated static func next(after memo: VoiceMemo?, recording: Bool, resume: Bool, done: Bool, at now: Date, controlsAvailable: Bool = true) -> VoiceMemo? {
        if !recording && !controlsAvailable { return memo }
        switch (recording, memo) {
        case (true, .recording?):
            return memo
        case (true, .paused(let length)?):
            return .recording(since: now - length)
        case (true, nil):
            return .recording(since: now)
        case (false, .recording(let since)?):
            if resume { return .paused(length: now.timeIntervalSince(since)) }
            return done ? memo : nil
        case (false, .paused?):
            return resume || done ? memo : nil
        case (false, nil):
            return nil
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
        canControl = access.isGranted() || access.request()
        guard canControl else { return }
        finishRecording()
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
    @Published private(set) var canControl: Bool
    enum SavedFileState: Equatable {
        case available, unavailable, openingFailed
    }
    @Published private(set) var savedFileState = SavedFileState.unavailable
    var canOpenSaved: Bool { savedFileState != .unavailable }
    /// The last one saved, which the notch opens.
    private(set) var saved: URL?
    /// At the bench: made up.
    private var benching = false
    private var clock: Timer?
    private var looking = false
    private var lastLook = Date.distantPast
    private var startedAt = Date.distantPast
    private var savingSince = Date.distantPast
    private var files: NSMetadataQuery?
    private let readIndicator: @Sendable () -> String?
    private let isEnabled: @MainActor () -> Bool
    private let captureIsRunning: @MainActor () -> Bool
    private let access: RecordingAccess
    private let stopRecording: () -> Void
    private let findSavedFile: (() -> Void)?
    private let fileIsAvailable: (URL) -> Bool
    private let openFile: (URL) -> Bool
    private let waitForSavedDismissal: @MainActor () async throws -> Void
    private var savedDismissal: Task<Void, Never>?
    private var savedPresentationID = UUID()

    init(
        readIndicator: (@Sendable () -> String?)? = nil,
        isEnabled: (@MainActor () -> Bool)? = nil,
        captureIsRunning: (@MainActor () -> Bool)? = nil,
        access: RecordingAccess = .system,
        stopRecording: (() -> Void)? = nil,
        findSavedFile: (() -> Void)? = nil,
        fileIsAvailable: ((URL) -> Bool)? = nil,
        openFile: ((URL) -> Bool)? = nil,
        waitForSavedDismissal: (@MainActor () async throws -> Void)? = nil
    ) {
        self.readIndicator = readIndicator ?? { Self.stopItem().map(Self.words) }
        self.isEnabled = isEnabled ?? { Self.enabled }
        self.captureIsRunning = captureIsRunning ?? { !NSRunningApplication.runningApplications(withBundleIdentifier: Self.capture).isEmpty }
        self.access = access
        canControl = access.isGranted()
        self.stopRecording = stopRecording ?? { Self.pressStop() }
        self.findSavedFile = findSavedFile
        self.fileIsAvailable = fileIsAvailable ?? Self.savedFileIsAvailable
        self.openFile = openFile ?? { NSWorkspace.shared.open($0) }
        let savedDelay = Self.savedFor
        self.waitForSavedDismissal = waitForSavedDismissal ?? { try await Task.sleep(for: .seconds(savedDelay)) }
    }

    deinit {
        clock?.invalidate()
        savedDismissal?.cancel()
    }

    nonisolated static let capture = "com.apple.screencaptureui"
    /// Longest it waits for the file once stopped, before it lets it go unsaid.
    static let savingLimit: TimeInterval = 20

    /// Background capture services do not always announce a launch. Keep a light idle check,
    /// and follow active recordings twice a second, without waiting for a running-app change.
    func start() {
        guard clock == nil, ActivityBench.scene == nil else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        clock = timer
        refresh()
    }

    private static var enabled: Bool {
        let defaults = UserDefaults.standard
        return defaults.bool(forKey: Preferences.activityScreenRecording) && defaults.bool(forKey: Preferences.notchEnabled)
    }

    func refresh() {
        guard isEnabled() else {
            recording = nil
            return
        }
        guard !benching, !looking else { return }
        if case .saved? = recording { refreshSavedAvailability() }
        canControl = access.isGranted()
        // An unavailable AX tree isn't evidence that a recording stopped. Keep the last known
        // state and explain the permission in its controls until observations are available again.
        guard canControl else { return }
        let now = Date.now
        guard captureIsRunning() || recording != nil || now.timeIntervalSince(lastLook) >= 2 else { return }
        lastLook = now
        looking = true
        let read = readIndicator
        Task { [weak self] in
            let words = await Task.detached { read() }.value
            guard let self else { return }
            self.looking = false
            guard !self.benching, self.isEnabled() else { return }
            self.canControl = self.access.isGranted()
            guard self.canControl else { return }
            self.update(words: words, at: .now)
        }
    }

    private func update(words: String?, at now: Date) {
        switch (words, recording) {
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
            if let findSavedFile { findSavedFile() } else { findFile() }
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
    }

    /// Screenshot's legacy stop item, or its Live Activity in either menu-bar tree.
    nonisolated static func stopItem() -> AXUIElement? {
        guard AXIsProcessTrusted() else { return nil }
        for bundle in [capture, "com.apple.MenuBarAgent"] {
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first else { continue }
            let element = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(element, 0.1)
            let roots = indicatorRoots(of: element)
            if let item = first(
                in: roots,
                matching: { item in
                    isRecordingControl(
                        role: SystemNotices.value(item, kAXRoleAttribute) as? String,
                        subrole: SystemNotices.value(item, kAXSubroleAttribute) as? String,
                        identifier: SystemNotices.value(item, kAXIdentifierAttribute) as? String
                    )
                })
            {
                return item
            }
            // The older stop button has no identifier, and belongs to Screenshot alone.
            if bundle == capture,
                let bar = SystemNotices.value(element, kAXExtrasMenuBarAttribute), CFGetTypeID(bar) == AXUIElementGetTypeID(),
                let item = first(in: [bar as! AXUIElement], matching: { SystemNotices.value($0, kAXRoleAttribute) as? String == kAXMenuBarItemRole })
            {
                return item
            }
        }
        return nil
    }

    nonisolated static func isRecordingControl(role: String?, subrole: String?, identifier: String?) -> Bool {
        (role == kAXMenuBarItemRole || subrole == liveActivity) && isRecordingItem(identifier)
    }

    nonisolated private static func indicatorRoots(of app: AXUIElement) -> [AXUIElement] {
        var roots = SystemNotices.value(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
        if let bar = SystemNotices.value(app, kAXExtrasMenuBarAttribute), CFGetTypeID(bar) == AXUIElementGetTypeID() {
            roots.append(bar as! AXUIElement)
        }
        return roots
    }

    /// A first match with bounded work, including trees that repeat the same element.
    nonisolated private static func first(in roots: [AXUIElement], matching match: (AXUIElement) -> Bool) -> AXUIElement? {
        var pending = roots.map { ($0, 0) }, seen = Set<AXUIElement>()
        var next = 0
        let deadline = Date.now.addingTimeInterval(0.5)
        while next < pending.count, seen.count < 750, Date.now < deadline {
            let (element, depth) = pending[next]
            next += 1
            guard seen.insert(element).inserted else { continue }
            if match(element) { return element }
            if depth < 12 {
                pending += (SystemNotices.value(element, kAXChildrenAttribute) as? [AXUIElement] ?? []).map { ($0, depth + 1) }
            }
        }
        return nil
    }

    /// A menu bar item that's screen recording's, by its identifier.
    nonisolated static func isRecordingItem(_ identifier: String?) -> Bool {
        guard let identifier = identifier?.lowercased() else { return false }
        return ["screencapture", "screenrecording", "screen-recording", "screenshot"].contains { identifier.contains($0) }
    }

    /// What a menu bar item says.
    nonisolated static func words(_ item: AXUIElement) -> String {
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
            return
        }
        let folder = FileManager.default.displayName(atPath: file.deletingLastPathComponent().path)
        Task {
            let preview = await Self.firstPicture(of: file)
            guard case .saving? = self.recording else { return }
            self.presentSaved(file: file, length: length, folder: folder, preview: preview)
        }
    }

    /// Accepts the saved result separately from finding the file and decoding its thumbnail, so
    /// availability and recovery can be checked with a fake file backend.
    func presentSaved(file: URL, length: TimeInterval, folder: String, preview: NSImage?) {
        saved = file
        savedFileState = fileIsAvailable(file) ? .available : .unavailable
        recording = .saved(length: length, folder: folder, preview: preview)
        restartSavedDismissal()
    }

    private static func savedFileIsAvailable(_ file: URL) -> Bool {
        guard file.isFileURL else { return false }
        var directory = ObjCBool(false)
        return FileManager.default.fileExists(atPath: file.path, isDirectory: &directory)
            && !directory.boolValue && FileManager.default.isReadableFile(atPath: file.path)
    }

    func refreshSavedAvailability() {
        guard !benching else { return }
        guard let saved, fileIsAvailable(saved) else {
            showSavedError(.unavailable)
            return
        }
        if savedFileState == .unavailable { savedFileState = .available }
    }

    /// A newly visible error gets its own reading/retry time. Repeated availability polls must
    /// not keep extending it, and an older task must never dismiss a later saved result.
    private func showSavedError(_ state: SavedFileState) {
        guard savedFileState != state else { return }
        savedFileState = state
        if case .saved? = recording { restartSavedDismissal() }
    }

    private func restartSavedDismissal() {
        savedDismissal?.cancel()
        let identity = UUID()
        savedPresentationID = identity
        let wait = waitForSavedDismissal
        savedDismissal = Task { @MainActor [weak self] in
            do { try await wait() } catch { return }
            guard !Task.isCancelled, let self, self.savedPresentationID == identity,
                !self.benching, case .saved? = self.recording
            else { return }
            self.savedDismissal = nil
            self.recording = nil
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

    /// Stops it, as macOS's own button in the menu bar does. Where macOS shows the recording as a
    /// Live Activity in the menu bar, as macOS 27.3 does, Screenshot has no button of its own there,
    /// and pressing the Live Activity only opens it: its own Stop Recording button, in what opens,
    /// is pressed as soon as it shows.
    func stop() {
        if benching { return ActivityBench.shared.stopped(.screenRecording) }
        canControl = access.isGranted() || access.request()
        guard canControl else { return }
        stopRecording()
    }

    private static func pressStop() {
        if let button = Self.openedStopButton() {
            AXUIElementPerformAction(button, kAXPressAction as CFString)
            return
        }
        guard let item = Self.stopItem() else { return }
        AXUIElementPerformAction(item, kAXPressAction as CFString)
        guard SystemNotices.value(item, kAXSubroleAttribute) as? String == Self.liveActivity else { return }
        Task {
            for _ in 0..<30 {
                if let button = Self.openedStopButton() {
                    AXUIElementPerformAction(button, kAXPressAction as CFString)
                    return
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    nonisolated static let liveActivity = "AXLiveActivity"

    /// The recording's Live Activity, opened under the menu bar: its stop button, while it shows.
    static func openedStopButton() -> AXUIElement? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.MenuBarAgent").first else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.1)
        return first(in: indicatorRoots(of: element)) {
            SystemNotices.value($0, kAXRoleAttribute) as? String == kAXButtonRole
                && isOpenedStopButton(SystemNotices.value($0, kAXIdentifierAttribute) as? String)
        }
    }

    /// The stop button in a screen recording's opened Live Activity, by its identifier, which is
    /// the same in every language: "ScreenRecording.BannerView" on macOS 27.3.
    nonisolated static func isOpenedStopButton(_ identifier: String?) -> Bool {
        identifier?.hasPrefix("ScreenRecording.") == true
    }

    /// Opens the one just saved, in the app that opens it.
    @discardableResult
    func openSaved() -> Bool {
        // The bench is a visual simulation, with no file to validate or open.
        if benching { return recording?.isSaved == true && canOpenSaved }
        refreshSavedAvailability()
        guard canOpenSaved, let saved else { return false }
        if openFile(saved) {
            savedFileState = .available
            return true
        }
        showSavedError(fileIsAvailable(saved) ? .openingFailed : .unavailable)
        return false
    }

    /// A made-up one, at the bench, or none.
    func bench(_ recording: ScreenRecording?) {
        benching = true
        savedDismissal?.cancel()
        savedDismissal = nil
        saved = nil
        savedFileState = recording?.isSaved == true ? .available : .unavailable
        self.recording = recording
    }

}
