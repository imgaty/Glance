//
//  ArtworkFlow.swift
//  Glance
//
//  Created by Gaty on 30/10/2026.
//

import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// The colors that flow behind the player, made as Apple Music makes them, and never just the cover
/// blurred: four copies of the cover, turning, the smaller two circling as well, each twisted around
/// a point off to one side, which draws its shapes out into long ribbons, laid over one another and
/// blurred together. The cover's palette (see `ArtworkPalette`) runs through them, and is what the
/// waveform shows, so the two agree with each other and with the progress bar. One picture of it is
/// drawn at a time, away from the main thread and only while something asks: nothing does while the
/// notch is closed, the waveform turning one still picture of the palette instead.
@MainActor
final class ArtworkFlow {
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
    private nonisolated static let side: CGFloat = 200
    /// The cover, small: the copies are blurred away, so nothing of its detail would show.
    private static let coverSide: CGFloat = 128

    /// How much of what's under them the three smaller copies leave showing, as a share of each.
    private nonisolated static let opacity: CGFloat = 0.75
    /// How far off a copy's middle it's twisted, and how far the twist reaches, as shares of the
    /// copy; and how far the middle of the twist is turned, in radians.
    private nonisolated static let twistOffset = 0.45
    private nonisolated static let twistReach: CGFloat = 1.2
    private nonisolated static let twistAngle: Float = 7
    /// The blur over them all, as a share of the picture.
    private nonisolated static let blur = 0.055
    /// How far the bars' darkest color is from black, as the iPhone's is.
    private nonisolated static let shadowLift: CGFloat = 0.3
    /// How much of the palette's picture the waveform shows across, its middle, so soft shades of it
    /// pass through the bars rather than patches.
    static let barsZoom: CGFloat = 0.6
    /// A turn of it there, in seconds.
    static let barsTurn = 20.0
    /// How strongly the palette shows through the colors, as light: all the way in the dark, none
    /// in white, so a dark cover takes on its colors and a white one stays white.
    private nonisolated static let paletteTint: CGFloat = 0.4

    static func of(_ image: NSImage) -> ArtworkFlow? {
        if let flow = flows.object(forKey: image) { return flow }
        guard let flow = ArtworkFlow(image) else { return nil }
        flows.setObject(flow, forKey: image)
        return flow
    }

    /// The cover is light overall: what's drawn over its colors has to be lighter too.
    let isLight: Bool
    /// The palette, its shadows lifted so it reads on black, as the iPhone's waveform does.
    let bars: CGImage
    private let cover: CIImage
    /// The palette's picture, which turns slowly.
    private let wash: CIImage
    private var latest: CGImage?
    private var drawing = false
    private var drawnAt = 0.0

    private init?(_ image: NSImage) {
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let input = CIImage(cgImage: source)
        let side = Self.coverSide
        let scaled = input.transformed(by: CGAffineTransform(scaleX: side / max(input.extent.width, 1), y: side / max(input.extent.height, 1)))
        let bounds = CGRect(x: 0, y: 0, width: side, height: side)
        guard let small = Self.context.createCGImage(scaled, from: bounds),
            let wash = AccentWash.image(for: ArtworkPalette.colors(of: image))?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }
        cover = CIImage(cgImage: small)
        self.wash = CIImage(cgImage: wash)
        let lift = Self.shadowLift
        let lifted = self.wash.applyingFilter(
            "CIColorMatrix",
            parameters: [
                "inputRVector": CIVector(x: 1 - lift, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 1 - lift, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 1 - lift, w: 0), "inputBiasVector": CIVector(x: lift, y: lift, z: lift, w: 0),
            ])
        guard let bars = Self.context.createCGImage(lifted, from: self.wash.extent) else { return nil }
        self.bars = bars
        isLight = Self.brightness(of: cover) > 0.55
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

    /// The latest picture there is for `time`, in seconds. The first is drawn on the spot; after
    /// that, a new one is on its way whenever the last is old enough, and it shows when it's ready.
    func frame(at time: Double) -> CGImage? {
        guard latest != nil else {
            drawnAt = time
            latest = Self.draw(cover, wash, at: time)
            return latest
        }
        if !drawing, abs(time - drawnAt) >= Self.interval {
            drawing = true
            drawnAt = time
            let cover = cover, wash = wash
            Self.queue.async { [weak self] in
                let frame = Self.draw(cover, wash, at: time)
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        self?.drawing = false
                        if let frame { self?.latest = frame }
                    }
                }
            }
        }
        return latest
    }

    private nonisolated static func draw(_ cover: CIImage, _ wash: CIImage, at time: Double) -> CGImage? {
        let side = Self.side
        let canvas = CGRect(x: 0, y: 0, width: side, height: side)
        var layers = CIImage(color: .black).cropped(to: canvas)
        for (index, copy) in copies(at: time).enumerated() {
            layers = layer(of: cover, copy, opaque: index == 0).composited(over: layers)
        }
        let colors = layers.cropped(to: canvas).clampedToExtent()
            .applyingGaussianBlur(sigma: Self.blur * side)
            .cropped(to: canvas)
            .applyingFilter(
                "CIColorControls", parameters: [kCIInputSaturationKey: 1.05, kCIInputContrastKey: 1.05])
        // The palette, as light through the colors, turning the other way.
        let tint = spun(wash, turn: -time / 30, across: side * 1.5, into: canvas)
            .applyingFilter(
                "CIColorMatrix",
                parameters: [
                    "inputRVector": CIVector(x: paletteTint, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: paletteTint, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: paletteTint, w: 0),
                ])
        let dimmed = tint.applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: colors])
            .applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: -0.15])
        return context.createCGImage(dimmed, from: canvas, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
    }

    /// The picture turned a share of the way around its middle, this wide, in the middle of a place.
    private nonisolated static func spun(_ image: CIImage, turn: Double, across: CGFloat, into place: CGRect) -> CIImage {
        let side = image.extent.width, scale = across / side
        return image.clampedToExtent()
            .transformed(
                by: CGAffineTransform(translationX: -side / 2, y: -side / 2)
                    .concatenating(CGAffineTransform(scaleX: scale, y: scale))
                    .concatenating(CGAffineTransform(rotationAngle: turn * 2 * .pi))
                    .concatenating(CGAffineTransform(translationX: place.midX, y: place.midY))
            )
            .cropped(to: place)
    }

    /// One copy of the cover, where it is at a moment, in shares of the picture.
    private struct Copy {
        let size: CGFloat
        /// In turns.
        let turn: Double
        let middle: CGVector
        let twistAt: CGVector
        let clockwise: Bool
    }

    /// As large as the picture and more; most of it; and half and a quarter of it, circling. A turn
    /// takes the best part of a minute, so the colors drift calmly.
    private nonisolated static func copies(at t: Double) -> [Copy] {
        func circling(_ turns: Double, _ radius: Double) -> CGVector {
            CGVector(dx: cos(turns * 2 * .pi) * radius, dy: sin(turns * 2 * .pi) * radius)
        }
        func copy(_ size: Double, turn: Double, middle: CGVector, twist: Double, index: Int, clockwise: Bool) -> Copy {
            let around = circling(twist + Double(index) * 0.37, size * twistOffset)
            return Copy(
                size: size, turn: turn, middle: middle,
                twistAt: CGVector(dx: middle.dx + around.dx, dy: middle.dy + around.dy), clockwise: clockwise)
        }
        return [
            copy(1.25, turn: t / 48, middle: .zero, twist: t / 37, index: 0, clockwise: false),
            copy(0.8, turn: -t / 24, middle: CGVector(dx: -0.1, dy: -0.1), twist: -t / 48, index: 1, clockwise: true),
            copy(0.5, turn: t / 48, middle: circling(t / 64, 0.25), twist: t / 59, index: 2, clockwise: false),
            copy(0.25, turn: -t / 36, middle: circling(-t / 40 + 0.4, 0.125), twist: -t / 70, index: 3, clockwise: true),
        ]
    }

    /// The largest is `opaque`, and its edges run on, so there's color everywhere.
    private nonisolated static func layer(of cover: CIImage, _ copy: Copy, opaque: Bool) -> CIImage {
        let side = Self.side, width = cover.extent.width
        let scale = copy.size * side / width
        let placed = (opaque ? cover.clampedToExtent() : cover).transformed(
            by: CGAffineTransform(translationX: -width / 2, y: -width / 2)
                .concatenating(CGAffineTransform(scaleX: scale, y: scale))
                .concatenating(CGAffineTransform(rotationAngle: copy.turn * 2 * .pi))
                .concatenating(CGAffineTransform(translationX: side * (0.5 + copy.middle.dx), y: side * (0.5 + copy.middle.dy))))
        let twist = CIFilter.twirlDistortion()
        twist.inputImage = placed
        twist.center = CGPoint(x: side * (0.5 + copy.twistAt.dx), y: side * (0.5 + copy.twistAt.dy))
        twist.radius = Float(twistReach * copy.size * side)
        twist.angle = copy.clockwise ? -twistAngle : twistAngle
        guard let twisted = twist.outputImage else { return placed }
        if opaque { return twisted }
        let faded = CIFilter.colorMatrix()
        faded.inputImage = twisted
        faded.aVector = CIVector(x: 0, y: 0, z: 0, w: opacity)
        return faded.outputImage ?? twisted
    }
}

extension NowPlaying {
    /// The cover's colors, or a chosen color's own shades; none with neither.
    func flow(from source: AccentSource) -> ArtworkFlow? {
        (source == .artwork ? artwork : source.nsColor.flatMap { AccentWash.image(for: [$0]) }).flatMap(ArtworkFlow.of)
    }
}
