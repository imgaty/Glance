import Foundation
import Testing

@testable import Glance

@MainActor
@Suite("Print jobs follow their real queue identity")
struct PrintActivityTests {
    private func job(_ number: Int32 = 12, printer: String = "Office", created: Int64 = 100, state: PrintJob.State = .printing) -> PrintJob {
        PrintJob(id: .init(printer: printer, number: number, created: created), title: "Project notes", owner: "fixture-user", state: state)
    }

    @Test("Queue admission excludes other users, terminal jobs, missing destinations and all-job sentinels")
    func queueAdmission() {
        func parsed(number: Int32 = 12, printer: String? = "Office", owner: String? = "me", state: Int32 = 5, created: Int64 = 100) -> PrintJob? {
            PrintJob.fromQueue(number: number, printer: printer, title: "  ", owner: owner, state: state, created: created, currentUser: "me")
        }
        #expect(parsed()?.title == "Print Job")
        #expect(parsed()?.canCancel == true)
        #expect(parsed(owner: "someone-else") == nil)
        #expect(parsed(owner: nil) == nil)
        #expect(parsed(number: 0) == nil)
        #expect(parsed(number: -1) == nil)
        #expect(parsed(printer: nil) == nil)
        #expect(parsed(printer: " ") == nil)
        for state in [Int32(7), 8, 9, 99] { #expect(parsed(state: state) == nil) }
        #expect(parsed(created: 0)?.canCancel == false)
    }

    @Test("Only valid authoritative totals produce progress; full progress does not mean the queue completed")
    func progressIsNotCompletion() {
        #expect(PrintJob.Progress(completed: 1, total: 0) == nil)
        #expect(PrintJob.Progress(completed: -1, total: 10) == nil)
        #expect(PrintJob.Progress(completed: 11, total: 10) == nil)
        #expect(PrintJob.Progress(completed: 2, total: 4)?.fraction == 0.5)
        var current = job()
        current.progress = .init(completed: 4, total: 4)
        #expect(current.canCancel)
        #expect(current.state == .printing)
    }

    @Test("The same active job stays selected as snapshots and progress arrive in another order")
    func stableSelection() {
        let queued = job(1, created: 90, state: .queued)
        let printing = job(2, created: 100)
        #expect(PrintJob.selected(in: [queued, printing], keeping: nil)?.id == printing.id)
        #expect(PrintJob.selected(in: [printing, queued], keeping: queued.id)?.id == queued.id)
        #expect(PrintJob.selected(in: [printing], keeping: queued.id)?.id == printing.id)
        #expect(PrintJob.selected(in: [job(state: .completed)], keeping: nil) == nil)
    }

    @Test("Cancel revalidates the exact printer, job and creation time before reaching the writer")
    func staleCancellation() async {
        for replacement in [job(13), job(printer: "Other"), job(created: 200), job(state: .completed)] {
            let original = job()
            let source = Source(jobs: [original])
            let watch = PrintActivity(source: source, cancellationDelay: .zero)
            await watch.refresh()
            await source.setJobs([replacement])
            #expect(!(await watch.cancel(expectedID: original.id)))
            #expect(await source.canceled.isEmpty)
            #expect(watch.shown?.job.id == (replacement.state.isActive ? replacement.id : nil))
        }
    }

    @Test("An acknowledged cancellation only removes a job after the queue confirms it")
    func cancelAndReadBack() async {
        let original = job()
        let source = Source(jobs: [original])
        let watch = PrintActivity(source: source, cancellationDelay: .zero)
        await watch.refresh()
        await source.configure(removeOnCancel: false)
        #expect(!(await watch.cancel(expectedID: original.id)))
        #expect(watch.shown?.job.id == original.id)
        #expect(watch.shown?.cancellation == .failed)

        await source.configure(removeOnCancel: true)
        #expect(await watch.cancel(expectedID: original.id))
        #expect(watch.shown == nil)
        #expect(await source.canceled == [original.id, original.id])
    }

    @Test("A rejected cancellation keeps the job and offers a retry")
    func cancellationError() async {
        let current = job()
        let source = Source(jobs: [current])
        let watch = PrintActivity(source: source, cancellationDelay: .zero)
        await watch.refresh()
        await source.configure(cancelFails: true)
        #expect(!(await watch.cancel(expectedID: current.id)))
        #expect(watch.shown?.cancellation == .failed)
        #expect(watch.shown?.canCancel == true)
        await source.configure(cancelFails: false)
        #expect(await watch.cancel(expectedID: current.id))
        #expect(watch.shown == nil)
    }

    @Test("A disconnected queue is not represented as completion, and Cancel is unavailable until it recovers")
    func sourceLossAndRecovery() async {
        let current = job()
        let source = Source(jobs: [current])
        let watch = PrintActivity(source: source)
        await watch.refresh()
        await source.configure(readFails: true)
        await watch.refresh()
        #expect(watch.shown?.job.id == current.id)
        #expect(watch.shown?.sourceAvailable == false)
        #expect(watch.shown?.canCancel == false)
        #expect(!(await watch.cancel(expectedID: current.id)))
        #expect(await source.canceled.isEmpty)
        await source.configure(readFails: false)
        await watch.refresh()
        #expect(watch.shown?.sourceAvailable == true)
        #expect(watch.shown?.canCancel == true)
    }

    @Test("Duplicate presses share one pending command and stopping the observer prevents a later write")
    func pendingCancellation() async throws {
        let current = job()
        let source = Source(jobs: [current])
        let watch = PrintActivity(source: source, cancellationDelay: .zero)
        await watch.refresh()
        await source.holdNextRead()
        let first = Task { await watch.cancel(expectedID: current.id) }
        try await waitUntil { await source.hasHeldRead }
        #expect(watch.shown?.cancellation == .pending)
        #expect(!(await watch.cancel(expectedID: current.id)))
        watch.stop()
        await source.resumeRead()
        #expect(!(await first.value))
        #expect(await source.canceled.isEmpty)
        #expect(watch.shown == nil)
    }

    @Test("Canceling one job leaves a second job available, with its own clean action state")
    func otherJobSurvives() async {
        let first = job()
        let second = job(13, printer: "Home", created: 200)
        let source = Source(jobs: [first, second])
        let watch = PrintActivity(source: source, cancellationDelay: .zero)
        await watch.refresh()
        #expect(watch.shown?.additionalJobs == 1)
        #expect(await watch.cancel(expectedID: first.id))
        #expect(watch.shown?.job.id == second.id)
        #expect(watch.shown?.cancellation == .idle)
        #expect(watch.shown?.additionalJobs == 0)
    }

    @Test("Disabling the activity hides it without canceling jobs")
    func disabled() async {
        let source = Source(jobs: [job()])
        var enabled = true
        let watch = PrintActivity(source: source, isEnabled: { enabled })
        await watch.refresh()
        #expect(watch.shown != nil)
        enabled = false
        await watch.refresh()
        #expect(watch.shown == nil)
        #expect(await source.canceled.isEmpty)
    }

    @Test("Print Center failure remains in place and a successful retry clears it")
    func openFailure() async {
        let source = Source(jobs: [job()])
        var fails = true
        let watch = PrintActivity(
            source: source,
            openCenter: {
                if fails { throw PrintSourceError.unavailable }
            })
        await watch.refresh()
        await watch.openPrintCenter()
        #expect(watch.shown?.openFailed == true)
        fails = false
        await watch.openPrintCenter()
        #expect(watch.shown?.openFailed == false)
    }

    private func waitUntil(_ predicate: () async -> Bool) async throws {
        for _ in 0..<100 {
            if await predicate() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("The isolated print source did not reach its pending state")
        throw PrintSourceError.unavailable
    }

    @Test("A preview never reads or cancels the live queue or opens another application")
    func previewIsIsolated() async {
        let current = job()
        let source = Source(jobs: [current])
        var opened = false
        let watch = PrintActivity(source: source, isEnabled: { false }, openCenter: { opened = true })
        watch.bench(PrintShown(job: current))
        await watch.refresh()
        await watch.openPrintCenter()
        #expect(watch.shown?.job.id == current.id)
        #expect(await watch.cancel(expectedID: current.id))
        #expect(watch.shown == nil)
        #expect(await source.readCount == 0)
        #expect(await source.canceled.isEmpty)
        #expect(!opened)
    }

    @Test("Keyboard access follows the current queue capabilities, including pending and failed actions")
    func keyboardCapabilities() {
        var shown = PrintShown(job: job())
        #expect(PrintJobView.controls(for: shown) == [.activityFirst, .activitySecond])
        shown.cancellation = .pending
        #expect(PrintJobView.controls(for: shown) == [.activityFirst])
        shown.cancellation = .failed
        #expect(PrintJobView.controls(for: shown) == [.activityFirst, .activitySecond])
        shown.job.state = .completed
        #expect(PrintJobView.controls(for: shown) == [.activityFirst])
        shown.sourceAvailable = false
        #expect(PrintJobView.controls(for: shown) == [.activityFirst, .activitySecond])
    }

    private actor Source: PrintJobSource {
        var jobs: [PrintJob]
        var canceled: [PrintJob.ID] = []
        var readCount = 0
        var readFails = false
        var cancelFails = false
        var removeOnCancel = true
        private var holdRead = false
        private var heldRead: CheckedContinuation<[PrintJob], Never>?

        init(jobs: [PrintJob]) { self.jobs = jobs }
        var hasHeldRead: Bool { heldRead != nil }
        func setJobs(_ jobs: [PrintJob]) { self.jobs = jobs }
        func configure(readFails: Bool? = nil, cancelFails: Bool? = nil, removeOnCancel: Bool? = nil) {
            if let readFails { self.readFails = readFails }
            if let cancelFails { self.cancelFails = cancelFails }
            if let removeOnCancel { self.removeOnCancel = removeOnCancel }
        }
        func holdNextRead() { holdRead = true }
        func resumeRead() {
            let pending = heldRead
            heldRead = nil
            pending?.resume(returning: jobs)
        }
        func read(keeping id: PrintJob.ID?) async throws -> [PrintJob] {
            readCount += 1
            if readFails { throw PrintSourceError.unavailable }
            if holdRead {
                holdRead = false
                return await withCheckedContinuation { heldRead = $0 }
            }
            return jobs
        }
        func cancel(_ id: PrintJob.ID) throws -> Bool {
            canceled.append(id)
            if cancelFails { throw PrintSourceError.requestFailed }
            if removeOnCancel { jobs.removeAll { $0.id == id } }
            return true
        }
    }
}
