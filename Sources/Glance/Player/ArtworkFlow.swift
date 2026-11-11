//
//  ArtworkFlow.swift
//  Glance
//
//  Created by Gaty on 30/10/2026.
//

import Accelerate
import AppKit
import Combine
import CoreImage
import CoreImage.CIFilterBuiltins

/// The background's three artwork planes and subdivided warp are rendered on the artwork queue.
/// The waveform keeps its own cover treatment; it never takes its colors from the background.
@MainActor
final class ArtworkFlow: ObservableObject {
    /// A paused picture still receives the first completed artwork frame. Later frames are
    /// requested by its own timeline, without publishing at the renderer's cadence.
    let objectWillChange = ObservableObjectPublisher()

    /// One for each picture, kept only as long as the picture is.
    private static let flows = NSMapTable<NSImage, ArtworkFlow>.weakToStrongObjects()
    private static let queue = DispatchQueue(label: "Glance.ArtworkFlow", qos: .userInitiated)
    private nonisolated static let context = CIContext(options: [
        .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any, .cacheIntermediates: false,
    ])

    /// The colors move slowly and are soft, so they're drawn small, each picture as soon as the last
    /// is old enough: a little sooner than the 30 times a second the background asks, so none of
    /// its asks is missed. At half that, they'd be seen to step.
    private static let interval = 1.0 / 40
    /// The cover, small: the copies are blurred away, so nothing of its detail would show.
    private static let coverSide: CGFloat = 128

    /// The waveform's colors, as Apple's own waveform takes them from the artwork (`MediaCoreUI`'s
    /// `WaveformTheme.artwork`, read from its layers on macOS 27.3): the cover stretched across the
    /// bars, more saturated and washed with white the darker it is, dimmed with black the brighter it
    /// is, then blurred by 6 points of a waveform about this wide, nothing outside the cover counting.
    /// Rebuilt here, the bars came within 2 levels of 255 of Apple's on covers dark, light and between.
    private nonisolated static let barsWidth: CGFloat = 21
    private nonisolated static let barsBlur: CGFloat = 6
    /// The picture's side, in pixels: three to a point.
    private nonisolated static let barsSide: CGFloat = 63
    /// How bright a cover is at the most before its bars are left as they are; at black, how much more
    /// saturated they're made and how much white is laid over them.
    nonisolated static let barsBright = 0.6
    nonisolated static let barsSaturation = (least: 1.25, most: 3.65)
    nonisolated static let barsWhite = 0.6
    /// How bright a cover is before its bars are dimmed, and the most black laid over them, at white.
    nonisolated static let barsDim = (from: 0.7, most: 0.3)
    private nonisolated static let barsContext = CIContext(options: [
        .workingColorSpace: CGColorSpace(name: CGColorSpace.displayP3) as Any, .cacheIntermediates: false,
    ])
    static func of(_ image: NSImage) -> ArtworkFlow? {
        if let flow = flows.object(forKey: image) { return flow }
        guard let flow = ArtworkFlow(image) else { return nil }
        flows.setObject(flow, forKey: image)
        return flow
    }

    /// The cover is light overall: what's drawn over its colors has to be lighter too.
    let isLight: Bool
    /// The cover itself, blurred, which the waveform shows through its bars laid across the whole of
    /// it, as Apple's own waveform does (see `bars(of:)`): a red cover's sides red, a blue middle blue.
    let bars: CGImage
    private let cover: CGImage
    private final class Frame {
        var renderer: ArtworkBackdrop?
        var latest: CGImage?
        var drawing = false
        var drawnAt = 0.0
    }
    private var frames: [Int: Frame] = [:]
    private let variant = Int.random(in: 0..<5)
    private var clock = ArtworkFlowClock()

    private init?(_ image: NSImage) {
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let input = CIImage(cgImage: source)
        let side = Self.coverSide
        let scaled = input.transformed(by: CGAffineTransform(scaleX: side / max(input.extent.width, 1), y: side / max(input.extent.height, 1)))
        let bounds = CGRect(x: 0, y: 0, width: side, height: side)
        guard let small = Self.context.createCGImage(scaled, from: bounds) else { return nil }
        cover = small
        guard let bars = Self.bars(of: source) else { return nil }
        self.bars = bars
        isLight = Self.brightness(of: CIImage(cgImage: cover)) > 0.55
    }

    /// How dark a cover is, for its bars: 0 from `barsBright` up, 1 at black.
    nonisolated static func barsDarkness(_ brightness: Double) -> Double { min(max(1 - brightness / barsBright, 0), 1) }

    /// How bright a cover looks, as Apple's waveform reckons it: each pixel's sqrt(0.299 r² + 0.587 g²
    /// + 0.114 b²), averaged, every pixel counted as it is rather than shrunk first.
    nonisolated static func barsBrightness(of image: CGImage) -> Double {
        // Keep the source grid: shrinking first can skip one color of fine alternating detail.
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard
                let context = CGContext(
                    data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            else { return false }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return 1 }
        // Batch the arithmetic in small vectors. The scratch space stays the same size however
        // large the cover is.
        let chunk = 16_384
        var red = [Float](repeating: 0, count: chunk)
        var green = red, blue = red
        var redWeight: Float = 0.299 / (255 * 255)
        var greenWeight: Float = 0.587 / (255 * 255)
        var blueWeight: Float = 0.114 / (255 * 255)
        let total = pixels.withUnsafeBufferPointer { source in
            red.withUnsafeMutableBufferPointer { r in
                green.withUnsafeMutableBufferPointer { g in
                    blue.withUnsafeMutableBufferPointer { b in
                        var total = 0.0
                        for offset in stride(from: 0, to: width * height, by: chunk) {
                            let count = min(chunk, width * height - offset)
                            let n = vDSP_Length(count)
                            let pixel = source.baseAddress! + offset * 4
                            vDSP_vfltu8(pixel, 4, r.baseAddress!, 1, n)
                            vDSP_vfltu8(pixel + 1, 4, g.baseAddress!, 1, n)
                            vDSP_vfltu8(pixel + 2, 4, b.baseAddress!, 1, n)
                            vDSP_vsq(r.baseAddress!, 1, r.baseAddress!, 1, n)
                            vDSP_vsq(g.baseAddress!, 1, g.baseAddress!, 1, n)
                            vDSP_vsq(b.baseAddress!, 1, b.baseAddress!, 1, n)
                            vDSP_vsmul(r.baseAddress!, 1, &redWeight, r.baseAddress!, 1, n)
                            vDSP_vsma(g.baseAddress!, 1, &greenWeight, r.baseAddress!, 1, r.baseAddress!, 1, n)
                            vDSP_vsma(b.baseAddress!, 1, &blueWeight, r.baseAddress!, 1, r.baseAddress!, 1, n)
                            var length = Int32(count)
                            vvsqrtf(r.baseAddress!, r.baseAddress!, &length)
                            var sum: Float = 0
                            vDSP_sve(r.baseAddress!, 1, &sum, n)
                            total += Double(sum)
                        }
                        return total
                    }
                }
            }
        }
        return total / Double(width * height)
    }

    /// The bars' picture, as Apple's waveform makes it from the cover.
    nonisolated static func bars(of source: CGImage) -> CGImage? {
        let brightness = barsBrightness(of: source)
        let darkness = barsDarkness(brightness)
        let dim = min(max(brightness - barsDim.from, 0), barsDim.most)
        let saturation = barsSaturation.least + (barsSaturation.most - barsSaturation.least) * darkness
        let side = barsSide
        let bounds = CGRect(x: 0, y: 0, width: side, height: side)
        var image = CIImage(cgImage: source)
        image = image.applyingFilter(
            "CILanczosScaleTransform",
            parameters: [kCIInputScaleKey: side / image.extent.height, kCIInputAspectRatioKey: image.extent.height / max(image.extent.width, 1)]
        )
        .cropped(to: bounds)
        // More saturated about each pixel's own luminance, kept within the screen's colors.
        let s = CGFloat(saturation)
        let weights: [CGFloat] = [0.2126, 0.7152, 0.0722]
        func row(_ channel: Int) -> CIVector {
            let r = (0..<3).map { (1 - s) * weights[$0] + ($0 == channel ? s : 0) }
            return CIVector(x: r[0], y: r[1], z: r[2], w: 0)
        }
        image = image.applyingFilter("CIColorMatrix", parameters: ["inputRVector": row(0), "inputGVector": row(1), "inputBVector": row(2)])
            .applyingFilter("CIColorClamp")
        // Black over a bright cover, white over a dark one; neither between.
        let black = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: CGFloat(dim))).cropped(to: bounds)
        let white = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: CGFloat(barsWhite * darkness))).cropped(to: bounds)
        image = white.composited(over: black.composited(over: image)).applyingFilter("CIColorClamp")
        // Blurred with nothing outside counting: what of the blur falls inside is made whole again.
        image = image.applyingGaussianBlur(sigma: barsBlur / barsWidth * side).cropped(to: bounds)
            .applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1)])
        return barsContext.createCGImage(image, from: bounds, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.displayP3))
    }

    /// How bright a picture looks overall, 0 to 1.
    private static func brightness(of image: CIImage) -> Double {
        var pixel = [UInt8](repeating: 0, count: 4)
        let average = image.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: image.extent)])
        context.render(
            average, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return (0.2126 * Double(pixel[0]) + 0.7152 * Double(pixel[1]) + 0.0722 * Double(pixel[2])) / 255
    }

    /// A soft cover is ready immediately. Shader compilation, textures and every rendered frame,
    /// including the first, are prepared on the artwork queue.
    func frame(at time: Double, aspect: Double = 1) -> CGImage? {
        let key = Int((min(max(aspect, 0.25), 8) * 20).rounded())
        let frame: Frame
        if let cached = frames[key] {
            frame = cached
        } else {
            frame = Frame()
            if frames.count >= 6, let old = frames.keys.first { frames.removeValue(forKey: old) }
            frames[key] = frame
        }
        let elapsed = clock.read(at: time)
        guard !frame.drawing, frame.latest == nil || abs(time - frame.drawnAt) >= Self.interval else { return frame.latest ?? bars }
        frame.drawing = true
        frame.drawnAt = time
        let cover = cover, previous = frame.renderer, variant = variant
        Self.queue.async {
            let renderer = previous ?? ArtworkBackdrop(cover, variant: variant, aspect: Double(key) / 20)
            let image = renderer?.frame(at: elapsed)
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    frame.renderer = renderer
                    frame.drawing = false
                    if let image {
                        if frame.latest == nil { self?.objectWillChange.send() }
                        frame.latest = image
                    }
                }
            }
        }
        return frame.latest ?? bars
    }
}

/// Time advances only while a view is asking for frames. A return from a hidden or paused view
/// resumes the previous phase, without feeding a large wall-clock value into Metal's floats.
struct ArtworkFlowClock {
    private var previous: Double?
    private(set) var elapsed = 0.0

    mutating func read(at time: Double) -> Double {
        if let previous {
            let step = time - previous
            if step > 0, step < 0.25 { elapsed += step }
        }
        previous = time
        return elapsed
    }
}

extension NowPlaying {
    /// The cover's colors, or a chosen color's own shades; none with neither.
    func flow(from source: AccentSource) -> ArtworkFlow? {
        (source == .artwork ? artwork : source.nsColor.flatMap { AccentWash.image(for: [$0]) }).flatMap(ArtworkFlow.of)
    }
}
