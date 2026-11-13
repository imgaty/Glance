import AppKit
import Testing
import os

@testable import Glance

@Suite("Screen recording indicators")
struct ScreenRecordingDetectionTests {
    @Test("An indicator appearing after launch is found without a Screenshot app launch")
    @MainActor
    func recordingWithoutAppChange() async throws {
        let indicator = OSAllocatedUnfairLock(initialState: Optional<String>.none)
        let watch = ScreenRecordingWatch(
            readIndicator: { indicator.withLock { $0 } },
            isEnabled: { true }, captureIsRunning: { false },
            access: RecordingAccess(isGranted: { true }, request: { false }),
            stopRecording: {}, findSavedFile: {}, openFile: { _ in }
        )
        watch.start()
        try await Task.sleep(for: .milliseconds(100))
        #expect(watch.recording == nil)
        indicator.withLock { $0 = "Stop Screen Recording" }
        let deadline = Date.now.addingTimeInterval(4)
        while watch.recording == nil, Date.now < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }
        guard case .recording? = watch.recording else {
            Issue.record("The recording was missed without an app launch notification")
            return
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
}
