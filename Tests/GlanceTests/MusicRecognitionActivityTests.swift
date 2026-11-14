import Foundation
import Testing

@testable import Glance

@MainActor
@Suite("User-started music recognition")
struct MusicRecognitionActivityTests {
    private let song = MusicRecognitionActivity.Song(
        title: "Song", artist: "Artist", musicURL: URL(string: "https://music.apple.com/song/example"))

    @Test("Constructing and dismissing the activity never requests access or creates a session")
    func inertUntilExplicitStart() {
        let source = Source()
        let activity = MusicRecognitionActivity(backend: source.backend)
        #expect(activity.state == .idle)
        #expect(!activity.isPresented)
        activity.cancel()
        activity.dismiss()
        #expect(source.permissionRequests == 0)
        #expect(source.sessions.isEmpty)
    }

    @Test("Dismissal before the recognition task runs never creates a session")
    func immediateDismissal() async throws {
        let source = Source()
        let activity = MusicRecognitionActivity(backend: source.backend)
        activity.recognize()
        activity.dismiss()
        try await Task.sleep(for: .milliseconds(20))
        #expect(source.sessions.isEmpty)
        #expect(source.permissionRequests == 0)
        #expect(activity.state == .idle)
    }

    @Test("Denied and restricted microphone access do not create a recognition session")
    func unavailablePermission() {
        let source = Source()
        let activity = MusicRecognitionActivity(backend: source.backend)
        source.permission = .denied
        activity.recognize()
        #expect(activity.state == .denied)
        #expect(source.permissionRequests == 0)
        #expect(source.sessions.isEmpty)
        activity.openMicrophoneSettings()
        #expect(source.openedSettings == 1)
        source.permission = .restricted
        activity.recognize()
        #expect(activity.state == .restricted)
        activity.openMicrophoneSettings()
        #expect(source.openedSettings == 1)
        #expect(source.sessions.isEmpty)
    }

    @Test("Cancelling a permission prompt prevents recording even if access is later granted")
    func cancelledPermissionPrompt() async throws {
        let source = Source()
        source.permission = .notDetermined
        let activity = MusicRecognitionActivity(backend: source.backend)
        activity.recognize()
        activity.recognize()
        try await settle { source.permissionReply != nil }
        #expect(activity.state == .requestingPermission)
        #expect(source.permissionRequests == 1)
        #expect(source.sessions.isEmpty)
        activity.cancel()
        source.replyToPermission(true)
        try await settle { source.permissionReturns == 1 }
        #expect(activity.state == .cancelled)
        #expect(source.sessions.isEmpty)
        activity.dismiss()
    }

    @Test("Permission grant starts one real backend session and a result stops it before presentation")
    func permissionAndMatch() async throws {
        let source = Source()
        source.permission = .notDetermined
        let activity = MusicRecognitionActivity(backend: source.backend)
        activity.recognize()
        try await settle { source.permissionReply != nil }
        source.replyToPermission(true)
        try await settle { source.sessions.first?.reply != nil }
        let session = try #require(source.sessions.first)
        #expect(activity.state == .recognizing)
        activity.recognize()
        #expect(source.sessions.count == 1)
        session.complete(.match(song))
        try await settle { activity.state == .match(song) }
        #expect(session.cancelCount == 1)
        #expect(!activity.isWorking)
        activity.dismiss()
        #expect(session.cancelCount == 1)
        #expect(activity.state == .idle)
    }

    @Test("A denied permission response never starts capture")
    func permissionRejected() async throws {
        let source = Source()
        source.permission = .notDetermined
        let activity = MusicRecognitionActivity(backend: source.backend)
        activity.recognize()
        try await settle { source.permissionReply != nil }
        source.replyToPermission(false)
        try await settle { activity.state == .denied }
        #expect(source.sessions.isEmpty)
        activity.dismiss()
    }

    @Test("Late cancelled results cannot replace a newer session or a dismissed activity")
    func supersededAndDismissedResults() async throws {
        let source = Source()
        let activity = MusicRecognitionActivity(backend: source.backend)
        activity.recognize()
        try await settle { source.sessions.first?.reply != nil }
        let first = try #require(source.sessions.first)
        activity.cancel()
        #expect(first.cancelCount == 1)
        activity.recognize()
        try await settle { source.sessions.count == 2 && source.sessions[1].reply != nil }
        let second = source.sessions[1]
        first.complete(.match(song))
        try await settle { first.resultReturns == 1 }
        #expect(activity.state == .recognizing)
        #expect(second.cancelCount == 0)
        activity.dismiss()
        #expect(second.cancelCount == 1)
        second.complete(.noMatch)
        try await settle { second.resultReturns == 1 }
        #expect(activity.state == .idle)
    }

    @Test("No match and service failure remain distinct, retryable results")
    func noMatchAndFailure() async throws {
        let source = Source()
        let activity = MusicRecognitionActivity(backend: source.backend)
        activity.recognize()
        try await settle { source.sessions.first?.reply != nil }
        source.sessions[0].complete(.noMatch)
        try await settle { activity.state == .noMatch }
        #expect(source.sessions[0].cancelCount == 1)
        activity.recognize()
        try await settle { source.sessions.count == 2 && source.sessions[1].reply != nil }
        source.sessions[1].complete(.failure(.recognition))
        try await settle { activity.state == .failure(.recognition) }
        #expect(source.sessions[1].cancelCount == 1)
        activity.dismiss()
    }

    @Test("Permission revoked during recognition is shown as denied instead of a successful match")
    func permissionRevoked() async throws {
        let source = Source()
        let activity = MusicRecognitionActivity(backend: source.backend)
        activity.recognize()
        try await settle { source.sessions.first?.reply != nil }
        source.permission = .denied
        source.sessions[0].complete(.match(song))
        try await settle { activity.state == .denied }
        #expect(source.sessions[0].cancelCount == 1)
        activity.dismiss()
    }

    @Test("Opening a returned song handles failure without discarding the match")
    func openSongFailure() async throws {
        let source = Source()
        let activity = MusicRecognitionActivity(backend: source.backend)
        activity.recognize()
        try await settle { source.sessions.first?.reply != nil }
        source.sessions[0].complete(.match(song))
        try await settle { activity.state == .match(song) }
        source.openSucceeds = false
        activity.openSong()
        #expect(source.openedURLs == [song.musicURL!])
        #expect(activity.actionFailure != nil)
        #expect(activity.state == .match(song))
        source.openSucceeds = true
        activity.openSong()
        #expect(activity.actionFailure == nil)
        activity.dismiss()
        activity.openSong()
        #expect(source.openedURLs.count == 2)
    }

    @Test("Only actual URL connection errors are called connection failures")
    func errorClassification() {
        #expect(MusicRecognitionActivity.failure(for: NSError(domain: "com.apple.ShazamKit", code: 202)) == .recognition)
        #expect(MusicRecognitionActivity.failure(for: URLError(.cancelled)) == .recognition)
        let underlying = NSError(domain: "com.apple.ShazamKit", code: 202, userInfo: [NSUnderlyingErrorKey: URLError(.notConnectedToInternet)])
        #expect(MusicRecognitionActivity.failure(for: underlying) == .connection)
    }

    @Test("Missing match metadata stays optional and non-web actions are discarded")
    func optionalMetadata() {
        let partial = MusicRecognitionActivity.Song(
            title: "  ", artist: "\n", artworkURL: URL(string: "file:///tmp/artwork.png"), musicURL: URL(string: "javascript:example"))
        #expect(!partial.title.isEmpty)
        #expect(partial.artist == nil)
        #expect(partial.artworkURL == nil)
        #expect(partial.musicURL == nil)
        #expect(partial.webURL == nil)
    }

    private enum WaitError: Error { case timeout }

    @Test("Disabling recognition cancels the owned session and prevents another microphone request")
    func preferenceStopsSession() async throws {
        let source = Source()
        var enabled = true
        let activity = MusicRecognitionActivity(backend: source.backend, isEnabled: { enabled })
        activity.recognize()
        try await settle { source.sessions.first?.reply != nil }
        let session = try #require(source.sessions.first)
        enabled = false
        activity.settingsChanged()
        #expect(activity.state == .idle)
        #expect(activity.identity == nil)
        #expect(session.cancelCount == 1)
        activity.recognize()
        #expect(source.sessions.count == 1)
        session.complete(.match(song))
        try await settle { session.resultReturns == 1 }
        #expect(activity.state == .idle)
    }

    @Test("Preview buttons never access the microphone, service, settings or another application")
    func benchIsIsolated() {
        let source = Source()
        let activity = MusicRecognitionActivity(backend: source.backend)
        activity.bench(.match(song))
        activity.openSong()
        activity.bench(.denied)
        activity.openMicrophoneSettings()
        activity.recognize()
        #expect(activity.state == .recognizing)
        activity.cancel()
        #expect(activity.state == .cancelled)
        activity.dismiss()
        #expect(activity.state == .idle)
        #expect(source.permissionRequests == 0)
        #expect(source.sessions.isEmpty)
        #expect(source.openedURLs.isEmpty)
        #expect(source.openedSettings == 0)
    }

    @Test("Keyboard actions expose only the current permission, recording and result capabilities")
    func keyboardActions() {
        #expect(MusicRecognitionActivityView.actions(for: .requestingPermission) == [.cancel])
        #expect(MusicRecognitionActivityView.actions(for: .recognizing) == [.cancel])
        #expect(MusicRecognitionActivityView.actions(for: .denied) == [.settings, .recognize, .done])
        #expect(MusicRecognitionActivityView.actions(for: .restricted) == [.done])
        #expect(MusicRecognitionActivityView.actions(for: .match(song)) == [.openSong, .done])
        #expect(MusicRecognitionActivityView.actions(for: .match(.init(title: nil, artist: nil))) == [.done])
        #expect(MusicRecognitionActivityView.actions(for: .noMatch) == [.recognize, .done])
        #expect(!NotchController.stepsAway(.recognition))
    }

    private func settle(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw WaitError.timeout
    }

    @MainActor
    private final class Source {
        var permission = MusicRecognitionActivity.Permission.authorized
        var permissionRequests = 0
        var permissionReturns = 0
        var permissionReply: CheckedContinuation<Bool, Never>?
        var sessions: [Recording] = []
        var openedURLs: [URL] = []
        var openedSettings = 0
        var openSucceeds = true

        var backend: MusicRecognitionActivity.Backend {
            .init(
                permission: { self.permission },
                requestPermission: {
                    self.permissionRequests += 1
                    let granted = await withCheckedContinuation { self.permissionReply = $0 }
                    self.permissionReturns += 1
                    return granted
                },
                makeSession: {
                    let recording = Recording()
                    self.sessions.append(recording)
                    return .init(
                        result: {
                            let result = await withCheckedContinuation { recording.reply = $0 }
                            recording.resultReturns += 1
                            return result
                        }, cancel: { recording.cancelCount += 1 })
                },
                openURL: {
                    self.openedURLs.append($0)
                    return self.openSucceeds
                },
                openMicrophoneSettings: {
                    self.openedSettings += 1
                    return self.openSucceeds
                })
        }

        func replyToPermission(_ allowed: Bool) {
            permission = allowed ? .authorized : .denied
            permissionReply?.resume(returning: allowed)
            permissionReply = nil
        }
    }

    @MainActor
    private final class Recording {
        var reply: CheckedContinuation<MusicRecognitionActivity.Result, Never>?
        var cancelCount = 0
        var resultReturns = 0

        func complete(_ result: MusicRecognitionActivity.Result) {
            reply?.resume(returning: result)
            reply = nil
        }
    }
}
