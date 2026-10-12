//
//  TrayTests.swift
//  GlanceTests
//
//  Created by Gaty on 12/10/2026.
//

import AppKit
import Foundation
import Testing

@testable import Glance

/// The tray: what it keeps of what's copied and dropped, what it never keeps, how long copies stay,
/// and that it gives back exactly what it took.
@MainActor
@Suite("Tray", .serialized)
struct TrayTests {
    /// A pasteboard of the test's own, holding what's given.
    private func pasteboard(_ fill: (NSPasteboard) -> Void) -> NSPasteboard {
        let pasteboard = NSPasteboard(name: .init("dev.vibe.Glance.tests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        fill(pasteboard)
        return pasteboard
    }

    private func tray() -> Tray {
        Tray(folder: FileManager.default.temporaryDirectory.appending(path: "GlanceTray-\(UUID().uuidString)"), pasteboard: pasteboard { _ in })
    }

    @Test("Copied text is kept as text, with its rich version")
    func text() throws {
        let board = pasteboard {
            $0.setString("Meet at eight", forType: .string)
            $0.setData(Data("{\\rtf1 Meet at eight}".utf8), forType: .rtf)
        }
        let capture = try #require(TrayCapture.make(from: board, kept: false, app: "com.apple.Notes"))
        #expect(capture.item.kind == .text)
        #expect(capture.item.text == "Meet at eight")
        #expect(capture.item.types == [NSPasteboard.PasteboardType.string.rawValue, NSPasteboard.PasteboardType.rtf.rawValue])
        #expect(capture.item.app == "com.apple.Notes")
        #expect(!capture.item.kept)
    }

    @Test("A web address on its own is a link; with words around it, text")
    func links() throws {
        let link = try #require(TrayCapture.make(from: pasteboard { $0.setString("https://www.apple.com/macos/", forType: .string) }, kept: false))
        #expect(link.item.kind == .link)
        #expect(link.item.title == "apple.com")
        let sentence = try #require(TrayCapture.make(from: pasteboard { $0.setString("see https://apple.com", forType: .string) }, kept: false))
        #expect(sentence.item.kind == .text)
        #expect(!TrayCapture.isLink("ftp://example.com"))
        #expect(!TrayCapture.isLink("apple"))
    }

    @Test("Passwords and other private copies are never kept", arguments: Array(TrayCapture.privateTypes))
    func privateCopies(type: String) {
        let board = pasteboard {
            $0.setString("hunter2", forType: .string)
            $0.setData(Data(), forType: .init(type))
        }
        #expect(TrayCapture.make(from: board, kept: false) == nil)
    }

    @Test("Nothing is kept from a password manager")
    func passwordApps() {
        let board = pasteboard { $0.setString("hunter2", forType: .string) }
        #expect(TrayCapture.make(from: board, kept: false, app: "com.apple.Passwords") == nil)
    }

    @Test("Blank text isn't kept")
    func blank() {
        #expect(TrayCapture.make(from: pasteboard { $0.setString("  \n ", forType: .string) }, kept: false) == nil)
    }

    @Test("A copied picture is kept as one, named as a screenshot is")
    func image() throws {
        let png = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!.representation(using: .png, properties: [:])!
        let capture = try #require(TrayCapture.make(from: pasteboard { $0.setData(png, forType: .png) }, kept: false))
        #expect(capture.item.kind == .image)
        #expect(capture.item.files.first?.hasPrefix("Image ") == true)
        #expect(capture.item.files.first?.hasSuffix(".png") == true)
        #expect(capture.data == [png])
    }

    @Test("Copied files are kept where they are, all together")
    func files() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "GlanceTrayFiles-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let urls = ["One.txt", "Two.txt"].map { folder.appending(path: $0) }
        for url in urls { try Data("x".utf8).write(to: url) }
        let capture = try #require(TrayCapture.make(from: pasteboard { $0.writeObjects(urls as [NSURL]) }, kept: false))
        #expect(capture.item.kind == .files)
        #expect(capture.item.names == ["One.txt", "Two.txt"])
        #expect(capture.item.title == "2 Items")
        #expect(capture.data.isEmpty)
        let tray = tray()
        tray.add(capture)
        #expect(tray.urls(of: tray.items[0]).map(\.lastPathComponent) == ["One.txt", "Two.txt"])
    }

    @Test("Copying the same thing again brings it to the front instead of adding it twice")
    func again() throws {
        let tray = tray()
        let first = try #require(TrayCapture.make(from: pasteboard { $0.setString("one", forType: .string) }, kept: false))
        let second = try #require(TrayCapture.make(from: pasteboard { $0.setString("two", forType: .string) }, kept: false))
        let again = try #require(TrayCapture.make(from: pasteboard { $0.setString("one", forType: .string) }, kept: true))
        tray.add(first)
        tray.add(second)
        tray.add(again)
        #expect(tray.items.map(\.text) == ["one", "two"])
        #expect(tray.items[0].id == first.item.id)
        // Dropped once, it's kept, however it came the other time.
        #expect(tray.items[0].kept)
    }

    @Test("Copies go after the time chosen; what was dropped stays")
    func expiry() throws {
        let now = Date.now
        let copy = try #require(TrayCapture.make(from: pasteboard { $0.setString("copied", forType: .string) }, kept: false, now: now))
        let dropped = try #require(TrayCapture.make(from: pasteboard { $0.setString("dropped", forType: .string) }, kept: true, now: now))
        #expect(!copy.item.expired(at: now + 29 * 60, keep: .halfHour))
        #expect(copy.item.expired(at: now + 31 * 60, keep: .halfHour))
        #expect(!copy.item.expired(at: now + 7 * 3600, keep: .eightHours))
        #expect(copy.item.expired(at: now + 9 * 3600, keep: .eightHours))
        #expect(!copy.item.expired(at: now + 6 * 86400, keep: .week))
        #expect(!dropped.item.expired(at: now + 365 * 86400, keep: .halfHour))
    }

    @Test("Spotlight's choices for how long copies stay, stored by name")
    func keepChoices() {
        #expect(ClipboardKeep.allCases.map(\.title) == ["30 Minutes", "8 Hours", "7 Days"])
        #expect(ClipboardKeep.allCases.map(\.rawValue) == ["halfHour", "eightHours", "week"])
    }

    @Test("The tray is still there after a restart, and removing an item takes its copy with it")
    func kept() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "GlanceTray-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let tray = Tray(folder: folder, pasteboard: pasteboard { _ in })
        let capture = try #require(TrayCapture.make(from: pasteboard { $0.setString("kept", forType: .string) }, kept: true))
        tray.add(capture)
        let saved = tray.file(capture.item.files[0], of: capture.item)
        #expect(FileManager.default.fileExists(atPath: saved.path))
        let reopened = Tray(folder: folder, pasteboard: pasteboard { _ in })
        #expect(reopened.items == tray.items)
        reopened.remove(capture.item.id)
        #expect(reopened.items.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: saved.path))
    }

    @Test("Copying an item back gives exactly what was copied, and isn't kept again")
    func copyBack() throws {
        let target = pasteboard { _ in }
        let tray = Tray(folder: FileManager.default.temporaryDirectory.appending(path: "GlanceTray-\(UUID().uuidString)"), pasteboard: target)
        let rtf = Data("{\\rtf1 Hello}".utf8)
        let capture = try #require(
            TrayCapture.make(
                from: pasteboard {
                    $0.setString("Hello", forType: .string)
                    $0.setData(rtf, forType: .rtf)
                }, kept: false))
        tray.add(capture)
        tray.copy(tray.items[0])
        #expect(target.string(forType: .string) == "Hello")
        #expect(target.data(forType: .rtf) == rtf)
        #expect(tray.justCopied == capture.item.id)
        #expect(tray.items.count == 1)
    }

    @Test("Clearing removes everything")
    func clear() throws {
        let tray = tray()
        for text in ["a", "b", "c"] {
            tray.add(try #require(TrayCapture.make(from: pasteboard { $0.setString(text, forType: .string) }, kept: text == "b")))
        }
        tray.clear()
        #expect(tray.items.isEmpty)
    }

    @Test("Files dropped together are each kept on their own, first at the front, until removed")
    func droppedFiles() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "GlanceTrayDrop-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let urls = ["A.txt", "B.txt"].map { folder.appending(path: $0) }
        for url in urls { try Data("x".utf8).write(to: url) }
        let tray = tray()
        #expect(tray.drop(pasteboard { $0.writeObjects(urls as [NSURL]) }))
        #expect(tray.items.map(\.title) == ["A.txt", "B.txt"])
        #expect(tray.items.allSatisfy { $0.kept })
        #expect(!tray.items[0].expired(at: .now + 365 * 86400, keep: .halfHour))
    }

    @Test("A file moved after it was kept is followed; one that's deleted goes")
    func movedFiles() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "GlanceTrayMove-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = folder.appending(path: "Report.txt")
        try Data("x".utf8).write(to: original)
        let tray = tray()
        tray.drop(pasteboard { $0.writeObjects([original as NSURL]) })
        let moved = folder.appending(path: "Moved.txt")
        try FileManager.default.moveItem(at: original, to: moved)
        #expect(tray.urls(of: tray.items[0]).map(\.lastPathComponent) == ["Moved.txt"])
        try FileManager.default.removeItem(at: moved)
        tray.purge(checkingFiles: true)
        #expect(tray.items.isEmpty)
    }

    @Test("Dropped text is kept until removed")
    func droppedText() {
        let tray = tray()
        #expect(tray.drop(pasteboard { $0.setString("A note", forType: .string) }))
        #expect(tray.items.first?.kind == .text)
        #expect(tray.items.first?.kept == true)
    }

    @Test("Drags it can take: files, pictures, links and text")
    func accepts() {
        #expect(Tray.accepts(pasteboard { $0.setString("words", forType: .string) }))
        #expect(!Tray.accepts(pasteboard { $0.setData(Data([1]), forType: .init("com.example.private")) }))
    }

    @Test("The shelf scrolls only as far as its last tile")
    func shelf() {
        #expect(Shelf.width(count: 0) == 0)
        #expect(Shelf.width(count: 2) == Shelf.tile * 2 + Shelf.spacing + PlayerLayout.padding * 2)
        #expect(Shelf.reach(count: 2, in: 400) == 0)
        #expect(Shelf.reach(count: 10, in: 400) == Shelf.width(count: 10) - 400)
    }
}
