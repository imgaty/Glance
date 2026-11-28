//
//  AirDropRequestsTests.swift
//  GlanceTests
//
//  Created by Gaty on 25/11/2026.
//

import Foundation
import Testing

@testable import Glance

@Suite("AirDrop requests read from sharingd's log")
struct AirDropRequestsTests {
    private typealias Log = AirDropRequests.RequestLog
    private static let start = Date(timeIntervalSince1970: 1000)
    private static let ended = "Receive StateMachine PreAccept END {response: %s, transfer.state: %s}"

    @Test("A file from the user's own devices, accepted by itself, never counts as asking")
    func autoAccepted() {
        var log = Log()
        log.read(AirDropRequests.askStarted, transfer: "AirDrop.9B539820", at: Self.start)
        log.read(Self.ended, transfer: "AirDrop.9B539820", at: Self.start + 0.003)
        #expect(!log.waiting)
        #expect(!log.asking(at: Self.start + 1))
    }

    @Test("A request left unanswered asks once the grace is over, until it's answered")
    func unanswered() {
        var log = Log()
        log.read(AirDropRequests.askStarted, transfer: "AirDrop.1", at: Self.start)
        #expect(log.waiting)
        #expect(!log.asking(at: Self.start + Log.grace / 2))
        #expect(log.asking(at: Self.start + Log.grace + 0.01))
        #expect(log.asking(at: Self.start + 60))
        log.read(Self.ended, transfer: "AirDrop.1", at: Self.start + 61)
        #expect(!log.asking(at: Self.start + 62))
    }

    @Test("Any later step of the same transfer ends its request; another transfer's doesn't")
    func byTransfer() {
        var log = Log()
        log.read(AirDropRequests.askStarted, transfer: "AirDrop.1", at: Self.start)
        log.read(AirDropRequests.askStarted, transfer: "AirDrop.2", at: Self.start)
        log.read("Monitoring Transfer END - Cancelled.", transfer: "AirDrop.1", at: Self.start + 5)
        #expect(log.asking(at: Self.start + 6))
        log.read("Receive StateMachine Linger END", transfer: "AirDrop.2", at: Self.start + 7)
        #expect(!log.asking(at: Self.start + 8))
    }

    @Test("A request whose end was never logged stops counting after the limit")
    func limit() {
        var log = Log()
        log.read(AirDropRequests.askStarted, transfer: "AirDrop.1", at: Self.start)
        #expect(!log.asking(at: Self.start + Log.limit))
        log.read("Monitoring Transfer START", transfer: "AirDrop.9", at: Self.start + Log.limit + 1)
        #expect(!log.waiting)
    }

    @Test("Each line log prints gives its words, unaffected by what's private, and its transfer")
    func lines() throws {
        // As log stream --style ndjson printed it for a real AirDrop, trimmed of unused fields.
        let line = #"{"timezoneName":"","messageType":"Default","eventType":"logEvent","formatString":"Receive StateMachine PreAccept END {response: %s, transfer.state: %s}","subsystem":"com.apple.sharing","category":"AirDrop.9B539820","processImagePath":"\/usr\/libexec\/sharingd","eventMessage":"Receive StateMachine PreAccept END {response: <private>, transfer.state: <private>}"}"#
        let entry = try #require(AirDropRequests.entry(Data(line.utf8)))
        #expect(entry.format.hasPrefix(AirDropRequests.askEnded))
        #expect(entry.transfer == "AirDrop.9B539820")
        #expect(AirDropRequests.entry(Data(#"Filtering the log data using "process == \"sharingd\"""#.utf8)) == nil)
    }

    @Test("AirDrop's is hidden only while requests would be seen and none waits for an answer")
    func hidingRule() {
        #expect(MenuBarDenyList.hides(wanted: true, requestsSeen: true, asking: false))
        #expect(!MenuBarDenyList.hides(wanted: true, requestsSeen: true, asking: true))
        #expect(!MenuBarDenyList.hides(wanted: true, requestsSeen: false, asking: false))
        #expect(!MenuBarDenyList.hides(wanted: false, requestsSeen: true, asking: false))
    }
}
