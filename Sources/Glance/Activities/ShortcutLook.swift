//
//  ShortcutLook.swift
//  Glance
//
//  Created by Gaty on 17/11/2026.
//

import AppKit
import SwiftUI

/// A shortcut's own look, as Shortcuts draws it and as the iPhone's Dynamic Island shows a shortcut
/// running: its color, which the ring takes, and its icon, the rounded square with its glyph. Either
/// may be missing; then the run shows in white with Shortcuts' layers.
struct ShortcutLook: Equatable {
    var color: NSColor?
    var icon: NSImage?

    var tint: Color? { color.map { Color(nsColor: $0) } }

    static func == (a: ShortcutLook, b: ShortcutLook) -> Bool { a.color == b.color && a.icon === b.icon }

    /// For Settings and the activity bench: one of Shortcuts' own colors, no icon.
    static let fixture = ShortcutLook(color: NSColor(srgbRed: 0x52 / 255, green: 0x9B / 255, blue: 0x6E / 255, alpha: 1))
}

/// Each shortcut's look, read once from Shortcuts through its scripting (`Shortcuts Events`), which
/// macOS asks the user to allow the first time. Read off the main thread, as Shortcuts Events may
/// take a moment to start. A shortcut that can't be read, or a refusal, isn't asked about again
/// until Glance next starts.
@MainActor
final class ShortcutLooks {
    static let shared = ShortcutLooks()

    private var known: [UUID: ShortcutLook] = [:]
    private var asked: Set<UUID> = []
    private let queue = DispatchQueue(label: "Glance.ShortcutLooks", qos: .utility)

    func look(for id: UUID) -> ShortcutLook? { known[id] }

    /// Reads the shortcut's look if it hasn't been, then calls back on the main actor.
    func load(_ id: UUID, then: @escaping @MainActor () -> Void) {
        guard !asked.contains(id) else { return }
        asked.insert(id)
        queue.async {
            let read = Self.read(id)
            Task { @MainActor in
                guard let read else { return }
                self.known[id] = ShortcutLook(
                    color: read.color.map { NSColor(srgbRed: $0.0, green: $0.1, blue: $0.2, alpha: 1) },
                    icon: read.icon.flatMap(NSImage.init(data:)))
                then()
            }
        }
    }

    private struct Read: Sendable {
        var color: (CGFloat, CGFloat, CGFloat)?
        var icon: Data?
    }

    nonisolated private static func read(_ id: UUID) -> Read? {
        let source = """
            tell application "Shortcuts Events"
                set found to shortcut id "\(id.uuidString)"
                return {color of found, icon of found}
            end tell
            """
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        guard error == nil, result.numberOfItems == 2 else { return nil }
        var read = Read()
        if let color = result.atIndex(1), color.numberOfItems == 3 {
            let parts = (1...3).compactMap { color.atIndex($0)?.int32Value }.map { CGFloat($0) / 65535 }
            if parts.count == 3 { read.color = (parts[0], parts[1], parts[2]) }
        }
        if let icon = result.atIndex(2)?.data, !icon.isEmpty { read.icon = icon }
        return read.color == nil && read.icon == nil ? nil : read
    }
}
