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

    /// The round: up from below straight to Keep in Tray, the notch opening for the drop on the way
    /// as the pointer comes within reach of it; let go, a rest on the tray, then away, the notch
    /// closing behind.
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
            // Closed, its places to drop ready for when it opens.
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) {
                model.state = .closed
                model.page = .tray
                model.dropping = true
                model.airDropTargeted = false
            }
            tray.remove(photo.id)
            out = true
            carried = photo
            letGo = false
            let closed = geometry.rect(.closed), open = geometry.rect(.open)
            let keep = CGRect(x: open.minX, y: open.minY + open.height * 0.25, width: open.width / 2, height: open.height * 0.7)
            let side = Shelf.icon * geometry.scale
            let from = CGPoint(x: size.width * 0.76, y: size.height + 24)
            // The photo over Keep in Tray's symbol, leaving its name in sight.
            let zone = CGPoint(x: open.minX + open.width * 0.26 + 6, y: open.minY + open.height * 0.5 - side / 2 + 10)
            // As on screen: within reach of the notch, it opens for the drop, without the pointer
            // stopping.
            let reach = NotchController.dropReach * geometry.scale
            guard
                await glide(
                    HandMove(from: from, to: zone), over: 1.5,
                    step: { point in
                        if model.state == .closed, closed.distance(to: point) < reach { model.open() }
                        copying = model.state == .open && keep.contains(point)
                    }),
                await wait(0.45)
            else { return }

            withAnimation(.easeIn(duration: 0.18)) { letGo = true }
            copying = false
            withAnimation(.smooth(duration: 0.3)) { model.dropping = false }
            withAnimation(.smooth(duration: 0.35)) { putBack(tray) }
            out = false
            // The hand eases off the button, and the pointer drifts a little.
            let rest = CGPoint(x: zone.x + 3, y: zone.y + 4)
            guard await glide(HandMove(from: zone, to: rest, corrects: false), over: 0.35), await wait(1.1) else { return }
            carried = nil

            let away = CGPoint(x: size.width * 0.6, y: size.height + 30)
            guard await glide(HandMove(from: rest, to: away, flicks: true), over: 0.6, at: 0.4, do: { model.close() }) else { return }
            tip = nil
            guard await wait(0.3) else { return }
        }
    }

    /// The photo back at the front of the tray, as a drop puts it, not chosen.
    private func putBack(_ tray: Tray) {
        tray.undoRemove()
        tray.deselect()
    }

    /// The pointer moved by hand from one place to another (see HandMove); partway, if asked,
    /// something happens. Whether it got there before the demo ended.
    private func glide(
        _ move: HandMove, over seconds: Double, step: (CGPoint) -> Void = { _ in }, at moment: Double = 2,
        do action: () -> Void = {}
    ) async -> Bool {
        let start = Date.now
        var acted = false
        while true {
            let s = min(Date.now.timeIntervalSince(start) / seconds, 1)
            let point = move.point(at: s)
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

/// How a hand moves a pointer, rather than how a machine would: a quick main movement along a slight
/// arc, fastest early on, that lands a little short of the place and to one side, then a small,
/// slower correction onto it. Leaving, a flick that speeds up as it goes, with no place to land.
struct HandMove {
    let from: CGPoint
    let to: CGPoint
    /// Lands short and corrects; otherwise it lands right where it's going, as a small move does.
    var corrects = true
    var flicks = false

    /// The share of the time the main movement takes; the correction takes the rest.
    static let main = 0.76

    /// Where the pointer is, a share of the way through the time.
    func point(at s: Double) -> CGPoint {
        let s = min(max(s, 0), 1)
        let dx = to.x - from.x, dy = to.y - from.y
        let length = hypot(dx, dy)
        guard length > 0 else { return to }
        // Along the way, and across it, to its left.
        let along = CGPoint(x: dx / length, y: dy / length)
        let across = CGPoint(x: -along.y, y: along.x)
        if flicks {
            // Off the picture: a slight arc, speeding up.
            return arc(from, to, bow: 0.06 * length, across: across, at: s * s)
        }
        guard corrects else { return arc(from, to, bow: 0, across: across, at: Self.reach(s)) }
        // Short of the place by a few points, and aside by fewer.
        let short = min(0.05 * length, 9), aside = min(0.03 * length, 5)
        let landing = CGPoint(x: to.x - along.x * short + across.x * aside, y: to.y - along.y * short + across.y * aside)
        if s < Self.main {
            return arc(from, landing, bow: 0.1 * length, across: across, at: Self.reach(s / Self.main))
        }
        return arc(landing, to, bow: 0, across: across, at: Self.reach((s - Self.main) / (1 - Self.main)))
    }

    /// From one point to another, bowed to one side at its middle by as much as asked.
    private func arc(_ a: CGPoint, _ b: CGPoint, bow: CGFloat, across: CGPoint, at t: Double) -> CGPoint {
        let t = CGFloat(t), u = 1 - t
        let control = CGPoint(x: (a.x + b.x) / 2 + across.x * bow, y: (a.y + b.y) / 2 + across.y * bow)
        return CGPoint(x: u * u * a.x + 2 * u * t * control.x + t * t * b.x, y: u * u * a.y + 2 * u * t * control.y + t * t * b.y)
    }

    /// How far through a reach, a share of the way through its time: quick to get going and slow to
    /// settle (minimum jerk), its speed peaking a little early, as a hand's does.
    static func reach(_ x: Double) -> Double {
        let t = pow(min(max(x, 0), 1), 0.8)
        return t * t * t * (10 - 15 * t + 6 * t * t)
    }
}
