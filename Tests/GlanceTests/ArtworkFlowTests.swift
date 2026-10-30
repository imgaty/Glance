//
//  ArtworkFlowTests.swift
//  GlanceTests
//
//  Created by Gaty on 30/10/2026.
//

import AppKit
import Testing

@testable import Glance

/// The colors behind the player and in the waveform.
@MainActor
@Suite("Artwork flow")
struct ArtworkFlowTests {
    /// Half red, half blue, as a cover with two colors.
    static func cover() -> NSImage {
        NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            NSColor.blue.setFill()
            NSRect(x: 16, y: 16, width: 32, height: 32).fill()
            return true
        }
    }

    static func brightness(of image: CGImage) -> (lowest: Double, colors: Set<UInt32>) {
        let side = image.width
        var pixels = [UInt32](repeating: 0, count: side * image.height)
        pixels.withUnsafeMutableBytes { bytes in
            let context = CGContext(
                data: bytes.baseAddress, width: side, height: image.height, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: side, height: image.height))
        }
        let lowest = pixels.map { pixel in
            max(Double(pixel & 0xFF), Double(pixel >> 8 & 0xFF), Double(pixel >> 16 & 0xFF)) / 255
        }.min() ?? 0
        return (lowest, Set(pixels))
    }

    @Test("One picture has one flow, for the background and the waveform alike")
    func shared() throws {
        let image = Self.cover()
        #expect(try #require(ArtworkFlow.of(image)) === ArtworkFlow.of(image))
    }

    @Test("The first frame is ready at once, a gradient and not a flat color, and the bars read on black")
    func firstFrame() throws {
        let flow = try #require(ArtworkFlow.of(Self.cover()))
        let frame = try #require(flow.frame(at: 100))
        #expect(frame.background.width > frame.bars.width)
        #expect(Self.brightness(of: frame.background).colors.count > 100)
        #expect(Self.brightness(of: frame.bars).lowest >= 0.25)
    }

    @Test("A moment later than the last is drawn away from the main thread, and shows when it's ready")
    func moves() async throws {
        let flow = try #require(ArtworkFlow.of(Self.cover()))
        let first = try #require(flow.frame(at: 100))
        _ = flow.frame(at: 130)
        #expect(flow.frame(at: 130)?.background === first.background)
        for _ in 0..<100 where flow.frame(at: 130)?.background === first.background {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(flow.frame(at: 130)?.background !== first.background)
    }
}
