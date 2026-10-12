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
    static let bandMargin: CGFloat = 12

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
/// as the Dock does for an app dragged into it.
struct TrayView: View {
    @ObservedObject var tray: Tray
    let isVisible: Bool
    /// Something is being dragged over the notch.
    let dropping: Bool
    /// How far the row is scrolled.
    let scroll: CGFloat
    /// Something dragged is over the AirDrop well.
    var airDropTargeted = false
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
        let room = proxy.size.height - top - PlayerLayout.padding + 4
        let well = Self.showsAirDrop(tray: tray, dropping: dropping)
        ZStack(alignment: .topTrailing) {
            shelf(width: proxy.size.width - (well ? Shelf.wellWidth : 0), height: proxy.size.height, top: top, room: room)
                .frame(width: proxy.size.width, alignment: .leading)
            if well {
                AirDropWell(targeted: airDropTargeted, chosen: tray.selection.count) {
                    tray.airDrop(tray.shareable(tray.chosen))
                }
                .notchControl(enabled: isVisible && !tray.selection.isEmpty)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(key: AirDropFrame.self, value: proxy.frame(in: .named(ControlFrames.space)))
                    }
                }
                .padding(.trailing, PlayerLayout.padding)
                .padding(.top, top + (room - Shelf.platterHeight) / 2)
                .transition(.move(edge: .trailing).combined(with: .opacity))
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
                .frame(width: CGFloat(count) * step - Shelf.spacing + Shelf.bandMargin * 2, height: Shelf.platterHeight + 12)
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
/// double-click to paste it where you were typing, drag it out to put it somewhere, or remove it
/// with the button that comes up on it, as on a notification.
private struct TrayTile: View {
    let item: TrayItem
    @ObservedObject var tray: Tray
    let isVisible: Bool
    @State private var hovered = false

    var body: some View {
        let copied = tray.justCopied.contains(item.id)
        let chosen = tray.selection.contains(item.id)
        let caption = TrayItemPicture.caption(for: item)
        VStack(spacing: 5) {
            TrayItemPicture(item: item, tray: tray, side: Shelf.picture)
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
                .font(.system(size: 10, weight: .medium))
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .frame(width: Shelf.tile - 6, height: Shelf.caption, alignment: .top)
        }
        .padding(.top, 8)
        .padding(.bottom, 2)
        .frame(width: Shelf.tile)
        // Chosen, as Finder shows chosen files: in the accent color; under the pointer, a little
        // brighter.
        .background {
            RoundedRectangle(cornerRadius: Shelf.platterRadius, style: .continuous)
                .fill(chosen ? Color.accentColor.opacity(0.5) : .white.opacity(hovered ? 0.1 : 0))
        }
        .overlay {
            TileInteraction(item: item, tray: tray, selector: tray, clickSelects: false) { hovered = $0 }
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
    }
}

/// AirDrop, at the end of the row: drop something on it, or click it with items chosen, and the
/// AirDrop window opens with them, ready to send.
private struct AirDropWell: View {
    let targeted: Bool
    let chosen: Int
    let send: () -> Void

    /// The AirDrop icon Finder shows in its sidebar.
    private static let icon = NSWorkspace.shared.icon(forFile: "/System/Library/CoreServices/Finder.app/Contents/Applications/AirDrop.app")

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
                .frame(width: Shelf.tile + Shelf.bandMargin * 2, height: Shelf.platterHeight + 12)
        }
        .accessibilityLabel(chosen > 0 ? "AirDrop \(chosen) Items" : "AirDrop")
    }
}

/// Where the AirDrop well is in the notch, for dropping on it.
struct AirDropFrame: PreferenceKey {
    static let defaultValue: CGRect? = nil
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) { value = nextValue() ?? value }
}

/// The band of blur behind the tray's row: macOS's own blur, as under its menus, but light, and with
/// none of its tint, so the row reads over a busy window and the notch keeps its look. It blurs
/// what the notch shows behind it, its glass and all, whether or not Glance is the app in front.
private struct TrayBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> LightBlurView { LightBlurView() }
    func updateNSView(_ view: LightBlurView, context: Context) {}
}

final class LightBlurView: NSVisualEffectView {
    /// Its own blur is 30 points; this is enough to soften text behind it out of the way.
    private static let radius: CGFloat = 10
    private static let corner = Shelf.platterRadius + 4

    override init(frame: NSRect) {
        super.init(frame: frame)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        appearance = NSAppearance(named: .darkAqua)
        maskImage = Self.mask
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    // AppKit can set its layers up again, as when it's laid out; each time, they're made light.
    override func layout() {
        super.layout()
        lighten()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        lighten()
        DispatchQueue.main.async { [weak self] in self?.lighten() }
    }

    private func lighten() {
        func visit(_ layer: CALayer) {
            if NSStringFromClass(type(of: layer)) == "CABackdropLayer" {
                if (layer.value(forKeyPath: "filters.gaussianBlur.inputRadius") as? CGFloat) != Self.radius {
                    layer.setValue(Self.radius, forKeyPath: "filters.gaussianBlur.inputRadius")
                }
            } else if layer !== self.layer, layer.opacity != 0, layer.sublayers?.isEmpty ?? true {
                // The material's tints.
                layer.opacity = 0
            }
            layer.sublayers?.forEach(visit)
        }
        layer.map(visit)
    }

    /// Rounded as the band is, at any size, its edges fading out over a few points rather than
    /// ending in a line, so the blur melts into the glass around it.
    private static let mask: NSImage = {
        let feather: CGFloat = 10, side = Int((corner + feather) * 2 + 1)
        let scale = 2
        let pixels = side * scale
        guard
            let context = CGContext(
                data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: pixels,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue),
            let data = context.data?.assumingMemoryBound(to: UInt8.self)
        else { return NSImage() }
        // How far each point is outside the rounded rectangle (negative inside), eased across the
        // feather.
        let half = CGFloat(side) / 2, inner = half - feather
        for y in 0..<pixels {
            for x in 0..<pixels {
                let px = abs((CGFloat(x) + 0.5) / CGFloat(scale) - half) - (inner - corner)
                let py = abs((CGFloat(y) + 0.5) / CGFloat(scale) - half) - (inner - corner)
                let distance = hypot(max(px, 0), max(py, 0)) + min(max(px, py), 0) - corner
                let t = min(max(0.5 - distance / feather, 0), 1)
                data[y * pixels + x] = UInt8((t * t * (3 - 2 * t) * 255).rounded())
            }
        }
        guard let cgImage = context.makeImage() else { return NSImage() }
        let image = NSImage(cgImage: cgImage, size: CGSize(width: side, height: side))
        let inset = corner + feather
        image.capInsets = NSEdgeInsets(top: inset, left: inset, bottom: inset, right: inset)
        image.resizingMode = .stretch
        return image
    }()
}

/// The open notch's two pages: the player, and the tray to its right.
enum NotchPage {
    case player, tray
}
