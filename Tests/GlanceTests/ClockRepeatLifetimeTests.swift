import ApplicationServices
import Foundation
import Testing

@testable import Glance

@MainActor
@Suite("Repeat keeps its source command and recovery available")
struct ClockRepeatLifetimeTests {
    @Test("Clock's actual picker container is found without accepting duplicate button groups")
    func accessibleTargets() {
        let nodes: [(id: String, role: String)] = [
            ("TimePicker", kAXGroupRole),
            ("TimePicker", kAXSliderRole),
            ("PauseResumeButton", kAXGroupRole),
            ("PauseResumeButton", kAXButtonRole),
            ("StartStopButton", kAXGroupRole),
            ("StartStopButton", kAXButtonRole),
        ]
        func match(_ target: ClockActivity.ControlTarget) -> Int? {
            nodes.firstIndex { target.matches(identifier: $0.id, role: $0.role) }
        }
        #expect(match(.timerPicker) == 0)
        #expect(match(.button("PauseResumeButton")) == 3)
        #expect(match(.button("StartStopButton")) == 5)
        #expect(match(.button("Gone")) == nil)
        #expect(!ClockActivity.ControlTarget.timerPicker.matches(identifier: nil, role: kAXGroupRole))
        #expect(!ClockActivity.ControlTarget.button("PauseResumeButton").matches(identifier: "PauseResumeButton", role: nil))
    }

    @Test("Expiry cannot cancel a pending repeat or hide its failure, and Retry can succeed")
    func failureKeepsRetry() async throws {
        let activities = Activities()
        let backend = RepeatBackend()
        let clock = ClockActivity(activities: activities, repeatAction: backend.restart)
        clock.benchRing(length: 30, title: "GlanceAudit")
        let alert = try #require(activities.alert)
        let expire = try #require(alert.expired)

        clock.repeatTimer()
        #expect(clock.repeatState == .pending)
        clock.repeatTimer()
        try await settle { backend.pending != nil }
        #expect(backend.requests.count == 1)
        #expect(backend.requests.first?.length == 30)
        #expect(backend.requests.first?.title == "GlanceAudit")
        expire()
        #expect(clock.rang != nil)
        #expect(clock.timer == nil)
        #expect(activities.alert?.id == alert.id)

        backend.complete(nil)
        try await settle { clock.repeatState == .failed }
        expire()
        #expect(clock.rang != nil)
        #expect(clock.timer == nil)
        #expect(activities.alert?.id == alert.id)

        clock.repeatTimer()
        try await settle { backend.pending != nil }
        #expect(clock.repeatState == .pending)
        #expect(backend.requests.count == 2)
        let until = Date.now + 30
        backend.complete((.running(until: until, total: 30), "repeated", "GlanceAudit"))
        try await settle { clock.rang == nil }
        #expect(clock.repeatState == .idle)
        #expect(clock.timer == .running(until: until, total: 30))
        #expect(clock.timerTitle == "GlanceAudit")
        #expect(activities.alert == nil)
        clock.cancelTimer()
    }

    @Test("Stop remains effective during a pending repeat and discards a late reply")
    func stopWhilePending() async throws {
        let activities = Activities()
        let backend = RepeatBackend()
        let clock = ClockActivity(activities: activities, repeatAction: backend.restart)
        clock.benchRing(length: 30)
        clock.repeatTimer()
        try await settle { backend.pending != nil }
        clock.dismissRing()
        #expect(clock.repeatState == .idle)
        #expect(clock.rang == nil)
        #expect(activities.alert == nil)
        backend.complete((.running(until: .now + 30, total: 30), "late", nil))
        try await settle { backend.returned }
        #expect(clock.timer == nil)
        #expect(clock.rang == nil)
    }

    @Test("A replacement ring survives the old repeat reply and its captured expiry")
    func replacementRing() async throws {
        let activities = Activities()
        let backend = RepeatBackend()
        let clock = ClockActivity(activities: activities, repeatAction: backend.restart)
        clock.benchRing(length: 30, title: "First")
        let expireFirst = try #require(activities.alert?.expired)
        clock.repeatTimer()
        try await settle { backend.pending != nil }
        clock.benchRing(length: 60, title: "Second")
        expireFirst()
        backend.complete((.running(until: .now + 30, total: 30), "old", "First"))
        try await settle { backend.returned && activities.alert?.spoken == "Second done" }
        #expect(clock.repeatState == .idle)
        #expect(clock.rang?.length == 60)
        #expect(clock.rang?.title == "Second")
        #expect(clock.timer == nil)
        clock.dismissRing()
    }

    @Test("An untouched done timer still expires normally")
    func untouchedExpiry() throws {
        let activities = Activities()
        let clock = ClockActivity(activities: activities)
        clock.benchRing(length: 30)
        let expire = try #require(activities.alert?.expired)
        expire()
        #expect(clock.rang == nil)
        #expect(activities.alert == nil)
        #expect(clock.timer == nil)
    }

    @Test("A new ring replaces an expired failed repeat without losing unrelated announcements")
    func failedRingReplacement() async throws {
        let activities = Activities()
        let backend = RepeatBackend()
        let clock = ClockActivity(activities: activities, repeatAction: backend.restart)
        clock.benchRing(length: 30, title: "First")
        let first = try #require(activities.alert)
        clock.repeatTimer()
        try await settle { backend.pending != nil }
        // The real expiry task invokes this once. Returning while pending ends that task.
        let expire = try #require(first.expired)
        expire()
        backend.complete(nil)
        try await settle { clock.repeatState == .failed }

        let charging = NotchAlert(kind: .charging, content: .battery(title: "Charging", level: .init(percent: 70, charging: true)), spoken: "Charging", stays: true)
        let device = NotchAlert(kind: .device, content: .device(model: .airpods, battery: 75), spoken: "AirPods connected", stays: true)
        activities.post(charging)
        activities.post(device)
        clock.benchRing(length: 60, title: "Second")

        #expect(activities.alert?.id != first.id)
        #expect(!activities.waiting.contains { $0.id == first.id })
        try await settle { activities.alert?.id == charging.id }
        #expect(activities.waiting.contains { $0.id == device.id })
        #expect(activities.waiting.filter { $0.kind == .timerDone }.map(\.spoken) == ["Second done"])
        activities.dismiss(id: charging.id)
        try await settle { activities.alert?.id == device.id }
        activities.dismiss(id: device.id)
        try await settle { activities.alert?.spoken == "Second done" }
        #expect(clock.rang?.title == "Second")
        #expect(clock.rang?.length == 60)
        #expect(clock.repeatState == .idle)
        #expect(clock.timer == nil)
        clock.dismissRing()
    }

    private enum WaitError: Error { case timeout }

    private func settle(_ ready: () -> Bool) async throws {
        for _ in 0..<200 {
            if ready() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("The isolated repeat did not reach its expected state")
        throw WaitError.timeout
    }

    @MainActor
    private final class RepeatBackend {
        var requests: [(length: TimeInterval, title: String?)] = []
        var pending: CheckedContinuation<ClockActivity.Found?, Never>?
        var returned = false

        func restart(length: TimeInterval, title: String?) async -> ClockActivity.Found? {
            requests.append((length, title))
            returned = false
            let result = await withCheckedContinuation { pending = $0 }
            returned = true
            return result
        }

        func complete(_ result: ClockActivity.Found?) {
            let continuation = pending
            pending = nil
            continuation?.resume(returning: result)
        }
    }
}
