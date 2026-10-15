//
//  ShareViewController.swift
//  GlanceShare
//
//  Created by Gaty on 15/10/2026.
//

import AppKit
import UniformTypeIdentifiers

/// Glance Tray, in the Share menu of Safari, Finder, Photos and every app that shares: what's
/// shared joins the tray as if it were dropped on the notch, with no window of its own, as Add to
/// Reading List has none. It runs in a sandbox, apart from Glance: it leaves what it's given on a
/// pasteboard of Glance's own, tells Glance it's there, and waits for Glance to have taken it, so a
/// file the sharing app made only for the moment is kept before it's gone (see TrayService).
final class ShareViewController: NSViewController {
    /// Also in TrayService, which reads them.
    static let pasteboard = NSPasteboard.Name("dev.vibe.Glance.share")
    static let shared = Notification.Name("dev.vibe.Glance.shared")
    static let taken = Notification.Name("dev.vibe.Glance.sharedTaken")

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        Task {
            var entries: [NSPasteboardItem] = []
            for provider in providers {
                if let entry = await Self.entry(for: provider) { entries.append(entry) }
            }
            if !entries.isEmpty { await hand(entries) }
            extensionContext?.completeRequest(returningItems: nil)
        }
    }

    /// On Glance's pasteboard, and Glance told; if it doesn't answer, as when it isn't open, it's
    /// opened, and takes what's waiting as it starts.
    private func hand(_ entries: [NSPasteboardItem]) async {
        let board = NSPasteboard(name: Self.pasteboard)
        board.clearContents()
        board.writeObjects(entries)
        let center = DistributedNotificationCenter.default()
        let answer = Answer()
        // Listening before Glance is told, so an answer that comes at once isn't missed.
        let watch = center.addObserver(forName: Self.taken, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { answer.came = true }
        }
        defer { center.removeObserver(watch) }
        center.postNotificationName(Self.shared, object: nil, userInfo: nil, deliverImmediately: true)
        if await answer.wait(seconds: 1.5) { return }
        // The app this extension is in: GlanceShare.appex is in Glance.app/Contents/PlugIns.
        let app = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let opening = NSWorkspace.OpenConfiguration()
        opening.activates = false
        _ = try? await NSWorkspace.shared.openApplication(at: app, configuration: opening)
        _ = await answer.wait(seconds: 5)
    }

    /// Whether Glance has said it took what's shared.
    @MainActor
    private final class Answer {
        var came = false

        func wait(seconds: Double) async -> Bool {
            let end = Date.now + seconds
            while !came, Date.now < end { try? await Task.sleep(for: .milliseconds(50)) }
            return came
        }
    }

    /// One thing shared, as the tray takes it from a drop: a file where it is, a picture as itself,
    /// a web address, or text.
    private static func entry(for provider: NSItemProvider) async -> NSPasteboardItem? {
        let entry = NSPasteboardItem()
        if let url = await url(from: provider, type: .fileURL), url.isFileURL {
            // A picture the app made just to share it goes as the picture itself.
            if UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true, isTemporary(url),
                let data = try? Data(contentsOf: url), let picture = picture(data)
            {
                entry.setData(picture.data, forType: picture.type)
            } else {
                entry.setString(url.absoluteString, forType: .fileURL)
            }
            return entry
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
            let item = try? await provider.loadItem(forTypeIdentifier: UTType.image.identifier),
            let data = (item as? Data) ?? (item as? URL).flatMap({ try? Data(contentsOf: $0) }) ?? (item as? NSImage)?.tiffRepresentation,
            let picture = picture(data)
        {
            entry.setData(picture.data, forType: picture.type)
            return entry
        }
        if let url = await url(from: provider, type: .url) {
            entry.setString(url.absoluteString, forType: .URL)
            entry.setString(url.absoluteString, forType: .string)
            return entry
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
            let item = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier),
            let text = (item as? String) ?? (item as? NSAttributedString)?.string ?? (item as? Data).flatMap({ String(data: $0, encoding: .utf8) })
        {
            entry.setString(text, forType: .string)
            return entry
        }
        return nil
    }

    private static func url(from provider: NSItemProvider, type: UTType) async -> URL? {
        guard provider.hasItemConformingToTypeIdentifier(type.identifier),
            let item = try? await provider.loadItem(forTypeIdentifier: type.identifier)
        else { return nil }
        return (item as? URL) ?? (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
    }

    /// A picture in a kind the tray keeps: PNG, JPEG and TIFF as they are, any other made a PNG.
    private static func picture(_ data: Data) -> (data: Data, type: NSPasteboard.PasteboardType)? {
        let start = [UInt8](data.prefix(4))
        if start == [0x89, 0x50, 0x4E, 0x47] { return (data, .png) }
        if start.starts(with: [0xFF, 0xD8]) { return (data, NSPasteboard.PasteboardType(UTType.jpeg.identifier)) }
        if start == [0x49, 0x49, 0x2A, 0x00] || start == [0x4D, 0x4D, 0x00, 0x2A] { return (data, .tiff) }
        guard let png = NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:]) else { return nil }
        return (png, .png)
    }

    private static func isTemporary(_ url: URL) -> Bool {
        let path = url.resolvingSymlinksInPath().path
        return path.hasPrefix("/private/var/folders/") || path.hasPrefix("/private/tmp/") || path.contains("/TemporaryItems/")
    }
}
