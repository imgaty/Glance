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
    /// An item: its icon, and its name under it, as Finder's icon view shows a file.
    static let tile = CGSize(width: 78, height: 98)
    /// The icon's square.
    static let icon: CGFloat = 56
    static let spacing: CGFloat = 10
    /// At the row's ends: the first icon lines up with the player's artwork.
    static let inset: CGFloat = PlayerLayout.padding - (tile.width - icon) / 2

    /// The row of items, from the first to the last, with its insets at both ends.
    static func width(count: Int) -> CGFloat {
        count == 0 ? 0 : CGFloat(count) * tile.width + CGFloat(count - 1) * spacing + inset * 2
    }

    /// How far the row scrolls in a notch this wide.
    /// The fewest items the tray is ever as narrow as: fewer sit in the middle of that width.
    static let fewest = 3
    /// The most it's as wide as: six items, and half of the next, so a tray with more shows at a
    /// glance that its row goes on.
    static let most = 6
    static let narrowest: CGFloat = width(count: fewest)
    static let peekWidth: CGFloat = inset + CGFloat(most) * (tile.width + spacing) + tile.width / 2

    static func reach(count: Int, in width: CGFloat) -> CGFloat {
        max(self.width(count: count) - width, 0)
    }
}

/// The tray in the open notch, as Finder's icon view: each item's icon with its name under it. It's
/// as wide as its items, up to a point (see `NotchModel.trayWidth`), and past that its row scrolls.
/// A click selects, as in Finder; a drag takes the item, or every selected one, anywhere; a
/// double-click pastes it; a right-click shows the rest. Something dragged in from another app gets
/// two places to go: the tray, and AirDrop.
struct TrayView: View {
    @ObservedObject var tray: Tray
    let isVisible: Bool
    /// Something from another app is being dragged over the notch.
    let dropping: Bool
    /// How far the row is scrolled.
    let scroll: CGFloat
    /// Something dragged is over AirDrop.
    var airDropTargeted = false
    @Environment(\.closedNotch) private var closedNotch
    @AppStorage(Preferences.trayClipboard) private var keepsCopies = true
    @AppStorage(Preferences.trayScreenshots) private var keepsScreenshots = true
    /// With Reduce Motion on, items come and go with a fade alone.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
        .animation(.smooth(duration: 0.2), value: airDropTargeted)
        .onChange(of: isVisible, initial: true) {
            guard isVisible else { return }
            built = true
            // Files moved to the Trash since it last showed go, once they've been looked for.
            tray.purge()
            Task { await tray.checkFiles() }
        }
        .task(id: isVisible) {
            guard !isVisible else { return }
            try? await Task.sleep(for: .seconds(0.5))
            if !Task.isCancelled { built = false }
        }
    }

    /// Where the room below the camera starts.
    private var top: CGFloat { closedNotch.height + PlayerLayout.cameraGap }
    /// Under the row, the player's padding, as under its buttons.
    private static let bottomRoom = PlayerLayout.padding
    /// Around the places to drop: their corners are then concentric with the notch's.
    private static let zoneInset: CGFloat = 12
    /// Each place's symbol, as a font's size.
    private static let zoneGlyph: CGFloat = 26

    @ViewBuilder private func content(_ proxy: GeometryProxy) -> some View {
        Group {
            if dropping {
                dropZones
                    .padding(.horizontal, Self.zoneInset)
                    .padding(.top, top)
                    .padding(.bottom, Self.zoneInset)
                    .transition(.opacity)
            } else if tray.items.isEmpty {
                empty
                    .padding(.top, top)
                    .padding(.bottom, Self.bottomRoom)
                    .transition(.opacity)
            } else {
                row(width: proxy.size.width)
                    .frame(maxHeight: .infinity)
                    .padding(.top, top)
                    .padding(.bottom, Self.bottomRoom)
                    .transition(.opacity)
            }
        }
        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
    }

    // MARK: The row

    /// Only the items in sight, and a few either side, are made; the rest of the row is space. It
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
                ItemTile(item: item, tray: tray, isVisible: isVisible)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.92, anchor: .bottom)))
            }
        }
        .padding(.horizontal, Shelf.inset)
        .offset(x: -scroll)
        // A row that fits sits in the middle, the same room either side; one that doesn't starts at
        // the left and scrolls.
        .frame(width: width, height: Shelf.tile.height, alignment: reach > 0 ? .leading : .center)
        .mask { EdgeFade(start: scroll > 1, end: scroll < reach - 1) }
    }

    // MARK: Empty

    /// With nothing in it: what it's for, as an app says it has nothing to show.
    private var empty: some View {
        VStack(spacing: 3) {
            Image(systemName: "tray")
                .font(.system(size: 26))
                .foregroundStyle(PlayerLayout.secondary)
                .padding(.bottom, 6)
            Text("Tray Is Empty")
                .font(.system(size: 13, weight: .semibold))
            Text(emptyLine)
                .font(.system(size: 11))
                .foregroundStyle(PlayerLayout.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// What shows up here besides what's dropped, as set in Settings.
    private var emptyLine: String {
        if keepsCopies, tray.pasteBlocked {
            return "To keep what you copy, allow Glance in Privacy & Security, under Paste from Other Apps."
        }
        return switch (keepsCopies, keepsScreenshots) {
        case (true, true): "Drop files here. Copies and screenshots show up too."
        case (true, false): "Drop files here. Copies show up too."
        case (false, true): "Drop files here. Screenshots show up too."
        case (false, false): "Drop files here to keep them close."
        }
    }

    // MARK: Dropping

    /// Something dragged in from another app: kept in the tray, or sent with AirDrop, whichever it's
    /// let go over.
    private var dropZones: some View {
        HStack(spacing: 8) {
            DropZone(title: "Keep in Tray", lit: !airDropTargeted, radius: PlayerLayout.cornerRadius - Self.zoneInset) {
                Image(systemName: "tray.and.arrow.down.fill").font(.system(size: Self.zoneGlyph))
            }
            // Both places in one style: a white symbol each, the same size.
            DropZone(title: "AirDrop", lit: airDropTargeted, radius: PlayerLayout.cornerRadius - Self.zoneInset) {
                AirDropSymbol.glyph(size: Self.zoneGlyph)
            }
            .reportsAirDropFrame()
        }
    }
}

/// One thing in the tray, with its name under it.
private struct ItemTile: View {
    let item: TrayItem
    @ObservedObject var tray: Tray
    let isVisible: Bool

    var body: some View {
        let chosen = tray.selection.contains(item.id)
        TileLayout(
            name: TrayItemPicture.title(of: item), keepsEnd: item.kind == .files || item.kind == .image, pinned: item.keptCopy, lit: chosen
        ) {
            TrayItemPicture(item: item, tray: tray, side: Shelf.icon)
        }
        .overlay {
            TileInteraction(item: item, tray: tray, live: isVisible)
        }
        .animation(.easeOut(duration: 0.12), value: chosen)
        .notchControl(enabled: isVisible)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TrayItemPicture.title(of: item))
        .accessibilityValue(TrayItemPicture.detail(of: item, in: tray))
        .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
        // What a click and the item's menu do, for VoiceOver and Voice Control.
        .accessibilityAction { tray.choose(item.id) }
        .accessibilityAction(named: "Copy") { tray.copy(tray.targets(of: item)) }
        .accessibilityAction(named: "Paste") { tray.paste(tray.targets(of: item)) }
        .accessibilityAction(named: "Quick Look") {
            TrayQuickLook.shared.show(TrayQuickLook.urls(for: tray.targets(of: item), in: tray))
        }
        .accessibilityActions {
            // What's dropped is always kept.
            if item.origin != .dropped {
                Button(item.keptCopy ? "Don't Keep" : "Keep") { tray.keep(Set(tray.targets(of: item).map(\.id)), !item.keptCopy) }
            }
        }
        .accessibilityAction(named: "Remove from Tray") { tray.remove(Set(tray.targets(of: item).map(\.id))) }
    }
}

/// An icon over its name, as Finder lays them out. Lit, as Finder shows a selected file: a gray
/// square behind the icon, and the name on the accent color.
private struct TileLayout<Icon: View>: View {
    let name: String
    /// A file's name is shortened in the middle, to keep its extension; a text's at its end.
    let keepsEnd: Bool
    /// A copy kept until it's removed: a pin before its name, as Finder sets a file's status by its
    /// name.
    var pinned = false
    let lit: Bool
    @ViewBuilder let icon: Icon

    var body: some View {
        VStack(spacing: 4) {
            icon
                .frame(width: Shelf.icon, height: Shelf.icon)
                .padding(4)
                .background {
                    if lit {
                        RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.white.opacity(0.2))
                    }
                }
            Text(pinned ? "\(Image(systemName: "pin.fill")) \(name)" : "\(name)")
                .font(.system(size: 11))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .truncationMode(keepsEnd ? .middle : .tail)
                // Legible on the glass, as names are on the desktop.
                .shadow(color: .black.opacity(lit ? 0 : 0.45), radius: 1, y: 0.5)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background {
                    if lit {
                        RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.accentColor)
                    }
                }
                .frame(width: Shelf.tile.width, height: 30, alignment: .top)
        }
        .frame(width: Shelf.tile.width, height: Shelf.tile.height, alignment: .top)
    }
}

/// AirDrop's own symbol, as Finder's sidebar shows it, in the white the notch's symbols are, for
/// the place to drop things to send them. Its app icon, which macOS draws in the icon style chosen
/// in Appearance settings (a gray glass tile with Clear), sat apart from everything around it.
private enum AirDropSymbol {
    /// The symbol, at a size as a font's. Apple keeps it among its own symbols, out of the public
    /// list, so it's asked for by its private name; failing that, the app icon stands in.
    @ViewBuilder static func glyph(size: CGFloat) -> some View {
        if let symbol = symbol?.withSymbolConfiguration(.init(pointSize: size, weight: .regular)) {
            Image(nsImage: symbol).renderingMode(.template)
        } else {
            Image(nsImage: icon).resizable().frame(width: size * 1.5, height: size * 1.5)
        }
    }

    private static let symbol: NSImage? = {
        let selector = NSSelectorFromString("imageWithPrivateSystemSymbolName:accessibilityDescription:")
        let images = NSImage.self as AnyObject
        guard images.responds(to: selector) else { return nil }
        return images.perform(selector, with: "airdrop", with: "AirDrop")?.takeUnretainedValue() as? NSImage
    }()

    private static let icon = NSWorkspace.shared.icon(forFile: "/System/Library/CoreServices/Finder.app/Contents/Applications/AirDrop.app")
}

/// One of the two places something dragged in from another app can go, lit while it's over it.
private struct DropZone<Glyph: View>: View {
    let title: String
    let lit: Bool
    let radius: CGFloat
    @ViewBuilder let glyph: Glyph

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // The symbol and its name dim together while the drag is elsewhere.
        VStack(spacing: 8) {
            glyph
                .frame(height: 40)
                .scaleEffect(lit && !reduceMotion ? 1.08 : 1)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(.white.opacity(lit ? 1 : 0.7))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.white.opacity(lit ? 0.16 : 0.06), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
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

/// The open notch's two pages: the player, and the tray to its right.
enum NotchPage {
    case player, tray
}
