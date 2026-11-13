import ApplicationServices
import Testing

@testable import Glance

@Suite("Clock command failures")
@MainActor
struct ClockCommandTests {
    private static let restartCommands = ["StartStopButton", "LapResetButton", "StartStopButton"]

    private final class FakeStopwatch {
        var running = true
        var elapsed: Double = 75
        var laps = 0
        var commands: [String] = []
        var failureAt: Int?
        var error = AXError.cannotComplete

        func press(_ identifier: String, index: Int) -> AXError {
            commands.append(identifier)
            if index == failureAt { return error }
            switch identifier {
            case "StartStopButton": running.toggle()
            case "LapResetButton":
                if running { laps += 1 } else { elapsed = 0 }
            default: return .actionUnsupported
            }
            return .success
        }
    }

    @Test("Restart stops, resets, and resumes in order")
    func restart() async {
        let clock = FakeStopwatch()
        let succeeded = await ClockActivity.performStopwatchCommands(Self.restartCommands) { clock.press($0, index: $1) }
        #expect(succeeded)
        #expect(clock.commands == Self.restartCommands)
        #expect(clock.running && clock.elapsed == 0 && clock.laps == 0)
    }

    @Test("A failed restart step prevents later commands", arguments: [0, 1, 2])
    func failedRestart(at step: Int) async {
        let clock = FakeStopwatch()
        clock.failureAt = step
        let succeeded = await ClockActivity.performStopwatchCommands(Self.restartCommands) { clock.press($0, index: $1) }
        #expect(!succeeded)
        #expect(clock.commands == Array(Self.restartCommands.prefix(step + 1)))
        #expect(clock.laps == 0)
        #expect(clock.running == (step == 0))
        #expect(clock.elapsed == (step < 2 ? 75 : 0))
    }

    @Test("A missing Clock control also stops the sequence")
    func missingControl() async {
        let clock = FakeStopwatch()
        clock.failureAt = 0
        clock.error = .noValue
        let succeeded = await ClockActivity.performStopwatchCommands(Self.restartCommands) { clock.press($0, index: $1) }
        #expect(!succeeded)
        #expect(clock.commands == ["StartStopButton"])
        #expect(clock.running && clock.elapsed == 75 && clock.laps == 0)
    }

    @Test("Reset while stopped remains a single command")
    func resetStopped() async {
        let clock = FakeStopwatch()
        clock.running = false
        let succeeded = await ClockActivity.performStopwatchCommands(["LapResetButton"]) { clock.press($0, index: $1) }
        #expect(succeeded)
        #expect(clock.commands == ["LapResetButton"])
        #expect(!clock.running && clock.elapsed == 0 && clock.laps == 0)
    }

    @Test("An empty command list never reports an action succeeded")
    func empty() async {
        let clock = FakeStopwatch()
        let succeeded = await ClockActivity.performStopwatchCommands([]) { clock.press($0, index: $1) }
        #expect(!succeeded)
        #expect(clock.commands.isEmpty)
    }
}
