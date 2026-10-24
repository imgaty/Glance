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

/// AirDrop as the iPhone's Dynamic Island draws it, by the island's height: in its blue, its
/// symbol beside the camera, and a ring filling as the file comes in.
enum AirDropLayout {
    static let tint = Color.blue
    static let title: CGFloat = 0.5
    static let subtitle: CGFloat = 0.42
    /// Between the picture and the words.
    static let gap: CGFloat = 0.32
    /// The picture's round corners, and AirDrop's badge on its corner, by the island's height.
    static let corner: CGFloat = 0.3
    static let badge: CGFloat = 0.6
    /// Opened, the ring around the stop button, its line, and the square in it.
    static let ring: CGFloat = 1.0
    static let ringLine: CGFloat = 0.09
    static let stop: CGFloat = 0.3

    /// As wide as the iPhone's expanded activities, or as its words need.
    @MainActor
    static func width(for shown: AirDropShown, restingHeight h: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: h * subtitle, weight: .semibold)
        let words = ceil((ExpandedAirDropView.from(shown) as NSString).size(withAttributes: [.font: font]).width)
        let needs = TimerLayout.rowEdge(h) * 2 + h * (TimerLayout.button * 2 + gap * 2) + words
        return min(max(h * TimerLayout.wide, needs), h * 14)
    }
}

/// How far along, as a ring filling clockwise from the top over a faint one.
struct AirDropRing: View {
    let fraction: Double
    let diameter: CGFloat
    let line: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(AirDropLayout.tint.opacity(0.3), lineWidth: line)
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

/// AirDrop beside the camera: its symbol at the left end, in its square, as the cover is; the ring
/// at the right, as far in from it as from the top and bottom, as the timer's is.
struct AirDropMark: View {
    let shown: AirDropShown
    let restingHeight: CGFloat
    let island: Bool

    var body: some View {
        let h = restingHeight
        let side = SystemActivityView.side(h, island)
        ZStack {
            AirDropSymbol.glyph(size: side * 0.72)
                .foregroundStyle(AirDropLayout.tint)
                .frame(width: side, height: side)
                .padding(.leading, LiveActivityView.edgeInset(island: island, restingHeight: h))
                .frame(maxWidth: .infinity, alignment: .leading)
            AirDropRing(fraction: shown.fraction, diameter: h * TimerLayout.ring, line: h * TimerLayout.ringLine)
                .padding(.trailing, SystemActivityView.ringEdge(h))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ExpandedAirDropView.spoken(shown))
    }
}

/// Opened, as the iPhone's AirDrop expands: a picture of the file with AirDrop's badge on its
/// corner, AirDrop and who it's from, and the ring around a button to stop it, all below the
/// camera, each end as far in as from the bottom, concentric with the round corners.
struct ExpandedAirDropView: View {
    let shown: AirDropShown
    let restingHeight: CGFloat
    let width: CGFloat
    @State private var hovering = false

    static func from(_ shown: AirDropShown) -> String { "From \(shown.sender)" }
    static func spoken(_ shown: AirDropShown) -> String {
        "AirDrop from \(shown.sender), \(Int((shown.fraction * 100).rounded())) percent"
    }

    var body: some View {
        let h = restingHeight
        let edge = TimerLayout.rowEdge(h)
        HStack(spacing: h * AirDropLayout.gap) {
            preview(h)
            VStack(alignment: .leading, spacing: 1) {
                Text("AirDrop")
                    .font(.system(size: h * AirDropLayout.title, weight: .semibold))
                    .foregroundStyle(.white)
                Text(Self.from(shown))
                    .font(.system(size: h * AirDropLayout.subtitle, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .lineLimit(1)
            .truncationMode(.tail)
            Spacer(minLength: 0)
            Button {
                AirDropWatch.shared.stop()
            } label: {
                ZStack {
                    Circle().fill(AirDropLayout.tint.opacity(hovering ? 0.3 : 0.2))
                    AirDropRing(fraction: shown.fraction, diameter: h * AirDropLayout.ring, line: h * AirDropLayout.ringLine)
                    RoundedRectangle(cornerRadius: h * 0.06, style: .continuous)
                        .fill(AirDropLayout.tint)
                        .frame(width: h * AirDropLayout.stop, height: h * AirDropLayout.stop)
                }
                .frame(width: h * TimerLayout.button, height: h * TimerLayout.button)
                .contentShape(Circle())
            }
            .buttonStyle(IslandPress(highlight: false, contactSize: nil))
            .onHover { hovering = $0 }
            .notchControl()
            .accessibilityLabel("Stop AirDrop")
        }
        .padding(.horizontal, edge)
        .padding(.top, h + LiveActivityView.cameraGap)
        .padding(.bottom, edge)
        .frame(width: width, height: TimerLayout.rowHeight(h), alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Self.spoken(shown))
    }

    /// The file, as macOS pictures it, or its kind's icon, with AirDrop's badge on its corner.
    private func preview(_ h: CGFloat) -> some View {
        let side = h * TimerLayout.button
        let picture = shown.preview ?? NSWorkspace.shared.icon(for: .data)
        return Image(nsImage: picture)
            .resizable()
            .aspectRatio(contentMode: shown.preview == nil ? .fit : .fill)
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: h * AirDropLayout.corner, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                AirDropSymbol.glyph(size: h * AirDropLayout.badge * 0.55)
                    .foregroundStyle(.white)
                    .frame(width: h * AirDropLayout.badge, height: h * AirDropLayout.badge)
                    .background(Circle().fill(AirDropLayout.tint))
                    .overlay(Circle().strokeBorder(.black, lineWidth: h * 0.05))
                    .offset(x: h * 0.15, y: h * 0.15)
            }
    }
}
