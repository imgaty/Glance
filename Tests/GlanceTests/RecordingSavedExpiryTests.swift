import Foundation
import Testing

@testable import Glance

@Suite("Saved recording expiry")
@MainActor
struct RecordingSavedExpiryTests {
    /// Deliberately ignores cancellation so a superseded wait can still finish. No wall-clock
    /// sleeps, filesystem access, permission prompts or workspace opening occur in this suite.
    @MainActor
    private final class Sleeper {
        private var continuations: [CheckedContinuation<Void, Never>?] = []
        private(set) var completed: Set<Int> = []
        var count: Int { continuations.count }

        func wait() async throws {
            let index = count
            await withCheckedContinuation { continuations.append($0) }
            completed.insert(index)
        }

        func release(_ index: Int) {
            guard continuations.indices.contains(index) else { return }
            continuations[index]?.resume()
            continuations[index] = nil
        }

        func releaseAll() {
            for index in continuations.indices { release(index) }
        }
    }

    @MainActor
    private final class Files {
        var available = true
        var opensSuccessfully = true
        let sleeper = Sleeper()

        func watch() -> ScreenRecordingWatch {
            ScreenRecordingWatch(
                readIndicator: { nil }, isEnabled: { true }, captureIsRunning: { false },
                access: RecordingAccess(isGranted: { false }, request: { false }),
                stopRecording: {}, findSavedFile: {},
                fileIsAvailable: { _ in self.available },
                openFile: { _ in self.opensSuccessfully },
                waitForSavedDismissal: { try await self.sleeper.wait() }
            )
        }
    }

    private func present(_ watch: ScreenRecordingWatch, length: TimeInterval = 75) {
        watch.presentSaved(
            file: URL(fileURLWithPath: "/isolated-review/recording-\(length).mov"),
            length: length, folder: "Desktop", preview: nil
        )
    }

    /// Run queued main-actor jobs only; time is advanced exclusively through Sleeper.release.
    private func drain(until condition: () -> Bool) async {
        for _ in 0..<100 {
            if condition() { break }
            await Task.yield()
        }
        #expect(condition())
        await Task.yield()
    }

    @Test("The current saved result expires when its own delay completes")
    func currentResultExpires() async {
        let files = Files()
        defer { files.sleeper.releaseAll() }
        let watch = files.watch()
        present(watch)
        await drain { files.sleeper.count == 1 }
        #expect(watch.recording != nil)
        files.sleeper.release(0)
        await drain { watch.recording == nil }
    }

    @Test("An old cancelled wait cannot remove a newer saved result")
    func newerResultSurvivesOldWait() async {
        let files = Files()
        defer { files.sleeper.releaseAll() }
        let watch = files.watch()
        present(watch)
        await drain { files.sleeper.count == 1 }
        present(watch, length: 12)
        await drain { files.sleeper.count == 2 }
        files.sleeper.release(0)
        await drain { files.sleeper.completed.contains(0) }
        #expect(watch.recording == .saved(length: 12, folder: "Desktop", preview: nil))
        files.sleeper.release(1)
        await drain { watch.recording == nil }
    }

    @Test("A newly shown open error gets a fresh retry interval")
    func retryErrorRestartsExpiry() async {
        let files = Files()
        defer { files.sleeper.releaseAll() }
        files.opensSuccessfully = false
        let watch = files.watch()
        present(watch)
        await drain { files.sleeper.count == 1 }
        #expect(!watch.openSaved())
        await drain { files.sleeper.count == 2 }
        files.sleeper.release(0)
        await drain { files.sleeper.completed.contains(0) }
        #expect(watch.recording != nil && watch.savedFileState == .openingFailed)
        files.sleeper.release(1)
        await drain { watch.recording == nil }
    }

    @Test("A missing-file error restarts expiry once rather than after every poll")
    func unavailableErrorDoesNotExtendForever() async {
        let files = Files()
        defer { files.sleeper.releaseAll() }
        let watch = files.watch()
        present(watch)
        await drain { files.sleeper.count == 1 }
        files.available = false
        watch.refreshSavedAvailability()
        await drain { files.sleeper.count == 2 }
        watch.refreshSavedAvailability()
        watch.refreshSavedAvailability()
        files.sleeper.release(0)
        await drain { files.sleeper.completed.contains(0) }
        #expect(watch.recording != nil && watch.savedFileState == .unavailable)
        #expect(files.sleeper.count == 2)
        files.sleeper.release(1)
        await drain { watch.recording == nil }
    }

    @Test("A previous saved result cannot dismiss a later bench presentation")
    func benchSurvivesPendingExpiry() async {
        let files = Files()
        defer { files.sleeper.releaseAll() }
        let watch = files.watch()
        present(watch)
        await drain { files.sleeper.count == 1 }
        let bench: ScreenRecording = .saved(length: 19, folder: "Movies", preview: nil)
        watch.bench(bench)
        files.sleeper.release(0)
        await drain { files.sleeper.completed.contains(0) }
        #expect(watch.recording == bench)
    }
}
