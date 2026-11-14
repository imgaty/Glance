import Foundation
import Testing

@testable import Glance

@Suite("Clock bench isolation")
@MainActor
struct ClockBenchIsolationTests {
    @Test("A seeded timer can pause, resume and cancel without Clock access")
    func timerControls() throws {
        let clock = ClockActivity(activities: Activities())
        clock.bench(timer: .paused(left: 90, total: 120))
        #expect(clock.canControl)
        clock.start()

        clock.toggleTimer()
        let running = try #require(clock.timer)
        #expect(running.isRunning)
        #expect(running.total == 120)
        #expect((89...90).contains(running.left()))

        clock.toggleTimer()
        #expect(clock.timer?.isRunning == false)
        clock.cancelTimer()
        #expect(clock.timer == nil)
        clock.toggleTimer()
        #expect(clock.timer == nil)
    }

    @Test("A seeded stopwatch can stop, resume, restart and reset locally")
    func stopwatchControls() throws {
        let clock = ClockActivity(activities: Activities())
        clock.bench(stopwatch: .stopped(elapsed: 75))
        #expect(clock.canControl)
        clock.startStopStopwatch()
        #expect(clock.stopwatch?.isRunning == true)
        #expect((75...76).contains(try #require(clock.stopwatch).elapsed()))

        clock.startStopStopwatch()
        #expect(clock.stopwatch?.isRunning == false)
        clock.startStopStopwatch()
        clock.resetStopwatch()
        #expect(clock.stopwatch?.isRunning == true)
        #expect(try #require(clock.stopwatch).elapsed() < 1)

        clock.startStopStopwatch()
        clock.resetStopwatch()
        #expect(clock.stopwatch == nil)
    }

    @Test("Repeating a seeded ring dismisses only its own alert and restarts its duration")
    func repeatRing() throws {
        let activities = Activities()
        let clock = ClockActivity(activities: activities)
        clock.benchRing(length: 42)
        #expect(clock.canControl)
        #expect(activities.alert?.kind == .timerDone)
        clock.repeatTimer()
        #expect(clock.rang == nil)
        #expect(activities.alert == nil)
        let timer = try #require(clock.timer)
        #expect(timer.isRunning)
        #expect(timer.total == 42)
        #expect((41...42).contains(timer.left()))
        clock.cancelTimer()
    }

    @Test("Stopping a seeded ring clears its alert without starting another timer")
    func stopRing() {
        let activities = Activities()
        let clock = ClockActivity(activities: activities)
        clock.benchRing(length: 42)
        clock.dismissRing()
        #expect(clock.rang == nil)
        #expect(clock.timer == nil)
        #expect(activities.alert == nil)
        clock.dismissRing()
        #expect(activities.alert == nil)
    }
}
