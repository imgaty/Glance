//
//  TrayView.swift
//  Glance
//
//  Created by Gaty on 12/10/2026.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The shelf's measures, shared by what draws it and what scrolls it.
enum Shelf {
    /// A tile's width, and its picture's side.
    static let tile: CGFloat = 72
    static let picture: CGFloat = 56
    static let spacing: CGFloat = 6
    /// Two lines of names under the pictures.
    static let caption: CGFloat = 27
    /// A tile's highlight under the pointer, and the band of blur behind them all, around them by
    /// a margin, rounded concentric with it.
    static let platterRadius: CGFloat = 14
    static let platterHeight: CGFloat = 8 + picture + 5 + caption + 2
    /// Wide enough that the band's soft edge fades out beyond the tiles, not over them.
    static let bandMargin: CGFloat = 16

    /// The row of tiles, from the first to the last, with the notch's padding at both ends.
    static func width(count: Int) -> CGFloat {
        count == 0 ? 0 : CGFloat(count) * tile + CGFloat(count - 1) * spacing + PlayerLayout.padding * 2
    }

    /// The room the AirDrop well takes at the row's end, its gap before it included.
    static let wellWidth: CGFloat = tile + PlayerLayout.padding

    /// How far the row scrolls in a notch this wide.
    static func reach(count: Int, in width: CGFloat) -> CGFloat {
        max(self.width(count: count) - width, 0)
    }
}

/// The tray in the open notch: what was dropped and copied, newest first, in a row that scrolls
/// sideways with two fingers. Dragging something over the notch opens a place for it at the front,
/// as the Dock does for an app dragged into it. Its handle, or a pull down, opens it out into the
/// history: everything it has kept, by day, in a grid that scrolls.
struct TrayView: View {
    @ObservedObject var tray: Tray
    let isVisible: Bool
    /// Something is being dragged over the notch.
    let dropping: Bool
    /// How far the row is scrolled.
    let scroll: CGFloat
    /// Something dragged is over the AirDrop well.
    var airDropTargeted = false
    /// Opened out into the history, and how to open it out or back.
    var expanded = false
    var expand: (Bool) -> Void = { _ in }
    @Environment(\.closedNotch) private var closedNotch
    @AppStorage(Preferences.trayClipboard) private var keepsCopies = true
    @State private var filter = HistoryFilter.all
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

    /// The AirDrop well shows while something's dragged over the notch or out of the tray, and
    /// while items are chosen, to send them.
    static func showsAirDrop(tray: Tray, dropping: Bool) -> Bool {
        dropping || tray.draggingOut || !tray.selection.isEmpty
    }

    @ViewBuilder private func content(_ proxy: GeometryProxy) -> some View {
        let top = closedNotch.height + PlayerLayout.cameraGap + 4
        // A little room left at the bottom for the handle.
        let room = proxy.size.height - top - PlayerLayout.padding - 2
        let well = Self.showsAirDrop(tray: tray, dropping: dropping)
        ZStack(alignment: .topTrailing) {
            shelf(width: proxy.size.width - (well ? Shelf.wellWidth : 0), height: proxy.size.height, top: top, room: room)
                .frame(width: proxy.size.width, alignment: .leading)
            if well {
                AirDropWell(targeted: airDropTargeted, chosen: tray.selection.count) {
                    tray.airDrop(tray.shareable(tray.chosen))
                }
                .notchControl(enabled: isVisible && !tray.selection.isEmpty)
                .reportsAirDropFrame()
                .padding(.trailing, PlayerLayout.padding)
                .padding(.top, top + (room - Shelf.platterHeight) / 2)
                .transition(.move(edge: .trailing).combined(with: .opacity))
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

    @ViewBuilder private func shelf(width: CGFloat, height: CGFloat, top: CGFloat, room: CGFloat) -> some View {
        if tray.items.isEmpty {
            empty
                .frame(width: width, height: room)
                .padding(.top, top)
                .background(alignment: .top) {
                    // The whole notch takes the drop: a ring just inside its edges, below the
                    // camera, its corners concentric with the notch's.
                    if dropping {
                        let inset: CGFloat = 10
                        RoundedRectangle(cornerRadius: PlayerLayout.cornerRadius - inset, style: .continuous)
                            .strokeBorder(.white.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                            .frame(width: width - inset * 2, height: height - closedNotch.height - 6 - inset)
                            .padding(.top, closedNotch.height + 6)
                            .transition(.opacity)
                    }
                }
        } else {
            row(width: width)
                .frame(height: room)
                .padding(.top, top)
        }
    }

    /// Only the tiles in sight, and a few either side, are made; the rest of the row is space.
    private func row(width: CGFloat) -> some View {
        let step = Shelf.tile + Shelf.spacing
        let skipped = max(Int(((scroll - (dropping ? step : 0)) / step).rounded(.down)) - 3, 0)
        let shown = tray.items.dropFirst(skipped).prefix(Int((width / step).rounded(.up)) + 6)
        let count = tray.items.count + (dropping ? 1 : 0)
        return ZStack(alignment: .leading) {
            // One band of blur behind the whole row, from the first tile to the last, so names
            // read over whatever's behind the notch.
            TrayBlur()
                .frame(width: CGFloat(count) * step - Shelf.spacing + Shelf.bandMargin * 2, height: Shelf.platterHeight + 20)
                .padding(.leading, PlayerLayout.padding - Shelf.bandMargin)
            row(shown, skipped: skipped, step: step)
        }
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

    private func row(_ shown: ArraySlice<TrayItem>, skipped: Int, step: CGFloat) -> some View {
        HStack(spacing: Shelf.spacing) {
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

    // MARK: The history

    /// Everything the tray has kept, in the notch opened out: what was copied, screenshots, and what
    /// was dropped, by day, newest first, in a grid that scrolls; which to show along the top, as
    /// Photos chooses its views, and the handle at the bottom to close it back to the row.
    private func history(_ proxy: GeometryProxy) -> some View {
        let shown = tray.items.filter(filter.admits)
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                HistoryFilterPicker(selection: $filter)
                    .notchControl(enabled: isVisible)
                Spacer(minLength: 0)
                if Self.showsAirDrop(tray: tray, dropping: dropping) {
                    AirDropButton(targeted: airDropTargeted, chosen: tray.selection.count) {
                        tray.airDrop(tray.shareable(tray.chosen))
                    }
                    .notchControl(enabled: isVisible && !tray.selection.isEmpty)
                    .reportsAirDropFrame()
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
            .padding(.horizontal, PlayerLayout.padding)
            .frame(height: 30)
            .padding(.top, closedNotch.height + 6)
            if shown.isEmpty {
                Text(filter == .all ? "No History" : "No \(filter.title)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PlayerLayout.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical) {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: Shelf.tile, maximum: Shelf.tile), spacing: Shelf.spacing)],
                        alignment: .leading, spacing: 4
                    ) {
                        ForEach(Self.days(of: shown), id: \.day) { group in
                            Section {
                                ForEach(group.items) { TrayTile(item: $0, tray: tray, isVisible: isVisible) }
                            } header: {
                                Text(Self.title(of: group.day))
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(PlayerLayout.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, 8)
                                    .padding(.leading, 4)
                            }
                        }
                    }
                    .padding(.horizontal, PlayerLayout.padding - 2)
                    .padding(.vertical, 6)
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
            }
            Grabber(label: "Show Less") { expand(false) }
                .notchControl(enabled: isVisible)
        }
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

/// Which of the tray's items the history shows.
enum HistoryFilter: String, CaseIterable, Identifiable {
    case all, copied, screenshots, dropped

    var id: Self { self }
    var title: String {
        switch self {
        case .all: "All"
        case .copied: "Copied"
        case .screenshots: "Screenshots"
        case .dropped: "Dropped"
        }
    }

    func admits(_ item: TrayItem) -> Bool {
        switch self {
        case .all: true
        case .copied: item.origin == .copied
        case .screenshots: item.origin == .screenshot
        case .dropped: item.origin == .dropped
        }
    }
}

/// The history's views, side by side in one capsule, the chosen one lit, as a segmented control is
/// drawn on Liquid Glass.
private struct HistoryFilterPicker: View {
    @Binding var selection: HistoryFilter
    @Namespace private var lit

    var body: some View {
        HStack(spacing: 0) {
            ForEach(HistoryFilter.allCases) { choice in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { selection = choice }
                } label: {
                    Text(choice.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(choice == selection ? .white : PlayerLayout.secondary)
                        .padding(.horizontal, 10)
                        .frame(height: 22)
                        .background {
                            if choice == selection {
                                Capsule().fill(.white.opacity(0.2)).matchedGeometryEffect(id: "lit", in: lit)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(choice == selection ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Capsule().fill(.white.opacity(0.08)))
    }
}

/// The handle at the bottom of the tray, as a sheet's: click it, or pull down, to open the history;
/// in the history, to close it back.
private struct Grabber: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Capsule()
                .fill(.white.opacity(0.35))
                .frame(width: 36, height: 5)
                .frame(width: 96, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// AirDrop in the history's top bar, for dropping on or sending what's chosen.
private struct AirDropButton: View {
    let targeted: Bool
    let chosen: Int
    let send: () -> Void

    var body: some View {
        Button(action: send) {
            HStack(spacing: 5) {
                Image(nsImage: AirDropWell.icon).resizable().frame(width: 16, height: 16)
                Text(chosen > 0 ? "AirDrop \(chosen)" : "AirDrop")
                    .font(.system(size: 11, weight: .semibold))
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Capsule().fill(.white.opacity(targeted ? 0.3 : 0.12)))
            .overlay(Capsule().strokeBorder(.white.opacity(targeted ? 0.5 : 0), lineWidth: 1))
            .scaleEffect(targeted ? 1.06 : 1)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

extension View {
    /// Says where the AirDrop target is, for drops on it.
    fileprivate func reportsAirDropFrame() -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(key: AirDropFrame.self, value: proxy.frame(in: .named(ControlFrames.space)))
            }
        }
    }
}

/// The place opened at the front of the row for what's being dragged in.
private struct DropSlot: View {
    var body: some View {
        RoundedRectangle(cornerRadius: Shelf.platterRadius, style: .continuous)
            .strokeBorder(.white.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            .overlay {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .frame(width: Shelf.tile, height: Shelf.platterHeight)
    }
}

/// One thing in the tray: its picture and its name, as Finder shows a file. Click it to copy it,
/// double-click to paste it where you were typing, drag it out to put it somewhere. Under the
/// pointer it lifts a little, as things do under the pointer on iPad; rest there a moment and a
/// button to remove it comes up on its corner, as on a desktop in Mission Control.
private struct TrayTile: View {
    let item: TrayItem
    @ObservedObject var tray: Tray
    let isVisible: Bool
    @State private var hovered = false
    @State private var removable = false

    var body: some View {
        let copied = tray.justCopied.contains(item.id)
        let chosen = tray.selection.contains(item.id)
        let caption = TrayItemPicture.caption(for: item)
        VStack(spacing: 5) {
            TrayItemPicture(item: item, tray: tray, side: Shelf.picture)
                .scaleEffect(hovered ? 1.07 : 1)
                .shadow(color: .black.opacity(hovered ? 0.35 : 0), radius: hovered ? 6 : 0, y: hovered ? 3 : 0)
                .overlay {
                    if copied {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 26, weight: .medium))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color(white: 0.2).opacity(0.85))
                            .transition(.scale(scale: 0.5).combined(with: .opacity))
                    }
                }
                .overlay(alignment: .topLeading) {
                    if removable {
                        Button {
                            tray.remove(item.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white.opacity(0.9))
                                .frame(width: 18, height: 18)
                                .background(Circle().fill(Color(white: 0.2)))
                                .overlay(Circle().strokeBorder(.white.opacity(0.2), lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove from Tray")
                        .offset(x: -7, y: -7)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                    }
                }
            Text(caption)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .frame(width: Shelf.tile - 6, height: Shelf.caption, alignment: .top)
        }
        .padding(.top, 8)
        .padding(.bottom, 2)
        .frame(width: Shelf.tile)
        // Chosen, as Finder shows chosen files: in the accent color.
        .background {
            RoundedRectangle(cornerRadius: Shelf.platterRadius, style: .continuous)
                .fill(chosen ? Color.accentColor.opacity(0.5) : .clear)
        }
        .overlay {
            TileInteraction(item: item, tray: tray, selector: tray, clickSelects: false) { hovered = $0 }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hovered)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: removable)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: copied)
        .task(id: hovered) {
            guard hovered else { return removable = false }
            try? await Task.sleep(for: .seconds(0.6))
            if !Task.isCancelled, hovered { removable = true }
        }
        .notchControl(enabled: isVisible)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(caption)
        .accessibilityAddTraits(.isButton)
    }
}

/// AirDrop, at the end of the row: drop something on it, or click it with items chosen, and the
/// AirDrop window opens with them, ready to send.
private struct AirDropWell: View {
    let targeted: Bool
    let chosen: Int
    let send: () -> Void

    /// The AirDrop icon Finder shows in its sidebar.
    static let icon = NSWorkspace.shared.icon(forFile: "/System/Library/CoreServices/Finder.app/Contents/Applications/AirDrop.app")

    var body: some View {
        Button(action: send) {
            VStack(spacing: 5) {
                Image(nsImage: Self.icon)
                    .resizable()
                    .frame(width: Shelf.picture, height: Shelf.picture)
                Text(chosen > 0 ? "AirDrop \(chosen)" : "AirDrop")
                    .font(.system(size: 10, weight: .medium))
                    .frame(height: Shelf.caption, alignment: .top)
            }
            .padding(.top, 8)
            .padding(.bottom, 2)
            .frame(width: Shelf.tile, height: Shelf.platterHeight)
            .background {
                RoundedRectangle(cornerRadius: Shelf.platterRadius, style: .continuous)
                    .fill(.white.opacity(targeted ? 0.22 : 0.08))
                RoundedRectangle(cornerRadius: Shelf.platterRadius, style: .continuous)
                    .strokeBorder(.white.opacity(targeted ? 0.5 : 0.18), lineWidth: 1)
            }
            .scaleEffect(targeted ? 1.06 : 1)
            .contentShape(RoundedRectangle(cornerRadius: Shelf.platterRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        // The same soft blur as under the row.
        .background {
            TrayBlur()
                .frame(width: Shelf.tile + Shelf.bandMargin * 2, height: Shelf.platterHeight + 20)
        }
        .accessibilityLabel(chosen > 0 ? "AirDrop \(chosen) Items" : "AirDrop")
    }
}

/// Where the AirDrop well is in the notch, for dropping on it.
struct AirDropFrame: PreferenceKey {
    static let defaultValue: CGRect? = nil
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) { value = nextValue() ?? value }
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
    private static let corner = Shelf.platterRadius + 4

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
