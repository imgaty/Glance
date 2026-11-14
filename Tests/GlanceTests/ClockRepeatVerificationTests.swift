import Foundation
import Testing

@testable import Glance

@MainActor
@Suite("Repeat confirms a running Clock timer")
struct ClockRepeatVerificationTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func running(_ id: String = "repeated", title: String = "GlanceAudit", length: Double = 30, until: Date? = nil) -> [String: Any] {
        [
            "$MTTimer": [
                "MTTimerID": id, "MTTimerTitle": title, "MTTimerDuration": length, "MTTimerState": 3,
                "MTTimerFireTime": ["$MTTimerDate": ["MTTimerTimeDate": until ?? now + length]],
            ]
        ]
    }

    @Test("An acknowledged notification that starts nothing falls back to Clock")
    func ineffectiveNotification() async throws {
        var stored: [[String: Any]] = []
        var editorPresses = 0
        let result = await ClockActivity.performTimerRepeat(
            notification: { true },
            editor: {
                editorPresses += 1
                stored = [running()]
                return true
            },
            readBack: { _ in
                ClockActivity.repeatedTimer(in: stored, before: [], length: 30, title: "GlanceAudit", at: now)
            })
        let started = try #require(result)
        #expect(editorPresses == 1)
        #expect(started.title == "GlanceAudit")
        #expect(started.state == .running(until: now + 30, total: 30))
    }

    @Test("A confirmed notification restart doesn't create a second timer")
    func confirmedNotification() async throws {
        var stored: [[String: Any]] = []
        var editorPresses = 0
        let result = await ClockActivity.performTimerRepeat(
            notification: {
                stored = [running()]
                return true
            },
            editor: {
                editorPresses += 1
                return true
            },
            readBack: { _ in
                ClockActivity.repeatedTimer(in: stored, before: [], length: 30, title: "GlanceAudit", at: now)
            })
        #expect(try #require(result).title == "GlanceAudit")
        #expect(editorPresses == 0)
    }

    @Test("Even two successful AX acknowledgements cannot fabricate a running timer")
    func unsuccessfulFallback() async {
        var editorPresses = 0
        let result = await ClockActivity.performTimerRepeat(
            notification: { true },
            editor: {
                editorPresses += 1
                return true
            }, readBack: { _ in nil })
        #expect(result == nil)
        #expect(editorPresses == 1)
    }

    @Test("Clock read-back can confirm a start even when its AX reply reports failure")
    func authoritativeReadBack() async throws {
        var stored: [[String: Any]] = []
        let result = await ClockActivity.performTimerRepeat(
            notification: { false },
            editor: {
                stored = [running()]
                return false
            },
            readBack: { _ in
                ClockActivity.repeatedTimer(in: stored, before: [], length: 30, title: "GlanceAudit", at: now)
            })
        #expect(try #require(result).state == .running(until: now + 30, total: 30))
    }

    @Test("An already running timer, another label, or another duration isn't restart confirmation")
    func unrelatedTimers() throws {
        let original = running("already-running", until: now + 20)
        let unrelated = [original, running("other-name", title: "Other"), running("other-length", length: 60)]
        #expect(ClockActivity.repeatedTimer(in: unrelated, before: [original], length: 30, title: "GlanceAudit", at: now) == nil)
        let result = try #require(
            ClockActivity.repeatedTimer(in: unrelated + [running()], before: [original], length: 30, title: "GlanceAudit", at: now))
        #expect(result.id == "repeated")
    }

    @Test("Restarting the same timer ID is recognized by its new fire time")
    func reusedIdentifier() throws {
        let old = running("same", until: now + 12)
        let new = running("same", until: now + 30)
        let result = try #require(ClockActivity.repeatedTimer(in: [new], before: [old], length: 30, title: "GlanceAudit", at: now))
        #expect(result.id == "same")
        #expect(result.state == .running(until: now + 30, total: 30))
    }

    @Test("Stopping a pending repeat before fallback prevents another Start command")
    func cancelledRequest() async {
        var editorPresses = 0
        let task = Task { @MainActor in
            await ClockActivity.performTimerRepeat(
                notification: { true },
                editor: {
                    editorPresses += 1
                    return true
                },
                readBack: { _ in
                    withUnsafeCurrentTask { $0?.cancel() }
                    return nil
                })
        }
        #expect(await task.value == nil)
        #expect(editorPresses == 0)
    }
}
