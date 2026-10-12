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
    /// The band of blur reaches past the thumbnails by this much, so its soft edge fades out
    /// beyond them, not over them.
    static let bandMargin: CGFloat = 16

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
/// parts the row for it, as the Dock does, with AirDrop at its end. Its handle, or a pull down,
/// opens it out into everything it's kept, by day.
struct TrayView: View {
    @ObservedObject var tray: Tray
    let isVisible: Bool
    /// Something is being dragged over the notch.
    let dropping: Bool
    /// How far the row is scrolled.
    let scroll: CGFloat
    /// Something dragged is over AirDrop.
    var airDropTargeted = false
    /// Opened out into the history, and how to open it out or back.
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
            if built || dropping {
                Group {
                    if expanded { history(proxy) } else { content(proxy) }
                }
                .transition(.opacity.animation(.easeOut(duration: 0.2)))
            }
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: tray.items.map(\.id))
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: dropping)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: Self.showsAirDrop(tray: tray, dropping: dropping))
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: airDropTargeted)
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

    /// Where the row sits: just below the camera, its thumbnails' tops lined up with the player's
    /// cover's.
    private var rowTop: CGFloat { closedNotch.height + PlayerLayout.cameraGap + 2 }

    @ViewBuilder private func content(_ proxy: GeometryProxy) -> some View {
        let well = Self.showsAirDrop(tray: tray, dropping: dropping)
        let rowHeight = Shelf.tile + Shelf.lift * 2
        Group {
            if tray.items.isEmpty {
                empty(proxy, well: well)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ZStack(alignment: .trailing) {
                        row(width: proxy.size.width - (well ? Shelf.wellWidth : 0))
                            .frame(width: proxy.size.width, height: rowHeight, alignment: .leading)
                        if well {
                            AirDropTarget(targeted: airDropTargeted)
                                .reportsAirDropFrame()
                                .padding(.trailing, PlayerLayout.padding)
                                .transition(.scale(scale: 0.6).combined(with: .opacity))
                        }
                    }
                    label
                        .padding(.horizontal, PlayerLayout.padding)
                        .padding(.top, -Shelf.lift + 6)
                }
                .padding(.top, rowTop - Shelf.lift)
                .background(alignment: .top) {
                    // One soft band of blur behind the row and its name, so they read over a busy
                    // window.
                    TrayBlur()
                        .frame(height: rowHeight + 34 + Shelf.bandMargin)
                        .padding(.horizontal, PlayerLayout.padding - Shelf.bandMargin)
                        .padding(.top, rowTop - Shelf.bandMargin)
                }
            }
        }
        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        .overlay(alignment: .bottom) {
            if !tray.items.isEmpty, !dropping {
                Grabber(label: "Show History") { expand(true) }
                    .notchControl(enabled: isVisible)
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
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
            if skipped > 0 {
                Color.clear.frame(width: CGFloat(skipped) * step - Shelf.spacing, height: 1)
            }
            ForEach(shown) { item in
                thumb(item)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
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
            // As names on the desktop are, readable over a bright window or wallpaper behind.
            .shadow(color: .black.opacity(0.45), radius: 2, y: 0.5)
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

    // MARK: The history

    /// Everything the tray has kept, in the notch opened out: what was copied, screenshots, and what
    /// was dropped, by day, newest first, in a grid that scrolls; the name of the one under the
    /// pointer above it, where the notch is darkest; and the handle to close it back to the row.
    private func history(_ proxy: GeometryProxy) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            label
                .padding(.horizontal, PlayerLayout.padding)
                .padding(.bottom, 2)
            ScrollView(.vertical) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: Shelf.tile, maximum: Shelf.tile), spacing: Shelf.spacing)],
                    alignment: .leading, spacing: Shelf.spacing
                ) {
                    ForEach(Self.days(of: tray.items), id: \.day) { group in
                        Section {
                            ForEach(group.items) { thumb($0) }
                        } header: {
                            Text(Self.title(of: group.day))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(PlayerLayout.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 6)
                        }
                    }
                }
                .padding(.horizontal, PlayerLayout.padding)
                .padding(.vertical, Shelf.lift)
            }
            .scrollIndicators(.never)
            // The grid softens away at its edges, as content scrolling under a toolbar does.
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 10)
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 14)
                }
            }
            .notchControl(enabled: isVisible)
            Grabber(label: "Show Less") { expand(false) }
                .notchControl(enabled: isVisible)
                .frame(maxWidth: .infinity)
        }
        .padding(.top, closedNotch.height + PlayerLayout.cameraGap + 2)
        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        // The soft blur behind all of it, below the camera, so it reads over a busy window.
        .background {
            TrayBlur()
                .padding(.horizontal, PlayerLayout.padding - Shelf.bandMargin)
                .padding(.top, closedNotch.height)
                .padding(.bottom, 2)
        }
    }

    /// Items by the day they came in.
    private static func days(of items: [TrayItem]) -> [(day: Date, items: [TrayItem])] {
        let calendar = Calendar.current
        var groups: [(day: Date, items: [TrayItem])] = []
        for item in items {
            let day = calendar.startOfDay(for: item.added)
            if groups.last?.day == day { groups[groups.count - 1].items.append(item) } else { groups.append((day, [item])) }
        }
        return groups
    }

    /// Today, Yesterday, then the weekday for this week, then the date, as Photos heads its days.
    private static func title(of day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        if let week = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: .now)), day >= week {
            return day.formatted(.dateTime.weekday(.wide))
        }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide))
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
            .scaleEffect(copied ? 0.94 : hovered ? 1.07 : 1)
            .shadow(color: .black.opacity(hovered ? 0.45 : 0), radius: hovered ? 8 : 0, y: hovered ? 4 : 0)
            .overlay {
                TileInteraction(item: item, tray: tray, selector: tray, clickSelects: false) { over in
                    hovered = over
                    pointing(over)
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hovered)
            .animation(.spring(response: 0.25, dampingFraction: 0.55), value: copied)
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

/// The handle at the bottom of the tray, as a sheet's: pull down, or click it, to open the history;
/// in the history, to close it back.
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

/// The band of blur behind the tray's row: a plain blur of what the notch shows behind it, its glass
/// and all, with no tint and no added color, so the notch keeps its look and only busy windows behind
/// it soften. Its edges fade out over many points, so there's no edge to see.
struct TrayBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> SoftBlurView { SoftBlurView() }
    func updateNSView(_ view: SoftBlurView, context: Context) {}
}

/// A backdrop layer, the kind macOS's blurs are made of, with only a blur on it: macOS's own blur
/// views add a tint and more saturated color, which made the band a darker rectangle.
final class SoftBlurView: NSView {
    static let radius: CGFloat = 7
    static let feather: CGFloat = 18
    private static let corner = TrayItemPicture.radius(for: Shelf.tile) + 6

    private let backdrop: CALayer = (NSClassFromString("CABackdropLayer") as? CALayer.Type)?.init() ?? CALayer()
    private let fade = CALayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        layer = CALayer()
        wantsLayer = true
        backdrop.setValue(0.5, forKey: "scale")
        if let type = NSClassFromString("CAFilter") as? NSObject.Type,
            let blur = type.perform(NSSelectorFromString("filterWithType:"), with: "gaussianBlur")?.takeUnretainedValue() as? NSObject
        {
            blur.setValue(Self.radius, forKey: "inputRadius")
            blur.setValue(true, forKey: "inputNormalizeEdges")
            backdrop.filters = [blur]
        }
        if let mask = Self.mask {
            let side = CGFloat(mask.width) / 2, inset = Self.corner + Self.feather
            fade.contents = mask
            fade.contentsScale = 2
            fade.contentsCenter = CGRect(x: inset / side, y: inset / side, width: 1 / side, height: 1 / side)
        }
        backdrop.mask = fade
        layer?.addSublayer(backdrop)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backdrop.frame = bounds
        fade.frame = bounds
        CATransaction.commit()
    }

    /// Rounded as the band is, its edges fading out over the feather, eased so the fade has no line
    /// where it starts or ends. Drawn at twice the size, and stretched in the middle.
    private static let mask: CGImage? = {
        let side = Int((corner + feather) * 2 + 1), scale = 2, pixels = side * scale
        guard
            let context = CGContext(
                data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: pixels,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue),
            let data = context.data?.assumingMemoryBound(to: UInt8.self)
        else { return nil }
        // How far each point is inside the rounded rectangle at the feather's inner edge.
        let half = CGFloat(side) / 2, inner = half - feather
        for y in 0..<pixels {
            for x in 0..<pixels {
                let px = abs((CGFloat(x) + 0.5) / CGFloat(scale) - half) - (inner - corner)
                let py = abs((CGFloat(y) + 0.5) / CGFloat(scale) - half) - (inner - corner)
                let outside = hypot(max(px, 0), max(py, 0)) + min(max(px, py), 0) - corner
                let t = min(max(-outside / feather + 1, 0), 1)
                data[y * pixels + x] = UInt8((t * t * (3 - 2 * t) * 255).rounded())
            }
        }
        return context.makeImage()
    }()
}

/// The open notch's two pages: the player, and the tray to its right.
enum NotchPage {
    case player, tray
}
