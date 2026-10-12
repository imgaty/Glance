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

/// An item's picture, as the desktop shows a file: a photo or a screenshot whole, with a thin edge;
/// a document, its first page; a folder, its icon; copied text, as a page with the text on it, as
/// Finder shows a document's first page; a link, its site's icon on a tile, as Safari shows a
/// favorite. Each fits the same square, so the row keeps an even rhythm.
struct TrayItemPicture: View {
    let item: TrayItem
    let tray: Tray
    let side: CGFloat
    @State private var thumbnail: NSImage?
    @State private var link: LinkPreview?

    /// The corners of a tile the size of a thumbnail.
    static func radius(for side: CGFloat) -> CGFloat { side * 0.2 }

    var body: some View {
        // Every item stands on the same line, at the foot of its square, as icons do in Finder and
        // the Dock.
        picture
            .frame(width: side, height: side, alignment: .bottom)
            .task(id: item.id) {
                if item.kind == .link {
                    link = LinkPreviews.cached(item)
                    if link == nil { link = await LinkPreviews.preview(for: item) }
                    return
                }
                thumbnail = TrayThumbnails.cached(item)
                if thumbnail == nil { thumbnail = await TrayThumbnails.image(for: item, in: tray, side: side) }
            }
    }

    @ViewBuilder private var picture: some View {
        switch item.kind {
        case .image:
            photo
        case .files where Self.isPhoto(item):
            photo.overlay(alignment: .topTrailing) { count }
        case .text:
            page
        case .files:
            // Until Quick Look has made its picture, or if it can't, the icon of its kind of file.
            Image(nsImage: thumbnail ?? Self.icon(of: item))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .overlay(alignment: .topTrailing) { count }
        case .link:
            site
        }
    }

    /// Photos and screenshots, whole, their corners a little rounded, with only a hairline to keep a
    /// dark one from melting into the notch; a video Quick Look can't show yet, its icon, bare.
    @ViewBuilder private var photo: some View {
        if let thumbnail, !TrayThumbnails.isIcon(item) {
            let shape = RoundedRectangle(cornerRadius: side * 0.05, style: .continuous)
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(shape)
                .overlay(shape.strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
        } else {
            Image(nsImage: thumbnail ?? Self.icon(of: item)).resizable().aspectRatio(contentMode: .fit)
        }
    }

    /// Copied text, as a page with the text on it, as Finder shows a document's first page; drawn
    /// here, as Quick Look draws a short text as a page too small to read.
    private var page: some View {
        let height = side * 0.94, shape = RoundedRectangle(cornerRadius: side * 0.035, style: .continuous)
        return
            shape
            .fill(Color(white: 0.96))
            .overlay(alignment: .topLeading) {
                Text(item.text ?? "")
                    .font(.system(size: side * 0.085))
                    .foregroundStyle(Color(white: 0.22))
                    .lineSpacing(-side * 0.01)
                    .lineLimit(9)
                    .padding(side * 0.07)
            }
            .clipShape(shape)
            .frame(width: height * 0.77, height: height)
    }

    /// Several files copied together: how many, as a stack of them is counted.
    @ViewBuilder private var count: some View {
        if item.kind == .files, item.names.count > 1 {
            Text("\(item.names.count)")
                .font(.system(size: side * 0.16, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, side * 0.08)
                .frame(minWidth: side * 0.3, minHeight: side * 0.3)
                .background(Capsule().fill(Color(white: 0.3)))
                .overlay(Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 0.5))
                .offset(x: side * 0.06, y: -side * 0.06)
        }
    }

    /// A link, as Safari shows a favorite: the site's icon on a tile, or its first letter.
    private var site: some View {
        let tile = side * 0.84
        let shape = RoundedRectangle(cornerRadius: Self.radius(for: tile), style: .continuous)
        return
            shape
            .fill(link?.icon == nil ? Self.color(for: item.title) : Color(white: 0.94))
            .overlay {
                if let icon = link?.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: tile * 0.56, height: tile * 0.56)
                        .clipShape(RoundedRectangle(cornerRadius: tile * 0.1, style: .continuous))
                } else {
                    Text(item.title.prefix(1).uppercased())
                        .font(.system(size: tile * 0.48, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: tile, height: tile)
    }

    /// A color for a site with no icon, the same every time for the same site, as Safari picks one.
    private static func color(for site: String) -> Color {
        let colors: [Color] = [.blue, .indigo, .purple, .pink, .orange, .teal, .green, .gray]
        let index = site.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF } % colors.count
        return colors[index].mix(with: .black, by: 0.15)
    }

    /// Photos, screenshots and videos show whole, with an edge; other files show as Finder shows them.
    private static func isPhoto(_ item: TrayItem) -> Bool {
        guard let type = UTType(filenameExtension: ((item.names.first ?? "") as NSString).pathExtension) else { return false }
        return type.conforms(to: .image) || type.conforms(to: .movie)
    }

    private static func icon(of item: TrayItem) -> NSImage {
        let ext = ((item.names.first ?? "") as NSString).pathExtension
        return NSWorkspace.shared.icon(for: UTType(filenameExtension: ext) ?? .data)
    }

    // MARK: Names

    /// What the item is called: a file's name, a link's page title or site, or the start of text.
    static func title(of item: TrayItem) -> String {
        switch item.kind {
        case .files: item.title
        case .image: item.origin == .screenshot ? "Screenshot" : "Image"
        case .link: LinkPreviews.cached(item)?.title ?? item.title
        case .text:
            (item.text ?? "").split(whereSeparator: \.isNewline).first.map {
                $0.trimmingCharacters(in: .whitespaces)
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
