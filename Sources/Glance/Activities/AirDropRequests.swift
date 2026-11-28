//
//  AirDropRequests.swift
//  Glance
//
//  Created by Gaty on 25/11/2026.
//

import Foundation
import os

/// Tells when an AirDrop someone is sending waits for an answer. On macOS 27.3 nothing but macOS's
/// own AirDrop Live Activity is told of a request, and it's drawn there, so while AirDrop's Live
/// Activity is hidden (see `MenuBarDenyList`) a request must bring it back until it's answered.
/// sharingd logs every file coming in: `Receive StateMachine PreAccept START` as it asks, then
/// `PreAccept END` once it's answered, at once for a sender it accepts by itself (the user's own
/// devices), or after someone clicks for anyone else. This follows that log with `log stream`.
///
/// Hiding is only allowed while this is ready: following the log, and with sharingd still logging
/// those words, so a request is never hidden because macOS changed what it says.
@MainActor
final class AirDropRequests {
    static let shared = AirDropRequests()

    /// Called whenever `ready` or `asking` changes.
    var changed: () -> Void = {}
    /// Following sharingd's log, so a request would be seen.
    private(set) var ready = false
    /// A request waits for an answer.
    var asking: Bool { requestLog.asking(at: .now) }

    private var requestLog = RequestLog()
    private var process: Process?
    private var wanted = false
    private var attaching: Task<Void, Never>?
    private var restart: Task<Void, Never>?
    private var recheck: Task<Void, Never>?
    /// Whether sharingd still logs the words this follows, read once.
    private static var sharingdLogs: Bool?
    nonisolated static let log = Logger(subsystem: "dev.vibe.Glance", category: "airdropRequests")

    /// Starts or stops following the log. Only runs while AirDrop's Live Activity is meant to be
    /// hidden.
    func follow(_ on: Bool) {
        guard on != wanted else { return }
        wanted = on
        if on { launch() } else { end() }
    }

    private func launch() {
        guard wanted, process == nil else { return }
        if Self.sharingdLogs == nil { Self.sharingdLogs = Self.sharingdHasWords() }
        guard Self.sharingdLogs == true else {
            Self.log.notice("sharingd no longer logs its AirDrop requests: AirDrop's Live Activity stays")
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = ["stream", "--style", "ndjson", "--predicate", Self.predicate]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        let buffer = LineBuffer()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            let entries = buffer.lines(adding: chunk).compactMap(Self.entry)
            guard !entries.isEmpty else { return }
            // In order: a request's end must never be read before its start.
            DispatchQueue.main.async { MainActor.assumeIsolated { AirDropRequests.shared.read(entries) } }
        }
        process.terminationHandler = { _ in
            pipe.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async { MainActor.assumeIsolated { AirDropRequests.shared.ended() } }
        }
        do {
            try process.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            scheduleRestart()
            return
        }
        self.process = process
        // A moment for log to attach before a request would count as seen.
        attaching = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, !Task.isCancelled, self.process === process, process.isRunning else { return }
            self.set(ready: true)
        }
    }

    private func end() {
        attaching?.cancel()
        restart?.cancel()
        recheck?.cancel()
        let process = self.process
        self.process = nil
        process?.terminate()
        requestLog = RequestLog()
        set(ready: false)
    }

    /// log stopped on its own: nothing is followed until it's back.
    private func ended() {
        guard process?.isRunning != true else { return }
        process = nil
        set(ready: false)
        scheduleRestart()
    }

    private func scheduleRestart() {
        guard wanted else { return }
        restart?.cancel()
        restart = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.launch()
        }
    }

    private func set(ready: Bool) {
        guard ready != self.ready else { return }
        self.ready = ready
        Self.log.notice("Following AirDrop requests: \(ready, privacy: .public)")
        changed()
    }

    private func read(_ entries: [(format: String, transfer: String)]) {
        let before = asking
        for entry in entries {
            requestLog.read(entry.format, transfer: entry.transfer, at: .now)
            if entry.format.hasPrefix(Self.askStarted) || entry.format.hasPrefix(Self.askEnded) {
                Self.log.notice("\(entry.transfer, privacy: .public): \(entry.format, privacy: .public)")
            }
        }
        if asking != before { changed() }
        // A request not answered within the grace starts asking then.
        recheck?.cancel()
        guard requestLog.waiting else { return }
        recheck = Task { [weak self] in
            try? await Task.sleep(for: .seconds(RequestLog.grace + 0.05))
            guard let self, !Task.isCancelled else { return }
            if self.asking != before {
                Self.log.notice("An AirDrop request waits for an answer: macOS's AirDrop shows")
                self.changed()
            }
        }
    }

    /// Glance is quitting.
    func stop() {
        wanted = false
        end()
    }

    nonisolated static let predicate =
        #"process == "sharingd" AND (eventMessage BEGINSWITH "Receive StateMachine" OR eventMessage BEGINSWITH "Monitoring Transfer")"#
    nonisolated static let askStarted = "Receive StateMachine PreAccept START"
    nonisolated static let askEnded = "Receive StateMachine PreAccept END"

    /// A log line's words, and which transfer it's about.
    nonisolated static func entry(_ line: Data) -> (format: String, transfer: String)? {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
            let format = (object["formatString"] as? String) ?? (object["eventMessage"] as? String)
        else { return nil }
        return (format, object["category"] as? String ?? "")
    }

    nonisolated private static func sharingdHasWords() -> Bool {
        guard let binary = try? Data(contentsOf: URL(fileURLWithPath: "/usr/libexec/sharingd"), options: .alwaysMapped) else { return false }
        return [askStarted, askEnded].allSatisfy { binary.range(of: Data($0.utf8)) != nil }
    }

    /// Bytes from log, read off the main thread, cut into lines.
    private final class LineBuffer: @unchecked Sendable {
        private var pending = Data()
        func lines(adding chunk: Data) -> [Data] {
            pending.append(chunk)
            var lines: [Data] = []
            while let end = pending.firstIndex(of: 0x0A) {
                lines.append(Data(pending[pending.startIndex..<end]))
                pending.removeSubrange(pending.startIndex...end)
            }
            return lines
        }
    }

    /// What sharingd's log says of the files coming in, by transfer.
    struct RequestLog {
        /// How long a request goes unanswered before it counts as asking: one accepted by itself
        /// ends within milliseconds, so it never brings macOS's Live Activity back.
        nonisolated static let grace: TimeInterval = 0.3
        /// Past this, a request whose end was never logged no longer counts.
        nonisolated static let limit: TimeInterval = 10 * 60
        private var started: [String: Date] = [:]

        /// A request has started and hasn't ended.
        var waiting: Bool { !started.isEmpty }

        mutating func read(_ format: String, transfer: String, at time: Date) {
            started = started.filter { time.timeIntervalSince($0.value) < Self.limit }
            if format.hasPrefix(AirDropRequests.askStarted) {
                started[transfer] = time
            } else {
                // The answer, or any later step: the request is over.
                started[transfer] = nil
            }
        }

        func asking(at time: Date) -> Bool {
            started.values.contains {
                let age = time.timeIntervalSince($0)
                return age >= Self.grace && age < Self.limit
            }
        }
    }
}
