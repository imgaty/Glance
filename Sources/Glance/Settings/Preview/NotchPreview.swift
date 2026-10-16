//
//  NotchPreview.swift
//  Glance
//
//  Created by Gaty on 07/10/2026.
//

import AppKit
import SwiftUI

/// The notch itself, live, at the top of the display's screen as it is on it: in the menu bar, over
/// a window open below it, with the camera housing on a display that has one. One scale for every
/// layout, the one the widest needs, so changing layout only reshapes the notch. The pointer works
/// it as on screen: it swells as the pointer nears, opens and closes, and what's in it answers the
/// pointer too. Interactive, it rests closed, to be opened; otherwise it rests open, and goes back
/// to that once the pointer leaves the picture.
struct NotchPreview: View {
    @ObservedObject var model: NotchModel
    @EnvironmentObject private var preview: SettingsPreview
    let display: String
    let top: ScreenTop
    var interactive = false
    /// Interactive, the pointer shows where to open it now and then.
    var hintsOpening = true
    /// The page behind holds still, on the Music page.
    var still = false
    /// Drawn to the scale a picture this wide would draw it, rather than its own width's: the
    /// welcome tour's pictures, wider, draw the notch as large as Settings' preview does.
    var scaleWidth: CGFloat?
    /// A scene it plays by itself, round after round; while it plays, the pointer leaves the notch
    /// be.
    var demo: NotchDemo?
    @EnvironmentObject private var nowPlaying: NowPlaying
    @AppStorage(Preferences.liveActivity) private var liveActivity = true
    @AppStorage(Preferences.openTrigger) private var trigger = OpenTrigger.both
    @State private var pressing = false
    /// The pointer is over the picture: the pointer showing how gives way.
    @State private var hovering = false
    /// When the pointer showing how set off, which it and the notch both go by.
    @State private var hintStart = Date.now
    @Environment(\.notchPaused) private var paused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let hinting = interactive && hintsOpening && !paused && !hovering && !pressing
        GeometryReader { proxy in
            let scale = Self.scale(for: scaleWidth ?? proxy.size.width, model: model)
            let geometry = SettingsPreview.Geometry(
                rect: { state in
                    let m = model.metrics(for: state)
                    return CGRect(
                        x: proxy.size.width / 2 - m.totalWidth * scale / 2, y: (top.edge + model.gap) * scale,
                        width: m.totalWidth * scale, height: m.height * scale)
                }, scale: scale)
            ZStack(alignment: .top) {
                ScreenPicture(top: top, size: CGSize(width: proxy.size.width / scale, height: proxy.size.height / scale)) {
                    ApplePage(scrolls: !still)
                } notch: {
                    // Its sizes change as a whole: drawn smaller, the glass otherwise loses its place
                    // as the notch changes size, and stays there.
                    NotchView(model: model, display: display)
                        .geometryGroup()
                }
                .scaleEffect(scale, anchor: .top)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                if interactive, hintsOpening {
                    let path = hintPath(proxy.size, geometry)
                    TryItPointer(from: path.from, to: path.to, active: hinting, start: hintStart, trigger: trigger)
                }
                if let demo {
                    NotchDemoScene(demo: demo, model: model, size: proxy.size, geometry: geometry)
                }
            }
            // The notch answers the pointer showing how, as it answers the real one.
            .task(id: "\(hinting) \(trigger) \(proxy.size.width) \(proxy.size.height)") {
                guard hinting else { return }
                await demonstrate(along: hintPath(proxy.size, geometry), geometry)
            }
            // Followed over the whole picture, the notch included, so what's in the notch still
            // gets the pointer and the clicks.
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                guard demo == nil else { return }
                switch phase {
                case .active(let p):
                    hovering = true
                    preview.pointer(at: p, geometry)
                case .ended:
                    hovering = false
                    preview.pointer(at: nil, geometry)
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        if demo == nil, !pressing {
                            pressing = true
                            preview.press(at: drag.startLocation, geometry)
                        }
                    }
                    .onEnded { drag in
                        guard pressing else { return }
                        pressing = false
                        preview.release(at: drag.location, geometry)
                    })
        }
        // As on screen: closed, the notch shows what's playing only while something plays.
        .onChange(of: "\(nowPlaying.isPlaying) \(liveActivity) \(ObjectIdentifier(model).hashValue)", initial: true) {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { model.activity = nowPlaying.isPlaying && liveActivity }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of the notch")
        .accessibilityHint(interactive ? "Try opening the notch." : "")
        .accessibilityAddTraits(.isImage)
    }

    /// One scale for every layout, the one the widest needs to fit a picture this wide.
    static func scale(for width: CGFloat, model: NotchModel) -> CGFloat {
        let widest = PlayerLayout.allCases.map { $0.size(closed: model.closedSize).width }.max() ?? model.openSize.width
        return min(1, width / (widest + PlayerLayout.cornerRadius * 2 + 24))
    }

    /// Where the pointer showing how sets off and where it rests, up on the notch.
    private func hintPath(_ size: CGSize, _ geometry: SettingsPreview.Geometry) -> (from: CGPoint, to: CGPoint) {
        let notch = geometry.rect(.closed)
        return (CGPoint(x: notch.midX + 34, y: size.height * 0.64), CGPoint(x: notch.midX, y: notch.maxY - 5 * geometry.scale))
    }

    /// Moves the notch with the pointer showing how, round after round, as the real pointer moves
    /// it: nearing, it swells; on it, it peeks and opens as set (resting on it, or with a click, or
    /// one and then the other), and gives no tap; once the pointer goes, it closes. What's in the
    /// notch answers it too.
    private func demonstrate(along path: (from: CGPoint, to: CGPoint), _ geometry: SettingsPreview.Geometry) async {
        let start = Date.now
        hintStart = start
        preview.feelsOpening = false
        var pressed = false
        defer {
            model.demoPointer = nil
            preview.feelsOpening = true
            preview.holdsHoverOpening = false
            if pressed { preview.cancelPress() }
        }
        while !Task.isCancelled {
            let elapsed = Date.now.timeIntervalSince(start)
            let t = elapsed.truncatingRemainder(dividingBy: TryItPointer.period)
            let clicks = TryItPointer.clicks(round: Int(elapsed / TryItPointer.period), trigger: trigger)
            // Showing a click, resting on it doesn't open it first.
            preview.holdsHoverOpening = clicks && trigger == .both
            let step = TryItPointer.step(at: t, clicks: clicks)
            let tip = TryItPointer.point(from: path.from, to: path.to, at: reduceMotion ? 1 : step.travel)
            let shown = step.opacity > 0.5
            // In the notch's own points, while it's over the notch.
            let notch = geometry.rect(model.state)
            let inside = shown && notch.contains(tip)
            let pointer = inside ? CGPoint(x: (tip.x - notch.minX) / geometry.scale, y: (tip.y - notch.minY) / geometry.scale) : nil
            if model.demoPointer != pointer { model.demoPointer = pointer }
            preview.pointer(at: shown ? tip : nil, geometry)
            let down = clicks && t >= TryItPointer.clickTime && t < TryItPointer.releaseTime
            if down != pressed {
                pressed = down
                down ? preview.press(at: tip, geometry) : preview.release(at: tip, geometry)
            }
            try? await Task.sleep(for: .milliseconds(16))
        }
    }
}

/// Showing where to try the notch, as Apple's own videos of the Mac show it: the Mac's real arrow
/// pointer comes in at the middle of the picture, glides up to the notch on a gentle curve, the way
/// a hand moves a pointer, and rests on it; to show a click, it clicks, with a circle around it as
/// macOS shows clicks in screen recordings. Opened by hovering, it only rests; by clicking, it
/// clicks; by either, it does one and then the other. The notch answers it as it answers the real
/// pointer (NotchPreview moves it along). It fades away and comes again. It gives way while the
/// pointer is over the picture; with Reduce Motion it rests where it goes.
private struct TryItPointer: View {
    /// Where the pointer's tip starts and where it rests.
    let from: CGPoint
    let to: CGPoint
    let active: Bool
    /// When it set off.
    let start: Date
    /// How the notch opens, which it shows.
    let trigger: OpenTrigger
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let cursor = NSCursor.arrow
    static let period = 3.4
    /// When, after it sets off, it presses, and lets go.
    static let clickTime = 1.6
    static let releaseTime = 1.75

    /// Whether a round clicks: never when hovering opens the notch, always when clicking does, and
    /// every other round when either does.
    static func clicks(round: Int, trigger: OpenTrigger) -> Bool {
        switch trigger {
        case .hover: false
        case .click: true
        case .both: round % 2 == 1
        }
    }

    var body: some View {
        let image = Self.cursor.image
        // The tip, from the image's top left, as the cursor's hot spot is given.
        let hot = Self.cursor.hotSpot
        TimelineView(.animation(paused: !active)) { context in
            let elapsed = context.date.timeIntervalSince(start)
            let t = elapsed.truncatingRemainder(dividingBy: Self.period)
            let step = Self.step(at: reduceMotion ? 1.4 : t, clicks: Self.clicks(round: Int(elapsed / Self.period), trigger: trigger))
            let tip = Self.point(from: from, to: to, at: step.travel)
            ZStack(alignment: .topLeading) {
                Circle()
                    .fill(.white.opacity(0.22))
                    .strokeBorder(.white.opacity(0.7), lineWidth: 1.5)
                    .shadow(color: .black.opacity(0.25), radius: 2)
                    .frame(width: 22, height: 22)
                    .scaleEffect(step.circleScale)
                    .opacity(step.circle)
                    .position(tip)
                Image(nsImage: image)
                    .frame(width: image.size.width, height: image.size.height)
                    .scaleEffect(step.press, anchor: UnitPoint(x: hot.x / image.size.width, y: hot.y / image.size.height))
                    .position(x: tip.x - hot.x + image.size.width / 2, y: tip.y - hot.y + image.size.height / 2)
                    .opacity(step.opacity)
            }
        }
        .opacity(active ? 1 : 0)
        .animation(.easeInOut(duration: 0.25), value: active)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Along a gentle curve, bowing out to the side it comes from, as a pointer moved by hand.
    static func point(from: CGPoint, to: CGPoint, at s: CGFloat) -> CGPoint {
        let bend = CGPoint(x: (from.x + to.x) / 2 + (from.x - to.x) * 0.9, y: (from.y + to.y) / 2)
        let u = 1 - s
        return CGPoint(
            x: u * u * from.x + 2 * u * s * bend.x + s * s * to.x,
            y: u * u * from.y + 2 * u * s * bend.y + s * s * to.y)
    }

    /// One round: in at the middle, up to the notch, a rest, a click (if it clicks), gone, a pause.
    static func step(at t: Double, clicks: Bool) -> (travel: CGFloat, press: CGFloat, circle: Double, circleScale: CGFloat, opacity: Double) {
        func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }
        func ease(_ x: Double) -> CGFloat {
            let x = clamp(x)
            return CGFloat(x * x * (3 - 2 * x))
        }
        // A hand's reach: quick to get going, slow to settle (minimum jerk).
        let r = clamp((t - 0.25) / 1.0)
        let travel = CGFloat(r * r * r * (10 - 15 * r + 6 * r * r))
        // The click: pressed at 1.6 s, let go at 1.75 s.
        let press: CGFloat = t < 1.6 ? 1 : t < 1.68 ? 1 - 0.1 * ease((t - 1.6) / 0.08) : 0.9 + 0.1 * ease((t - 1.75) / 0.12)
        let circle: Double = t < 1.6 ? 0 : t < 1.7 ? clamp((t - 1.6) / 0.1) : 1 - clamp((t - 1.8) / 0.3)
        let circleScale: CGFloat = t < 1.7 ? 0.6 + 0.4 * ease((t - 1.6) / 0.1) : 1 + 0.15 * ease((t - 1.8) / 0.3)
        let opacity: Double = t < 0.25 ? t / 0.25 : t < 2.25 ? 1 : 1 - clamp((t - 2.25) / 0.3)
        return clicks ? (travel, press, circle, circleScale, opacity) : (travel, 1, 0, 1, opacity)
    }
}

/// A choice's picture: the real notch, open in a layout, playing what's playing, in the look of the
/// display shown above (or with a given background), at the top of that display's screen, over a
/// window below the menu bar, as the preview above shows it.
struct NotchThumbnail: View {
    let display: String
    let top: ScreenTop
    let background: MusicBackground?
    @StateObject private var model: NotchModel
    @Environment(\.shownPage) private var shownPage
    @Environment(\.settingsPage) private var page

    init(layout: PlayerLayout, display: String, background: MusicBackground? = nil) {
        let top = ScreenTop(NSScreen.with(id: display) ?? NSScreen.main)
        self.display = display
        self.top = top
        self.background = background
        _model = StateObject(wrappedValue: .picture(of: top, layout: layout))
    }

    var body: some View {
        GeometryReader { proxy in
            let size = model.openSize
            let scale = proxy.size.width / (size.width + PlayerLayout.cornerRadius * 2 + 20)
            let screen = CGSize(width: proxy.size.width / scale, height: proxy.size.height / scale)
            ZStack(alignment: .top) {
                // What's under the notch never changes; the notch does, all the time.
                StillScreen(top: top, size: screen, scale: scale, edge: false) {
                    ApplePage.Still()
                }
                ScreenPicture(top: top, size: screen, edge: false, still: false) {
                    EmptyView()
                } notch: {
                    NotchView(model: model, display: display, background: background)
                        .allowsHitTesting(false)
                        // Still on a page not shown.
                        .environment(\.notchPaused, page != nil && shownPage.map { $0.page != page } == true)
                        .environment(\.notchThumbnail, true)
                }
                .scaleEffect(scale, anchor: .top)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            }
            // Drawn at the picture's own size, rather than drawn large and shrunk, which leaves
            // the text and edges jagged.
            .drawingGroup()
        }
        .allowsHitTesting(false)
    }
}
