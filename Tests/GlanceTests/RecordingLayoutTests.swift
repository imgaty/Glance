import AppKit
import SwiftUI
import Testing

@testable import Glance

@MainActor
@Suite("Recording text layout", .serialized)
struct RecordingLayoutTests {
    @Test("Long saved-folder names leave the open button and its gap unobstructed")
    func savedFolderKeepsButtonClear() throws {
        let h: CGFloat = 32
        let length: TimeInterval = 7383
        let nativeWidth = RecordingLook.screenWidth(restingHeight: h, camera: 185, length: length)
        for width in [nativeWidth, 540] {
            let short = try render(folder: "Desktop", width: width, height: h, length: length)
            let long = try render(
                folder: "A very long destination folder name for layout and truncation review with many more words at the end",
                width: width, height: h, length: length)
            #expect(short.width == long.width && short.height == long.height)
            // Compare actual rendered pixels in the button and its separating gap. The label
            // can shorten on its own side; it must never alter pixels in this control's lane.
            let buttonLeading = width - TimerLayout.buttonEdge(h) - TimerLayout.content(h)
            let from = Int(ceil((buttonLeading - PlayerLayout.padding + 1) * 2))
            var differences = 0
            for y in 0..<short.height {
                for x in max(from, 0)..<short.width {
                    let offset = (y * short.width + x) * 4
                    if short.bytes[offset..<(offset + 4)] != long.bytes[offset..<(offset + 4)] { differences += 1 }
                }
            }
            #expect(differences == 0)
        }
    }

    private func render(folder: String, width: CGFloat, height: CGFloat, length: TimeInterval) throws -> (width: Int, height: Int, bytes: [UInt8]) {
        let view = ExpandedRecordingView(
            recording: .screen(.saved(length: length, folder: folder, preview: nil)), restingHeight: height, camera: 185, width: width,
            controlPermissionOverride: true, savedFileStateOverride: .available, stopAction: {}, openAction: {}
        )
        .environment(\.colorScheme, .dark)
        .environment(\.notchOnScreen, false)
        .background(Color.black)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        let w = image.width, h = image.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        try pixels.withUnsafeMutableBytes { raw in
            let context = try #require(
                CGContext(
                    data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return (w, h, pixels)
    }
}
