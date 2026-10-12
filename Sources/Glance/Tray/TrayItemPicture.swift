//
//  TrayItemPicture.swift
//  Glance
//
//  Created by Gaty on 12/10/2026.
//

import AppKit
import LinkPresentation
import SwiftUI
import UniformTypeIdentifiers

/// What an item shows in its tile's well: a preview of its contents where Quick Look can make one,
/// filling the well but for a narrow margin; otherwise its icon, smaller, in the middle. Text shows
/// as a text document's symbol, a link as its site's icon, or a link's symbol until that's fetched.
struct TrayItemPicture: View {
    let item: TrayItem
    let tray: Tray
    /// The well it fills.
    let size: CGSize
    @State private var thumbnail: NSImage?
    @State private var link: LinkPreview?

    var body: some View {
        content
            .frame(width: size.width, height: size.height)
            .task(id: item.id) {
                if item.kind == .link {
                    link = LinkPreviews.cached(item)
                    if link == nil { link = await LinkPreviews.preview(for: item) }
                    return
                }
                guard item.kind != .text else { return }
                thumbnail = TrayThumbnails.cached(item)
                if thumbnail == nil { thumbnail = await TrayThumbnails.image(for: item, in: tray, side: 64) }
            }
    }

    @ViewBuilder private var content: some View {
        switch item.kind {
        case .text:
            symbol("doc.plaintext")
        case .link:
            if let icon = link?.icon {
                Image(nsImage: icon).resizable().aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 13)
            } else {
                symbol("link")
            }
        case .files, .image:
            if let thumbnail, !TrayThumbnails.isIcon(item) {
                // A preview, nearly filling the well.
                Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    .padding(4)
            } else {
                // An icon, smaller, in the middle.
                Image(nsImage: thumbnail ?? Self.icon(of: item)).resizable().aspectRatio(contentMode: .fit)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 8)
            }
        }
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: size.height * 0.4, weight: .regular))
            .foregroundStyle(.white.opacity(0.75))
    }

    private static func icon(of item: TrayItem) -> NSImage {
        let ext = ((item.names.first ?? "") as NSString).pathExtension
        return NSWorkspace.shared.icon(for: UTType(filenameExtension: ext) ?? .data)
    }

    // MARK: Names

    /// What the item is called, under its tile: a file's name, a text's first line, a link's site.
    static func title(of item: TrayItem) -> String {
        switch item.kind {
        case .files: item.title
        case .image: item.origin == .screenshot ? "Screenshot" : "Image"
        case .link: item.title
        case .text:
            (item.text ?? "").split(whereSeparator: \.isNewline).first.map {
                String($0.trimmingCharacters(in: .whitespaces).prefix(48))
            } ?? "Text"
        }
    }

    /// Where it came from and when, as a notification says: copied from an app, a screenshot, or,
    /// for a dropped file, the folder it's in.
    static func detail(of item: TrayItem, in tray: Tray) -> String {
        // As Notification Center says it: "now", "2m ago".
        let when = item.added.formatted(.relative(presentation: .named, unitsStyle: .narrow))
        let count = item.kind == .files && item.names.count > 1 ? "\(item.names.count) Items · " : ""
        return count + source(of: item, in: tray) + " · " + when
    }

    private static func source(of item: TrayItem, in tray: Tray) -> String {
        switch item.origin {
        case .copied:
            return item.app.flatMap(appName).map { "Copied from \($0)" } ?? "Copied"
        case .screenshot:
            return "Screenshot"
        case .dropped:
            guard item.kind == .files, item.names.count == 1, let url = tray.urls(of: item).first else { return "Dropped" }
            return "In " + FileManager.default.displayName(atPath: url.deletingLastPathComponent().path)
        }
    }

    /// For menus and accessibility: a file's name; a link's site; text or a picture, by the app it
    /// came from.
    static func caption(for item: TrayItem) -> String {
        switch item.kind {
        case .files, .link: item.title
        case .image, .text: item.app.flatMap(appName) ?? item.title
        }
    }

    /// Looked up once for each app.
    private static var appNames: [String: String?] = [:]

    static func appName(_ bundle: String) -> String? {
        if let name = appNames[bundle] { return name }
        let name = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle)
            .map { FileManager.default.displayName(atPath: $0.path) }
            .map { $0.hasSuffix(".app") ? String($0.dropLast(4)) : $0 }
        appNames[bundle] = name
        return name
    }
}

/// A page's title and its site's icon, as macOS's link previews show them.
struct LinkPreview {
    var title: String?
    var icon: NSImage?
}

/// Link previews, fetched from the page once each, as Messages fetches a link's, and kept while
/// Glance runs.
@MainActor
enum LinkPreviews {
    private static var previews: [UUID: LinkPreview] = [:]
    private static var fetching: [UUID: Task<LinkPreview, Never>] = [:]

    static func cached(_ item: TrayItem) -> LinkPreview? { previews[item.id] }

    static func preview(for item: TrayItem) async -> LinkPreview? {
        if let preview = previews[item.id] { return preview }
        guard let address = item.text, let url = URL(string: address) else { return nil }
        let task =
            fetching[item.id]
            ?? Task {
                let provider = LPMetadataProvider()
                provider.timeout = 6
                guard let metadata = try? await provider.startFetchingMetadata(for: url) else { return LinkPreview() }
                var preview = LinkPreview(title: metadata.title)
                if let icon = metadata.iconProvider { preview.icon = await load(icon) }
                return preview
            }
        fetching[item.id] = task
        let preview = await task.value
        fetching[item.id] = nil
        previews[item.id] = preview
        return preview
    }

    private static func load(_ provider: NSItemProvider) async -> NSImage? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: NSImage.self) { image, _ in
                continuation.resume(returning: image as? NSImage)
            }
        }
    }
}
