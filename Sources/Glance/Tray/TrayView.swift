//
//  TrayView.swift
//  Glance
//
//  Created by Gaty on 12/10/2026.
//

import AppKit
import SwiftUI

/// The tray's measures, shared by what draws it and what scrolls it.
enum Shelf {
    /// A tile: its picture's well, and its name under it.
    static let tile = CGSize(width: 78, height: 88)
    /// The lit well a picture sits in, at the top of its tile.
    static let well = CGSize(width: 64, height: 50)
    static let spacing: CGFloat = 10
    /// At the row's ends: the first well lines up with the player's artwork.
    static let inset: CGFloat = PlayerLayout.padding - (tile.width - well.width) / 2

    /// The row of tiles, from the first to the last, with its insets at both ends.
    static func width(count: Int) -> CGFloat {
        count == 0 ? 0 : CGFloat(count) * tile.width + CGFloat(count - 1) * spacing + inset * 2
    }

    /// The room AirDrop's tile takes at the row's end while items are dragged out.
    static let airDropWidth: CGFloat = tile.width + inset

    /// How far the row scrolls in a notch this wide.
    static func reach(count: Int, in width: CGFloat) -> CGFloat {
        max(self.width(count: count) - width, 0)
    }
}

/// The tray in the open notch: a row of tiles, each a lit well with the item's picture and its name
/// under it, and a line under the row saying what the one under the pointer is, how many are
/// selected, or what can be done. A click selects, as in Finder; a drag takes the item, or every
/// selected one, anywhere, AirDrop included; a double-click pastes it; a right-click shows the rest.
/// Something dragged in from another app gets two places to go: the tray, and AirDrop.
struct TrayView: View {
    @ObservedObject var tray: Tray
    let isVisible: Bool
    /// Something from another app is being dragged over the notch.
    let dropping: Bool
    /// How far the row is scrolled.
    let scroll: CGFloat
    /// Something dragged is over AirDrop.
    var airDropTargeted = false
    /// Widened to show everything, and how to widen it or bring it back.
    var expanded = false
    var expand: (Bool) -> Void = { _ in }
    @Environment(\.closedNotch) private var closedNotch
    @AppStorage(Preferences.trayClipboard) private var keepsCopies = true
    /// The item under the pointer, whose detail shows under the row.
    @State private var pointed: UUID?
    /// Built only while it shows, and a moment after, to fade out: closed, or on the player, the
    /// tray costs nothing.
    @State private var built = false

    var body: some View {
        GeometryReader { proxy in
            if built || dropping { content(proxy) }
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .animation(.smooth(duration: 0.24), value: tray.items.map(\.id))
        .animation(.smooth(duration: 0.24), value: dropping)
        .animation(.smooth(duration: 0.24), value: tray.draggingOut)
        .animation(.easeOut(duration: 0.15), value: airDropTargeted)
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

    /// AirDrop's tile is at the row's end only while items are dragged out of it.
    static func showsAirDropTile(_ tray: Tray) -> Bool { tray.draggingOut }

    /// Where the room below the camera starts.
    private var top: CGFloat { closedNotch.height + PlayerLayout.cameraGap }
    /// Kept clear at the bottom for the handle.
    private static let handleRoom: CGFloat = 14

    @ViewBuilder private func content(_ proxy: GeometryProxy) -> some View {
        Group {
            if dropping {
                dropZones
                    .padding(.horizontal, PlayerLayout.padding)
                    .padding(.top, top)
                    .padding(.bottom, Self.handleRoom)
                    .transition(.opacity)
            } else if tray.items.isEmpty {
                empty
                    .padding(.horizontal, PlayerLayout.padding)
                    .padding(.top, top)
                    .padding(.bottom, Self.handleRoom)
                    .transition(.opacity)
            } else {
                shelf(width: proxy.size.width)
                    .frame(maxHeight: .infinity)
                    .padding(.top, top)
                    .padding(.bottom, Self.handleRoom)
                    .transition(.opacity)
            }
        }
        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        .overlay(alignment: .bottom) {
            // Only when there's more than fits, or it's widened to show it all.
            if !dropping, expanded || Shelf.width(count: tray.items.count) > proxy.size.width {
                Grabber(label: expanded ? "Show Less" : "Show All") { expand(!expanded) }
                    .notchControl(enabled: isVisible)
                    .transition(.opacity)
            }
        }
    }

    // MARK: The shelf

    private func shelf(width: CGFloat) -> some View {
        let airDrop = Self.showsAirDropTile(tray)
        return VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .trailing) {
                row(width: width - (airDrop ? Shelf.airDropWidth : 0))
                    .frame(width: width, alignment: .leading)
                if airDrop {
                    AirDropTile(targeted: airDropTargeted)
                        .reportsAirDropFrame()
                        .padding(.trailing, Shelf.inset)
                        .transition(.opacity)
                }
            }
            footer
                .padding(.horizontal, PlayerLayout.padding)
        }
    }

    /// Only the tiles in sight, and a few either side, are made; the rest of the row is space. It
    /// fades at an edge only where there's more past it.
    private func row(width: CGFloat) -> some View {
        let step = Shelf.tile.width + Shelf.spacing
        let skipped = max(Int((scroll / step).rounded(.down)) - 3, 0)
        let shown = tray.items.dropFirst(skipped).prefix(Int((width / step).rounded(.up)) + 6)
        let reach = Shelf.reach(count: tray.items.count, in: width)
        return HStack(spacing: Shelf.spacing) {
            if skipped > 0 {
                Color.clear.frame(width: CGFloat(skipped) * step - Shelf.spacing, height: 1)
            }
            ForEach(shown) { item in
                ShelfTile(item: item, tray: tray, isVisible: isVisible) { over in
                    if over { pointed = item.id } else if pointed == item.id { pointed = nil }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
        .padding(.horizontal, Shelf.inset)
        .offset(x: -scroll)
        .frame(width: width, height: Shelf.tile.height, alignment: .leading)
        .mask { EdgeFade(start: scroll > 1, end: scroll < reach - 1) }
    }

    // MARK: The line under the row

    /// What the item under the pointer is and where it came from; or how many are selected; or,
    /// with neither, what can be done.
    private var footer: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            let (text, symbol) = footerText
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol).font(.system(size: 9, weight: .semibold)) }
                Text(text).lineLimit(1).truncationMode(.middle)
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .id(text)
            .transition(.opacity)
        }
        .animation(.easeOut(duration: 0.15), value: pointed)
        .animation(.easeOut(duration: 0.15), value: tray.selection)
        .animation(.easeOut(duration: 0.15), value: tray.justCopied)
    }

    private var footerText: (String, String?) {
        if let item = tray.items.first(where: { $0.id == pointed }) {
            if tray.justCopied.contains(item.id) { return ("Copied", "checkmark") }
            return (TrayItemPicture.detail(of: item, in: tray), nil)
        }
        if let item = tray.items.first(where: { tray.justCopied.contains($0.id) }) {
            return ("Copied \(TrayItemPicture.title(of: item))", "checkmark")
        }
        if !tray.selection.isEmpty { return ("\(tray.selection.count) of \(tray.items.count) selected", nil) }
        return ("Click to select, drag anywhere, double-click to paste", nil)
    }

    // MARK: Empty

    /// With nothing in it: what it's for, in a dashed outline of where things will go.
    private var empty: some View {
        HStack(spacing: 14) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.white.opacity(0.65))
                .frame(width: 56, height: 56)
                .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .accessibilityHidden(true)
            Text(emptyLine)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 260, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.18), style: StrokeStyle(lineWidth: 0.75, dash: [4, 5]))
        }
    }

    private var emptyLine: String {
        guard keepsCopies else { return "Drop files here to keep them close." }
        return tray.pasteBlocked
            ? "To keep what you copy, allow Glance in Privacy & Security, under Paste from Other Apps."
            : "Drop files here. What you copy and your screenshots show up here too."
    }

    // MARK: Dropping

    /// Something dragged in from another app: kept in the tray, or sent with AirDrop, whichever it's
    /// let go over.
    private var dropZones: some View {
        HStack(spacing: 10) {
            DropZone(title: "Keep in Tray", lit: !airDropTargeted) {
                Image(systemName: "tray.and.arrow.down").font(.system(size: 28, weight: .light))
            }
            // AirDrop has no symbol of its own: its icon, as the Share menu shows it.
            DropZone(title: "AirDrop", lit: airDropTargeted) {
                Image(nsImage: AirDropTile.icon).resizable().frame(width: 36, height: 36)
            }
            .reportsAirDropFrame()
        }
    }
}

/// One thing in the tray: its picture in a lit well, and its name under it. Selected, the tile
/// takes the accent color, edged with it, with a checkmark in its corner. Several files kept
/// together show as a stack, with how many on it.
private struct ShelfTile: View {
    let item: TrayItem
    @ObservedObject var tray: Tray
    let isVisible: Bool
    let pointing: (Bool) -> Void

    var body: some View {
        let chosen = tray.selection.contains(item.id)
        let count = item.kind == .files ? item.names.count : 1
        VStack(spacing: 3) {
            ZStack(alignment: .topLeading) {
                if count > 1 { Backplates() }
                Well { TrayItemPicture(item: item, tray: tray, size: Shelf.well) }
            }
            .frame(width: Shelf.well.width, height: Shelf.well.height, alignment: .topLeading)
            TileName(TrayItemPicture.title(of: item), middle: item.kind == .files || item.kind == .image)
        }
        .padding(.top, 6)
        .frame(width: Shelf.tile.width, height: Shelf.tile.height, alignment: .top)
        .overlay(alignment: .topLeading) {
            if count > 1 {
                Text("\(count)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 15)
                    .background(Color.accentColor, in: Capsule())
                    .offset(x: 50, y: 39)
            }
        }
        .tileChrome(lit: chosen)
        .overlay(alignment: .topLeading) {
            if chosen {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.accentColor)
                    .frame(width: 16, height: 16)
                    .offset(x: 4, y: count > 1 ? 22 : 4)
                    .transition(.opacity)
            }
        }
        .overlay {
            TileInteraction(item: item, tray: tray, selector: tray, clickSelects: true, hover: pointing)
        }
        .animation(.easeOut(duration: 0.15), value: chosen)
        .notchControl(enabled: isVisible)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TrayItemPicture.title(of: item))
        .accessibilityValue(TrayItemPicture.detail(of: item, in: tray))
        .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
    }
}

/// The faintly lit well at the top of a tile that its picture sits in.
private struct Well<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(.white.opacity(0.06))
            .frame(width: Shelf.well.width, height: Shelf.well.height)
            .overlay { content }
    }
}

/// Two wells behind a tile's own, a little down and to the right of it, for a stack.
private struct Backplates: View {
    var body: some View {
        ForEach([6, 3], id: \.self) { (step: CGFloat) in
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(step == 6 ? 0.035 : 0.055))
                .strokeBorder(.white.opacity(0.05), lineWidth: 1)
                .frame(width: Shelf.well.width, height: Shelf.well.height)
                .offset(x: step, y: step)
        }
    }
}

/// A tile's name: small, gray, centered. A file's is shortened in the middle, to keep its
/// extension; a text's or a link's runs on to a second line.
private struct TileName: View {
    let text: String
    var middle = true
    init(_ text: String, middle: Bool = true) {
        self.text = text
        self.middle = middle
    }

    var body: some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .lineLimit(middle ? 1 : 2)
            .truncationMode(middle ? .middle : .tail)
            .frame(width: Shelf.tile.width - 6, height: 26, alignment: .top)
    }
}

extension View {
    /// A selected tile, or one something's dragged over: tinted with the accent color, and edged
    /// with it.
    fileprivate func tileChrome(lit: Bool) -> some View {
        background {
            if lit {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.16))
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .transition(.opacity)
            }
        }
    }
}

/// AirDrop, as a tile at the row's end while items are dragged out: let go on it to send them.
private struct AirDropTile: View {
    let targeted: Bool

    static let icon = NSWorkspace.shared.icon(forFile: "/System/Library/CoreServices/Finder.app/Contents/Applications/AirDrop.app")

    var body: some View {
        VStack(spacing: 3) {
            Well {
                Image(nsImage: Self.icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 8)
            }
            TileName("AirDrop")
        }
        .padding(.top, 6)
        .frame(width: Shelf.tile.width, height: Shelf.tile.height, alignment: .top)
        .tileChrome(lit: targeted)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("AirDrop")
    }
}

/// One of the two places something dragged in from another app can go, lit while it's over it.
private struct DropZone<Glyph: View>: View {
    let title: String
    let lit: Bool
    @ViewBuilder let glyph: Glyph

    var body: some View {
        VStack(spacing: 12) {
            glyph.frame(height: 36)
            Text(title).font(.callout.weight(.medium)).multilineTextAlignment(.center)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.white.opacity(lit ? 0.14 : 0.04), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(lit ? 0.7 : 0.2), lineWidth: lit ? 1.5 : 0.75)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(lit ? .isSelected : [])
    }
}

/// The row's mask: solid, but for a short fade at each end there's more past.
private struct EdgeFade: View {
    let start: Bool
    let end: Bool

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                Color.black.opacity(start ? 0 : 1)
            }
            .frame(width: 16)
            Color.black
            ZStack {
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                Color.black.opacity(end ? 0 : 1)
            }
            .frame(width: 16)
        }
        .animation(.easeOut(duration: 0.18), value: start)
        .animation(.easeOut(duration: 0.18), value: end)
    }
}

/// Where AirDrop is in the notch, for dropping on it.
struct AirDropFrame: PreferenceKey {
    static let defaultValue: CGRect? = nil
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) { value = nextValue() ?? value }
}

extension View {
    /// Says where AirDrop is, for drops on it.
    fileprivate func reportsAirDropFrame() -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(key: AirDropFrame.self, value: proxy.frame(in: .named(ControlFrames.space)))
            }
        }
    }
}

/// The handle at the bottom of the tray, as a sheet's: pull down, or click it, to widen the notch
/// to show everything; again, to bring it back.
private struct Grabber: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Capsule()
            .fill(.white.opacity(0.3))
            .frame(width: 36, height: 5)
            .frame(width: 96, height: 16)
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
    }
}

/// The open notch's two pages: the player, and the tray to its right.
enum NotchPage {
    case player, tray
}
