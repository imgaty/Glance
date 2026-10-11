//
//  DemoSong.swift
//  Glance
//
//  Created by Gaty on 10/10/2026.
//

import AppKit

/// The made-up song for the welcome tour's pictures, for when the tour's song can't be fetched: its
/// own drawn cover and words written for it.
struct DemoSong {
    let title = "Lights Over Water"
    let artist = "The Meridians"
    let album = "Tidal"
    let duration: Double = 200

    /// The stretch that plays, again and again: two seconds before the first line to just after
    /// the last.
    let loop: ClosedRange<Double> = 8...45

    private let lines = [
        "Streetlights fold into the river", "Every color starts to shiver", "We drive until the night runs thin",
        "And let the morning in", "Oh, lights over water", "Carry us farther", "Hold on, the city's glowing",
        "Wherever we're going",
    ]

    /// A line every four and a half seconds, from ten seconds in.
    var lyrics: TimedLyrics {
        let lrc = lines.enumerated().map { index, line in
            let time = 10 + 4.5 * Double(index)
            return String(format: "[%02d:%05.2f]%@", Int(time) / 60, time.truncatingRemainder(dividingBy: 60), line)
        }
        return TimedLyrics(lrc: lrc.joined(separator: "\n"), duration: duration)!
    }

    /// Drawn once, the first time it's asked for.
    @MainActor var artwork: NSImage {
        if let drawn = Self.cover { return drawn }
        let drawn = CoverPainter.drawSunset()
        Self.cover = drawn
        return drawn
    }

    @MainActor private static var cover: NSImage?
}

/// Draws the made-up song's cover, a sunset over water, at 600 by 600.
private struct CoverPainter {
    let context: CGContext
    static let side: CGFloat = 600

    @MainActor static func drawSunset() -> NSImage {
        let side = Int(Self.side)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return NSImage() }
        // Top left at the origin, as the scene is laid out.
        context.translateBy(x: 0, y: Self.side)
        context.scaleBy(x: 1, y: -1)
        CoverPainter(context: context).paintSunset()
        guard let image = context.makeImage() else { return NSImage() }
        return NSImage(cgImage: image, size: NSSize(width: side, height: side))
    }

    private func paintSunset() {
        let s = Self.side
        let horizon = s * 0.58
        gradient([rgb(0.10, 0.10, 0.32), rgb(0.55, 0.18, 0.48), rgb(0.98, 0.45, 0.30)], in: CGRect(x: 0, y: 0, width: s, height: horizon))
        clipped(to: CGRect(x: 0, y: 0, width: s, height: horizon)) {
            circle(CGPoint(x: s / 2, y: horizon - 30), radius: 120, colors: [rgb(1, 0.86, 0.45), rgb(1, 0.55, 0.30)])
        }
        gradient([rgb(0.30, 0.12, 0.36), rgb(0.06, 0.06, 0.20)], in: CGRect(x: 0, y: horizon, width: s, height: s - horizon))
        // The sun on the water, in streaks narrowing toward the horizon.
        for row in 0..<9 {
            let depth = CGFloat(row) / 8
            let width = 220 * (1 - depth * 0.7)
            let y = s - 30 - depth * (s - horizon - 40)
            ellipse(CGRect(x: s / 2 - width / 2, y: y, width: width, height: 9 - depth * 5), rgb(1, 0.70, 0.40, 0.75 - depth * 0.35))
        }
    }

    // MARK: Drawing

    private func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    /// Top to bottom.
    private func gradient(_ colors: [NSColor], in rect: CGRect) {
        guard let gradient = CGGradient(colorsSpace: nil, colors: colors.map(\.cgColor) as CFArray, locations: nil) else { return }
        clipped(to: rect) {
            context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: rect.minY), end: CGPoint(x: 0, y: rect.maxY), options: [])
        }
    }

    /// From the middle out.
    private func circle(_ center: CGPoint, radius: CGFloat, colors: [NSColor]) {
        guard let gradient = CGGradient(colorsSpace: nil, colors: colors.map(\.cgColor) as CFArray, locations: nil) else { return }
        context.saveGState()
        context.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        context.clip()
        context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
        context.restoreGState()
    }

    private func ellipse(_ rect: CGRect, _ color: NSColor) {
        context.setFillColor(color.cgColor)
        context.fillEllipse(in: rect)
    }

    private func clipped(to rect: CGRect, _ draw: () -> Void) {
        context.saveGState()
        context.clip(to: rect)
        draw()
        context.restoreGState()
    }
}
