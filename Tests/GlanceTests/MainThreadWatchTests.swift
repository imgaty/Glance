//
//  MainThreadWatchTests.swift
//  GlanceTests
//
//  Created by Gaty on 08/11/2026.
//

import Foundation
import Testing

@testable import Glance

/// How long the main thread has gone without answering, which stops a frozen Glance.
@Suite("Main thread watch", .serialized)
@MainActor
struct MainThreadWatchTests {
    @Test("Silence counts while the main thread is busy, and ends once it answers")
    func silence() async throws {
        let watch = MainThreadWatch()
        watch.ask()
        // The main thread held, as when frozen: the question waits.
        Thread.sleep(forTimeInterval: 1.2)
        #expect(watch.silent >= 1.1)
        // Free again, it answers, as soon as the main thread gets to it.
        for _ in 0..<40 where watch.silent >= 0.5 { try await Task.sleep(for: .milliseconds(50)) }
        #expect(watch.silent < 0.5)
    }
}
