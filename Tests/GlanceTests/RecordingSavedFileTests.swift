import Foundation
import Testing

@testable import Glance

@Suite("Saved recording recovery")
@MainActor
struct RecordingSavedFileTests {
    private static let file = URL(fileURLWithPath: "/isolated-review/recording.mov")

    @MainActor
    private final class Files {
        var available = true
        var opensSuccessfully = true
        var disappearsDuringOpen = false
        var opened: [URL] = []
        var permissionRequests = 0

        func watch() -> ScreenRecordingWatch {
            ScreenRecordingWatch(
                readIndicator: { nil }, isEnabled: { true }, captureIsRunning: { false },
                access: RecordingAccess(
                    isGranted: { false },
                    request: {
                        self.permissionRequests += 1
                        return false
                    }),
                stopRecording: {}, findSavedFile: {},
                fileIsAvailable: { _ in self.available },
                openFile: {
                    self.opened.append($0)
                    if self.disappearsDuringOpen { self.available = false }
                    return self.opensSuccessfully
                }
            )
        }
    }

    @Test("A missing saved file never reaches the opener")
    func missingFile() {
        let files = Files()
        files.available = false
        let watch = files.watch()
        #expect(!watch.openSaved())
        watch.presentSaved(file: Self.file, length: 75, folder: "Desktop", preview: nil)
        #expect(!watch.canOpenSaved && watch.savedFileState == .unavailable)
        #expect(!watch.openSaved())
        #expect(files.opened.isEmpty)
    }

    @Test("Deleting the file after the preview disables Open before invoking it")
    func deletedFile() {
        let files = Files()
        let watch = files.watch()
        watch.presentSaved(file: Self.file, length: 75, folder: "Desktop", preview: nil)
        #expect(watch.canOpenSaved)
        files.available = false
        #expect(!watch.openSaved())
        #expect(watch.savedFileState == .unavailable)
        #expect(files.opened.isEmpty)
    }

    @Test("Failed opening offers a retry and successful retry clears the failure")
    func retry() {
        let files = Files()
        files.opensSuccessfully = false
        let watch = files.watch()
        watch.presentSaved(file: Self.file, length: 75, folder: "Desktop", preview: nil)
        #expect(!watch.openSaved())
        #expect(watch.savedFileState == .openingFailed && watch.canOpenSaved)
        files.opensSuccessfully = true
        #expect(watch.openSaved())
        #expect(watch.savedFileState == .available)
        #expect(files.opened == [Self.file, Self.file])
        #expect(files.permissionRequests == 0)
    }

    @Test("A file that reappears becomes available without opening it automatically")
    func fileReturns() {
        let files = Files()
        files.available = false
        let watch = files.watch()
        watch.presentSaved(file: Self.file, length: 75, folder: "Desktop", preview: nil)
        files.available = true
        watch.refreshSavedAvailability()
        #expect(watch.savedFileState == .available && watch.canOpenSaved)
        #expect(files.opened.isEmpty)
        #expect(watch.recording == .saved(length: 75, folder: "Desktop", preview: nil))
    }

    @Test("An open failure caused by a vanished file is unavailable rather than retryable")
    func disappearedDuringOpen() {
        let files = Files()
        files.opensSuccessfully = false
        files.disappearsDuringOpen = true
        let watch = files.watch()
        watch.presentSaved(file: Self.file, length: 75, folder: "Desktop", preview: nil)
        #expect(!watch.openSaved())
        #expect(watch.savedFileState == .unavailable && !watch.canOpenSaved)
        #expect(!watch.openSaved())
        #expect(files.opened.count == 1)
    }

    @Test("A later saved recording does not inherit an older open failure")
    func newRecording() {
        let files = Files()
        files.opensSuccessfully = false
        let watch = files.watch()
        watch.presentSaved(file: Self.file, length: 75, folder: "Desktop", preview: nil)
        #expect(!watch.openSaved())
        let next = URL(fileURLWithPath: "/isolated-review/next.mov")
        watch.presentSaved(file: next, length: 12, folder: "Movies", preview: nil)
        #expect(watch.savedFileState == .available && watch.saved == next)
        #expect(watch.recording == .saved(length: 12, folder: "Movies", preview: nil))
    }
}
