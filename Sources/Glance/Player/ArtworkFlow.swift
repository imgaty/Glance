//
//  ArtworkFlow.swift
//  Glance
//
//  Created by Gaty on 30/10/2026.
//

import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// The colors that flow behind the player and through the waveform, made as Apple Music makes
/// them, and never just the cover blurred: four copies of the cover, turning, the smaller two
/// circling as well, each twisted around a point off to one side, which draws its shapes out into
/// long ribbons, laid over one another and blurred together. One picture of it is drawn at a time,
/// away from the main thread and only while something asks, and the background and the waveform
/// both show it.
@MainActor
final class ArtworkFlow {
    /// A moment of it: for the background, and, its shadows lifted so it reads on black as the
    /// iPhone's waveform does, for the waveform's bars.
    struct Frame {
        let background: CGImage
        let bars: CGImage
    }

    /// One for each picture, kept only as long as the picture is.
    private static let flows = NSMapTable<NSImage, ArtworkFlow>.weakToStrongObjects()
    private static let queue = DispatchQueue(label: "Glance.ArtworkFlow", qos: .userInitiated)
    private nonisolated static let context = CIContext(options: [
        .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any, .cacheIntermediates: false,
    ])

    /// The colors move slowly and are soft, so they're drawn small and 15 times a second, as
    /// Apple Music's are.
    private static let interval = 1.0 / 15
    private nonisolated static let side: CGFloat = 200
    private nonisolated static let barsSide: CGFloat = 40
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

    static func of(_ image: NSImage) -> ArtworkFlow? {
        if let flow = flows.object(forKey: image) { return flow }
        guard let flow = ArtworkFlow(image) else { return nil }
        flows.setObject(flow, forKey: image)
        return flow
    }

    private let cover: CIImage
    private var latest: Frame?
    private var drawing = false
    private var drawnAt = 0.0

    private init?(_ image: NSImage) {
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let input = CIImage(cgImage: source)
        let side = Self.coverSide
        let scaled = input.transformed(by: CGAffineTransform(scaleX: side / max(input.extent.width, 1), y: side / max(input.extent.height, 1)))
        let bounds = CGRect(x: 0, y: 0, width: side, height: side)
        guard let small = Self.context.createCGImage(scaled, from: bounds) else { return nil }
        cover = CIImage(cgImage: small)
    }

    /// The latest picture there is for `time`, in seconds. The first is drawn on the spot; after
    /// that, a new one is on its way whenever the last is old enough, and it shows when it's ready.
    func frame(at time: Double) -> Frame? {
        guard latest != nil else {
            drawnAt = time
            latest = Self.draw(cover, at: time)
            return latest
        }
        if !drawing, abs(time - drawnAt) >= Self.interval {
            drawing = true
            drawnAt = time
            let cover = cover
            Self.queue.async { [weak self] in
                let frame = Self.draw(cover, at: time)
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

    private nonisolated static func draw(_ cover: CIImage, at time: Double) -> Frame? {
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
        let dimmed = colors.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: -0.15])
        let scale = barsSide / side
        let lifted = colors.applyingFilter(
            "CIColorMatrix",
            parameters: [
                "inputRVector": CIVector(x: 1 - shadowLift, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 1 - shadowLift, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 1 - shadowLift, w: 0),
                "inputBiasVector": CIVector(x: shadowLift, y: shadowLift, z: shadowLift, w: 0),
            ]
        ).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let space = CGColorSpace(name: CGColorSpace.sRGB)
        guard let background = context.createCGImage(dimmed, from: canvas, format: .RGBA8, colorSpace: space),
            let bars = context.createCGImage(
                lifted, from: CGRect(x: 0, y: 0, width: barsSide, height: barsSide), format: .RGBA8, colorSpace: space)
        else { return nil }
        return Frame(background: background, bars: bars)
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
        (source == .artwork ? artwork : source.nsColor.flatMap(AccentWash.image(for:))).flatMap(ArtworkFlow.of)
    }
}
