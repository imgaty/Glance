//
//  NotchDemo.swift
//  Glance
//
//  Created by Gaty on 16/10/2026.
//

import AppKit
import SwiftUI

/// A scene the notch's picture plays by itself, round after round, for the welcome tour and the
/// pictures of Glance: what a feature does, shown rather than told. The README's GIFs are recorded
/// from these.
enum NotchDemo {
    /// Open on the player, turning from one layout to the other and back.
    case layouts
    /// A photo dragged up to the closed notch, which opens with its two places to drop; let go on
    /// Keep in Tray, not AirDrop, the photo joins the front of the tray, and the notch closes as the
    /// pointer leaves.
    case dropInTray
}

/// Plays a demo over the notch's picture: moves the notch, and draws the pointer and what it
/// carries, as macOS draws a drag. With Reduce Motion on, it plays nothing: the picture rests as
/// it is.
struct NotchDemoScene: View {
    let demo: NotchDemo
    @ObservedObject var model: NotchModel
    let size: CGSize
    let geometry: SettingsPreview.Geometry
    /// The made-up tray, which the drop takes from and gives back to; the real one, never.
    @Environment(\.tray) private var demoTray
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tip: CGPoint?
    @State private var carried: TrayItem?
    /// Over a place that takes the drop: the pointer shows the green plus, as it does to copy.
    @State private var copying = false
    @State private var letGo = false

    var body: some View {
        let side = Shelf.icon * geometry.scale
        ZStack(alignment: .topLeading) {
            if let tip {
                if let carried, let demoTray {
                    // As Finder drags a file: its picture, a little see-through, under the pointer.
                    TrayItemPicture(item: carried, tray: demoTray, side: side)
                        .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                        .opacity(letGo ? 0 : 0.82)
                        .scaleEffect(letGo ? 0.4 : 1)
                        .position(x: tip.x - 6, y: tip.y + side / 2 - 10)
                }
                let cursor = copying ? NSCursor.dragCopy : NSCursor.arrow
                let image = cursor.image, hot = cursor.hotSpot
                Image(nsImage: image)
                    .frame(width: image.size.width, height: image.size.height)
                    .position(x: tip.x - hot.x + image.size.width / 2, y: tip.y - hot.y + image.size.height / 2)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: "\(demo) \(size.width) \(size.height) \(reduceMotion)") {
            guard !reduceMotion else { return }
            switch demo {
            case .layouts: await switchLayouts()
            case .dropInTray: await dropInTray()
            }
        }
    }

    // MARK: Layouts

    /// Every couple of seconds the other layout, reshaping the notch in place, as choosing it does.
    private func switchLayouts() async {
        while await wait(2.2) {
            withAnimation(.spring(response: 0.5, dampingFraction: 1)) { model.use(model.layout == .top ? .side : .top) }
        }
    }

    // MARK: Dropping in the tray

    /// The round: up from below to the notch, a moment's rest while it opens for the drop, over to
    /// Keep in Tray, let go, a rest on the tray, then away, the notch closing behind.
    private func dropInTray() async {
        guard let tray = demoTray, let photo = tray.items.first(where: { $0.kind == .files }) else { return }
        // Taken out while it's carried; put back however the round ends.
        var out = false
        defer {
            tip = nil
            carried = nil
            copying = false
            if out { putBack(tray) }
            // Ended partway, as when the tour moves on: no places to drop are left behind.
            model.dropping = false
            model.airDropTargeted = false
        }
        while !Task.isCancelled {
            // Open, as the tour's last step left it: closed first, as the pointer leaving closes it.
            if model.state != .closed {
                model.close()
                guard await wait(0.6) else { return }
            }
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) {
                model.state = .closed
                model.page = .tray
                model.dropping = false
                model.airDropTargeted = false
            }
            tray.remove(photo.id)
            out = true
            carried = photo
            letGo = false
            let closed = geometry.rect(.closed)
            let from = CGPoint(x: size.width * 0.76, y: size.height + 24)
            let near = CGPoint(x: closed.midX + 28, y: closed.maxY + 26)
            guard await glide(from, near, over: 1.1), await wait(0.25) else { return }

            // Near the notch a moment, as a folder springs open under a dragged file.
            withAnimation(.smooth(duration: 0.3)) { model.dropping = true }
            model.open()
            guard await wait(0.15) else { return }
            let open = geometry.rect(.open)
            let keep = CGRect(x: open.minX, y: open.minY + open.height * 0.25, width: open.width / 2, height: open.height * 0.7)
            let side = Shelf.icon * geometry.scale
            // The photo over Keep in Tray's symbol, leaving its name in sight.
            let zone = CGPoint(x: open.minX + open.width * 0.26 + 6, y: open.minY + open.height * 0.5 - side / 2 + 10)
            guard await glide(near, zone, over: 0.8, step: { copying = keep.contains($0) }), await wait(0.45) else { return }

            withAnimation(.easeIn(duration: 0.18)) { letGo = true }
            copying = false
            withAnimation(.smooth(duration: 0.3)) { model.dropping = false }
            withAnimation(.smooth(duration: 0.35)) { putBack(tray) }
            out = false
            guard await wait(1.45) else { return }
            carried = nil

            let away = CGPoint(x: size.width * 0.64, y: size.height + 30)
            guard await glide(zone, away, over: 0.9, at: 0.45, do: { model.close() }) else { return }
            tip = nil
            guard await wait(0.5) else { return }
        }
    }

    /// The photo back at the front of the tray, as a drop puts it, not chosen.
    private func putBack(_ tray: Tray) {
        tray.undoRemove()
        tray.deselect()
    }

    /// The pointer from one place to another on a gentle curve, the way a hand moves it, easing in
    /// and out; partway, if asked, something happens. Whether it got there before the demo ended.
    private func glide(
        _ from: CGPoint, _ to: CGPoint, over seconds: Double, step: (CGPoint) -> Void = { _ in }, at moment: Double = 2,
        do action: () -> Void = {}
    ) async -> Bool {
        let start = Date.now
        var acted = false
        while true {
            let s = min(Date.now.timeIntervalSince(start) / seconds, 1)
            let e = CGFloat(s * s * (3 - 2 * s))
            let bend = CGPoint(x: (from.x + to.x) / 2 + (from.x - to.x) * 0.5, y: (from.y + to.y) / 2)
            let u = 1 - e
            let point = CGPoint(
                x: u * u * from.x + 2 * u * e * bend.x + e * e * to.x, y: u * u * from.y + 2 * u * e * bend.y + e * e * to.y)
            tip = point
            step(point)
            if s >= moment, !acted {
                acted = true
                action()
            }
            if s >= 1 { return true }
            try? await Task.sleep(for: .milliseconds(16))
            if Task.isCancelled { return false }
        }
    }

    private func wait(_ seconds: Double) async -> Bool {
        try? await Task.sleep(for: .seconds(seconds))
        return !Task.isCancelled
    }
}
