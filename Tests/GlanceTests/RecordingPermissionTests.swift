import Foundation
import Testing
import os

@testable import Glance

@Suite("Recording permission boundaries")
@MainActor
struct RecordingPermissionTests {
    private func waitFor(_ predicate: () -> Bool) async throws {
        for _ in 0..<100 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(predicate())
    }

    @Test("Losing access preserves a recording without looking for a saved file")
    func screenPermissionLoss() async throws {
        let indicator = OSAllocatedUnfairLock(initialState: (words: Optional("Stop Screen Recording"), reads: 0))
        var granted = true
        var fileLookups = 0
        let watch = ScreenRecordingWatch(
            readIndicator: {
                indicator.withLock {
                    $0.reads += 1
                    return $0.words
                }
            },
            isEnabled: { true }, captureIsRunning: { true },
            access: RecordingAccess(isGranted: { granted }, request: { false }),
            stopRecording: {}, findSavedFile: { fileLookups += 1 }, openFile: { _ in }
        )
        watch.refresh()
        try await waitFor { watch.recording?.isRecording == true }
        let observed = watch.recording
        granted = false
        indicator.withLock { $0.words = nil }
        let reads = indicator.withLock { $0.reads }
        watch.refresh()
        #expect(!watch.canControl)
        #expect(watch.recording == observed)
        #expect(fileLookups == 0)
        #expect(indicator.withLock { $0.reads } == reads)

        granted = true
        watch.refresh()
        try await waitFor { watch.recording?.isSaving == true }
        #expect(watch.canControl)
        #expect(fileLookups == 1)
    }

    @Test("A denied initial observation never reads the native source")
    func deniedObservation() {
        let reads = OSAllocatedUnfairLock(initialState: 0)
        var fileLookups = 0
        let watch = ScreenRecordingWatch(
            readIndicator: {
                reads.withLock { $0 += 1 }
                return "Stop Screen Recording"
            },
            isEnabled: { true }, captureIsRunning: { true },
            access: RecordingAccess(isGranted: { false }, request: { false }),
            stopRecording: {}, findSavedFile: { fileLookups += 1 }, openFile: { _ in }
        )
        watch.refresh()
        #expect(watch.recording == nil)
        #expect(reads.withLock { $0 } == 0)
        #expect(fileLookups == 0)
    }

    @Test("Screen Stop requests permission only when needed and never stops after denial")
    func screenStopPermission() {
        var granted = false
        var accept = false
        var requests = 0
        var stops = 0
        let access = RecordingAccess(
            isGranted: { granted },
            request: {
                requests += 1
                granted = accept
                return granted
            })
        let watch = ScreenRecordingWatch(
            readIndicator: { nil }, isEnabled: { true }, captureIsRunning: { false },
            access: access, stopRecording: { stops += 1 }, findSavedFile: {}, openFile: { _ in }
        )
        watch.stop()
        #expect(requests == 1 && stops == 0 && !watch.canControl)
        accept = true
        watch.stop()
        #expect(requests == 2 && stops == 1 && watch.canControl)
        watch.stop()
        #expect(requests == 2 && stops == 2)
    }

    @Test("Voice Memo Stop cannot finish a memo after permission denial")
    func memoStopPermission() {
        var granted = false
        var requests = 0
        var finishes = 0
        let watch = VoiceMemoWatch(
            access: RecordingAccess(
                isGranted: { granted },
                request: {
                    requests += 1
                    return false
                }),
            finishRecording: { finishes += 1 }
        )
        watch.stop()
        #expect(requests == 1 && finishes == 0 && !watch.canControl)
        granted = true
        watch.stop()
        #expect(requests == 1 && finishes == 1 && watch.canControl)
    }

    @Test("An unavailable Voice Memos interface cannot imply that a memo finished")
    func memoPermissionLoss() {
        let now = Date(timeIntervalSince1970: 1_000)
        let running = VoiceMemo.recording(since: now - 75)
        let paused = VoiceMemo.paused(length: 75)
        for previous in [running, paused] {
            #expect(VoiceMemoWatch.next(after: previous, recording: false, resume: false, done: false, at: now, controlsAvailable: false) == previous)
            #expect(VoiceMemoWatch.next(after: previous, recording: false, resume: false, done: false, at: now, controlsAvailable: true) == nil)
        }
        #expect(VoiceMemoWatch.next(after: nil, recording: false, resume: false, done: false, at: now, controlsAvailable: false) == nil)
    }
}
