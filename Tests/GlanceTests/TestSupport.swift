//
//  TestSupport.swift
//  GlanceTests
//
//  Created by Gaty on 10/10/2026.
//

import AppKit

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
