//
//  MusicRecognitionActivity.swift
//  Glance
//
//  Created by Gaty on 14/11/2026.
//

import AVFoundation
import AppKit
import ShazamKit

/// A recognition session explicitly started in Glance. This does not observe Control Center's
/// recognition session or write songs to the person's Shazam library.
@MainActor
final class MusicRecognitionActivity: ObservableObject {
    static let shared = MusicRecognitionActivity(isEnabled: {
        (UserDefaults.standard.object(forKey: Preferences.activityRecognition) as? Bool ?? true)
            && (UserDefaults.standard.object(forKey: Preferences.notchEnabled) as? Bool ?? true)
    })

    enum Permission: Equatable {
        case notDetermined, authorized, denied, restricted
    }

    struct Song: Equatable, Sendable {
        let title: String
        let artist: String?
        let artworkURL: URL?
        let musicURL: URL?
        let webURL: URL?

        init(title: String?, artist: String?, artworkURL: URL? = nil, musicURL: URL? = nil, webURL: URL? = nil) {
            self.title = Self.nonempty(title) ?? String(localized: "Song Found")
            self.artist = Self.nonempty(artist)
            self.artworkURL = Self.webLink(artworkURL)
            self.musicURL = Self.webLink(musicURL)
            self.webURL = Self.webLink(webURL)
        }

        private static func nonempty(_ value: String?) -> String? {
            guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
            return trimmed
        }

        private static func webLink(_ url: URL?) -> URL? {
            guard let url, url.scheme?.lowercased() == "https", url.host != nil else { return nil }
            return url
        }
    }

    enum Failure: Equatable, Sendable {
        case connection, recognition

        var title: String {
            switch self {
            case .connection: String(localized: "Connection Problem")
            case .recognition: String(localized: "Couldn’t Recognize Music")
            }
        }

        var message: String {
            switch self {
            case .connection: String(localized: "Check your internet connection, then try again.")
            case .recognition: String(localized: "Music recognition is unavailable right now. Try again.")
            }
        }
    }

    enum Result: Equatable, Sendable {
        case match(Song), noMatch, failure(Failure)
    }

    enum State: Equatable {
        case idle, requestingPermission, recognizing, match(Song), noMatch, denied, restricted, failure(Failure), cancelled

        var isWorking: Bool {
            self == .requestingPermission || self == .recognizing
        }

        var title: String {
            switch self {
            case .idle: String(localized: "Recognize Music")
            case .requestingPermission: String(localized: "Microphone Access")
            case .recognizing: String(localized: "Recognizing Music…")
            case .match(let song): song.title
            case .noMatch: String(localized: "No Song Found")
            case .denied: String(localized: "Microphone Access Is Off")
            case .restricted: String(localized: "Microphone Access Is Restricted")
            case .failure(let failure): failure.title
            case .cancelled: String(localized: "Recognition Cancelled")
            }
        }
    }

    /// A fresh session for each request prevents a cancelled session's delayed result or cancel
    /// command from affecting a later request. Test sessions must supply their own operations.
    @MainActor
    struct Session {
        var result: @MainActor () async -> Result
        var cancel: @MainActor () -> Void
    }

    @MainActor
    struct Backend {
        var permission: () -> Permission
        var requestPermission: () async -> Bool
        var makeSession: () -> Session
        var openURL: (URL) -> Bool
        var openMicrophoneSettings: () -> Bool

        static var native: Backend {
            Backend(
                permission: Native.permission,
                requestPermission: { await AVCaptureDevice.requestAccess(for: .audio) },
                makeSession: Native.session,
                openURL: { NSWorkspace.shared.open($0) },
                openMicrophoneSettings: {
                    guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else { return false }
                    return NSWorkspace.shared.open(url)
                })
        }
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var actionFailure: String?
    @Published private(set) var identity: UUID?

    var isPresented: Bool { state != .idle }
    var isWorking: Bool { state.isWorking }

    private let backend: Backend
    private let isEnabled: () -> Bool
    private let live: Bool
    private var benched = false
    private var settingsObserver: NSObjectProtocol?
    private var shutdownObserver: NSObjectProtocol?
    private var task: Task<Void, Never>?
    private var session: Session?
    private var request: UUID?

    init(backend: Backend? = nil, isEnabled: @escaping () -> Bool = { true }) {
        self.backend = backend ?? .native
        self.live = backend == nil
        self.isEnabled = isEnabled
    }

    /// Observe only lifecycle preferences here. Starting Glance never starts recognition.
    func start() {
        guard settingsObserver == nil else { return }
        settingsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.settingsChanged() }
        }
        shutdownObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }
    }

    func settingsChanged() {
        if !benched, !isEnabled() { dismiss() }
    }

    /// Call only in response to an explicit Recognize Music or Try Again action. Constructing the
    /// model, enabling the activity, opening its view and expanding the notch never start recording.
    func recognize() {
        guard !isWorking else { return }
        guard benched || isEnabled(), benched || !live || ActivityBench.scene == nil else { return }
        identity = UUID()
        actionFailure = nil
        if benched {
            state = .recognizing
            return
        }
        switch backend.permission() {
        case .denied:
            state = .denied
            return
        case .restricted:
            state = .restricted
            return
        case .authorized:
            state = .recognizing
        case .notDetermined:
            state = .requestingPermission
        }

        let token = UUID()
        request = token
        task = Task { @MainActor [weak self] in
            guard let self, request == token, !Task.isCancelled else { return }
            guard isEnabled() else {
                dismiss()
                return
            }
            if state == .requestingPermission {
                let allowed = await backend.requestPermission()
                guard request == token, !Task.isCancelled else { return }
                guard isEnabled() else {
                    dismiss()
                    return
                }
                guard allowed else {
                    state = backend.permission() == .restricted ? .restricted : .denied
                    finish(token)
                    return
                }
            }
            // Recheck after the async permission prompt and before creating any recording session.
            guard backend.permission() == .authorized else {
                state = backend.permission() == .restricted ? .restricted : .denied
                finish(token)
                return
            }
            let current = backend.makeSession()
            session = current
            state = .recognizing
            let result = await current.result()
            guard request == token, !Task.isCancelled else { return }
            // Even a framework failure must leave the microphone off. Stop before publishing a
            // terminal state so the visible result never implies recording has finished early.
            current.cancel()
            session = nil
            guard isEnabled() else {
                dismiss()
                return
            }
            switch backend.permission() {
            case .denied: state = .denied
            case .restricted: state = .restricted
            default:
                switch result {
                case .match(let song): state = .match(song)
                case .noMatch: state = .noMatch
                case .failure(let failure): state = .failure(failure)
                }
            }
            finish(token)
        }
    }

    func cancel() {
        guard isWorking else { return }
        endRequest()
        state = .cancelled
        actionFailure = nil
    }

    /// Used for Done, disabling the activity or app shutdown. Collapsing the notch should leave
    /// the request running and keep Cancel available when the activity is expanded again.
    func dismiss() {
        endRequest()
        state = .idle
        identity = nil
        actionFailure = nil
        if benched { ActivityBench.shared.stopped(.recognition) }
    }

    func openSong() {
        guard case .match(let song) = state, let url = song.musicURL ?? song.webURL else { return }
        guard !benched, !live || ActivityBench.scene == nil else {
            actionFailure = nil
            return
        }
        actionFailure = backend.openURL(url) ? nil : String(localized: "The song couldn’t be opened. Try again.")
    }

    func openMicrophoneSettings() {
        guard state == .denied else { return }
        guard !benched, !live || ActivityBench.scene == nil else {
            actionFailure = nil
            return
        }
        actionFailure = backend.openMicrophoneSettings() ? nil : String(localized: "Open System Settings, then Privacy & Security → Microphone.")
    }

    /// Inert source-build presentation. Neither its buttons nor rendering reach the microphone,
    /// the recognition service, or another app.
    func bench(_ state: State, actionFailure: String? = nil) {
        endRequest()
        benched = true
        identity = state == .idle ? nil : UUID()
        self.state = state
        self.actionFailure = actionFailure
    }

    private func endRequest() {
        request = nil
        task?.cancel()
        task = nil
        session?.cancel()
        session = nil
    }

    private func finish(_ token: UUID) {
        guard request == token else { return }
        request = nil
        task = nil
    }

    /// Shazam's general match-attempt error also covers service/configuration failures, so it
    /// must not be labeled "No Internet" without an actual underlying networking error.
    static func failure(for error: Error) -> Failure {
        var current = error as NSError
        for _ in 0..<8 {
            if current.domain == NSURLErrorDomain,
                [
                    NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorCannotConnectToHost,
                    NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed, NSURLErrorTimedOut,
                ].contains(current.code)
            {
                return .connection
            }
            guard let underlying = current.userInfo[NSUnderlyingErrorKey] as? NSError else { break }
            current = underlying
        }
        return .recognition
    }

    @MainActor
    private enum Native {
        static func permission() -> Permission {
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .notDetermined: .notDetermined
            case .authorized: .authorized
            case .denied: .denied
            case .restricted: .restricted
            @unknown default: .restricted
            }
        }

        static func session() -> Session {
            let managed = SHManagedSession()
            return Session(
                result: {
                    // Do not call prepare(): it starts prerecording. Only this explicit request
                    // starts SHManagedSession, which manages its own microphone capture.
                    guard !Task.isCancelled else { return .failure(.recognition) }
                    return await withTaskCancellationHandler {
                        switch await managed.result() {
                        case .match(let match):
                            guard let item = match.mediaItems.first else { return .failure(.recognition) }
                            return .match(
                                Song(
                                    title: item.title, artist: item.artist, artworkURL: item.artworkURL,
                                    musicURL: item.appleMusicURL, webURL: item.webURL))
                        case .noMatch: return .noMatch
                        case .error(let error, _): return .failure(MusicRecognitionActivity.failure(for: error))
                        }
                    } onCancel: {
                        managed.cancel()
                    }
                }, cancel: { managed.cancel() })
        }
    }
}
