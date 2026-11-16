//
//  GlanceMarkTests.swift
//  GlanceTests
//
//  Created by Gaty on 16/11/2026.
//

import AppKit
import Testing

@testable import Glance

/// The logo drawn in the app is the app icon's mark, and stays drawable at the menu bar's size.
@Suite("Glance mark")
struct GlanceMarkTests {
    private static let assets = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Resources/AppIcon.icon/Assets")

    @Test("The app icon's frame and panel are the mark at the icon's measures", arguments: ["screen", "panel"])
    @MainActor
    func iconLayersMatch(layer: String) throws {
        // The panel's fade aside: only the shapes are compared.
        let svg = try String(contentsOf: Self.assets.appendingPathComponent("\(layer).svg"), encoding: .utf8)
            .replacingOccurrences(of: "url(#p)", with: "#fff")
        let icon = try #require(NSImage(data: Data(svg.utf8)))
        let drawn = Self.coverage { context in
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            icon.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024))
            NSGraphicsContext.current = nil
        }
        let mark = GlanceMark.icon
        let built = Self.coverage { context in
            context.translateBy(x: 0, y: 1024)
            context.scaleBy(x: 1, y: -1)
            context.translateBy(x: (1024 - GlanceMark.width) / 2, y: (1024 - GlanceMark.height) / 2)
            context.addPath(layer == "screen" ? mark.framePath : mark.panelPath)
            context.fillPath(using: layer == "screen" ? .evenOdd : .winding)
        }
        let differing = zip(drawn, built).filter { ($0 > 127) != ($1 > 127) }.count
        #expect(drawn.filter { $0 > 127 }.count > 10_000)
        #expect(differing <= 20)
    }

    @Test("The icon's panel fades as the logo's does")
    func iconFade() throws {
        let svg = try String(contentsOf: Self.assets.appendingPathComponent("panel.svg"), encoding: .utf8)
        #expect(svg.contains("stop-opacity=\"\(GlanceMark.fade.top)\""))
        #expect(svg.contains("stop-opacity=\"\(GlanceMark.fade.bottom)\""))
    }

    @Test("Frame and gap keep their widths all round, in the icon and the menu bar")
    func evenLines() {
        for mark in [GlanceMark.icon, .lines(height: 16, frame: 1.5, gap: 1)] {
            let frame = mark.framePath.boundingBoxOfPath
            #expect(isClose(frame.minX, 0, tolerance: 0.01) && isClose(frame.maxX, GlanceMark.width, tolerance: 0.01))
            #expect(isClose(frame.minY, 0, tolerance: 0.01) && isClose(frame.maxY, GlanceMark.height, tolerance: 0.01))
            let panel = mark.panelPath.boundingBoxOfPath
            let inset = mark.frame + mark.gap
            #expect(isClose(panel.minX, inset, tolerance: 0.01) && isClose(panel.minY, inset, tolerance: 0.01))
            #expect(isClose(panel.maxX, GlanceMark.width - inset, tolerance: 0.01))
            #expect(isClose(panel.maxY, GlanceMark.height - inset, tolerance: 0.01))
        }
        let menuBar = GlanceMark.lines(height: 16, frame: 1.5, gap: 1)
        #expect(isClose(menuBar.frame * 16 / GlanceMark.height, 1.5) && isClose(menuBar.gap * 16 / GlanceMark.height, 1))
    }

    @Test("The mark is drawn 9% wider than tall, so it reads as square")
    func optically() {
        #expect(isClose(GlanceMark.width / GlanceMark.height, 1.09))
    }

    @Test("The menu bar's logo is 16 points tall, as wide as the mark, and a template")
    @MainActor
    func menuBarImage() {
        let size = GlanceLogo.menuBar.size
        #expect(isClose(size.height, 16, tolerance: 0.001) && isClose(size.width, 17.44, tolerance: 0.001))
        #expect(GlanceLogo.menuBar.isTemplate)
    }

    /// Each pixel's alpha, 0 to 255, of what `draw` fills on a 1,024 square.
    private static func coverage(_ draw: (CGContext) -> Void) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: 1024 * 1024 * 4)
        pixels.withUnsafeMutableBytes { buffer in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 1024 * 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return }
            draw(context)
        }
        return stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }
    }
}
