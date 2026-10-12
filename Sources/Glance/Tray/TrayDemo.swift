//
//  TrayDemo.swift
//  Glance
//
//  Created by Gaty on 12/10/2026.
//

import AppKit
import ImageIO
import UniformTypeIdentifiers

extension Tray {
    /// A made-up tray for the welcome tour and the pictures of Glance: a photo and a document
    /// dropped on the notch, a note and a link copied. Its files are made once, in Glance's caches;
    /// it never watches the clipboard.
    static let demo: Tray = {
        let folder = URL.cachesDirectory.appending(path: "dev.vibe.Glance/Tour Tray")
        let files = folder.appending(path: "Files")
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
        let tray = Tray(folder: folder, pasteboard: NSPasteboard(name: .init("dev.vibe.Glance.tour")))
        let now = Date.now
        var captures: [TrayCapture] = []

        func file(_ url: URL, minutesAgo: Double) {
            guard let bookmark = try? url.bookmarkData() else { return }
            captures.append(
                TrayCapture(
                    item: TrayItem(
                        id: UUID(), added: now - minutesAgo * 60, kind: .files, kept: true, bookmarks: [bookmark],
                        names: [url.lastPathComponent], fingerprint: "files:" + url.path),
                    data: []))
        }
        func copied(_ text: String, from app: String, minutesAgo: Double) {
            let pasteboard = NSPasteboard(name: .init("dev.vibe.Glance.tour.\(captures.count)"))
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            if let capture = TrayCapture.make(from: pasteboard, kept: false, app: app, now: now - minutesAgo * 60) {
                captures.append(capture)
            }
            pasteboard.releaseGlobally()
        }

        if let photo = photo(in: files) { file(photo, minutesAgo: 1) }
        copied("Dinner on Friday at eight? I booked the table by the window.", from: "com.apple.Notes", minutesAgo: 4)
        if let document = document(in: files) { file(document, minutesAgo: 12) }
        copied("https://github.com/imgaty/Glance", from: "com.apple.Safari", minutesAgo: 25)
        let projects = files.appending(path: "Projects")
        try? FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        file(projects, minutesAgo: 40)

        // Oldest first, so the newest ends up at the front.
        for capture in captures.reversed() { tray.add(capture) }
        return tray
    }()

    /// One of macOS's own desktop pictures, made small.
    private static func photo(in folder: URL) -> URL? {
        let pictures = URL(fileURLWithPath: "/System/Library/Desktop Pictures")
        guard
            let original = ["Sonoma.heic", "iMac Blue.heic", "Mac Blue.heic"].map({ pictures.appending(path: $0) })
                .first(where: { FileManager.default.fileExists(atPath: $0.path) }),
            let source = CGImageSourceCreateWithURL(original as CFURL, nil),
            let image = CGImageSourceCreateThumbnailAtIndex(
                source, 0,
                [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1200] as CFDictionary)
        else { return nil }
        let url = folder.appending(path: "Weekend.jpg")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? url : nil
    }

    /// A page of a trip's plans.
    private static func document(in folder: URL) -> URL? {
        let url = folder.appending(path: "Itinerary.pdf")
        var page = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(url as CFURL, mediaBox: &page, nil) else { return nil }
        context.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        NSAttributedString(string: "Lisbon", attributes: [.font: NSFont.systemFont(ofSize: 44, weight: .bold)])
            .draw(at: CGPoint(x: 60, y: 680))
        let lines = [
            "Friday", "Flight TP 1351 · 9:40", "Check in · Alfama", "", "Saturday", "Tram 28 · Belém", "Pastéis · 4:00",
            "", "Sunday", "Sintra · day trip",
        ]
        for (index, line) in lines.enumerated() {
            let bold = ["Friday", "Saturday", "Sunday"].contains(line)
            NSAttributedString(string: line, attributes: [.font: NSFont.systemFont(ofSize: 22, weight: bold ? .semibold : .regular)])
                .draw(at: CGPoint(x: 60, y: 610 - CGFloat(index) * 34))
        }
        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
        context.closePDF()
        return url
    }
}
