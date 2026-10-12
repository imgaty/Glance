//
//  TrayItemPicture.swift
//  Glance
//
//  Created by Gaty on 12/10/2026.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// An item's picture, in the notch and in the history window alike: a file as Finder shows it, its
/// contents where Quick Look can show them; a copied picture, shrunk; text and links on a card.
struct TrayItemPicture: View {
    let item: TrayItem
    let tray: Tray
    let side: CGFloat
    @State private var thumbnail: NSImage?

    var body: some View {
        picture
            .frame(width: side, height: side)
            .task(id: item.id) {
                thumbnail = TrayThumbnails.cached(item)
                if thumbnail == nil { thumbnail = await TrayThumbnails.image(for: item, in: tray, side: side) }
            }
    }

    @ViewBuilder private var picture: some View {
        let scale = side / Shelf.picture
        switch item.kind {
        case .files:
            ZStack(alignment: .topTrailing) {
                // Until its picture is made, or if it can't be, the icon of its kind of file.
                Image(nsImage: thumbnail ?? Self.icon(of: item)).resizable().aspectRatio(contentMode: .fit)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                // As Finder counts files dragged together.
                if item.names.count > 1 {
                    Text("\(item.names.count)")
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Capsule().fill(.red))
                        .offset(x: 4, y: -4)
                }
            }
        case .image:
            if let thumbnail {
                Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: 8 * scale, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8 * scale, style: .continuous).strokeBorder(.primary.opacity(0.15), lineWidth: 0.5))
            }
        case .link:
            card(scale) {
                Image(systemName: "link")
                    .font(.system(size: 20 * scale, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.75))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .text:
            card(scale) {
                Text(item.text ?? "")
                    .font(.system(size: 7.5 * scale))
                    .foregroundStyle(.primary.opacity(0.8))
                    .lineLimit(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(6 * scale)
            }
        }
    }

    /// Text and links, on a card like a note's.
    private func card<Content: View>(_ scale: CGFloat, @ViewBuilder _ content: () -> Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10 * scale, style: .continuous)
        return
            shape
            .fill(.primary.opacity(0.12))
            .overlay(shape.strokeBorder(.primary.opacity(0.1), lineWidth: 0.5))
            .overlay { content() }
            .clipShape(shape)
    }

    /// A file's name; a link's site; text or a picture, by the app it came from.
    static func caption(for item: TrayItem) -> String {
        switch item.kind {
        case .files, .link: item.title
        case .image, .text: item.app.flatMap(appName) ?? item.title
        }
    }

    private static func icon(of item: TrayItem) -> NSImage {
        let ext = ((item.names.first ?? "") as NSString).pathExtension
        return NSWorkspace.shared.icon(for: UTType(filenameExtension: ext) ?? .data)
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
