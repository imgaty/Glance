//
//  TrayActionsTests.swift
//  GlanceTests
//
//  Created by Gaty on 15/10/2026.
//

import AppKit
import Foundation
import Testing

@testable import Glance

/// What can be done with what's in the tray: keeping a copy, pasting only its words, choosing an
/// item by typing its name, opening it with another app, apps whose copies are never kept, and the
/// Services menu's way in.
@MainActor
@Suite("Tray actions", .serialized)
struct TrayActionsTests {
    private func pasteboard(_ fill: (NSPasteboard) -> Void = { _ in }) -> NSPasteboard {
        let pasteboard = NSPasteboard(name: .init("dev.vibe.Glance.tests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        fill(pasteboard)
        return pasteboard
    }

    private func folder() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "GlanceTray-\(UUID().uuidString)")
    }

    private func copy(_ text: String, into tray: Tray, now: Date = .now) throws {
        tray.add(try #require(TrayCapture.make(from: pasteboard { $0.setString(text, forType: .string) }, kept: false, now: now)))
    }

    private func titles(_ items: [TrayItem], in tray: Tray) -> [String] {
        TrayMenu(items: items, tray: tray, anchor: nil).menu.items.map(\.title)
    }

    @Test("A copy kept stays past its time, and still after a restart; let go, it has its full time again")
    func keep() throws {
        try preservingDefaults([Preferences.trayClipboardKeep]) {
            UserDefaults.standard.set(ClipboardKeep.eightHours.rawValue, forKey: Preferences.trayClipboardKeep)
            try keepFor8Hours()
        }
    }

    private func keepFor8Hours() throws {
        let folder = folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let tray = Tray(folder: folder, pasteboard: pasteboard())
        let then = Date.now - 3 * 86400
        try copy("Keep me", into: tray, now: then)
        let id = tray.items[0].id
        tray.keep([id])
        #expect(tray.items[0].keptCopy)
        #expect(tray.items[0].origin == .copied)
        tray.purge(now: .now)
        #expect(tray.items.map(\.id) == [id])
        #expect(Tray(folder: folder, pasteboard: pasteboard()).items[0].keptCopy)
        tray.keep([id], false)
        #expect(!tray.items[0].kept)
        // Copied three days ago, but let go of just now: kept as long as any copy, from now.
        tray.purge(now: .now + 3600)
        #expect(tray.items.map(\.id) == [id])
        tray.purge(now: .now + 9 * 3600)
        #expect(tray.items.isEmpty)
    }

    @Test("What's dropped is always kept, and has nothing to keep or let go of")
    func keepDropped() throws {
        let tray = Tray(folder: folder(), pasteboard: pasteboard())
        #expect(tray.drop(pasteboard { $0.setString("Dropped", forType: .string) }))
        let dropped = tray.items[0]
        tray.keep([dropped.id], false)
        #expect(tray.items[0].kept)
        #expect(!tray.items[0].keptCopy)
        #expect(!titles([dropped], in: tray).contains { $0.hasPrefix("Keep") || $0.hasPrefix("Don't Keep") })
    }

    @Test("The menu keeps copies, or lets go of them once they're all kept")
    func keepMenu() throws {
        let tray = Tray(folder: folder(), pasteboard: pasteboard())
        try copy("one", into: tray)
        try copy("two", into: tray)
        #expect(titles([tray.items[0]], in: tray).contains("Keep"))
        #expect(titles(tray.items, in: tray).contains("Keep 2 Items"))
        tray.keep([tray.items[0].id])
        // One of the two still goes in time: both can be kept.
        #expect(titles(tray.items, in: tray).contains("Keep 2 Items"))
        #expect(titles([tray.items[0]], in: tray).contains("Don't Keep"))
    }

    @Test("A copy that's kept, copied again, stays kept")
    func keepAgain() throws {
        let tray = Tray(folder: folder(), pasteboard: pasteboard())
        try copy("again", into: tray)
        tray.keep([tray.items[0].id])
        try copy("again", into: tray)
        #expect(tray.items.count == 1)
        #expect(tray.items[0].keptCopy)
    }

    @Test("Paste and Match Style puts only the words on the clipboard, without their style")
    func plain() throws {
        let target = pasteboard()
        let tray = Tray(folder: folder(), pasteboard: target)
        tray.add(
            try #require(
                TrayCapture.make(
                    from: pasteboard {
                        $0.setString("Bold words", forType: .string)
                        $0.setData(Data("{\\rtf1 \\b Bold words}".utf8), forType: .rtf)
                    }, kept: false)))
        tray.copy(tray.items, plain: true)
        #expect(target.string(forType: .string) == "Bold words")
        #expect(target.data(forType: .rtf) == nil)
        tray.copy(tray.items)
        #expect(target.data(forType: .rtf) != nil)
        #expect(tray.items.count == 1)
    }

    @Test("Typing a name chooses the first item it starts, whatever the case or accents")
    func typeToChoose() throws {
        let tray = Tray(folder: folder(), pasteboard: pasteboard())
        for text in ["Résumé notes", "Groceries", "https://www.apple.com/macos/", "Grape jam"] { try copy(text, into: tray) }
        // Newest first: Grape jam, apple.com, Groceries, Résumé notes.
        #expect(tray.first(named: "gr") == tray.items[0].id)
        #expect(tray.first(named: "gro") == tray.items[2].id)
        #expect(tray.first(named: "resume") == tray.items[3].id)
        #expect(tray.first(named: "APPLE") == tray.items[1].id)
        #expect(tray.first(named: "zebra") == nil)
    }

    @Test("Apps chosen in Settings are remembered, each once, and can be taken off again")
    func ignoredApps() {
        preservingDefaults([Preferences.trayIgnoredApps]) {
            UserDefaults.standard.removeObject(forKey: Preferences.trayIgnoredApps)
            #expect(!TrayApps.ignores("com.apple.Terminal"))
            #expect(!TrayApps.ignores(nil))
            TrayApps.add("com.apple.Terminal")
            TrayApps.add("com.apple.Notes")
            TrayApps.add("com.apple.Terminal")
            #expect(TrayApps.ignored == ["com.apple.Notes", "com.apple.Terminal"])
            #expect(TrayApps.ignores("com.apple.Terminal"))
            TrayApps.remove("com.apple.Terminal")
            #expect(TrayApps.ignored == ["com.apple.Notes"])
            #expect(!TrayApps.ignores("com.apple.Terminal"))
        }
    }

    @Test("Open With lists the app a file opens in first, then others, then any app")
    func openWith() throws {
        let place = folder()
        try FileManager.default.createDirectory(at: place, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: place) }
        let file = place.appending(path: "Note.txt")
        try Data("Hello".utf8).write(to: file)
        let tray = Tray(folder: folder(), pasteboard: pasteboard())
        #expect(tray.drop(pasteboard { $0.writeObjects([file as NSURL]) }))
        let menu = TrayMenu(items: tray.items, tray: tray, anchor: nil).menu
        let apps = try #require(menu.item(withTitle: "Open With")?.submenu)
        #expect(apps.items.first?.title.hasSuffix(" (default)") == true)
        #expect(apps.items.last?.title == "Other…")
        #expect(!apps.items.contains { $0.title.hasPrefix("Glance") })
        // Text has nothing to open; Open and Open With are for one item.
        try copy("Words", into: tray)
        #expect(TrayMenu(items: [tray.items[0]], tray: tray, anchor: nil).menu.item(withTitle: "Open With") == nil)
        #expect(TrayMenu(items: tray.items, tray: tray, anchor: nil).menu.item(withTitle: "Open With") == nil)
    }

    @Test("Add to Glance Tray in the Services menu keeps what's chosen, as if it were dropped")
    func service() {
        preservingDefaults([Preferences.tray]) {
            let tray = Tray(folder: folder(), pasteboard: pasteboard())
            let service = TrayService(tray: tray)
            var error: NSString?
            UserDefaults.standard.set(false, forKey: Preferences.tray)
            service.addToTray(pasteboard { $0.setString("Off", forType: .string) }, userData: nil, error: &error)
            #expect(tray.items.isEmpty)
            #expect(error != nil)
            error = nil
            UserDefaults.standard.set(true, forKey: Preferences.tray)
            service.addToTray(pasteboard { $0.setString("Chosen words", forType: .string) }, userData: nil, error: &error)
            #expect(error == nil)
            #expect(tray.items.first?.text == "Chosen words")
            #expect(tray.items.first?.origin == .dropped)
        }
    }

    @Test("The Services entry names the method that takes it, and is on from the start")
    func serviceEntry() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let plist = try #require(NSDictionary(contentsOf: root.appending(path: "Resources/Info.plist")))
        let services = try #require(plist["NSServices"] as? [[String: Any]])
        let entry = try #require(services.first)
        let message = try #require(entry["NSMessage"] as? String)
        #expect(TrayService.instancesRespond(to: NSSelectorFromString(message + ":userData:error:")))
        #expect(entry["NSPortName"] as? String == plist["CFBundleName"] as? String)
        // Without a context, macOS lists a new service turned off.
        #expect(entry["NSRequiredContext"] != nil)
        #expect((entry["NSMenuItem"] as? [String: String])?["default"] == "Add to Glance Tray")
    }
}
