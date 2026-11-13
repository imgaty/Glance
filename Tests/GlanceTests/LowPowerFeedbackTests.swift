import Testing

@testable import Glance

@MainActor
@Suite("Low Power Mode feedback")
struct LowPowerFeedbackTests {
    @MainActor
    private final class Fixture {
        var on = false
        var appliesChange = false
        var acknowledged = false
        var writes: [Bool] = []
        var holds: [Double] = []
        lazy var model = LowPowerMode(
            readMode: { [unowned self] in on },
            setMode: { [unowned self] desired in
                writes.append(desired)
                if appliesChange { on = desired }
                return acknowledged
            },
            keepAlert: { [unowned self] in holds.append($0) },
            observesChanges: false
        )
    }

    @Test("A failed change keeps the actual mode and offers retry", arguments: [false, true])
    func failureAndRetry(initial: Bool) async throws {
        let fixture = Fixture()
        fixture.on = initial
        let request = try #require(fixture.model.toggle())
        #expect(fixture.model.isChanging)
        await request.value
        #expect(fixture.model.changeFailed)
        #expect(fixture.model.isOn == initial)
        #expect(!fixture.model.isChanging)
        #expect(fixture.writes == [!initial])
        #expect(fixture.holds == [8, 5])

        fixture.appliesChange = true
        fixture.acknowledged = true
        await fixture.model.toggle()?.value
        #expect(!fixture.model.changeFailed)
        #expect(fixture.model.isOn == !initial)
        #expect(fixture.writes == [!initial, !initial])
    }

    @Test("Observed state wins over a helper acknowledgment in either direction")
    func observedTruth() async {
        let fixture = Fixture()
        fixture.acknowledged = true
        await fixture.model.toggle()?.value
        #expect(fixture.model.changeFailed)
        #expect(!fixture.model.isOn)

        fixture.acknowledged = false
        fixture.appliesChange = true
        await fixture.model.toggle()?.value
        #expect(!fixture.model.changeFailed)
        #expect(fixture.model.isOn)
    }

    @Test("A real external mode change clears the stale failure")
    func externalChange() async {
        let fixture = Fixture()
        await fixture.model.toggle()?.value
        #expect(fixture.model.changeFailed)
        fixture.model.refresh()
        #expect(fixture.model.changeFailed)
        fixture.on = true
        fixture.model.refresh()
        #expect(fixture.model.isOn)
        #expect(!fixture.model.changeFailed)
        #expect(fixture.writes == [true])
    }

    @Test("A pending request rejects duplicate pointer or keyboard actions")
    func pendingRequest() async throws {
        var finish: CheckedContinuation<Bool, Never>?
        var writes = 0
        let model = LowPowerMode(
            readMode: { false },
            setMode: { _ in
                writes += 1
                return await withCheckedContinuation { finish = $0 }
            },
            keepAlert: { _ in },
            observesChanges: false
        )
        let request = try #require(model.toggle())
        #expect(model.toggle() == nil)
        #expect(model.isChanging)
        for _ in 0..<20 where finish == nil { await Task.yield() }
        let completion = try #require(finish)
        completion.resume(returning: false)
        await request.value
        #expect(writes == 1)
        #expect(!model.isChanging)
        #expect(model.changeFailed)
    }
}
