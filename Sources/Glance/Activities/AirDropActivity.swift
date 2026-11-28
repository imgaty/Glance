//
//  AirDropActivity.swift
//  Glance
//
//  Created by Gaty on 24/10/2026.
//

import AppKit
import SwiftUI

/// A file coming in or going out over AirDrop: who with, a picture of it, and how far along it is.
struct AirDropShown: Equatable {
    let id: String
    /// The sender's name, or their device's when it's one of their own.
    let sender: String
    var preview: NSImage?
    var fraction: Double
    /// Going out from this Mac, rather than coming in.
    var sending = false
    /// Going out: the device it's going to, as far as that's known, and the file.
    var recipient: String?
    var file: String?
    /// Whether the transfer currently exposes a reachable cancellation action.
    var canStop = true
    /// Coming in and waiting to be accepted or declined: what macOS asks before a file comes.
    var asking = false

    var done: Bool { fraction >= 1 && !asking }
    var offersStop: Bool { canStop && !done && !asking }
}

/// Session updates may arrive in any order. Keep the visible transfer until it leaves, then use
/// the oldest eligible session, without letting progress updates move it to the back.
struct AirDropTransferOrder {
    private var identifiers: [String] = []

    mutating func received(_ id: String) {
        if !identifiers.contains(id) { identifiers.append(id) }
    }

    mutating func removed(_ id: String) {
        identifiers.removeAll { $0 == id }
    }

    func first(in available: Set<String>, keeping current: String?) -> String? {
        if let current, identifiers.contains(current), available.contains(current) { return current }
        return identifiers.first { available.contains($0) }
    }
}

/// Files coming in over AirDrop, as the iPhone's Dynamic Island shows them: beside the camera from
/// when the file starts coming until it's in, AirDrop's symbol at one end and how far along it is
/// at the other; opened, a picture of it, who it's from, and a button to stop it. Up to macOS 27.2,
/// macOS told apps of them through its own observer, the one its AirDrop notices used, which has no
/// public way in. From 27.3 its new AirDrop service tells only its own Live Activity, and what comes
/// in is followed by the progress macOS publishes for it in Downloads instead (see
/// `AirDropReceiveWatch`). What waits to be accepted shows as it asks, opened by itself, with
/// Decline and Accept, which answer it as macOS's own buttons do (see `AirDropAnswer`); macOS's own
/// request stays where it is too, to be answered there.
@MainActor
final class AirDropWatch: NSObject, ObservableObject {
    static let shared = AirDropWatch()

    @Published private(set) var transfer: AirDropShown?
    private var observer: NSObject?
    /// macOS's transfers under way, by their identifiers.
    private var transfers: [String: NSObject] = [:]
    private var order = AirDropTransferOrder()
    /// Each one's picture, made once.
    private var previews: [String: NSImage] = [:]
    private var ticker: Timer?
    private var finishing: Task<Void, Never>?
    private var lettingGo: Task<Void, Never>?
    private let sends = AirDropSendWatch()
    /// What's going out, which shows when nothing's coming in.
    private var outgoing: AirDropShown?
    private let receives = AirDropReceiveWatch()
    /// What's coming in as macOS 27.3's AirDrop publishes it in Downloads, which shows after what
    /// the observer tells of.
    private var receiving: AirDropShown?

    func start() {
        sends.changed = { [weak self] in
            self?.outgoing = $0
            self?.refresh()
        }
        sends.start()
        receives.changed = { [weak self] in
            self?.receiving = $0
            self?.refresh()
        }
        if !ActivityBench.fakes { receives.start() }
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
                self.order.removed(id)
                self.previews[id] = nil
                self.refresh()
            }
        }
    }

    /// What's shown at the bench (see `ActivityBench`).
    func bench(_ fake: AirDropShown?) {
        transfer = fake
    }

    /// macOS's own notice for a file coming in stays out of sight while the notch shows it, and for a
    /// moment after, when macOS says it's in. What's waiting to be accepted keeps macOS's own request
    /// in sight, to be answered there as well.
    private func hideNotice() {
        guard ActivityBench.scene == nil else { return }
        if transfer?.asking == true {
            lettingGo?.cancel()
            lettingGo = nil
            NotificationWindow.shared.letGo(.airDrop)
        } else if let transfer, !transfer.sending {
            lettingGo?.cancel()
            lettingGo = nil
            NotificationWindow.shared.hold(.airDrop)
        } else if lettingGo == nil {
            lettingGo = Task {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                SystemNotices.closeAll(from: "AirDrop")
                NotificationWindow.shared.letGo(.airDrop)
                self.lettingGo = nil
            }
        }
    }

    /// Stops the one showing, as its notice's Cancel does.
    func stop() {
        guard transfer?.offersStop == true else { return }
        guard !ActivityBench.fakes else { return ActivityBench.shared.stopped(.airdrop) }
        if transfer?.sending == true { return sends.stop() }
        guard let id = transfer?.id, let shown = transfers[id] else { return receives.stop() }
        // The notice's own Cancel, if macOS gave it a way to run; otherwise the transfer's progress.
        let cancel = shown.value(forKey: "cancelAction") as? NSObject
        if cancel.map(AirDropAnswer.trigger) != true { (shown.value(forKey: "transferProgress") as? Progress)?.cancel() }
    }

    /// Accepts or declines the request showing, as macOS's own Accept and Decline do.
    func answer(_ choice: AirDropAnswer.Choice) {
        guard let shown = transfer, shown.asking else { return }
        guard !ActivityBench.fakes else { return ActivityBench.shared.answered(choice) }
        AirDropAnswer.answer(choice, transfer: transfers[shown.id])
    }

    private func updated(_ transfer: NSObject) {
        guard let id = transfer.value(forKey: "identifier") as? String else { return }
        order.received(id)
        transfers[id] = transfer
        refresh()
    }

    /// The first under way, read again: shown from once it's accepted until it's in, which shows
    /// a moment full; gone once cancelled or failed.
    private func refresh() {
        let enabled = UserDefaults.standard.bool(forKey: Preferences.activityAirDrop) && LiveActivityPlace.allows(Preferences.activityAirDrop)
        let incoming = enabled ? Dictionary(uniqueKeysWithValues: transfers.values.compactMap(shown).map { ($0.id, $0) }) : [:]
        let current = transfer?.sending == false ? transfer?.id : nil
        let first = order.first(in: Set(incoming.keys), keeping: current).flatMap { incoming[$0] }
        let next = enabled ? first ?? receiving ?? outgoing : nil
        if next?.id != transfer?.id {
            finishing?.cancel()
            finishing = nil
        }
        if let next, next.done, !next.sending {
            if transfer != next { transfer = next }
            finishing =
                finishing
                ?? Task { [weak self] in
                    try? await Task.sleep(for: .seconds(1.2))
                    guard let self, !Task.isCancelled else { return }
                    self.transfers[next.id] = nil
                    self.order.removed(next.id)
                    self.previews[next.id] = nil
                    self.finishing = nil
                    self.refresh()
                }
        } else if next != transfer {
            transfer = next
        }
        hideNotice()
        // Its progress read a few times a second while it comes in; the observer says less often.
        if let transfer, !transfer.sending, transfers[transfer.id] != nil, ticker == nil {
            let ticker = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
            RunLoop.main.add(ticker, forMode: .common)
            self.ticker = ticker
        } else if transfer.map({ $0.sending || transfers[$0.id] == nil }) ?? true {
            ticker?.invalidate()
            ticker = nil
        }
    }

    private func shown(_ transfer: NSObject) -> AirDropShown? {
        guard let id = transfer.value(forKey: "identifier") as? String else { return nil }
        let meta = transfer.value(forKey: "metaData") as? NSObject
        func text(_ key: String) -> String? { (meta?.value(forKey: key) as? String).flatMap { $0.isEmpty ? nil : $0 } }
        let mine = meta?.value(forKey: "senderIsMe") as? Bool ?? false
        let sender = (mine ? text("senderComputerName") : nil) ?? text("senderCompositeName") ?? text("senderComputerName") ?? String(localized: "Nearby")
        let preview =
            previews[id] ?? Self.image(meta?.value(forKey: "smallPreviewImage")) ?? Self.image(meta?.value(forKey: "previewImage"))
        previews[id] = preview
        // Asking to be accepted: shown with Decline and Accept while macOS's own actions can answer it.
        if transfer.value(forKey: "needsAction") as? Bool == true {
            return AirDropShown(id: id, sender: sender, preview: preview, fraction: 0, canStop: false, asking: true)
        }
        guard let progress = transfer.value(forKey: "transferProgress") as? Progress, !progress.isCancelled, progress.totalUnitCount > 0
        else { return nil }
        let cancel = transfer.value(forKey: "cancelAction") as? NSObject
        let canStop = cancel?.responds(to: NSSelectorFromString("triggerAction")) == true || progress.isCancellable
        return AirDropShown(id: id, sender: sender, preview: preview, fraction: min(max(progress.fractionCompleted, 0), 1), canStop: canStop)
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
    // Beside the camera.
    static let symbol: CGFloat = 0.575
    static let symbolEdge: CGFloat = 0.148
    /// As large as every other activity's mark beside the camera, as far in from its end as from the top.
    static let ring: CGFloat = TimerLayout.ring
    static let ringLine: CGFloat = 0.075
    static let ringEdge: CGFloat = (1 - ring) / 2
    // Opened.
    static let badge: CGFloat = 0.55
    static let badgeOut: CGFloat = 0.065
    /// How far in from its square macOS's document icon draws its paper, by the square's side.
    static let paperMargin: CGFloat = 0.16
    static let gap: CGFloat = 0.35
    static let bigRingLine: CGFloat = 0.127
    static let stop: CGFloat = 0.43
    /// Accept's check, by its button's side, as the call's Accept handset is by its own.
    static let check: CGFloat = 0.4

    /// The picture as far in from its end as the ring is from the other, the iPhone's 17 points.
    static func thumbEdge(_ h: CGFloat) -> CGFloat { TimerLayout.buttonEdge(h) }
    /// The opened ring's distance from the end: iOS 27's, as its other activities' round controls.
    static func ringEdge(_ h: CGFloat) -> CGFloat { TimerLayout.circleEdge(h) }

    /// Opened: only as wide as the camera needs it: the picture and the ring stand as high as the
    /// camera, so beside it, and the words, as high as they go under it, run on beneath it. Asking to
    /// be accepted, Decline and Accept stand where the ring would, side by side.
    @MainActor
    static func width(restingHeight h: CGFloat, camera: CGFloat, asking: Bool = false) -> CGFloat {
        let gap = LiveActivityView.cameraGap
        let left = thumbEdge(h) + TimerLayout.content(h) + gap
        let right = gap + trailing(h, asking: asking) + ringEdge(h)
        return (camera + max(left, right) * 2).rounded(.up)
    }

    /// What stands at the right end: the ring, or Decline and Accept with the timer's gap between.
    static func trailing(_ h: CGFloat, asking: Bool) -> CGFloat {
        asking ? TimerLayout.circle(h) * 2 + TimerLayout.circleGap(h) : TimerLayout.circle(h)
    }

    /// Where the words' first line, "AirDrop", stands: as high as it goes under the camera.
    static func wordsBaseline(_ h: CGFloat) -> CGFloat {
        UnderCamera.baseline(["AirDrop"], font: .systemFont(ofSize: NotchType.size, weight: .semibold), restingHeight: h)
    }

    /// Opened, how low its two lines reach, the second saying who it's `from`: the picture and the
    /// ring end there too (see `UnderCamera.twoLineSidesMiddle`), and the notch's edge comes up as far
    /// under it as they stand in from the ends.
    static func wordsBottom(_ h: CGFloat, from: String) -> CGFloat {
        UnderCamera.twoLineBottom(
            ["AirDrop"], first: .systemFont(ofSize: NotchType.size, weight: .semibold), line: from, font: .systemFont(ofSize: NotchType.size),
            restingHeight: h)
    }
    /// Where the picture and the ring stand: their middle, so they end where the words do.
    static func sidesMiddle(_ h: CGFloat, from: String) -> CGFloat {
        UnderCamera.twoLineSidesMiddle(bottom: wordsBottom(h, from: from), side: TimerLayout.content(h))
    }
    static func openHeight(_ h: CGFloat, from: String) -> CGFloat {
        UnderCamera.twoLineHeight(bottom: wordsBottom(h, from: from), edge: ringEdge(h))
    }

    /// Where the words start, from the left end.
    static func wordsStart(_ h: CGFloat) -> CGFloat { thumbEdge(h) + TimerLayout.content(h) + h * gap }

    /// As far as who it's from can run, under the camera, before the ring or the buttons.
    static func wordsRoom(_ h: CGFloat, width: CGFloat, asking: Bool = false) -> CGFloat {
        max(width - wordsStart(h) - ringEdge(h) - trailing(h, asking: asking) - h * gap, 0)
    }

}

/// How far along, as a ring filling clockwise from the top over a navy one.
struct AirDropRing: View {
    let fraction: Double
    let diameter: CGFloat
    let line: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().stroke(AirDropLayout.track, lineWidth: line)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(AirDropLayout.tint, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .linear(duration: 0.15), value: fraction)
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
    /// Only the symbol, with another activity detached (see `SystemActivityView.leadingOnly`).
    var leadingOnly = false

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
                .islandFade(!leadingOnly)
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
    let width: CGFloat
    /// The notch is open to it.
    var revealed = true
    /// How wide the notch is closed, if it shows beside the camera there, for its ring to grow out of.
    var closedWidth: CGFloat? = nil
    /// How far below its middle at rest the closed notch's middle was, swollen under the pointer.
    var closedDrop: CGFloat = 0
    /// Isolated render fixtures can exercise the control without touching a real transfer.
    var stop: () -> Void = { AirDropWatch.shared.stop() }
    var answer: (AirDropAnswer.Choice) -> Void = { AirDropWatch.shared.answer($0) }
    @Environment(\.activityBubbleCenter) private var bubbleCenter
    @Environment(\.trailingGrows) private var trailingGrows

    /// Who it's with; going out, the file, until macOS's window says who it's going to. Coming in
    /// on macOS 27.3, which tells only its own AirDrop who sends, the file.
    static func from(_ shown: AirDropShown) -> String {
        guard shown.sending else { return shown.sender.isEmpty ? shown.file ?? String(localized: "Nearby") : String(localized: "From \(shown.sender)") }
        return shown.recipient.map { String(localized: "To \($0)") } ?? shown.file ?? String(localized: "Sending")
    }

    static func spoken(_ shown: AirDropShown) -> String {
        if shown.asking { return String(localized: "AirDrop from \(shown.sender), waiting for an answer") }
        let who =
            shown.sending
            ? shown.recipient.map { String(localized: "to \($0)") } ?? String(localized: "sending")
            : shown.sender.isEmpty ? shown.file ?? String(localized: "Nearby") : String(localized: "from \(shown.sender)")
        return String(localized: "AirDrop \(who), \(Int((shown.fraction * 100).rounded())) percent")
    }

    var body: some View {
        let h = restingHeight
        let left = preview(h).padding(.leading, AirDropLayout.thumbEdge(h))
        // The words, as high as they go under the camera, run on beneath it to the ring.
        let words = VStack(alignment: .leading, spacing: 0) {
            Text("AirDrop")
                .font(IslandType.title(restingHeight))
                .foregroundStyle(.white)
            Text(Self.from(shown))
                .font(IslandType.detail(restingHeight))
                .foregroundStyle(NotchType.detailColor)
        }
        .lineLimit(1)
        .truncationMode(.tail)
        .frame(maxWidth: AirDropLayout.wordsRoom(h, width: width, asking: shown.asking), alignment: .leading)
        .firstBaseline(AirDropLayout.wordsBaseline(h))
        .padding(.leading, AirDropLayout.wordsStart(h))
        // The ring grows out of where it shows beside the camera, as the Timer's does.
        let out = revealed
        let spread = ((closedWidth ?? width) - width) / 2
        let rise = h / 2 - AirDropLayout.sidesMiddle(h, from: Self.from(shown)) + closedDrop
        let ringFrom = CGSize(
            width: bubbleCenter.map { $0 - width / 2 + AirDropLayout.ringEdge(h) + h * AirDropLayout.ring / 2 }
                ?? (spread - h * AirDropLayout.ringEdge + AirDropLayout.ringEdge(h)), height: rise)
        let right = stopButton(h)
            .modifier(
                GrowsOut(out: out || (closedWidth == nil || !trailingGrows) && bubbleCenter == nil, scale: h * AirDropLayout.ring / TimerLayout.circle(h), anchor: .trailing, from: ringFrom)
            )
            .modifier(GrownFade(shown: revealed, grows: closedWidth != nil && trailingGrows || bubbleCenter != nil))
            .padding(.trailing, AirDropLayout.ringEdge(h))
        ZStack {
            left.modifier(IslandReveal(hidden: !revealed)).frame(maxWidth: .infinity, alignment: .leading)
            words.modifier(IslandReveal(hidden: !revealed))
            if shown.asking {
                // Nothing beside the camera to grow from: they come in as the rest does.
                answerButtons(h)
                    .modifier(IslandReveal(hidden: !revealed))
                    .padding(.trailing, AirDropLayout.ringEdge(h))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                right.frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        // Laid out twice as tall as the picture's and the ring's middle, so they, in the middle of it, end
        // where the words do; the notch ends sooner, under them (see `AirDropLayout.openHeight`).
        .frame(width: width, height: 2 * AirDropLayout.sidesMiddle(h, from: Self.from(shown)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Self.spoken(shown))
    }

    /// A transfer without a reachable cancellation action keeps its progress ring without a button.
    @ViewBuilder
    private func stopButton(_ h: CGFloat) -> some View {
        if shown.offersStop {
            stopControl(h)
        } else {
            // As iOS 27's airdrop-progress.ca opened, with no stop button.
            AirDropRing(fraction: shown.fraction, diameter: TimerLayout.circle(h) * 2 * TaskRingLook.radius, line: TimerLayout.circle(h) * TaskRingLook.openLine)
                .frame(width: TimerLayout.circle(h), height: TimerLayout.circle(h))
                .accessibilityHidden(true)
        }
    }

    /// Decline, a white ✕ on its faint circle as the Timer's, and Accept, a check on AirDrop's blue,
    /// round buttons as every other activity's, at the right end.
    private func answerButtons(_ h: CGFloat) -> some View {
        let side = TimerLayout.circle(h)
        return HStack(spacing: TimerLayout.circleGap(h)) {
            IslandCircleButton(control: .activityFirst, height: h, tint: .white, label: String(localized: "Decline"), side: side) {
                perform(.decline)
            } glyph: {
                CrossGlyph(height: h)
            }
            .accessibilityIdentifier("decline-airdrop")
            IslandCircleButton(control: .activitySecond, height: h, tint: .white, label: String(localized: "Accept"), fill: AirDropLayout.tint, side: side) {
                perform(.accept)
            } glyph: {
                Image(systemName: "checkmark")
                    .font(.system(size: side * AirDropLayout.check, weight: .bold))
                    .foregroundStyle(.white)
            }
            .accessibilityIdentifier("accept-airdrop")
        }
    }

    func perform(_ choice: AirDropAnswer.Choice) {
        guard revealed, shown.asking else { return }
        answer(choice)
    }

    func performStop() {
        guard revealed, shown.offersStop else { return }
        stop()
    }

    /// The ring around a square that stops it: iOS 27's `airdrop-progress.ca` opened, the progress
    /// ring the iPhone's Shortcuts and background tasks share, in AirDrop's blue on its dark-blue track.
    private func stopControl(_ h: CGFloat) -> some View {
        TaskRingButton(
            status: .counting(shown.fraction), control: .activityFirst, height: h, label: String(localized: "Stop AirDrop"),
            tint: AirDropLayout.tint, track: AirDropLayout.track, side: TimerLayout.circle(h), action: performStop)
    }

    /// The file, as macOS pictures it, or its kind's icon, with AirDrop's badge, a dark tile with
    /// the iPhone's AirDrop glyph, on its corner.
    private func preview(_ h: CGFloat) -> some View {
        let side = TimerLayout.content(h)
        let badge = h * AirDropLayout.badge
        let picture = shown.preview ?? NSWorkspace.shared.icon(for: .data)
        return Image(nsImage: picture)
            .resizable()
            .aspectRatio(contentMode: shown.preview == nil ? .fit : .fill)
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: side * PlayerLayout.thumbnailCorner, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                AirDropBadgeGlyph(side: badge)
                    .background(RoundedRectangle(cornerRadius: badge * 0.22, style: .continuous).fill(AirDropLayout.badgeFill))
                    .overlay(
                        RoundedRectangle(cornerRadius: badge * 0.22, style: .continuous)
                            .strokeBorder(.black.opacity(0.6), lineWidth: h * 0.03)
                    )
                    .offset(x: h * AirDropLayout.badgeOut, y: h * AirDropLayout.badgeOut)
            }
            // A kind's icon has room around its paper: the paper goes on the padding, as a picture does.
            .offset(x: shown.preview == nil ? -side * AirDropLayout.paperMargin : 0)
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
                .clipShape(
                    Circle().size(width: side * Self.outer, height: side * Self.outer)
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
