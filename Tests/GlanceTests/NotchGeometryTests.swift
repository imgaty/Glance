//
//  NotchGeometryTests.swift
//  GlanceTests
//
//  Created by Gaty on 10/10/2026.
//

import AppKit
import SwiftUI
import Testing

@testable import Glance

/// How the open notch's glass looks for the Appearance sliders.
@Suite("Glass look")
struct GlassLookTests {
    @Test("No blur at none, 24 points at full")
    func blurEnds() {
        #expect(GlassLook.blur(0) == 0)
        #expect(isClose(GlassLook.blur(1), 24))
    }

    @Test("Blur eases in, so the slider's first half covers the subtle blurs")
    func blurEasesIn() {
        #expect(isClose(GlassLook.blur(0.25), 3))
        #expect(isClose(GlassLook.blur(0.5), 24 * pow(0.5, 1.5)))
        #expect(GlassLook.blur(0.5) < 12)
    }

    @Test("Blur stays within none and full", arguments: [-1.0, -0.01, 1.01, 2, 100])
    func blurClamped(amount: Double) {
        let blur = GlassLook.blur(amount)
        #expect(blur >= 0 && blur <= 24)
    }

    @Test("Blur grows with the slider")
    func blurIncreases() {
        let steps = stride(from: 0.0, through: 1, by: 0.05).map(GlassLook.blur)
        #expect(zip(steps, steps.dropFirst()).allSatisfy { $0 < $1 })
    }

    @Test("Clear glass is dimmed by a third, as Apple dims clear glass over bright content; full darkness is solid")
    func blackEnds() {
        #expect(isClose(GlassLook.black(0), 0.35))
        #expect(isClose(GlassLook.black(1), 1))
    }

    @Test("Darkness eases in, so most of the way is glass")
    func blackEasesIn() {
        #expect(isClose(GlassLook.black(0.5), 0.5125))
        let steps = stride(from: 0.0, through: 1, by: 0.05).map(GlassLook.black)
        #expect(zip(steps, steps.dropFirst()).allSatisfy { $0 < $1 })
    }
}

/// The notch's corners, closed and open.
@Suite("Notch corners")
struct NotchCornersTests {
    private let notch = NotchCorners(restingHeight: 32, radius: 38.5)

    @Test("Closed, it has the hardware notch's flares and corners")
    func resting() {
        let radii = notch.radii(forHeight: 32)
        #expect(radii.flare == 6)
        #expect(radii.bottom == 12)
    }

    @Test("Closed with wings out, it keeps the hardware notch's flares, and their ends are round")
    func wings() {
        let radii = notch.radii(forHeight: 32, wingEnds: 1)
        #expect(radii.flare == 6)
        #expect(isClose(radii.bottom, 16))
    }

    @Test("Swollen under the pointer, it keeps the hardware notch's flares")
    func swollen() {
        #expect(notch.radii(forHeight: 39).flare == 6)
        #expect(isClose(notch.radii(forHeight: 39, wingEnds: 1).bottom, 19.5))
    }

    @Test("Open, the bottom corners are the one radius, however tall it stands, and the top follow its height", arguments: [77.0, 130.0, 172.0, 400.0])
    func open(height: CGFloat) {
        for wingEnds in [0.0, 1.0] {
            let radii = notch.radii(forHeight: height, wingEnds: wingEnds)
            #expect(isClose(radii.flare, min(38.5 * height / 148, 38.5)))
            #expect(isClose(radii.bottom, 38.5))
        }
    }

    @Test("Shorter than closed, the corners stay at the closed ones")
    func belowResting() {
        let radii = notch.radii(forHeight: 10)
        #expect(radii.flare == 6)
        #expect(radii.bottom == 12)
    }

    @Test("The flare is counted on both sides of the width")
    func metricsWidth() {
        let metrics = NotchMetrics(bodyWidth: 200, height: 32, flare: 6)
        #expect(metrics.totalWidth == 212)
    }
}

/// How far the pointer is from the notch.
@Suite("Distance to a rectangle")
struct RectDistanceTests {
    private let rect = CGRect(x: 0, y: 0, width: 10, height: 10)

    @Test(
        "Inside or on the edge is no distance",
        arguments: [
            CGPoint(x: 5, y: 5), CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10), CGPoint(x: 10, y: 3),
        ])
    func inside(point: CGPoint) {
        #expect(rect.distance(to: point) == 0)
    }

    @Test(
        "Beside it, the distance to the nearest side",
        arguments: [
            (CGPoint(x: 13, y: 5), 3.0),
            (CGPoint(x: -2, y: 5), 2.0),
            (CGPoint(x: 5, y: 14), 4.0),
            (CGPoint(x: 5, y: -1), 1.0),
        ])
    func beside(point: CGPoint, distance: Double) {
        #expect(isClose(rect.distance(to: point), CGFloat(distance)))
    }

    @Test("Off a corner, the straight-line distance to it")
    func diagonal() {
        #expect(isClose(rect.distance(to: CGPoint(x: 13, y: 14)), 5))
        #expect(isClose(rect.distance(to: CGPoint(x: -3, y: -4)), 5))
    }
}

/// The open player's layouts and sizes.
@Suite("Player layout")
struct PlayerLayoutTests {
    private let closed = CGSize(width: 185, height: 32)

    @Test("The cover is smaller on top than on the side")
    func artwork() {
        #expect(PlayerLayout.top.artwork == 60)
        #expect(PlayerLayout.side.artwork == 120)
        // A thumbnail's corners.
        #expect(PlayerLayout.top.artworkRadius == PlayerLayout.top.artwork * PlayerLayout.thumbnailCorner)
        // Concentric with the notch's.
        #expect(PlayerLayout.side.artworkRadius == PlayerLayout.cornerRadius - PlayerLayout.padding)
    }

    @Test("The open corners are concentric with what's round at the ends")
    func cornerRadius() {
        #expect(PlayerLayout.cornerRadius == PlayerLayout.padding + TimerLayout.content(32) / 2)
    }

    @Test("Cover on top, around the usual notch")
    func topSize() {
        // Wide enough to keep the cover clear of the camera: 185 + 2 × (14 + 60 + 8) = 349, made even.
        // Tall enough for the padding, cover, timeline and controls: 14 + 60 + 12 + 16 + 8 + 40 + 14.
        #expect(PlayerLayout.top.size(closed: closed) == CGSize(width: 350, height: 164))
    }

    @Test("Cover on the side, around the usual notch")
    func sideSize() {
        // 185 + 2 × (14 + 120 + 8) = 469, made even; the cover sets the height: 14 + 120 + 14.
        #expect(PlayerLayout.side.size(closed: closed) == CGSize(width: 470, height: 148))
    }

    @Test("A narrow camera still leaves room for the controls")
    func narrowCamera() {
        let small = CGSize(width: 100, height: 20)
        // 14 × 2 + 280 = 308 on top; 14 × 2 + 120 + 17 + 280 = 445 on the side, made even.
        #expect(PlayerLayout.top.size(closed: small).width == 308)
        #expect(PlayerLayout.side.size(closed: small).width == 446)
    }

    @Test("A tall camera pushes the side layout's column down")
    func tallCamera() {
        let tall = CGSize(width: 185, height: 60)
        let column = tall.height + PlayerLayout.cameraGap - PlayerLayout.padding + NowPlayingView.sideColumnHeight
        #expect(PlayerLayout.side.size(closed: tall).height == PlayerLayout.padding * 2 + column)
    }

    @Test(
        "The open width is always even, so the notch centers on whole points",
        arguments: PlayerLayout.allCases, [100.0, 151, 185, 187.5, 203, 250])
    func evenWidth(layout: PlayerLayout, cameraWidth: Double) {
        let width = layout.size(closed: CGSize(width: cameraWidth, height: 32)).width
        #expect(width.truncatingRemainder(dividingBy: 2) == 0)
    }

    @Test("Open, the notch is always bigger than closed", arguments: PlayerLayout.allCases)
    func biggerThanClosed(layout: PlayerLayout) {
        let size = layout.size(closed: closed)
        #expect(size.width > closed.width)
        #expect(size.height > closed.height)
    }

    @Test("Layouts have names for Settings")
    func titles() {
        #expect(PlayerLayout.top.title == "Cover on top")
        #expect(PlayerLayout.side.title == "Cover on the side")
    }
}

/// The player's buttons and colors, as Settings offers them.
@Suite("Player options")
struct PlayerOptionsTests {
    @Test("Every control is offered, and none isn't one of them")
    func controls() {
        #expect(PlayerSlot.controls == [.favorite, .shuffle, .repeatMode, .output, .lyrics])
        #expect(!PlayerSlot.controls.contains(.empty))
        #expect(Set(PlayerSlot.controls + [.empty]) == Set(PlayerSlot.allCases))
    }

    @Test("Each control has a name, a symbol and a description", arguments: PlayerSlot.controls)
    func controlDetails(slot: PlayerSlot) {
        #expect(!slot.title.isEmpty)
        #expect(!slot.symbol.isEmpty)
        #expect(!slot.summary.isEmpty)
        #expect(NSImage(systemSymbolName: slot.symbol, accessibilityDescription: nil) != nil)
    }

    @Test("No control has no description")
    func emptySlot() {
        #expect(PlayerSlot.empty.title == "None")
        #expect(PlayerSlot.empty.summary.isEmpty)
        #expect(NSImage(systemSymbolName: PlayerSlot.empty.symbol, accessibilityDescription: nil) != nil)
    }

    @Test("As it comes, the player has favorite on the left and sound output on the right")
    func standardPlaces() {
        #expect(ControlPlace.left.standard == .favorite)
        #expect(ControlPlace.right.standard == .output)
    }

    @Test("Backgrounds have names for Settings")
    func backgroundTitles() {
        #expect(MusicBackground.allCases.map(\.title) == ["Replace glass", "Spotlight", "None"])
    }

    @Test("The spotlight goes round the cover and nowhere else, and never reaches the camera housing")
    func spotlightRoundTheCover() {
        let closed = CGSize(width: 185, height: 32)
        for layout in PlayerLayout.allCases {
            let open = layout.size(closed: closed)
            let artwork = layout.artwork
            // In the open notch's own points: the cover up in its top left corner, the housing in the
            // middle of its top edge.
            let cover = CGPoint(x: PlayerLayout.padding + artwork / 2, y: PlayerLayout.padding + artwork / 2)
            let camera = CGRect(x: open.width / 2 - closed.width / 2, y: 0, width: closed.width, height: closed.height)
            var widths: [CGFloat] = []
            for step in 0..<240 {
                let t = Spotlight.loop * Double(step) / 240
                let spot = Spotlight.spot(cover: cover, artwork: artwork, camera: camera, travelled: t)
                // Round the cover, at the same distance all the way.
                #expect(abs(hypot(spot.center.x - cover.x, spot.center.y - cover.y) - artwork * Spotlight.reach) < 0.01)
                // Its soft edge stops short of the housing, even at its corner; right beside it, it's gone.
                let nearest = CGPoint(x: min(max(spot.center.x, camera.minX), camera.maxX), y: min(spot.center.y, camera.maxY))
                let gap = hypot(spot.center.x - nearest.x, spot.center.y - nearest.y) - spot.diameter / 2 - Spotlight.fringe(artwork: artwork)
                #expect(spot.diameter == 0 || gap >= Spotlight.clearance - 0.01, "\(layout) at \(t) s: \(gap)")
                widths.append(spot.diameter)
                // Without a housing, it never shrinks.
                #expect(Spotlight.spot(cover: cover, artwork: artwork, camera: nil, travelled: t).diameter == artwork * Spotlight.width)
            }
            // Full width away from the housing, shrinking behind the cover toward it.
            #expect(widths.max() == artwork * Spotlight.width)
            #expect(widths.min() == 0)
            // It comes out below and left of the cover's middle, and goes up its left side first.
            let first = Spotlight.spot(cover: cover, artwork: artwork, camera: camera, travelled: 0).center
            let next = Spotlight.spot(cover: cover, artwork: artwork, camera: camera, travelled: 1).center
            #expect(first.x < cover.x && first.y > cover.y)
            #expect(next.x < first.x && next.y < first.y)
        }
    }

    @Test("Accent colors are named as System Settings names them")
    func accentTitles() {
        #expect(
            AccentSource.allCases.map(\.title) == [
                "Cover", "System", "Blue", "Purple", "Pink", "Red", "Orange", "Yellow", "Green", "Graphite",
            ])
    }

    @Test("Only the artwork's accent has no fixed color")
    func accentColors() {
        #expect(AccentSource.artwork.nsColor == nil)
        #expect(AccentSource.artwork.color == nil)
        for source in AccentSource.allCases where source != .artwork {
            #expect(source.nsColor != nil)
            #expect(source.color != nil)
        }
        #expect(AccentSource.system.nsColor == .controlAccentColor)
        #expect(AccentSource.graphite.nsColor == .systemGray)
    }

    @Test("Opening triggers have names for Settings")
    func triggerTitles() {
        #expect(OpenTrigger.allCases.map(\.title) == ["Hover", "Click", "Hover or click"])
    }

    @Test("An accent color's wash is a small picture, made once")
    @MainActor
    func accentWash() throws {
        let image = try #require(AccentWash.image(for: [.systemBlue]))
        #expect(image.size == NSSize(width: 64, height: 64))
        #expect(AccentWash.image(for: [.systemBlue]) === image)
        #expect(AccentWash.image(for: [.systemRed]) !== image)
    }
}

/// The Settings window's sidebar.
@Suite("Settings pages")
struct SettingsPaneTests {
    @Test("The sidebar's pages, in order")
    func order() {
        #expect(SettingsPane.allCases.map(\.title) == ["General", "Appearance", "Player", "Tray", "Live Activities", "Opening", "Displays"])
    }

    @Test("Each page has its own icon", arguments: SettingsPane.allCases)
    func symbols(pane: SettingsPane) {
        #expect(NSImage(systemSymbolName: pane.symbol, accessibilityDescription: nil) != nil)
    }

    @Test("Page icons are all different")
    func distinctSymbols() {
        #expect(Set(SettingsPane.allCases.map(\.symbol)).count == SettingsPane.allCases.count)
    }

    @Test("The pages about the notch's look and behavior show it at the top")
    func previews() {
        #expect(SettingsPane.allCases.filter(\.showsPreview) == [.appearance, .player, .tray, .activities, .opening])
        #expect(SettingsPane.allCases.filter(\.restsClosed) == [.activities, .opening])
    }

    @Test("Each page can be found by search", arguments: SettingsPane.allCases)
    func keywords(pane: SettingsPane) {
        #expect(!pane.keywords.isEmpty)
        #expect(pane.keywords == pane.keywords.lowercased())
    }

    @Test(
        "Searching finds the page you'd expect",
        arguments: [
            ("login", SettingsPane.general),
            ("blur", .appearance),
            ("spotify", .player),
            ("haptic", .opening),
            ("monitor", .displays),
        ])
    func search(word: String, pane: SettingsPane) {
        let found = SettingsPane.allCases.filter { $0.keywords.split(separator: " ").contains { $0.hasPrefix(word) } }
        #expect(found == [pane])
    }

    @Test(
        "Search finds a setting on the page it's on",
        arguments: [
            ("airdrop", SettingsPane.activities),
            ("AirDrop", .activities),
            ("timers", .activities),
            ("stopwatch", .activities),
            ("clock", .activities),
            ("beats", .activities),
            ("update", .general),
            ("volume", .player),
            ("recordings", .tray),
            ("announce", .activities),
        ])
    func searchFinds(query: String, pane: SettingsPane) {
        #expect(SettingsPane.matching(query) == [pane])
    }

    @Test("With Reduce Motion on, the notch's springs settle without a bounce")
    func reducedSprings() {
        #expect(NotchMotion.spring(response: 0.3, dampingFraction: 0.6, reduced: false) == .spring(response: 0.3, dampingFraction: 0.6))
        #expect(NotchMotion.spring(response: 0.3, dampingFraction: 0.6, reduced: true) == .spring(response: 0.3, dampingFraction: 1))
    }

    @Test("The View menu has Back, Forward, Search and every page, and comes before Window and Help")
    @MainActor
    func viewMenu() throws {
        _ = NSApplication.shared
        let main = AppDelegate().makeMainMenu()
        #expect(main.items.compactMap { $0.submenu?.title }.suffix(3) == ["View", "Window", "Help"])
        let view = try #require(main.items.first { $0.submenu?.title == "View" }?.submenu)
        let items = view.items.filter { !$0.isSeparatorItem }
        #expect(items.map(\.title) == ["Back", "Forward", "Search"] + SettingsPane.allCases.map(\.title))
        #expect(items.prefix(3).map(\.keyEquivalent) == ["[", "]", "f"])
    }

    @Test("Search finds nothing for what Glance doesn't have, and every page with nothing typed")
    func searchEdges() {
        #expect(SettingsPane.matching("mouse").isEmpty)
        #expect(SettingsPane.matching("  ") == SettingsPane.allCases)
    }
}

/// How far a drag stretches the notch: after the fingers, more and more slowly, up to a limit, down
/// and across alike.
@MainActor
@Suite("Stretching")
struct StretchTests {
    @Test("Down, across and pushed up, it stretches more slowly the further it goes, never past its limit")
    func limits() {
        for band in [NotchController.rubberBand, NotchController.sideBand] {
            #expect(band(0) == 0)
            #expect(band(10) > 0 && band(-10) < 0)
            #expect(band(40) > band(20) && band(40) - band(20) < band(20) - band(0))
        }
        #expect(NotchController.rubberBand(10_000) <= 18)
        #expect(NotchController.rubberBand(-10_000) >= -10)
        #expect(NotchController.sideBand(10_000) <= 12 && NotchController.sideBand(-10_000) >= -12)
        // Across, a little less than down.
        #expect(NotchController.sideBand(60) < NotchController.rubberBand(60))
        #expect(abs(NotchController.pageLean(10_000)) <= 20)
    }

    @Test("What's in the notch stretches half as much as the notch")
    func contentGives() {
        #expect(NotchModel.contentGive == 0.5)
    }

    @Test("A drag at a slant stretches the notch both ways at once")
    func slant() {
        let model = NotchModel(closedSize: CGSize(width: 185, height: 32), layout: .top, hasCamera: true)
        model.state = .open
        let still = model.metrics(for: .open)
        model.stretch = NotchController.rubberBand(30)
        model.lean = NotchController.sideBand(30)
        let pulled = model.metrics(for: .open)
        #expect(pulled.height > still.height)
        #expect(pulled.bodyWidth > still.bodyWidth + model.lean)
    }
}
