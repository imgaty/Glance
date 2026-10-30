//
//  NotchGeometryTests.swift
//  GlanceTests
//
//  Created by Gaty on 10/10/2026.
//

import AppKit
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

/// The notch's corners as it opens.
@Suite("Notch corners")
struct NotchCornersTests {
    private let notch = NotchCorners(restingHeight: 32, openHeight: 200, openRadius: 29)

    @Test("Closed, it has the hardware notch's flares and corners")
    func resting() {
        let radii = notch.radii(forHeight: 32)
        #expect(radii.flare == 6)
        #expect(radii.bottom == 12)
    }

    @Test("Open, all four corners are the open radius")
    func open() {
        let radii = notch.radii(forHeight: 200)
        #expect(isClose(radii.flare, 29))
        #expect(isClose(radii.bottom, 29))
    }

    @Test("Halfway open, the corners are halfway grown")
    func halfway() {
        let radii = notch.radii(forHeight: 116)
        #expect(isClose(radii.flare, 17.5))
        #expect(isClose(radii.bottom, 20.5))
    }

    @Test("Pulled past open, the corners stay at the open radius")
    func pastOpen() {
        let radii = notch.radii(forHeight: 400)
        #expect(isClose(radii.flare, 29))
        #expect(isClose(radii.bottom, 29))
    }

    @Test("Shorter than closed, the corners stay at the closed ones")
    func belowResting() {
        let radii = notch.radii(forHeight: 10)
        #expect(radii.flare == 6)
        #expect(radii.bottom == 12)
    }

    @Test("Open and closed at the same height doesn't divide by zero")
    func sameHeights() {
        let flat = NotchCorners(restingHeight: 32, openHeight: 32, openRadius: 29)
        let radii = flat.radii(forHeight: 32)
        #expect(radii.flare.isFinite && radii.bottom.isFinite)
        #expect(radii.flare == 6)
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
        #expect(PlayerLayout.top.artworkRadius == 11)
        #expect(PlayerLayout.side.artworkRadius == 14)
    }

    @Test("The open corners are concentric with the cover's")
    func cornerRadius() {
        #expect(PlayerLayout.cornerRadius == PlayerLayout.padding + PlayerLayout.top.artworkRadius)
    }

    @Test("Cover on top, around the usual notch")
    func topSize() {
        // Wide enough to keep the cover clear of the camera: 185 + 2 × (18 + 60 + 8) = 357, made even.
        // Tall enough for the padding, cover, timeline and controls: 18 + 60 + 12 + 16 + 8 + 40 + 18.
        #expect(PlayerLayout.top.size(closed: closed) == CGSize(width: 358, height: 172))
    }

    @Test("Cover on the side, around the usual notch")
    func sideSize() {
        // 185 + 2 × (18 + 120 + 8) = 477, made even; the cover sets the height: 18 + 120 + 18.
        #expect(PlayerLayout.side.size(closed: closed) == CGSize(width: 478, height: 156))
    }

    @Test("A narrow camera still leaves room for the controls")
    func narrowCamera() {
        let small = CGSize(width: 100, height: 20)
        // 18 × 2 + 280 = 316 on top; 18 × 2 + 120 + 17 + 280 = 453 on the side, made even.
        #expect(PlayerLayout.top.size(closed: small).width == 316)
        #expect(PlayerLayout.side.size(closed: small).width == 454)
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

    @Test("Accent colors are named as System Settings names them")
    func accentTitles() {
        #expect(
            AccentSource.allCases.map(\.title) == [
                "Artwork", "System", "Blue", "Purple", "Pink", "Red", "Orange", "Yellow", "Green", "Graphite",
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
        let image = try #require(AccentWash.image(for: .systemBlue))
        #expect(image.size == NSSize(width: 64, height: 64))
        #expect(AccentWash.image(for: .systemBlue) === image)
        #expect(AccentWash.image(for: .systemRed) !== image)
    }
}

/// The Settings window's sidebar.
@Suite("Settings pages")
struct SettingsPaneTests {
    @Test("The sidebar's pages, in order")
    func order() {
        #expect(SettingsPane.allCases.map(\.title) == ["General", "Appearance", "Music", "Tray", "Live Activities", "Opening", "Displays"])
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
        #expect(SettingsPane.allCases.filter(\.showsPreview) == [.appearance, .music, .tray, .opening])
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
            ("spotify", .music),
            ("haptic", .opening),
            ("monitor", .displays),
        ])
    func search(word: String, pane: SettingsPane) {
        let found = SettingsPane.allCases.filter { $0.keywords.split(separator: " ").contains { $0.hasPrefix(word) } }
        #expect(found == [pane])
    }
}
