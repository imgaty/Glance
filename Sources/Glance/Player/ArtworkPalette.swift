//
//  ArtworkPalette.swift
//  Glance
//
//  Created by Gaty on 30/10/2026.
//

import AppKit

/// The colors a cover is known by, the strongest first, up to three, which the progress bar, the
/// waveform and the colors behind the player all take, so they agree. Each is a color the cover
/// really has: its pixels are sorted by hue, and those of a hue averaged, where mixing them all
/// would make a color of a many-colored cover it doesn't have. None for a cover in black, white and
/// gray.
enum ArtworkPalette {
    private static let side = 24
    private static let hues = 12
    private static let most = 3
    /// How much of a hue it takes, in fully vivid pixels, for a cover to count as having color.
    private static let least = 4.0
    /// Next to the strongest, how much of another it takes to count.
    private static let share = 0.2

    private struct Hue {
        var weight = 0.0
        var red = 0.0
        var green = 0.0
        var blue = 0.0
    }

    static func colors(of image: NSImage) -> [NSColor] {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil), let space = CGColorSpace(name: CGColorSpace.sRGB)
        else { return [] }
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard
            let context = CGContext(
                data: &pixels, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return [] }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))

        var buckets = [Hue](repeating: Hue(), count: hues)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let pixel = NSColor(
                srgbRed: CGFloat(pixels[i]) / 255, green: CGFloat(pixels[i + 1]) / 255, blue: CGFloat(pixels[i + 2]) / 255, alpha: 1)
            let saturation = Double(pixel.saturationComponent), brightness = Double(pixel.brightnessComponent)
            guard saturation > 0.25, brightness > 0.2 else { continue }
            let bucket = Int(pixel.hueComponent * CGFloat(hues)) % hues
            let weight = saturation * saturation * brightness
            buckets[bucket].weight += weight
            buckets[bucket].red += Double(pixel.redComponent) * weight
            buckets[bucket].green += Double(pixel.greenComponent) * weight
            buckets[bucket].blue += Double(pixel.blueComponent) * weight
        }
        let ranked = buckets.indices.sorted { buckets[$0].weight > buckets[$1].weight }
        guard let strongest = ranked.first, buckets[strongest].weight >= least else { return [] }
        var kept: [Int] = []
        for bucket in ranked where kept.count < most && buckets[bucket].weight >= buckets[strongest].weight * share {
            // Hues side by side are one color.
            let apart = kept.allSatisfy {
                let distance = abs($0 - bucket)
                return min(distance, hues - distance) > 1
            }
            if apart { kept.append(bucket) }
        }
        return kept.map { index in
            let hue = buckets[index]
            return NSColor(srgbRed: hue.red / hue.weight, green: hue.green / hue.weight, blue: hue.blue / hue.weight, alpha: 1)
        }
    }
}
