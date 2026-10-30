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
/// and lifted a little; anything else, its icon. Copied text is a page of its words, as Finder
/// shows a text file, so two notes never look alike; a link is its site's icon where the site has a
/// sharp one, or a web location. Several files kept together are a pile. A preview sits on the
/// bottom of its square, just over its name, as Finder sets a wide photo; an icon fills its square,
/// and a site's icon, shaped like an app's, sits in the middle of it, as an app icon sits on Apple's
/// icon grid.
struct TrayItemPicture: View {
    let item: TrayItem
    let tray: Tray
    let side: CGFloat
    @State private var thumbnail: NSImage?
    @State private var link: LinkPreview?

    /// Drawn at once from what's already made, so nothing flickers in, and so a picture of it, as
    /// for a drag, has it too.
    init(item: TrayItem, tray: Tray, side: CGFloat) {
        self.item = item
        self.tray = tray
        self.side = side
        _thumbnail = State(initialValue: TrayThumbnails.cached(item))
        _link = State(initialValue: LinkPreviews.cached(item))
    }

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
            TextPage(text: item.text ?? "", side: side)
        case .link:
            if let site = link?.icon, Self.isSharp(site) {
                let shape = RoundedRectangle(cornerRadius: side * 0.18, style: .continuous)
                Image(nsImage: site).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    .frame(width: side * 0.8, height: side * 0.8)
                    .clipShape(shape)
                    .overlay { shape.strokeBorder(.white.opacity(0.15), lineWidth: 0.5) }
                    // Centered, with as much room above as below, so a selection's square sits
                    // evenly around it.
                    .frame(width: side, height: side)
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
            preview(thumbnail)
        } else {
            icon(thumbnail ?? Self.icon(for: item.names.first))
        }
    }

    /// What's in it, edged and lifted a little off the glass.
    private func preview(_ image: NSImage) -> some View {
        Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
            .overlay { Rectangle().strokeBorder(.white.opacity(0.18), lineWidth: 0.5) }
            .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
            .padding(side * 0.06)
    }

    private func icon(_ image: NSImage) -> some View {
        Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
    }

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

    /// What the item is called, under its tile: a file's name, a text's first line, a link's site,
    /// and on a second line, where on the site it goes, so two links to one site can be told apart.
    static func title(of item: TrayItem) -> String {
        switch item.kind {
        case .files: item.title
        case .image: item.origin == .screenshot ? "Screenshot" : "Image"
        case .link:
            item.text.flatMap(URLComponents.init(string:)).map { link in
                let path = link.path.split(separator: "/").joined(separator: "/")
                return path.isEmpty ? item.title : item.title + "\n" + (path.removingPercentEncoding ?? path)
            } ?? item.title
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
        return (item.keptCopy ? "Kept · " : "") + count + source(of: item, in: tray) + " · " + when
    }

    private static func source(of item: TrayItem, in tray: Tray) -> String {
        switch item.origin {
        case .copied:
            return item.app.flatMap(InstalledApps.name).map { "Copied from \($0)" } ?? "Copied"
        case .screenshot:
            let isMovie = item.names.first.flatMap { UTType(filenameExtension: ($0 as NSString).pathExtension) }?.conforms(to: .movie) == true
            return isMovie ? "Screen Recording" : "Screenshot"
        case .dropped:
            // As last looked, away from the notch (see Tray.checkFiles): never looked for here, as
            // the tray is drawn.
            return tray.folders[item.id].map { "In " + $0 } ?? "Dropped"
        }
    }
}

/// Copied text as a page of its first words, as Finder draws a text file, so two notes never look
/// alike: a sheet of paper, as tall as a document's preview, with the words small and dark at its top.
private struct TextPage: View {
    let text: String
    let side: CGFloat

    var body: some View {
        let height = side * 0.88, width = height * 0.77
        Text(text)
            .font(.system(size: side * 0.1))
            .foregroundStyle(Color(white: 0.25))
            .frame(width: width - side * 0.12, height: height - side * 0.12, alignment: .topLeading)
            .clipped()
            .frame(width: width, height: height)
            .background(.white)
            .overlay { Rectangle().strokeBorder(.white.opacity(0.18), lineWidth: 0.5) }
            .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
            .padding(.bottom, side * 0.06)
            .accessibilityHidden(true)
    }
}

/// A link's site's icon, as macOS's link previews show it.
struct LinkPreview {
    var icon: NSImage?
}

/// Link previews, fetched once for each site, as Messages fetches a link's, and kept while Glance
/// runs. Only the site's home page is asked, never the address copied: a link can do something
/// just by being opened, like a sign-in or unsubscribe link, which works only once.
@MainActor
enum LinkPreviews {
    private static var previews: [URL: LinkPreview] = [:]
    private static var fetching: [URL: Task<LinkPreview, Never>] = [:]

    static func cached(_ item: TrayItem) -> LinkPreview? { site(of: item).flatMap { previews[$0] } }

    static func preview(for item: TrayItem) async -> LinkPreview? {
        guard let site = site(of: item) else { return nil }
        if let preview = previews[site] { return preview }
        let task =
            fetching[site]
            ?? Task {
                let provider = LPMetadataProvider()
                provider.timeout = 6
                guard let metadata = try? await provider.startFetchingMetadata(for: site) else { return LinkPreview() }
                var preview = LinkPreview()
                if let icon = metadata.iconProvider { preview.icon = await load(icon) }
                return preview
            }
        fetching[site] = task
        let preview = await task.value
        fetching[site] = nil
        previews[site] = preview
        return preview
    }

    /// The home page of the link's site: its scheme, host and port, and nothing of the rest.
    static func site(of item: TrayItem) -> URL? {
        guard let address = item.text, let link = URLComponents(string: address), let host = link.encodedHost, !host.isEmpty else {
            return nil
        }
        var site = URLComponents()
        site.scheme = link.scheme
        site.encodedHost = host
        site.port = link.port
        site.path = "/"
        return site.url
    }

    private static func load(_ provider: NSItemProvider) async -> NSImage? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: NSImage.self) { image, _ in
                continuation.resume(returning: image as? NSImage)
            }
        }
    }
}
