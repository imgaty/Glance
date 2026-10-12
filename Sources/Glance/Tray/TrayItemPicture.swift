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

/// An item's picture, a rounded square as the player's cover is, so the tray reads as one row of
/// things: a photo or a screenshot fills it, as artwork does; a document shows its first page and a
/// folder its icon, as Finder shows them; text is a note, its first line bold, as Notes shows one;
/// a link is the page's own preview, its site's icon and title, as Messages shows it.
struct TrayItemPicture: View {
    let item: TrayItem
    let tray: Tray
    let side: CGFloat
    @State private var thumbnail: NSImage?
    @State private var link: LinkPreview?

    /// Concentric with the player's cover at the same size.
    static func radius(for side: CGFloat) -> CGFloat { side * 0.2 }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.radius(for: side), style: .continuous)
        picture(shape)
            .frame(width: side, height: side)
            .task(id: item.id) {
                if item.kind == .link {
                    link = await LinkPreviews.preview(for: item)
                    return
                }
                thumbnail = TrayThumbnails.cached(item)
                if thumbnail == nil { thumbnail = await TrayThumbnails.image(for: item, in: tray, side: side) }
            }
    }

    @ViewBuilder private func picture(_ shape: RoundedRectangle) -> some View {
        switch item.kind {
        case .image:
            filled(shape)
        case .files where item.names.count > 1:
            stack(shape)
        case .files where Self.fills(item):
            filled(shape)
        case .files:
            // Until its picture is made, or if it can't be, the icon of its kind of file.
            Image(nsImage: thumbnail ?? Self.icon(of: item))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                .padding(side * 0.04)
        case .text:
            note(shape)
        case .link:
            linkCard(shape)
        }
    }

    /// A picture, filling the square as a cover does.
    private func filled(_ shape: RoundedRectangle) -> some View {
        Color(white: 0.16)
            .overlay {
                if let thumbnail {
                    Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fill)
                }
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
    }

    /// Several files copied together: the first, with the edges of the others behind it, as a
    /// stack of photos is shown.
    private func stack(_ shape: RoundedRectangle) -> some View {
        ZStack {
            ForEach([2, 1], id: \.self) { depth in
                shape
                    .fill(Color(white: 0.22 + 0.06 * Double(2 - depth)))
                    .overlay(shape.strokeBorder(.white.opacity(0.1), lineWidth: 0.5))
                    .scaleEffect(1 - 0.06 * CGFloat(depth))
                    .offset(y: -side * 0.05 * CGFloat(depth))
            }
            Group {
                if Self.fills(item) {
                    filled(shape)
                } else {
                    Color(white: 0.16)
                        .overlay {
                            Image(nsImage: thumbnail ?? Self.icon(of: item))
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .padding(side * 0.14)
                        }
                        .clipShape(shape)
                }
            }
            .scaleEffect(0.92, anchor: .bottom)
        }
    }

    /// Text, as a note: its first line bold, then the rest.
    private func note(_ shape: RoundedRectangle) -> some View {
        let lines = (item.text ?? "").split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true)
        let first = lines.first.map(String.init) ?? ""
        let rest = lines.count > 1 ? String(lines[1]) : ""
        return VStack(alignment: .leading, spacing: 1) {
            Text(first)
                .font(.system(size: side * 0.13, weight: .semibold))
                .lineLimit(rest.isEmpty ? 5 : 2)
            if !rest.isEmpty {
                Text(rest)
                    .font(.system(size: side * 0.12))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(3)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(side * 0.12)
        .background(Color(white: 0.17))
        .clipShape(shape)
        .overlay(shape.strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
    }

    /// A link, as the page shows itself: its site's icon and its title, the site under them.
    private func linkCard(_ shape: RoundedRectangle) -> some View {
        VStack(alignment: .leading, spacing: side * 0.05) {
            Group {
                if let icon = link?.icon {
                    Image(nsImage: icon).resizable().aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: side * 0.06, style: .continuous))
                } else {
                    Image(systemName: "safari")
                        .resizable()
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
            .frame(width: side * 0.26, height: side * 0.26)
            Spacer(minLength: 0)
            // The page's title once it's known, over its site; until then, the site alone.
            if let title = link?.title {
                Text(title)
                    .font(.system(size: side * 0.13, weight: .semibold))
                    .lineLimit(2)
            }
            Text(item.title)
                .font(.system(size: side * (link?.title == nil ? 0.13 : 0.11), weight: link?.title == nil ? .semibold : .regular))
                .foregroundStyle(.white.opacity(link?.title == nil ? 1 : 0.6))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(side * 0.12)
        .background(Color(white: 0.17))
        .clipShape(shape)
        .overlay(shape.strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
    }

    /// Photos, screenshots and videos fill their square; other files show as Finder shows them.
    private static func fills(_ item: TrayItem) -> Bool {
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
