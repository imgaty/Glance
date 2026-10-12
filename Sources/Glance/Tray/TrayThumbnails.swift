//
//  TrayThumbnails.swift
//  Glance
//
//  Created by Gaty on 12/10/2026.
//

import AppKit
import QuickLookThumbnailing

/// Pictures of what's in the tray, as Finder draws them: a file's contents where Quick Look can
/// show them, its icon otherwise; a copied picture, shrunk. Made once each and kept.
@MainActor
enum TrayThumbnails {
    private static let cache = NSCache<NSString, NSImage>()
    /// Items Quick Look could only give an icon for, not their contents: they're shown bare, without
    /// the edge a photo has.
    private static var iconsOnly: Set<UUID> = []

    static func isIcon(_ item: TrayItem) -> Bool { iconsOnly.contains(item.id) }

    /// Already made, for drawing at once and for dragging.
    static func cached(_ item: TrayItem) -> NSImage? {
        cache.object(forKey: item.id.uuidString as NSString)
    }

    static func image(for item: TrayItem, in tray: Tray, side: CGFloat) async -> NSImage? {
        if let image = cached(item) { return image }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        var image: NSImage?
        switch item.kind {
        case .files:
            guard let url = tray.urls(of: item).first else { return nil }
            if let (picture, contents) = await thumbnail(of: url, side: side, scale: scale) {
                image = picture
                if !contents { iconsOnly.insert(item.id) }
            } else {
                image = NSWorkspace.shared.icon(forFile: url.path)
                iconsOnly.insert(item.id)
            }
        case .image:
            guard let name = item.files.first else { return nil }
            image = await thumbnail(of: tray.file(name, of: item), side: side, scale: scale)?.0
        case .link, .text:
            return nil
        }
        if let image { cache.setObject(image, forKey: item.id.uuidString as NSString) }
        return image
    }

    /// The picture, and whether it shows the file's contents rather than its icon.
    private static func thumbnail(of url: URL, side: CGFloat, scale: CGFloat) async -> (NSImage, Bool)? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: side, height: side), scale: scale, representationTypes: .all)
        guard let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else { return nil }
        return (representation.nsImage, representation.type == .thumbnail)
    }
}
