//
//  Headphones.swift
//  Glance
//
//  Created by Gaty on 16/10/2026.
//

import AVFoundation
import AppKit
import CoreImage
import UniformTypeIdentifiers

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

    /// By the model's product ID, or the model macOS names for it, a newer one as the newest of its
    /// kind; none for AirPods 1 and 2, which Apple never modelled, AirPods Max, older Beats and the
    /// rest.
    init?(product: Int) {
        switch product {
        case 0x200E: self = .airpodsPro
        case 0x2014, 0x2024: self = .airpodsPro2
        case 0x2027: self = .airpodsPro3
        case 0x2013: self = .airpods3
        case 0x2019, 0x201B, 0x201C, 0x201E, 0x2020, 0x2030, 0x2036: self = .airpods4
        case 0x2010: self = .beatsFlex
        case 0x2011, 0x2016: self = .beatsStudioBudsPlus
        case 0x2017: self = .beatsStudioPro
        case 0x201A: self = .beatsPill
        case 0x201D: self = .powerbeatsPro2
        case 0x2025: self = .beatsSolo4
        case 0x2026: self = .beatsSoloBuds
        case 0x202F: self = .powerbeatsFit
        case 0x2038: self = .beats360
        default:
            let tag = UTTagClass(rawValue: "com.apple.device-model-code")
            guard let model = UTType(tag: "Device1,\(product)", tagClass: tag, conformingTo: nil)?.identifier,
                let found = Self.newest(named: model)
            else { return nil }
            self = found
        }
    }

    /// The newest of a kind, by the model's name as macOS gives it.
    private static func newest(named model: String) -> Headphones? {
        // In order: a more particular name before one it contains.
        let kinds: [(String, Headphones)] = [
            ("airpods-pro", .airpodsPro3), ("airpods-gen", .airpods4), ("studio-buds", .beatsStudioBudsPlus), ("studio-pro", .beatsStudioPro),
            ("solo-buds", .beatsSoloBuds), ("beats-solo", .beatsSolo4), ("beats-pill", .beatsPill), ("power-beats-pro", .powerbeatsPro2),
            ("fit-pro", .powerbeatsFit), ("beats-flex", .beatsFlex), ("beats-360", .beats360),
        ]
        return kinds.first { model.contains($0.0) }?.1
    }

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
        return DeviceTurn(frames: frames, rest: rest, canvas: CGSize(width: first.width, height: first.height))
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
