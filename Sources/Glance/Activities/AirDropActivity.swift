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
enum AirDropLayout {
    static let tint = Color(red: 0x57 / 255, green: 0xA9 / 255, blue: 0xF8 / 255)
    static let track = Color(red: 0x13 / 255, green: 0x42 / 255, blue: 0x7B / 255)
    static let badgeFill = Color(red: 0x25 / 255, green: 0x25 / 255, blue: 0x28 / 255)
    static let badgeGlyph = Color(red: 0x3C / 255, green: 0x8F / 255, blue: 0xE6 / 255)
    static let secondary = Color(red: 0x91 / 255, green: 0x91 / 255, blue: 0x91 / 255)
    // Beside the camera.
    static let symbol: CGFloat = 0.58
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
    /// them, each side as wide as the wider; on an island, as wide as the iPhone's, or as its words
    /// need.
    @MainActor
    static func width(for shown: AirDropShown, restingHeight h: CGFloat, camera: CGFloat) -> CGFloat {
        let gap = LiveActivityView.cameraGap
        let left = thumbEdge(h) + h * (thumb + self.gap) + words(for: shown, h) + gap
        let right = gap + h * bigRing + ringEdge(h)
        return camera > 0 ? camera + max(left, right) * 2 : max(h * TimerLayout.wide, left + right + h * self.gap)
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
    let island: Bool

    var body: some View {
        let h = restingHeight
        ZStack {
            AirDropSymbol.glyph(size: h * AirDropLayout.symbol)
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
    /// The camera housing's width, which the row goes either side of; none on an island.
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
        Group {
            if camera > 0 {
                let side = max((width - camera) / 2, 0)
                HStack(spacing: 0) {
                    left.frame(width: side, alignment: .leading)
                    Color.clear.frame(width: camera)
                    right.frame(width: side, alignment: .trailing)
                }
            } else {
                ZStack {
                    left.frame(maxWidth: .infinity, alignment: .leading)
                    right.frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
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
    /// its symbol in blue, on its corner.
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
                AirDropSymbol.glyph(size: badge * 0.64)
                    .foregroundStyle(AirDropLayout.badgeGlyph)
                    .frame(width: badge, height: badge)
                    .background(RoundedRectangle(cornerRadius: badge * 0.22, style: .continuous).fill(AirDropLayout.badgeFill))
                    .overlay(
                        RoundedRectangle(cornerRadius: badge * 0.22, style: .continuous)
                            .strokeBorder(.black.opacity(0.6), lineWidth: h * 0.03))
                    .offset(x: h * AirDropLayout.badgeOut, y: h * AirDropLayout.badgeOut)
            }
    }
}
