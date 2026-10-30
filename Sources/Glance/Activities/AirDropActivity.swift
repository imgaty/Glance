//
//  AirDropActivity.swift
//  Glance
//
//  Created by Gaty on 24/10/2026.
//

import AppKit
import SwiftUI

/// A file coming in over AirDrop: who sent it, a picture of it, and how far along it is.
struct AirDropShown: Equatable {
    let id: String
    /// The sender's name, or their device's when it's one of their own.
    let sender: String
    let preview: NSImage?
    var fraction: Double

    var done: Bool { fraction >= 1 }
}

/// Files coming in over AirDrop, as the iPhone's Dynamic Island shows them: beside the camera from
/// when the file starts coming until it's in, AirDrop's symbol at one end and how far along it is
/// at the other; opened, a picture of it, who it's from, and a button to stop it. macOS tells
/// apps of them through its own observer, the one its AirDrop notices use, which has no public way
/// in; without it, nothing shows. What waits to be accepted shows once it's accepted.
@MainActor
final class AirDropWatch: NSObject, ObservableObject {
    static let shared = AirDropWatch()

    @Published private(set) var transfer: AirDropShown?
    private var observer: NSObject?
    /// macOS's transfers under way, by their identifiers.
    private var transfers: [String: NSObject] = [:]
    /// Each one's picture, made once.
    private var previews: [String: NSImage] = [:]
    private var ticker: Timer?
    private var finishing: Task<Void, Never>?

    func start() {
        guard observer == nil,
            dlopen("/System/Library/PrivateFrameworks/Sharing.framework/Sharing", RTLD_LAZY) != nil,
            let type = NSClassFromString("SFAirDropTransferObserver") as? NSObject.Type
        else { return }
        if let delegate = objc_getProtocol("SFAirDropTransferObserverDelegate") { class_addProtocol(Self.self, delegate) }
        let observer = type.init()
        observer.setValue(self, forKey: "delegate")
        observer.perform(NSSelectorFromString("activate"))
        self.observer = observer
    }

    @objc nonisolated func updatedTransfer(_ transfer: NSObject) {
        nonisolated(unsafe) let transfer = transfer
        DispatchQueue.main.async { MainActor.assumeIsolated { self.updated(transfer) } }
    }

    @objc nonisolated func removedTransfer(_ transfer: NSObject) {
        nonisolated(unsafe) let transfer = transfer
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard let id = transfer.value(forKey: "identifier") as? String else { return }
                self.transfers[id] = nil
                self.previews[id] = nil
                self.refresh()
            }
        }
    }

    /// Stops the one showing, as its notice's Cancel does.
    func stop() {
        guard let id = transfer?.id, let shown = transfers[id] else { return }
        if let cancel = shown.value(forKey: "cancelAction") as? NSObject, cancel.responds(to: NSSelectorFromString("triggerAction")) {
            cancel.perform(NSSelectorFromString("triggerAction"))
        } else {
            (shown.value(forKey: "transferProgress") as? Progress)?.cancel()
        }
    }

    private func updated(_ transfer: NSObject) {
        guard let id = transfer.value(forKey: "identifier") as? String else { return }
        transfers[id] = transfer
        refresh()
    }

    /// The first under way, read again: shown from once it's accepted until it's in, which shows
    /// a moment full; gone once cancelled or failed.
    private func refresh() {
        let enabled = UserDefaults.standard.bool(forKey: Preferences.activityAirDrop)
        let next = enabled ? transfers.values.lazy.compactMap(shown).first : nil
        if next?.id != transfer?.id {
            finishing?.cancel()
            finishing = nil
        }
        if let next, next.done {
            if transfer?.done != true { transfer = next }
            finishing = finishing ?? Task { [weak self] in
                try? await Task.sleep(for: .seconds(1.2))
                guard let self, !Task.isCancelled else { return }
                self.transfers[next.id] = nil
                self.previews[next.id] = nil
                self.finishing = nil
                self.refresh()
            }
        } else if next != transfer {
            transfer = next
        }
        // Its progress read a few times a second while it comes in; macOS says less often.
        if transfer != nil, ticker == nil {
            let ticker = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
            RunLoop.main.add(ticker, forMode: .common)
            self.ticker = ticker
        } else if transfer == nil {
            ticker?.invalidate()
            ticker = nil
        }
    }

    private func shown(_ transfer: NSObject) -> AirDropShown? {
        guard let id = transfer.value(forKey: "identifier") as? String,
            transfer.value(forKey: "needsAction") as? Bool != true,
            let progress = transfer.value(forKey: "transferProgress") as? Progress,
            !progress.isCancelled, progress.totalUnitCount > 0
        else { return nil }
        let meta = transfer.value(forKey: "metaData") as? NSObject
        func text(_ key: String) -> String? { (meta?.value(forKey: key) as? String).flatMap { $0.isEmpty ? nil : $0 } }
        let mine = meta?.value(forKey: "senderIsMe") as? Bool ?? false
        let sender = (mine ? text("senderComputerName") : nil) ?? text("senderCompositeName") ?? text("senderComputerName") ?? "Nearby"
        let preview =
            previews[id] ?? Self.image(meta?.value(forKey: "smallPreviewImage")) ?? Self.image(meta?.value(forKey: "previewImage"))
        previews[id] = preview
        return AirDropShown(id: id, sender: sender, preview: preview, fraction: min(max(progress.fractionCompleted, 0), 1))
    }

    /// A picture as macOS hands it over: an image, its data, or a Core Graphics image.
    private static func image(_ value: Any?) -> NSImage? {
        guard let value else { return nil }
        if let image = value as? NSImage { return image }
        if let data = value as? Data { return NSImage(data: data) }
        let object = value as CFTypeRef
        if CFGetTypeID(object) == CGImage.typeID {
            let image = object as! CGImage
            return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        }
        return nil
    }
}

/// AirDrop as the iPhone's Dynamic Island draws it, measured from it, by the island's height: in
/// its light blue, its symbol beside the camera and a ring filling over a navy one; opened, as tall
/// as the Alarm, a picture of the file at the left end, the ring around a stop button at the right.
/// Its colors are the iPhone's own, in Display P3.
enum AirDropLayout {
    static let tint = Color.p3(0x45, 0x98, 0xF8)
    static let track = Color.p3(0x11, 0x31, 0x6A)
    static let badgeFill = Color.p3(0x1E, 0x1F, 0x1E)
    static let secondary = Color.p3(0x85, 0x85, 0x85)
    // Beside the camera.
    static let symbol: CGFloat = 0.59
    static let symbolEdge: CGFloat = 0.21
    static let ring: CGFloat = 0.62
    static let ringLine: CGFloat = 0.075
    static let ringEdge: CGFloat = 0.22
    // Opened.
    static let thumb: CGFloat = 1.35
    static let thumbCorner: CGFloat = 0.23
    static let badge: CGFloat = 0.55
    static let badgeOut: CGFloat = 0.065
    static let gap: CGFloat = 0.35
    static let title: CGFloat = 0.455
    static let subtitle: CGFloat = 0.42
    static let lineGap: CGFloat = -0.055
    static let bigRing: CGFloat = 1.34
    static let bigRingLine: CGFloat = 0.127
    static let stop: CGFloat = 0.43
    /// Who it's from runs this far before it's cut short.
    static let wordsLimit: CGFloat = 7

    /// The picture and the ring as far in from their ends as from the top and bottom.
    static func thumbEdge(_ h: CGFloat) -> CGFloat { LiveActivityView.concentric(h * thumb, in: TimerLayout.tallHeight(h)) }
    static func ringEdge(_ h: CGFloat) -> CGFloat { LiveActivityView.concentric(h * bigRing, in: TimerLayout.tallHeight(h)) }

    /// Opened: the picture and the words at the left end, the ring at the right, the camera between
    /// them, each side as wide as the wider.
    @MainActor
    static func width(for shown: AirDropShown, restingHeight h: CGFloat, camera: CGFloat) -> CGFloat {
        let gap = LiveActivityView.cameraGap
        let left = thumbEdge(h) + h * (thumb + self.gap) + words(for: shown, h) + gap
        let right = gap + h * bigRing + ringEdge(h)
        return camera + max(left, right) * 2
    }

    @MainActor
    static func words(for shown: AirDropShown, _ h: CGFloat) -> CGFloat {
        func width(_ text: String, _ size: CGFloat, _ weight: NSFont.Weight) -> CGFloat {
            ceil((text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: h * size, weight: weight)]).width)
        }
        return min(max(width("AirDrop", title, .semibold), width(ExpandedAirDropView.from(shown), subtitle, .medium)), h * wordsLimit)
    }
}

/// How far along, as a ring filling clockwise from the top over a navy one.
struct AirDropRing: View {
    let fraction: Double
    let diameter: CGFloat
    let line: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(AirDropLayout.track, lineWidth: line)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(AirDropLayout.tint, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.15), value: fraction)
        }
        .frame(width: diameter - line, height: diameter - line)
        .frame(width: diameter, height: diameter)
    }
}

/// AirDrop beside the camera, as the iPhone's: its symbol at the left end, the ring at the right,
/// each as far in from its end.
struct AirDropMark: View {
    let shown: AirDropShown
    let restingHeight: CGFloat

    var body: some View {
        let h = restingHeight
        ZStack {
            AirDropSymbol.glyph(size: h * AirDropLayout.symbol, weight: .medium)
                .foregroundStyle(AirDropLayout.tint)
                .padding(.leading, h * AirDropLayout.symbolEdge)
                .frame(maxWidth: .infinity, alignment: .leading)
            AirDropRing(fraction: shown.fraction, diameter: h * AirDropLayout.ring, line: h * AirDropLayout.ringLine)
                .padding(.trailing, h * AirDropLayout.ringEdge)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ExpandedAirDropView.spoken(shown))
    }
}

/// Opened, as the iPhone's AirDrop expands, as tall as the Alarm: a picture of the file with
/// AirDrop's badge on its corner and, beside it, AirDrop and who it's from, at the left end; the
/// ring around a button to stop it at the right; the camera between them.
struct ExpandedAirDropView: View {
    let shown: AirDropShown
    let restingHeight: CGFloat
    /// The camera housing's width, which the row goes either side of.
    let camera: CGFloat
    let width: CGFloat
    @State private var hovering = false

    static func from(_ shown: AirDropShown) -> String { "From \(shown.sender)" }
    static func spoken(_ shown: AirDropShown) -> String {
        "AirDrop from \(shown.sender), \(Int((shown.fraction * 100).rounded())) percent"
    }

    var body: some View {
        let h = restingHeight
        let left = HStack(spacing: h * AirDropLayout.gap) {
            preview(h)
            VStack(alignment: .leading, spacing: h * AirDropLayout.lineGap) {
                Text("AirDrop")
                    .font(.system(size: h * AirDropLayout.title, weight: .semibold))
                    .foregroundStyle(.white)
                Text(Self.from(shown))
                    .font(.system(size: h * AirDropLayout.subtitle, weight: .medium))
                    .foregroundStyle(AirDropLayout.secondary)
            }
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: AirDropLayout.words(for: shown, h), alignment: .leading)
        }
        .padding(.leading, AirDropLayout.thumbEdge(h))
        let right = stopButton(h).padding(.trailing, AirDropLayout.ringEdge(h))
        let side = max((width - camera) / 2, 0)
        HStack(spacing: 0) {
            left.frame(width: side, alignment: .leading)
            Color.clear.frame(width: camera)
            right.frame(width: side, alignment: .trailing)
        }
        .frame(width: width, height: TimerLayout.tallHeight(h))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Self.spoken(shown))
    }

    /// The ring around a square that stops it, as the iPhone's, faintly lit under the pointer.
    private func stopButton(_ h: CGFloat) -> some View {
        Button {
            AirDropWatch.shared.stop()
        } label: {
            ZStack {
                Circle().fill(AirDropLayout.tint.opacity(hovering ? 0.12 : 0))
                AirDropRing(fraction: shown.fraction, diameter: h * AirDropLayout.bigRing, line: h * AirDropLayout.bigRingLine)
                RoundedRectangle(cornerRadius: h * AirDropLayout.stop * 0.22, style: .continuous)
                    .fill(AirDropLayout.tint)
                    .frame(width: h * AirDropLayout.stop, height: h * AirDropLayout.stop)
            }
            .frame(width: h * AirDropLayout.bigRing, height: h * AirDropLayout.bigRing)
            .contentShape(Circle())
            .animation(.easeOut(duration: 0.15), value: hovering)
        }
        .buttonStyle(IslandPress(highlight: false, contactSize: nil))
        .onHover { hovering = $0 }
        .notchControl()
        .accessibilityLabel("Stop AirDrop")
    }

    /// The file, as macOS pictures it, or its kind's icon, with AirDrop's badge, a dark tile with
    /// the iPhone's AirDrop glyph, on its corner.
    private func preview(_ h: CGFloat) -> some View {
        let side = h * AirDropLayout.thumb
        let badge = h * AirDropLayout.badge
        let picture = shown.preview ?? NSWorkspace.shared.icon(for: .data)
        return Image(nsImage: picture)
            .resizable()
            .aspectRatio(contentMode: shown.preview == nil ? .fit : .fill)
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: h * AirDropLayout.thumbCorner, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                AirDropBadgeGlyph(side: badge)
                    .background(RoundedRectangle(cornerRadius: badge * 0.22, style: .continuous).fill(AirDropLayout.badgeFill))
                    .overlay(
                        RoundedRectangle(cornerRadius: badge * 0.22, style: .continuous)
                            .strokeBorder(.black.opacity(0.6), lineWidth: h * 0.03))
                    .offset(x: h * AirDropLayout.badgeOut, y: h * AirDropLayout.badgeOut)
            }
    }
}

/// AirDrop's glyph on the badge, as the iPhone draws it: three blue discs one inside another, each
/// lighter at the top, the dot brightest, and a dark wedge opening down from just under the dot.
struct AirDropBadgeGlyph: View {
    /// The badge's side.
    let side: CGFloat

    /// Across each disc, and the wedge's opening, as the badge's side measures them.
    static let outer: CGFloat = 0.826
    static let middle: CGFloat = 0.5
    static let dot: CGFloat = 0.207
    static let wedge: Angle = .degrees(86)
    static let outerShades: (Color, Color) = (.p3(0x1F, 0x49, 0x74), .p3(0x0F, 0x2A, 0x44))
    static let middleShades: (Color, Color) = (.p3(0x2D, 0x72, 0xA9), .p3(0x22, 0x50, 0x7C))
    static let dotShades: (Color, Color) = (.p3(0x3F, 0x86, 0xF0), .p3(0x2E, 0x7A, 0xDD))
    static let wedgeFill = Color.p3(0x10, 0x10, 0x0F)

    var body: some View {
        ZStack {
            disc(Self.outer, Self.outerShades)
            disc(Self.middle, Self.middleShades)
            // The wedge over the two bands, inside the outer disc, from just under the dot.
            Wedge(apex: side * Self.dot / 2, opening: Self.wedge)
                .fill(Self.wedgeFill)
                .clipShape(Circle().size(width: side * Self.outer, height: side * Self.outer)
                    .offset(x: side * (1 - Self.outer) / 2, y: side * (1 - Self.outer) / 2))
            disc(Self.dot, Self.dotShades)
        }
        .frame(width: side, height: side)
    }

    private func disc(_ across: CGFloat, _ shades: (Color, Color)) -> some View {
        Circle()
            .fill(LinearGradient(colors: [shades.0, shades.1], startPoint: .top, endPoint: .bottom))
            .frame(width: side * across, height: side * across)
    }

    /// From a point under the middle, opening downward, wider than the badge.
    private struct Wedge: Shape {
        let apex: CGFloat
        let opening: Angle

        func path(in rect: CGRect) -> Path {
            let top = CGPoint(x: rect.midX, y: rect.midY + apex)
            let reach = rect.height
            let spread = reach * tan(opening.radians / 2)
            var path = Path()
            path.move(to: top)
            path.addLine(to: CGPoint(x: top.x - spread, y: top.y + reach))
            path.addLine(to: CGPoint(x: top.x + spread, y: top.y + reach))
            path.closeSubpath()
            return path
        }
    }
}
