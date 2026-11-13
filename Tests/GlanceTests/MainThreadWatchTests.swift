//
//  MainThreadWatchTests.swift
//  GlanceTests
//
//  Created by Gaty on 08/11/2026.
//

import AppKit
import Testing

@testable import Glance

/// How long the main thread has gone without answering, which stops a frozen Glance.
@Suite("Main thread watch", .serialized)
@MainActor
struct MainThreadWatchTests {
    @Test("Responsive menu and modal loops answer even while a main-queue task is open", arguments: [RunLoop.Mode.eventTracking, .modalPanel])
    func menuTracking(mode: RunLoop.Mode) async {
        _ = NSApplication.shared
        let watch = MainThreadWatch()
        let silence = await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                // A menu can run this nested loop without returning from its caller.
                let timer = Timer(timeInterval: 0.05, repeats: true) { _ in watch.ask() }
                RunLoop.current.add(timer, forMode: mode)
                let end = Date.now.addingTimeInterval(0.8)
                while Date.now < end { RunLoop.current.run(mode: mode, before: end) }
                timer.invalidate()
                continuation.resume(returning: watch.silent)
            }
        }
        #expect(silence < 0.4)
    }

    @Test("Silence counts while the main thread is busy, and ends once it answers")
    func silence() async throws {
        let watch = MainThreadWatch()
        watch.ask()
        // The main thread held, as when frozen: the question waits.
        stallMainThread()
        #expect(watch.silent >= 1.1)
        // Free again, it answers, as soon as the main thread gets to it.
        for _ in 0..<40 where watch.silent >= 0.5 { try await Task.sleep(for: .milliseconds(50)) }
        #expect(watch.silent < 0.5)
    }

    /// Deliberately block rather than suspend: the watchdog must detect a thread that cannot run.
    private func stallMainThread() { Thread.sleep(forTimeInterval: 1.2) }

}
