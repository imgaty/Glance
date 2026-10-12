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
    /// A thumbnail's side: the player's cover's, in its layout with the cover on top.
    static let tile: CGFloat = 60
    static let spacing: CGFloat = 10
    /// Room around each thumbnail for it to lift, and for the ring around a chosen one.
    static let lift: CGFloat = 10

    /// The row of thumbnails, from the first to the last, with the notch's padding at both ends.
    static func width(count: Int) -> CGFloat {
        count == 0 ? 0 : CGFloat(count) * tile + CGFloat(count - 1) * spacing + PlayerLayout.padding * 2
    }

    /// The room AirDrop takes at the row's end while something's dragged, its gap included.
    static let wellWidth: CGFloat = tile + PlayerLayout.padding

    /// How far the row scrolls in a notch this wide.
    static func reach(count: Int, in width: CGFloat) -> CGFloat {
        max(self.width(count: count) - width, 0)
    }
}

/// The tray in the open notch, drawn as the player is: a row of pictures the size of its cover,
/// and under them, as its title and artist, the name of the one under the pointer, or the newest,
/// and where and when it came from. Nothing on it is a button: an item is clicked to copy it,
/// dragged to put it somewhere, right-clicked for everything else. Something dragged over the notch
/// parts the row for it, as the Dock does, with AirDrop at its end. With more in it than fits, its
/// handle, or a pull down, widens the notch to show them all.
struct TrayView: View {
    @ObservedObject var tray: Tray
    let isVisible: Bool
    /// Something is being dragged over the notch.
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
    /// The item under the pointer, whose name shows.
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
        // Smooth, settling without overshoot, as the system's own motion does.
        .animation(.smooth(duration: 0.35), value: tray.items.map(\.id))
        .animation(.smooth(duration: 0.3), value: dropping)
        .animation(.smooth(duration: 0.3), value: Self.showsAirDrop(tray: tray, dropping: dropping))
        .animation(.smooth(duration: 0.25), value: airDropTargeted)
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

    /// AirDrop is there to drop on only while something's being dragged: over the notch, or out of
    /// the tray.
    static func showsAirDrop(tray: Tray, dropping: Bool) -> Bool {
        dropping || tray.draggingOut
    }

    /// Where the room for the row starts: just below the camera.
    private var rowTop: CGFloat { closedNotch.height + PlayerLayout.cameraGap }
    /// Kept clear at the bottom for the handle.
    private static let handleRoom: CGFloat = 14

    @ViewBuilder private func content(_ proxy: GeometryProxy) -> some View {
        let well = Self.showsAirDrop(tray: tray, dropping: dropping)
        let rowHeight = Shelf.tile + Shelf.lift * 2
        Group {
            if tray.items.isEmpty {
                empty(proxy, well: well)
            } else {
                // The row and its name, in the middle of the room below the camera, with as much
                // space under them as above.
                VStack(alignment: .leading, spacing: 0) {
                    ZStack(alignment: .trailing) {
                        row(width: proxy.size.width - (well ? Shelf.wellWidth : 0))
                            .frame(width: proxy.size.width, height: rowHeight, alignment: .leading)
                        if well {
                            AirDropTarget(targeted: airDropTargeted)
                                .reportsAirDropFrame()
                                .padding(.trailing, PlayerLayout.padding)
                                .transition(.scale(scale: 0.8).combined(with: .opacity))
                        }
                    }
                    label
                        .padding(.horizontal, PlayerLayout.padding)
                        .padding(.top, -Shelf.lift + 8)
                }
                .frame(maxHeight: .infinity)
                .padding(.top, rowTop - Shelf.lift)
                .padding(.bottom, Self.handleRoom - Shelf.lift)
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

    /// Only the thumbnails in sight, and a few either side, are made; the rest of the row is space.
    private func row(width: CGFloat) -> some View {
        let step = Shelf.tile + Shelf.spacing
        let skipped = max(Int(((scroll - (dropping ? step : 0)) / step).rounded(.down)) - 3, 0)
        let shown = tray.items.dropFirst(skipped).prefix(Int((width / step).rounded(.up)) + 6)
        return HStack(spacing: Shelf.spacing) {
            if dropping {
                DropSlot()
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
            if skipped > 0 {
                Color.clear.frame(width: CGFloat(skipped) * step - Shelf.spacing, height: 1)
            }
            ForEach(shown) { item in
                thumb(item)
                    .transition(.scale(scale: 0.8, anchor: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, PlayerLayout.padding)
        // Room above and below for a thumbnail to lift, and for the ring around a chosen one.
        .padding(.vertical, Shelf.lift)
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

    private func thumb(_ item: TrayItem) -> some View {
        TrayThumb(item: item, tray: tray, isVisible: isVisible) { over in
            if over { pointed = item.id } else if pointed == item.id { pointed = nil }
        }
    }

    // MARK: The name under the row

    /// The name of the item under the pointer, or of the newest, and where and when it came from;
    /// while something's dragged over the notch, what letting go does.
    private var label: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            let (title, detail, symbol) = labelText
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: PlayerLayout.titleSize - 1, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 4) {
                    if let symbol { Image(systemName: symbol).font(.system(size: 10, weight: .semibold)) }
                    Text(detail).lineLimit(1)
                }
                .font(.system(size: PlayerLayout.timeSize + 1))
                .foregroundStyle(PlayerLayout.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .id(title + detail)
            .transition(.opacity)
        }
        .animation(.easeOut(duration: 0.15), value: pointed)
        .animation(.easeOut(duration: 0.15), value: tray.justCopied)
    }

    private var labelText: (String, String, String?) {
        if airDropTargeted { return ("AirDrop", "Let go to send it to a device nearby", nil) }
        if dropping { return ("Keep in Tray", "Let go to keep it here, or drop it on AirDrop to send it", nil) }
        let chosen = tray.chosen
        if chosen.count > 1, pointed == nil { return ("\(chosen.count) Items", "Selected", nil) }
        guard let item = tray.items.first(where: { $0.id == pointed }) ?? tray.items.first else { return ("", "", nil) }
        if tray.justCopied.contains(item.id) { return (TrayItemPicture.title(of: item), "Copied", "checkmark") }
        return (TrayItemPicture.title(of: item), TrayItemPicture.detail(of: item, in: tray), nil)
    }

    // MARK: Empty

    /// With nothing in it: what it's for; with something dragged over it, the whole notch takes it.
    private func empty(_ proxy: GeometryProxy, well: Bool) -> some View {
        let width = proxy.size.width - (well ? Shelf.wellWidth : 0)
        return ZStack(alignment: .trailing) {
            VStack(spacing: 4) {
                Image(systemName: dropping ? "tray.and.arrow.down.fill" : "tray")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(dropping ? .white : PlayerLayout.secondary)
                    .contentTransition(.symbolEffect(.replace))
                    .padding(.bottom, 3)
                Text(dropping ? (airDropTargeted ? "AirDrop" : "Keep in Tray") : "Tray Is Empty")
                    .font(.system(size: 13, weight: .semibold))
                    .contentTransition(.opacity)
                Text(dropping ? (airDropTargeted ? "Let go to send it to a device nearby" : "Let go to keep it here") : emptyLine)
                    .font(.system(size: 11))
                    .foregroundStyle(PlayerLayout.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 250)
            }
            .frame(width: width)
            .frame(maxHeight: .infinity)
            .padding(.top, closedNotch.height)
            .frame(maxWidth: .infinity, alignment: .leading)
            if well {
                AirDropTarget(targeted: airDropTargeted)
                    .reportsAirDropFrame()
                    .padding(.trailing, PlayerLayout.padding)
                    .padding(.top, closedNotch.height)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .frame(height: proxy.size.height - 10)
    }

    private var emptyLine: String {
        guard keepsCopies else { return "Drop files on the notch to keep them close." }
        return tray.pasteBlocked
            ? "To keep what you copy, allow Glance in Privacy & Security, under Paste from Other Apps."
            : "Drop files on the notch. What you copy and your screenshots show up here too."
    }
}

/// One thing in the tray: its picture, nothing more; its name shows under the row. Under the
/// pointer it lifts, as things do under the pointer on iPad; chosen, a ring in the accent color goes
/// around it, as Photos marks chosen photos; copied, it gives a little.
private struct TrayThumb: View {
    let item: TrayItem
    @ObservedObject var tray: Tray
    let isVisible: Bool
    let pointing: (Bool) -> Void
    @State private var hovered = false

    var body: some View {
        let chosen = tray.selection.contains(item.id)
        let copied = tray.justCopied.contains(item.id)
        let radius = TrayItemPicture.radius(for: Shelf.tile)
        TrayItemPicture(item: item, tray: tray, side: Shelf.tile)
            .overlay {
                if chosen {
                    RoundedRectangle(cornerRadius: radius + 4, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 2.5)
                        .padding(-4)
                        .transition(.opacity)
                }
            }
            .scaleEffect(copied ? 0.95 : hovered ? 1.05 : 1, anchor: .bottom)
            .overlay {
                TileInteraction(item: item, tray: tray, selector: tray, clickSelects: false) { over in
                    hovered = over
                    pointing(over)
                }
            }
            .animation(.smooth(duration: 0.2), value: hovered)
            .animation(.smooth(duration: 0.2), value: copied)
            .animation(.easeOut(duration: 0.15), value: chosen)
            .notchControl(enabled: isVisible)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(TrayItemPicture.title(of: item))
            .accessibilityValue(TrayItemPicture.detail(of: item, in: tray))
            .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
    }
}

/// The place opened in the row for what's being dragged in: the row parts, as the Dock does.
private struct DropSlot: View {
    var body: some View {
        RoundedRectangle(cornerRadius: TrayItemPicture.radius(for: Shelf.tile), style: .continuous)
            .fill(.white.opacity(0.07))
            .frame(width: Shelf.tile, height: Shelf.tile)
    }
}

/// AirDrop, at the row's end while something's dragged: its icon, as Finder shows it, lifting as
/// something comes over it.
private struct AirDropTarget: View {
    let targeted: Bool

    static let icon = NSWorkspace.shared.icon(forFile: "/System/Library/CoreServices/Finder.app/Contents/Applications/AirDrop.app")

    var body: some View {
        Image(nsImage: Self.icon)
            .resizable()
            .frame(width: Shelf.tile + 8, height: Shelf.tile + 8)
            .scaleEffect(targeted ? 1.14 : 1)
            .shadow(color: .black.opacity(targeted ? 0.45 : 0.2), radius: targeted ? 10 : 4, y: targeted ? 4 : 2)
            .frame(width: Shelf.tile, height: Shelf.tile)
            .accessibilityLabel("AirDrop")
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
