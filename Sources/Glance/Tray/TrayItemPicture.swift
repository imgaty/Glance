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

/// An item's icon, as Finder shows it. A picture or a document is a preview of what's in it, edged
/// and lifted a little; anything else, its icon. Copied text is a text clipping and a link a web
/// location, as each is once dragged to the desktop, or a link is its site's icon where the site has
/// a sharp one. Several files kept together are a pile. Each sits on the bottom of its square.
struct TrayItemPicture: View {
    let item: TrayItem
    let tray: Tray
    let side: CGFloat
    @State private var thumbnail: NSImage?
    @State private var link: LinkPreview?

    var body: some View {
        picture
            .frame(width: side, height: side, alignment: .bottom)
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

    @ViewBuilder private var picture: some View {
        switch item.kind {
        case .text:
            icon(Self.clipping)
        case .link:
            if let site = link?.icon, Self.isSharp(site) {
                let shape = RoundedRectangle(cornerRadius: side * 0.18, style: .continuous)
                Image(nsImage: site).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    .frame(width: side * 0.8, height: side * 0.8)
                    .clipShape(shape)
                    .overlay { shape.strokeBorder(.white.opacity(0.15), lineWidth: 0.5) }
                    .padding(.bottom, side * 0.06)
            } else {
                icon(Self.location)
            }
        case .files where item.names.count > 1:
            // The next two behind the first, askew, as files pile on the desktop.
            ZStack(alignment: .bottom) {
                ForEach(Array(item.names.dropFirst().prefix(2).enumerated().reversed()), id: \.offset) { index, name in
                    icon(Self.icon(for: name))
                        .scaleEffect(0.86, anchor: .bottom)
                        .rotationEffect(.degrees(index == 0 ? -9 : 8), anchor: .bottom)
                }
                single
            }
        case .files, .image:
            single
        }
    }

    @ViewBuilder private var single: some View {
        if let thumbnail, !TrayThumbnails.isIcon(item) {
            Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fit)
                .overlay { Rectangle().strokeBorder(.white.opacity(0.18), lineWidth: 0.5) }
                .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
                .padding(side * 0.06)
        } else {
            icon(thumbnail ?? Self.icon(for: item.names.first))
        }
    }

    private func icon(_ image: NSImage) -> some View {
        Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
    }

    private static let clipping = NSWorkspace.shared.icon(for: UTType("com.apple.finder.textclipping") ?? .plainText)
    private static let location = NSWorkspace.shared.icon(for: UTType("com.apple.web-internet-location") ?? .url)

    private static func icon(for name: String?) -> NSImage {
        let ext = ((name ?? "") as NSString).pathExtension
        return NSWorkspace.shared.icon(for: UTType(filenameExtension: ext) ?? .data)
    }

    /// Big enough to show at an icon's size without blurring.
    private static func isSharp(_ image: NSImage) -> Bool {
        (image.representations.map(\.pixelsWide).max() ?? 0) >= 64
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
