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
        let lowest =
            pixels.map { pixel in
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
        #expect(frame.width > flow.bars.width)
        #expect(Self.brightness(of: frame).colors.count > 100)
        #expect(Self.brightness(of: flow.bars).lowest >= 0.25)
    }

    static func solid(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> CGImage {
        let context = CGContext(
            data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 128, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        return context.makeImage()!
    }

    @Test("A cover's brightness is Apple's: each pixel's, averaged, so red reads brighter than blue")
    func brightness() {
        #expect(abs(ArtworkFlow.barsBrightness(of: Self.solid(0.5, 0.5, 0.5)) - 0.5) < 0.01)
        #expect(abs(ArtworkFlow.barsBrightness(of: Self.solid(1, 0, 0)) - 0.299.squareRoot()) < 0.01)
        #expect(abs(ArtworkFlow.barsBrightness(of: Self.solid(0, 0, 1)) - 0.114.squareRoot()) < 0.01)
        #expect(ArtworkFlow.barsDarkness(0.6) == 0 && ArtworkFlow.barsDarkness(0.9) == 0)
        #expect(ArtworkFlow.barsDarkness(0) == 1 && abs(ArtworkFlow.barsDarkness(0.3) - 0.5) < 0.001)
    }

    @Test("Fine detail in a large cover counts toward brightness, whichever pixels come first")
    func largeCoverBrightness() async throws {
        try await Task.detached {
            let side = 2048
            for phase in 0...1 {
                var pixels = [UInt8](repeating: 255, count: side * side * 4)
                for y in 0..<side {
                    for x in 0..<side {
                        let value: UInt8 = (x + y + phase).isMultiple(of: 2) ? 0 : 255
                        let offset = (y * side + x) * 4
                        pixels[offset] = value
                        pixels[offset + 1] = value
                        pixels[offset + 2] = value
                    }
                }
                let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
                let image = try #require(
                    CGImage(
                        width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
                #expect(abs(ArtworkFlow.barsBrightness(of: image) - 0.5) < 0.001)
            }
        }.value
    }

    @Test("A dark cover's bars are washed with white, so they read on black")
    func darkCoverBars() throws {
        let dark = NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
            NSColor(srgbRed: 0.1, green: 0.05, blue: 0.16, alpha: 1).setFill()
            rect.fill()
            return true
        }
        let flow = try #require(ArtworkFlow.of(dark))
        let levels = Self.channels(of: flow.bars).map { max($0.r, $0.g, $0.b) }
        #expect(levels.reduce(0, +) / Double(levels.count) >= 0.4)
    }

    @Test("The made-up song's bars come a reading at a time, as often as music's, the bass rising on each beat and falling away")
    func demoBarsEase() {
        let rate = WaveformGlyph.demoRate
        #expect(abs(rate - 48_000.0 / 4096) < 0.001)
        // One reading holds until the next is due.
        #expect(WaveformGlyph.demoLevels(at: 1000.001) == WaveformGlyph.demoLevels(at: 1000.02))
        var bass: [Float] = []
        for i in 1...Int(rate * 4) {
            let levels = WaveformGlyph.demoLevels(at: 1000 + Double(i) / rate)
            #expect(levels.count == AudioLevels.bands)
            bass.append(levels[0])
        }
        #expect((bass.max() ?? 0) > 0.6)
        #expect((bass.max() ?? 0) - (bass.min() ?? 1) > 0.3)
        // Every bar moves, none pinned at the top or a dot.
        let spread = (0..<AudioLevels.bands).map { bar in
            (0..<Int(rate * 4)).map { WaveformGlyph.demoLevels(at: 2000 + Double($0) / rate)[bar] }
        }
        for bar in spread { #expect((bar.max() ?? 0) - (bar.min() ?? 0) > 0.1 && (bar.max() ?? 1) <= 1 && (bar.min() ?? 0) > 0) }
    }

    @Test("The made-up song hits hard once every eight beats, and only then do the colors pulse")
    func demoBangs() {
        let rate = WaveformGlyph.demoRate
        let period = 8 / 1.8
        // Sixteen beats from a hard kick: the waveform passes nine tenths only just after one.
        let start = (3000 / period).rounded(.up) * period
        var tall: [Double] = []
        for i in 0..<Int(rate * 2 * period) {
            let t = start + Double(i) / rate
            if (WaveformGlyph.demoLevels(at: t).max() ?? 0) >= AudioLevels.bang { tall.append(t - start) }
        }
        #expect(!tall.isEmpty)
        for since in tall { #expect(since.truncatingRemainder(dividingBy: period) < 0.2, "\(since)") }
        // The pulse peaks just after the hard kick, is mostly gone by the next beat and all but gone
        // by the one after, easing away as music's does (about a third of a second).
        #expect(WaveformGlyph.demoPulse(at: start + 0.07) > 0.6)
        #expect(WaveformGlyph.demoPulse(at: start + 1 / 1.8) < 0.2)
        #expect(WaveformGlyph.demoPulse(at: start + 2 / 1.8) < 0.05)
        #expect(WaveformGlyph.demoPulse(at: start + period - 0.01) < 0.001)
    }

    /// White with a black ball in the middle, the harshest a cover gets.
    static func ball() -> NSImage {
        NSImage(size: NSSize(width: 128, height: 128), flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            NSColor.black.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 38, dy: 38)).fill()
            return true
        }
    }

    static func channels(of image: CGImage) -> [(r: Double, g: Double, b: Double)] {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        pixels.withUnsafeMutableBytes { bytes in
            let context = CGContext(
                data: bytes.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return stride(from: 0, to: pixels.count, by: 4).map { (Double(pixels[$0]) / 255, Double(pixels[$0 + 1]) / 255, Double(pixels[$0 + 2]) / 255) }
    }

    @Test("A hard cover makes a soft waveform: its dark part still shows, and no hard edge across it")
    func softBars() throws {
        let flow = try #require(ArtworkFlow.of(Self.ball()))
        let bars = flow.bars
        let levels = Self.channels(of: bars).map(\.r)
        #expect((levels.min() ?? 0) >= 0.23)
        // The cover itself shows: lighter at the sides than in its dark middle, and dimmed, as Apple's
        // waveform dims a bright cover's bars: its middle bars measured 163 of 255, its outer 186.
        let row = bars.height / 2
        #expect(levels[row * bars.width] > levels[row * bars.width + bars.width / 2] + 0.08)
        #expect((levels.max() ?? 1) < 0.8)
        for y in 0..<bars.height {
            for x in 1..<bars.width {
                #expect(abs(levels[y * bars.width + x] - levels[y * bars.width + x - 1]) < 0.04)
            }
        }
    }

    @Test("Behind the player every color is dimmed evenly, so white stays white and a red stays red")
    func backgroundEven() throws {
        func solid(_ color: NSColor) -> NSImage {
            NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
                color.setFill()
                rect.fill()
                return true
            }
        }
        let white = Self.channels(of: try #require(ArtworkFlow.of(solid(.white))?.frame(at: 100)))
        let red = Self.channels(of: try #require(ArtworkFlow.of(solid(NSColor(srgbRed: 0.8, green: 0.1, blue: 0.15, alpha: 1)))?.frame(at: 100)))
        // Apple Music's white, measured, once the notch's dim is on it.
        #expect((white.map(\.g).min() ?? 0) * 0.62 > 0.5)
        #expect((red.map(\.r).max() ?? 0) > 0.6)
        #expect((red.map(\.g).max() ?? 1) < 0.25)
    }

    @Test("A light cover is told from a dark one, for what's drawn over its colors")
    func light() throws {
        #expect(try #require(ArtworkFlow.of(Self.ball())).isLight)
        #expect(try !#require(ArtworkFlow.of(Self.cover())).isLight)
    }

    @Test("A cover's palette is its own colors, the strongest first, and none for black and white")
    func palette() throws {
        let colors = ArtworkPalette.colors(of: Self.cover())
        #expect(colors.count == 2)
        #expect(colors[0].redComponent > 0.9)
        #expect(colors[1].blueComponent > 0.9)
        #expect(ArtworkPalette.colors(of: Self.ball()).isEmpty)
    }

    @Test("A many-colored cover's color is one it has, not all of them mixed")
    func manyColors() throws {
        let stripes = NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
            let colors: [(NSColor, CGFloat)] = [(.red, 34), (.green, 15), (.blue, 15)]
            var x: CGFloat = 0
            for (color, width) in colors {
                color.setFill()
                NSRect(x: x, y: 0, width: width, height: rect.height).fill()
                x += width
            }
            return true
        }
        let first = try #require(ArtworkPalette.colors(of: stripes).first)
        #expect(first.redComponent > 0.9 && first.greenComponent < 0.2 && first.blueComponent < 0.2)
    }

    @Test("The waveform takes the cover's strongest color, as the progress bar does")
    func barsTakeThePalette() throws {
        let red = NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
            NSColor(srgbRed: 0.85, green: 0.1, blue: 0.15, alpha: 1).setFill()
            rect.fill()
            return true
        }
        let bars = Self.channels(of: try #require(ArtworkFlow.of(red)).bars)
        for pixel in bars { #expect(pixel.r > pixel.g && pixel.r > pixel.b) }
    }

    @Test("A moment later than the last is drawn away from the main thread, and shows when it's ready")
    func moves() async throws {
        let flow = try #require(ArtworkFlow.of(Self.cover()))
        let first = try #require(flow.frame(at: 100))
        _ = flow.frame(at: 130)
        #expect(flow.frame(at: 130) === first)
        for _ in 0..<100 where flow.frame(at: 130) === first {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(flow.frame(at: 130) !== first)
    }
}

/// The bars in the notch on screen, as they move.
@Suite("Live bars")
@MainActor
struct LiveBarsTests {
    @Test("Paused, the bars settle into dots over 0.9 s, and what's still heard doesn't cut it short")
    func settling() throws {
        let bars = LiveBarsView(frame: NSRect(x: 0, y: 0, width: 21, height: 22))
        bars.isPlaying = true
        bars.heard([0.9, 0.7, 0.6, 0.5, 0.4, 0.3])
        bars.isPlaying = false
        let settling = try #require(bars.layer?.sublayers?.first?.mask?.animation(forKey: "path") as? CABasicAnimation)
        #expect(settling.duration == WaveformGlyph.settlingIn)
        // The music still heard for a moment after it pauses.
        bars.heard([0.5, 0.4, 0.3, 0.2, 0.1, 0.1])
        bars.heard([0.1, 0.1, 0, 0, 0, 0])
        let after = try #require(bars.layer?.sublayers?.first?.mask?.animation(forKey: "path") as? CABasicAnimation)
        #expect(after.duration == WaveformGlyph.settlingIn)
        // Playing again, each reading eases in.
        bars.isPlaying = true
        bars.heard([0.8, 0.6, 0.5, 0.4, 0.3, 0.2])
        let reading = try #require(bars.layer?.sublayers?.first?.mask?.animation(forKey: "path") as? CABasicAnimation)
        #expect(reading.duration == WaveformGlyph.readingIn)
    }
}
