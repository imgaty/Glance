import AppKit
import Testing
import os

@testable import Glance

@Suite("Screen recording indicators")
struct ScreenRecordingDetectionTests {
    @Test("A preserved native indicator drives recording and saving without a process hint")
    @MainActor
    func nativeIndicatorLifecycle() async throws {
        let indicator = OSAllocatedUnfairLock(initialState: Optional("Stop Screen Recording"))
        var searches = 0
        let watch = ScreenRecordingWatch(
            readIndicator: { indicator.withLock { $0 } },
            isEnabled: { true }, captureIsRunning: { false },
            access: RecordingAccess(isGranted: { true }, request: { false }),
            stopRecording: { Issue.record("A passive observation must not stop a recording") },
            findSavedFile: { searches += 1 }, fileIsAvailable: { _ in false }, openFile: { _ in false }
        )
        watch.refresh()
        try await settle("A native recording indicator wasn't observed") { watch.recording?.isRecording == true }
        indicator.withLock { $0 = nil }
        watch.refresh()
        try await settle("Disappearing native control didn't enter saving") { watch.recording?.isSaving == true }
        #expect(searches == 1)
    }

    @Test("An indicator appearing after launch is found without a Screenshot app launch")
    @MainActor
    func recordingWithoutAppChange() async throws {
        let indicator = OSAllocatedUnfairLock(initialState: Optional<String>.none)
        let watch = ScreenRecordingWatch(
            readIndicator: { indicator.withLock { $0 } },
            isEnabled: { true }, captureIsRunning: { false },
            access: RecordingAccess(isGranted: { true }, request: { false }),
            stopRecording: {}, findSavedFile: {}, fileIsAvailable: { _ in false }, openFile: { _ in true }
        )
        watch.start()
        try await Task.sleep(for: .milliseconds(100))
        #expect(watch.recording == nil)
        indicator.withLock { $0 = "Stop Screen Recording" }
        // Idle, the watch looks only every two seconds, and its timer waits for a busy main thread.
        try await settle("The recording was missed without an app launch notification", timeout: .seconds(10)) {
            watch.recording?.isRecording == true
        }
    }

    @Test("A recording Live Activity can be a group rather than a menu item")
    func liveActivityGroup() {
        #expect(
            ScreenRecordingWatch.isRecordingControl(
                role: kAXGroupRole, subrole: "AXLiveActivity",
                identifier: "live-activity-pill-com.apple.screencaptureui"
            ))
    }

    @Test("The legacy recording stop item remains recognized")
    func legacyItem() {
        #expect(
            ScreenRecordingWatch.isRecordingControl(
                role: kAXMenuBarItemRole, subrole: nil,
                identifier: "com.apple.menuextra.screencapture"
            ))
    }

    @Test("Screenshot's toolbar and unrelated Live Activities are not recordings")
    func unrelatedControls() {
        #expect(
            !ScreenRecordingWatch.isRecordingControl(
                role: kAXButtonRole, subrole: nil,
                identifier: "com.apple.screencaptureui.capture"
            ))
        #expect(
            !ScreenRecordingWatch.isRecordingControl(
                role: kAXGroupRole, subrole: "AXLiveActivity",
                identifier: "live-activity-pill-com.apple.MediaRemoteUIService"
            ))
        #expect(ScreenRecordingWatch.isRecordingControl(role: nil, subrole: nil, identifier: nil) == false)
    }

    @Test("With Screenshot's Live Activity off, a recording is read from the movie ReplayKit writes for Screenshot alone")
    func recordingFile() {
        let home = NSHomeDirectory()
        #expect(ScreenRecordingWatch.isScreenshotRecording("\(home)/Library/Group Containers/group.com.apple.screencapture/ScreenRecordings/85E31A3C-831F-4970-B67E-696C2FB6BE79.mov"))
        // The folder itself, a still screenshot, and another app's recording aren't.
        #expect(!ScreenRecordingWatch.isScreenshotRecording("\(home)/Library/Group Containers/group.com.apple.screencapture/ScreenRecordings/"))
        #expect(!ScreenRecordingWatch.isScreenshotRecording("\(home)/Desktop/Screenshot 2026-11-23 at 11.22.47.png"))
        #expect(!ScreenRecordingWatch.isScreenshotRecording("\(home)/Movies/Capture.mov"))
    }

    @Test("Stopped from Screenshot's own toolbar, by its stop button's symbol, the same in every language")
    func toolbarStop() {
        #expect(ScreenRecordingWatch.isToolbarStop("stop.circle.fill"))
        #expect(!ScreenRecordingWatch.isToolbarStop("rectangle.dashed.badge.record"))
        #expect(!ScreenRecordingWatch.isToolbarStop(nil))
    }
}

