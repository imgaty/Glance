//
//  TrayView.swift
//  Glance
//
//  Created by Gaty on 12/10/2026.
//

import AppKit
import SwiftUI

/// The shelf's measures, shared by what draws it and what scrolls it.
enum Shelf {
    /// A tile's width, and its picture's side.
    static let tile: CGFloat = 72
    static let picture: CGFloat = 56
    static let spacing: CGFloat = 4
    /// Two lines of names under the pictures.
    static let caption: CGFloat = 27

    /// The row of tiles, from the first to the last, with the notch's padding at both ends.
    static func width(count: Int) -> CGFloat {
        count == 0 ? 0 : CGFloat(count) * tile + CGFloat(count - 1) * spacing + PlayerLayout.padding * 2
    }

    /// How far the row scrolls in a notch this wide.
    static func reach(count: Int, in width: CGFloat) -> CGFloat {
        max(self.width(count: count) - width, 0)
    }
}

/// The tray in the open notch: what was dropped and copied, newest first, in a row that scrolls
/// sideways with two fingers. Dragging something over the notch opens a place for it at the front,
/// as the Dock does for an app dragged into it.
struct TrayView: View {
    @ObservedObject var tray: Tray
    let isVisible: Bool
    /// Something is being dragged over the notch.
    let dropping: Bool
    /// How far the row is scrolled.
    let scroll: CGFloat
    @Environment(\.closedNotch) private var closedNotch
    @AppStorage(Preferences.trayClipboard) private var keepsCopies = true
    /// Built only while it shows, and a moment after, to fade out: closed, or on the player, the
    /// tray costs nothing.
    @State private var built = false

    var body: some View {
        GeometryReader { proxy in
            if built || dropping { content(proxy) }
        }
        .foregroundStyle(.white)
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: tray.items.map(\.id))
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: dropping)
        .onChange(of: isVisible, initial: true) {
            guard isVisible else { return }
            built = true
            // Files moved to the Trash since it last showed go.
            tray.purge(checkingFiles: true)
        }
        .task(id: isVisible) {
            guard !isVisible else { return }
            try? await Task.sleep(for: .seconds(0.5))
            if !Task.isCancelled { built = false }
        }
    }

    @ViewBuilder private func content(_ proxy: GeometryProxy) -> some View {
        let top = closedNotch.height + PlayerLayout.cameraGap + 4
        let room = proxy.size.height - top - PlayerLayout.padding + 4
        if tray.items.isEmpty {
            empty
                .frame(width: proxy.size.width, height: room)
                .padding(.top, top)
                .background(alignment: .top) {
                    // The whole notch takes the drop: a ring just inside its edges, below the
                    // camera, its corners concentric with the notch's.
                    if dropping {
                        let inset: CGFloat = 10
                        RoundedRectangle(cornerRadius: PlayerLayout.cornerRadius - inset, style: .continuous)
                            .strokeBorder(.white.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                            .frame(width: proxy.size.width - inset * 2, height: proxy.size.height - closedNotch.height - 6 - inset)
                            .padding(.top, closedNotch.height + 6)
                            .transition(.opacity)
                    }
                }
        } else {
            row(width: proxy.size.width)
                .frame(height: room)
                .padding(.top, top)
        }
    }

    /// Only the tiles in sight, and a few either side, are made; the rest of the row is space.
    private func row(width: CGFloat) -> some View {
        let step = Shelf.tile + Shelf.spacing
        let skipped = max(Int(((scroll - (dropping ? step : 0)) / step).rounded(.down)) - 3, 0)
        let shown = tray.items.dropFirst(skipped).prefix(Int((width / step).rounded(.up)) + 6)
        return HStack(spacing: Shelf.spacing) {
            if dropping {
                DropSlot()
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
            if skipped > 0 {
                Color.clear.frame(width: CGFloat(skipped) * step - Shelf.spacing, height: 1)
            }
            ForEach(shown) { item in
                TrayTile(item: item, tray: tray, isVisible: isVisible)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .padding(.horizontal, PlayerLayout.padding)
        .offset(x: -scroll)
        .frame(width: width, alignment: .leading)
        // The row fades out under the notch's sides rather than being cut off by them.
        .mask {
            HStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing).frame(width: 14)
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 14)
            }
        }
    }

    /// With nothing in it: what it's for, or, with something dragged over it, where it goes.
    private var empty: some View {
        VStack(spacing: 5) {
            Image(systemName: dropping ? "tray.and.arrow.down.fill" : "tray")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(dropping ? .white : PlayerLayout.secondary)
                .contentTransition(.symbolEffect(.replace))
                .padding(.bottom, 2)
            Text(dropping ? "Drop to Keep" : "Drop Files Here")
                .font(.system(size: 13, weight: .semibold))
            if !dropping, let line = emptyLine {
                Text(line)
                    .font(.system(size: 11))
                    .foregroundStyle(PlayerLayout.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 240)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyLine: String? {
        guard keepsCopies else { return nil }
        return tray.pasteBlocked
            ? "To keep what you copy, allow Glance in Privacy & Security, under Paste from Other Apps."
            : "What you copy shows up here too."
    }
}

/// The place opened at the front of the row for what's being dragged in.
private struct DropSlot: View {
    var body: some View {
        VStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .overlay {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .frame(width: Shelf.picture, height: Shelf.picture)
            Color.clear.frame(height: Shelf.caption)
        }
        .frame(width: Shelf.tile)
    }
}

/// One thing in the tray: its picture and its name, as Finder shows a file. Click it to copy it,
/// double-click to paste it where you were typing, drag it out to put it somewhere, or remove it
/// with the button that comes up on it, as on a notification.
private struct TrayTile: View {
    let item: TrayItem
    @ObservedObject var tray: Tray
    let isVisible: Bool
    @State private var thumbnail: NSImage?
    @State private var hovered = false

    var body: some View {
        let copied = tray.justCopied == item.id
        VStack(spacing: 5) {
            picture
                .frame(width: Shelf.picture, height: Shelf.picture)
                .overlay {
                    if copied {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 26, weight: .medium))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color(white: 0.2).opacity(0.85))
                            .transition(.scale(scale: 0.5).combined(with: .opacity))
                    }
                }
            Text(caption)
                .font(.system(size: 10.5, weight: .medium))
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .frame(width: Shelf.tile - 4, height: Shelf.caption, alignment: .top)
        }
        .padding(.top, 4)
        .frame(width: Shelf.tile)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(hovered ? 0.1 : 0))
        }
        .overlay {
            TileInteraction(item: item, tray: tray) { hovered = $0 }
        }
        .overlay(alignment: .topLeading) {
            if hovered {
                Button {
                    tray.remove(item.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color(white: 0.22)))
                        .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove from Tray")
                .offset(x: 1, y: 0)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.15), value: hovered)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: copied)
        .notchControl(enabled: isVisible)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(caption)
        .accessibilityAddTraits(.isButton)
        .task(id: item.id) {
            thumbnail = TrayThumbnails.cached(item)
            if thumbnail == nil { thumbnail = await TrayThumbnails.image(for: item, in: tray, side: Shelf.picture) }
        }
    }

    /// A file's name; a link's site; text or a picture, by the app it came from.
    private var caption: String {
        switch item.kind {
        case .files, .link: item.title
        case .image, .text: item.app.flatMap(Self.appName) ?? item.title
        }
    }

    /// Looked up once for each app.
    private static var appNames: [String: String?] = [:]

    private static func appName(_ bundle: String) -> String? {
        if let name = appNames[bundle] { return name }
        let name = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle)
            .map { FileManager.default.displayName(atPath: $0.path) }
            .map { $0.hasSuffix(".app") ? String($0.dropLast(4)) : $0 }
        appNames[bundle] = name
        return name
    }

    @ViewBuilder private var picture: some View {
        switch item.kind {
        case .files:
            ZStack(alignment: .topTrailing) {
                if let thumbnail {
                    Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fit)
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                }
                // As Finder counts files dragged together.
                if item.names.count > 1 {
                    Text("\(item.names.count)")
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .padding(.horizontal, 5)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Capsule().fill(.red))
                        .offset(x: 4, y: -4)
                }
            }
        case .image:
            if let thumbnail {
                Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: Shelf.picture, height: Shelf.picture)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
            }
        case .link:
            card {
                Image(systemName: "link")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .text:
            card {
                Text(item.text ?? "")
                    .font(.system(size: 7.5))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(6)
            }
        }
    }

    /// Text and links, on a card like a note's.
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(.white.opacity(0.12))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.1), lineWidth: 0.5))
            .overlay { content() }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// The notch's two pages, side by side beside the camera, as Spotlight puts its own beside its
/// search field: the player and the tray, ⇧⌘1 and ⇧⌘2.
struct NotchPagePicker: View {
    @ObservedObject var tray: Tray
    let page: NotchPage
    let enabled: Bool
    let select: (NotchPage) -> Void
    @Namespace private var selection

    var body: some View {
        HStack(spacing: 0) {
            ForEach(NotchPage.allCases) { choice in
                Button {
                    select(choice)
                } label: {
                    Image(systemName: choice == .tray && !tray.items.isEmpty ? "tray.full.fill" : choice.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(choice == page ? .white : PlayerLayout.secondary)
                        .frame(width: 28, height: 20)
                        .background {
                            if choice == page {
                                Capsule()
                                    .fill(.white.opacity(0.2))
                                    .matchedGeometryEffect(id: "selection", in: selection)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(choice.title)
                .accessibilityAddTraits(choice == page ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Capsule().fill(.white.opacity(0.08)))
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: page)
        .notchControl(enabled: enabled)
    }
}

enum NotchPage: String, CaseIterable, Identifiable {
    case player, tray

    var id: Self { self }
    var title: String { self == .player ? "Player" : "Tray" }
    var symbol: String { self == .player ? "music.note" : "tray.fill" }

    /// The page the notch opens on: the one it was left on.
    static var last: NotchPage {
        guard Tray.isOn else { return .player }
        return NotchPage(rawValue: UserDefaults.standard.string(forKey: Preferences.notchPage) ?? "") ?? .player
    }
}
