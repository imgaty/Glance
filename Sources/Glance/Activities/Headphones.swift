//
//  Headphones.swift
//  Glance
//
//  Created by Gaty on 16/10/2026.
//

import AVFoundation
import AppKit
import CoreImage

/// AirPods and Beats that Glance shows turning as they connect, as the Dynamic Island shows AirPods:
/// each from its maker's own 3D model, drawn once into a clip among Glance's resources (see
/// Tools/DeviceClips). The raw value is the clip's name.
enum Headphones: String, CaseIterable {
    case airpodsPro = "airpods-pro"
    case airpodsPro2 = "airpods-pro-2"
    case airpodsPro3 = "airpods-pro-3"
    case airpods3 = "airpods-3"
    /// AirPods 4, with or without noise cancellation, and AirPods 5, which Apple models alike.
    case airpods4 = "airpods-4"
    case beatsSoloBuds = "beats-solo-buds"
    /// Beats Studio Buds and Studio Buds +, which Beats shows alike.
    case beatsStudioBudsPlus = "beats-studio-buds-plus"
    case powerbeatsPro2 = "powerbeats-pro-2"
    case powerbeatsFit = "powerbeats-fit"
    case beatsFlex = "beats-flex"
    case beatsSolo4 = "beats-solo-4"
    case beatsStudioPro = "beats-studio-pro"
    case beats360 = "beats-360"
    case beatsPill = "beats-pill"

    /// The model macOS knows a product ID as, or the nearest it's a kind of that has a clip; none
    /// for AirPods 1 and 2, which Apple never modelled, AirPods Max, older Beats and the rest.
    init?(product: Int) {
        guard let found = SystemDevices.lineage(product: product).lazy.compactMap({ Self.clips[$0] }).first else { return nil }
        self = found
    }

    /// Each clip by the type macOS declares for the model.
    private static let clips: [String: Headphones] = [
        "com.apple.airpods-pro": .airpodsPro, "com.apple.airpods-pro-gen2": .airpodsPro2, "com.apple.airpods-pro-2025": .airpodsPro3,
        "com.apple.airpods-gen3": .airpods3, "com.apple.airpods-gen4": .airpods4, "com.apple.airpods-gen5": .airpods4,
        "com.apple.beats-flex": .beatsFlex, "com.apple.beats-studio-buds": .beatsStudioBudsPlus,
        "com.apple.beats-studio-buds-plus": .beatsStudioBudsPlus, "com.apple.beats-studio-pro": .beatsStudioPro,
        "com.apple.beats-pill": .beatsPill, "com.apple.power-beats-pro-gen2": .powerbeatsPro2, "com.apple.beats-solo-4": .beatsSolo4,
        "com.apple.beats-solo-buds": .beatsSoloBuds, "com.apple.beats-fit-pro-2025": .powerbeatsFit, "com.apple.beats-360": .beats360,
    ]

    /// Its clip, among Glance's resources.
    var url: URL? { Bundle.main.url(forResource: rawValue, withExtension: "mov", subdirectory: "Headphones") }
}

/// A device turning, a frame every degree and a half of a full turn, face on first, read once from
/// its clip, so the notch only shows pictures.
struct DeviceTurn {
    /// A full turn, from face on.
    let frames: [CGImage]
    /// The device face on, in the frames' pixels: what the notch lays out.
    let rest: CGRect
    /// The frames' size, in pixels.
    let canvas: CGSize
    /// The furthest the device reaches from the middle it turns about, either side, all the way
    /// round, in pixels.
    let reach: CGFloat

    func frame(at degrees: Double) -> CGImage {
        let step = 360 / Double(frames.count)
        let index = Int((degrees / step).rounded()) % frames.count
        return frames[(index + frames.count) % frames.count]
    }

    @MainActor private static var turns: [Headphones: DeviceTurn] = [:]

    @MainActor static func cached(_ headphones: Headphones) -> DeviceTurn? { turns[headphones] }

    /// Reads the turn, away from the main thread, the first time it's needed: from Glance's own clip
    /// of it, or another.
    @MainActor static func prepare(_ headphones: Headphones, from clip: URL? = nil) async -> DeviceTurn? {
        if let turn = turns[headphones] { return turn }
        guard let url = clip ?? headphones.url else { return nil }
        let turn = await Task.detached(priority: .userInitiated) { await load(url) }.value
        turns[headphones] = turn
        return turn
    }

    /// Every frame of a clip, and where the device stands in the first.
    static func load(_ url: URL) async -> DeviceTurn? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first, let reader = try? AVAssetReader(asset: asset) else {
            return nil
        }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output)
        guard reader.startReading() else { return nil }
        let context = CIContext()
        var frames: [CGImage] = []
        while let sample = output.copyNextSampleBuffer() {
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            let image = CIImage(cvPixelBuffer: buffer)
            if let frame = context.createCGImage(image, from: image.extent) { frames.append(frame) }
        }
        guard let first = frames.first, let rest = opaque(first) else { return nil }
        let middle = CGFloat(first.width) / 2
        let reach = frames.compactMap(opaque).map { max($0.maxX - middle, middle - $0.minX) }.max() ?? rest.width / 2
        return DeviceTurn(frames: frames, rest: rest, canvas: CGSize(width: first.width, height: first.height), reach: reach)
    }

    /// Where a picture isn't clear, in its pixels, from the top left.
    static func opaque(_ image: CGImage) -> CGRect? {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard
            let context = CGContext(
                data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var (minX, minY, maxX, maxY) = (width, height, -1, -1)
        for y in 0..<height {
            for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 8 {
                (minX, minY, maxX, maxY) = (min(minX, x), min(minY, y), max(maxX, x), max(maxY, y))
            }
        }
        guard maxX >= minX else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}
