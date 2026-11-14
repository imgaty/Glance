//
//  PrintActivity.swift
//  Glance
//
//  Created by Gaty on 14/11/2026.
//

import AppKit
import CUPS
import Darwin

/// A job in this Mac's print queue. The creation time distinguishes a reused queue identifier.
struct PrintJob: Equatable, Sendable, Identifiable {
    struct ID: Hashable, Sendable {
        let printer: String
        let number: Int32
        let created: Int64

        var isSpecific: Bool { number > 0 && created > 0 && !printer.isEmpty }
    }

    enum State: Int32, Sendable {
        case queued = 3, held, printing, stopped, canceled, failed, completed

        var isActive: Bool { [.queued, .held, .printing, .stopped].contains(self) }

        var title: String {
            switch self {
            case .queued: String(localized: "Waiting to Print")
            case .held: String(localized: "Print Job on Hold")
            case .printing: String(localized: "Printing")
            case .stopped: String(localized: "Printing Stopped")
            case .canceled: String(localized: "Print Job Canceled")
            case .failed: String(localized: "Printing Failed")
            case .completed: String(localized: "Printing Complete")
            }
        }
    }

    /// Counts from IPP, never inferred from elapsed time or file size.
    struct Progress: Equatable, Sendable {
        let completed: Int
        let total: Int

        init?(completed: Int, total: Int) {
            guard total > 0, completed >= 0, completed <= total else { return nil }
            self.completed = completed
            self.total = total
        }

        var fraction: Double { Double(completed) / Double(total) }
    }

    let id: ID
    let title: String
    let owner: String
    var state: State
    var progress: Progress?
    var printerName: String?

    var canCancel: Bool { id.isSpecific && state.isActive }
    var displayPrinter: String { printerName ?? id.printer }
    var spoken: String { "\(title), \(displayPrinter), \(state.title)" }

    static func fromQueue(number: Int32, printer: String?, title: String?, owner: String?, state: Int32, created: Int64, currentUser: String) -> PrintJob? {
        guard number > 0, let printer, !printer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            let owner, !currentUser.isEmpty, owner == currentUser,
            let state = State(rawValue: state), state.isActive
        else { return nil }
        let words = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        return PrintJob(
            id: .init(printer: printer, number: number, created: created),
            title: words.flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: "Print Job"), owner: owner, state: state)
    }

    /// Keep the job being read or acted on. Arrival order is deterministic across CUPS snapshots.
    static func selected(in jobs: [PrintJob], keeping id: ID?) -> PrintJob? {
        let active = jobs.filter { $0.state.isActive }
        if let id, let kept = active.first(where: { $0.id == id }) { return kept }
        return active.sorted {
            if $0.state == .printing, $1.state != .printing { return true }
            if $1.state == .printing, $0.state != .printing { return false }
            if $0.id.created != $1.id.created { return $0.id.created < $1.id.created }
            if $0.id.number != $1.id.number { return $0.id.number < $1.id.number }
            return $0.id.printer < $1.id.printer
        }.first
    }
}

struct PrintShown: Equatable {
    enum Cancellation: Equatable { case idle, pending, unconfirmed, failed }

    var job: PrintJob
    var additionalJobs = 0
    var sourceAvailable = true
    var cancellation = Cancellation.idle
    var openFailed = false

    var canCancel: Bool { sourceAvailable && job.canCancel && cancellation != .pending }
    var canRetryCancellation: Bool { cancellation == .failed || cancellation == .unconfirmed }

    var status: String {
        if cancellation == .unconfirmed { return String(localized: "Unable to Confirm Cancellation") }
        if !sourceAvailable { return String(localized: "Print Status Unavailable") }
        if cancellation == .pending { return String(localized: "Canceling Print Job…") }
        if cancellation == .failed { return String(localized: "Couldn't Cancel Print Job") }
        if openFailed { return String(localized: "Couldn't Open Print Center") }
        return job.state.title
    }

    var spoken: String { "\(job.title), \(job.displayPrinter), \(status)" }
}

protocol PrintJobSource: Sendable {
    func read(keeping id: PrintJob.ID?) async throws -> [PrintJob]
    /// False means the exact job has already left or is no longer cancelable; nothing was sent.
    func cancel(_ id: PrintJob.ID) async throws -> Bool
}

enum PrintSourceError: Error { case unavailable, requestFailed }

/// Blocking CUPS calls run on this actor, never on the main actor. Only the local spooler is used;
/// remote printers remain represented by their local queues, as in Print Center.
actor CUPSPrintSource: PrintJobSource {
    private let owner = NSUserName()

    func read(keeping id: PrintJob.ID?) throws -> [PrintJob] {
        let connection = try connect()
        defer { httpClose(connection) }
        var jobs = try activeJobs(connection)
        if let selected = PrintJob.selected(in: jobs, keeping: id), let index = jobs.firstIndex(where: { $0.id == selected.id }) {
            jobs[index].progress = progress(for: selected.id, connection: connection)
            jobs[index].printerName = printerName(selected.id.printer, connection: connection)
        }
        return jobs
    }

    func cancel(_ id: PrintJob.ID) throws -> Bool {
        guard id.isSpecific else { return false }
        let connection = try connect()
        defer { httpClose(connection) }
        // A captured button cannot cancel a different printer, another owner's job, or a reused ID.
        guard try activeJobs(connection).contains(where: { $0.id == id && $0.canCancel }) else { return false }
        let status = id.printer.withCString { cupsCancelJob2(connection, $0, id.number, 0) }
        guard Self.succeeded(status) else { throw PrintSourceError.requestFailed }
        return true
    }

    private func connect() throws -> OpaquePointer {
        // Background reads and cancellation don't request credentials. Print Center handles any
        // authentication the queue needs. CUPS stores this callback in its thread-local context.
        cupsSetPasswordCB2({ _, _, _, _, _ in nil }, nil)
        guard let connection = httpConnect2("localhost", 631, nil, AF_UNSPEC, HTTP_ENCRYPTION_IF_REQUESTED, 1, 1_500, nil) else {
            throw PrintSourceError.unavailable
        }
        httpSetTimeout(connection, 2, nil, nil)
        return connection
    }

    private func activeJobs(_ connection: OpaquePointer) throws -> [PrintJob] {
        var records: UnsafeMutablePointer<cups_job_t>?
        let count = cupsGetJobs2(connection, &records, nil, 1, CUPS_WHICHJOBS_ACTIVE)
        defer { if let records { cupsFreeJobs(max(count, 0), records) } }
        guard count >= 0, Self.succeeded(cupsLastError()) else { throw PrintSourceError.unavailable }
        guard count > 0, let records else { return [] }
        return UnsafeBufferPointer(start: records, count: Int(count)).compactMap { record in
            PrintJob.fromQueue(
                number: record.id, printer: record.dest.map { String(cString: $0) }, title: record.title.map { String(cString: $0) },
                owner: record.user.map { String(cString: $0) }, state: Int32(record.state.rawValue), created: Int64(record.creation_time), currentUser: owner)
        }
    }

    private func printerName(_ name: String, connection: OpaquePointer) -> String? {
        guard let destination = cupsGetNamedDest(connection, name, nil) else { return nil }
        defer { cupsFreeDests(1, destination) }
        guard let info = cupsGetOption("printer-info", destination.pointee.num_options, destination.pointee.options) else { return nil }
        let title = String(cString: info).trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    private func progress(for id: PrintJob.ID, connection: OpaquePointer) -> PrintJob.Progress? {
        guard let request = ippNewRequest(IPP_OP_GET_JOB_ATTRIBUTES) else { return nil }
        ippAddString(request, IPP_TAG_OPERATION, IPP_TAG_URI, "job-uri", nil, "ipp://localhost/jobs/\(id.number)")
        ippAddString(request, IPP_TAG_OPERATION, IPP_TAG_NAME, "requesting-user-name", nil, owner)
        guard let response = cupsDoRequest(connection, request, "/") else { return nil }
        defer { ippDelete(response) }
        guard Self.succeeded(ippGetStatusCode(response)),
            let total = ippFindAttribute(response, "job-impressions", IPP_TAG_INTEGER),
            let completed = ippFindAttribute(response, "job-impressions-completed", IPP_TAG_INTEGER)
        else { return nil }
        return .init(completed: Int(ippGetInteger(completed, 0)), total: Int(ippGetInteger(total, 0)))
    }

    private static func succeeded(_ status: ipp_status_t) -> Bool {
        status.rawValue >= IPP_STATUS_OK.rawValue && status.rawValue < IPP_STATUS_REDIRECTION_OTHER_SITE.rawValue
    }
}

/// The current user's active print jobs. Source loss is distinct from an empty queue, and an
/// acknowledged cancellation is not presented as complete until the exact job leaves the queue.
@MainActor
final class PrintActivity: ObservableObject {
    static let shared = PrintActivity(isEnabled: { UserDefaults.standard.object(forKey: Preferences.activityPrint) as? Bool ?? true })

    @Published private(set) var shown: PrintShown?
    private let source: any PrintJobSource
    private let live: Bool
    private let isEnabled: @MainActor () -> Bool
    private let openCenter: @MainActor () async throws -> Void
    private let cancellationDelay: Duration
    private var poll: Task<Void, Never>?
    private var reading = false
    private var cancellationID: PrintJob.ID?
    private var generation = 0
    private var benched = false

    init(
        source: any PrintJobSource = CUPSPrintSource(),
        isEnabled: @escaping @MainActor () -> Bool = { true },
        cancellationDelay: Duration = .milliseconds(250),
        openCenter: @escaping @MainActor () async throws -> Void = {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.printcenter") else {
                throw PrintSourceError.unavailable
            }
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    ) {
        self.source = source
        self.live = source is CUPSPrintSource
        self.isEnabled = isEnabled
        self.cancellationDelay = cancellationDelay
        self.openCenter = openCenter
    }

    func start() {
        guard poll == nil else { return }
        poll = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stop() {
        poll?.cancel()
        poll = nil
        generation += 1
        cancellationID = nil
        shown = nil
    }

    func refresh() async {
        if benched {
            shown?.sourceAvailable = true
            return
        }
        guard !live || ActivityBench.scene == nil else { return }
        guard isEnabled() else {
            generation += 1
            cancellationID = nil
            shown = nil
            return
        }
        guard !reading, cancellationID == nil else { return }
        reading = true
        let request = generation
        defer { reading = false }
        do {
            let jobs = try await source.read(keeping: shown?.job.id)
            guard request == generation, isEnabled(), !Task.isCancelled else { return }
            apply(jobs)
        } catch {
            guard request == generation, isEnabled(), !Task.isCancelled else { return }
            shown?.sourceAvailable = false
        }
    }

    @discardableResult
    func cancel(expectedID: PrintJob.ID) async -> Bool {
        guard benched || isEnabled(), cancellationID == nil, let current = shown,
            current.job.id == expectedID, current.canCancel
        else { return false }
        if benched {
            shown = nil
            ActivityBench.shared.stopped(.printing)
            return true
        }
        guard !live || ActivityBench.scene == nil else { return false }
        generation += 1
        let request = generation
        cancellationID = expectedID
        // An earlier accepted request remains uncertain even if a later retry is rejected.
        var acknowledged = current.cancellation == .unconfirmed
        var readingQueue = true
        shown?.cancellation = .pending
        defer {
            if generation == request, cancellationID == expectedID {
                cancellationID = nil
                if shown?.job.id == expectedID, shown?.cancellation == .pending {
                    shown?.cancellation = acknowledged ? .unconfirmed : .idle
                }
            }
        }

        do {
            let before = try await source.read(keeping: expectedID)
            guard request == generation, isEnabled(), !Task.isCancelled else { return false }
            guard before.contains(where: { $0.id == expectedID && $0.canCancel }) else {
                apply(before)
                return false
            }
            readingQueue = false
            let accepted = try await source.cancel(expectedID)
            acknowledged = acknowledged || accepted
            guard request == generation, isEnabled(), !Task.isCancelled else { return false }
            readingQueue = true
            for attempt in 0..<(accepted ? 8 : 1) {
                let jobs = try await source.read(keeping: expectedID)
                guard request == generation, isEnabled(), !Task.isCancelled else { return false }
                apply(jobs)
                if !jobs.contains(where: { $0.id == expectedID && $0.state.isActive }) { return accepted }
                if attempt < 7, accepted { try await Task.sleep(for: cancellationDelay) }
            }
            if shown?.job.id == expectedID { shown?.cancellation = acknowledged ? .unconfirmed : .failed }
            return false
        } catch {
            guard request == generation, isEnabled(), !Task.isCancelled else { return false }
            if shown?.job.id == expectedID {
                shown?.cancellation = acknowledged ? .unconfirmed : .failed
                if readingQueue { shown?.sourceAvailable = false }
            }
            return false
        }
    }

    func openPrintCenter() async {
        if benched {
            shown?.openFailed = false
            return
        }
        guard !live || ActivityBench.scene == nil else { return }
        let id = shown?.job.id
        do {
            try await openCenter()
            if shown?.job.id == id { shown?.openFailed = false }
        } catch {
            if shown?.job.id == id { shown?.openFailed = true }
        }
    }

    /// Source-build scenes are isolated from the queue and from real application launches.
    func bench(_ value: PrintShown?) {
        poll?.cancel()
        poll = nil
        generation += 1
        cancellationID = nil
        benched = true
        shown = value
    }

    private func apply(_ jobs: [PrintJob]) {
        let previous = shown
        guard let job = PrintJob.selected(in: jobs, keeping: previous?.job.id) else {
            shown = nil
            return
        }
        shown = PrintShown(
            job: job, additionalJobs: jobs.filter { $0.state.isActive && $0.id != job.id }.count,
            cancellation: previous?.job.id == job.id ? previous?.cancellation ?? .idle : .idle,
            openFailed: previous?.job.id == job.id && previous?.openFailed == true)
    }
}
