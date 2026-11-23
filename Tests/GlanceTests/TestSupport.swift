//
//  TestSupport.swift
//  GlanceTests
//
//  Created by Gaty on 10/10/2026.
//

import AppKit
import Testing

/// What `settle` throws when what it waited for never happened.
struct SettleTimeout: Error {}

/// Waits for `condition` to hold, looking every few milliseconds on the caller's actor, for up to
/// `timeout`. If it never does, it records an issue at the caller, saying `comment`, and throws,
/// so the test stops there. A busy Mac only makes it wait longer, where a fixed sleep fails as
/// soon as other work pushes the awaited moment past it. To check that a delay was kept, compare
/// the time it took with the delay afterwards: a delayed task never finishes early, however late
/// it starts.
func settle(
    _ comment: Comment? = nil,
    timeout: Duration = .seconds(5),
    isolation: isolated (any Actor)? = #isolation,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ condition: () -> Bool
) async throws {
    guard await eventually(timeout: timeout, condition) else {
        Issue.record(comment ?? "Waited \(timeout) and it never came true", sourceLocation: sourceLocation)
        throw SettleTimeout()
    }
}

/// Whether `condition` comes to hold within `timeout`, looking as `settle` does; for `#expect`.
func eventually(
    timeout: Duration = .seconds(5),
    isolation: isolated (any Actor)? = #isolation,
    _ condition: () -> Bool
) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        guard ContinuousClock.now < deadline else { return false }
        do { try await Task.sleep(for: .milliseconds(5)) } catch { return condition() }
    }
    return true
}

/// AppKit sends a menu item's action through `NSApp`, which stays nil until something asks for
/// `NSApplication.shared`: until then `performActionForItem(at:)` does nothing at all. Other
/// suites usually create it first, so a suite that presses menu items makes sure of it itself.
@MainActor
func appKitApplication() {
    _ = NSApplication.shared
}

/// Whether two numbers are equal but for floating-point rounding.
func isClose(_ a: Double, _ b: Double, tolerance: Double = 1e-9) -> Bool {
    abs(a - b) <= tolerance
}

func isClose(_ a: CGFloat, _ b: CGFloat, tolerance: CGFloat = 1e-9) -> Bool {
    abs(a - b) <= tolerance
}

/// Runs `body` with the given keys of the standard defaults as they are, then puts back whatever
/// they held before, so tests don't leave settings behind.
func preservingDefaults<T>(_ keys: [String], _ body: () throws -> T) rethrows -> T {
    let defaults = UserDefaults.standard
    let saved = keys.map { defaults.object(forKey: $0) }
    defer {
        for (key, value) in zip(keys, saved) {
            if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
    }
    return try body()
}
