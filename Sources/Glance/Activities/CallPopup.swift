//
//  CallPopup.swift
//  Glance
//
//  Created by Gaty on 05/11/2026.
//

import AppKit
import CoreMedia
@preconcurrency import ScreenCaptureKit
import Vision

/// What macOS's popup for a phone or FaceTime call shows. Its contents are another process's view,
/// which Accessibility can't see into, so it's read from its picture, as a person would.
struct CallPopup: Equatable {
    /// Who the call is with.
    var name: String?
    /// The line under it, with the time once it's connected.
    var detail: String?
    /// The red button, ending or declining it, and the green one, accepting it, as shares of the
    /// popup from its top left.
    var red: CGPoint?
    var green: CGPoint?
    /// When its time started, worked out from the moment that time changed, so the notch's ticks with it.
    var started: Date?

    /// How long it's been going, by the time it shows.
    var elapsed: Int? { Self.elapsed(in: detail) }
    /// All the notch needs to stand in for it.
    var readable: Bool { name != nil && red != nil }

    /// Where its waveform is, as shares of the popup.
    static let wave = CGRect(x: 0.668, y: 0.225, width: 0.2381, height: 0.135)

    struct Line: Equatable {
        var text: String
        /// As Vision gives it: shares of the picture, from its bottom left.
        var box: CGRect
    }

    /// The words beside the caller's picture, top first. Anything else read, like the picture's
    /// initial or the buttons' marks, is to the side or below.
    nonisolated static func words(in lines: [Line]) -> (name: String?, detail: String?) {
        let column = lines.filter { (0.12...0.45).contains($0.box.minX) && $0.box.maxY >= 0.45 }
            .sorted { $0.box.maxY > $1.box.maxY }
        return (column.first?.text, column.dropFirst().first?.text)
    }

    /// The seconds in a time at the end of a line, like "Using Your iPhone - 4:37".
    nonisolated static func elapsed(in detail: String?) -> Int? {
        guard let last = detail?.split(whereSeparator: \.isWhitespace).last else { return nil }
        let parts = last.filter { $0.isNumber || $0 == ":" }.split(separator: ":", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count), parts.dropFirst().allSatisfy({ $0.count == 2 }) else { return nil }
        let numbers = parts.compactMap { Int($0) }
        guard numbers.count == parts.count else { return nil }
        return numbers.reduce(0) { $0 * 60 + $1 }
    }

    /// When a time started, from two readings either side of its changing to a number of seconds.
    nonisolated static func started(changedBetween before: Date, and after: Date, to seconds: Int) -> Date {
        before.addingTimeInterval(after.timeIntervalSince(before) / 2 - TimeInterval(seconds))
    }

    /// The middle of the red and of the green button, among 8-bit pixels with four channels each,
    /// red first. They're always in the popup's right half, and big, which leaves out a caller's
    /// picture and the waveform's green.
    nonisolated static func buttons(pixels: UnsafeBufferPointer<UInt8>, width: Int, height: Int) -> (red: CGPoint?, green: CGPoint?) {
        var red = (x: 0, y: 0, count: 0)
        var green = (x: 0, y: 0, count: 0)
        for y in 0..<height {
            for x in (width / 2)..<width {
                let at = (y * width + x) * 4
                let (r, g, b) = (Int(pixels[at]), Int(pixels[at + 1]), Int(pixels[at + 2]))
                if r > 170, g < 60, b < 60 {
                    red = (red.x + x, red.y + y, red.count + 1)
                } else if r < 110, g > 120, b < 120, g - r > 60 {
                    green = (green.x + x, green.y + y, green.count + 1)
                }
            }
        }
        let enough = max(width * height / 200, 1)
        func middle(_ found: (x: Int, y: Int, count: Int)) -> CGPoint? {
            guard found.count >= enough else { return nil }
            return CGPoint(
                x: CGFloat(found.x) / CGFloat(found.count) / CGFloat(width),
                y: CGFloat(found.y) / CGFloat(found.count) / CGFloat(height))
        }
        return (middle(red), middle(green))
    }

    /// How loud each voice is in a picture of the popup's waveform, from 0 to 1: the other person's
    /// bars are its left, yours its right, each by its tallest bar above a quiet dot. Anything lit is
    /// a bar, whatever its color, so it reads the same in either order of color channels.
    nonisolated static func levels(pixels: UnsafeBufferPointer<UInt8>, width: Int, height: Int, rowBytes: Int) -> (theirs: CGFloat, yours: CGFloat) {
        guard width > 0, height > 0, pixels.count >= rowBytes * height else { return (0, 0) }
        let count = 30
        let heights: [Int] = (0..<count).map { bar in
            let middle = Int((Double(bar) + 0.5) / Double(count) * Double(width))
            return (max(middle - 1, 0)...min(middle + 1, width - 1)).map { x in
                (0..<height).filter { y in
                    let at = y * rowBytes + x * 4
                    return max(pixels[at], pixels[at + 1], pixels[at + 2]) > 110
                }.count
            }.max() ?? 0
        }
        // A quiet dot is about a seventh of the strip; the tallest bar about three quarters.
        func level(_ bars: ArraySlice<Int>) -> CGFloat {
            let dot = CGFloat(height) * 0.14, tallest = CGFloat(height) * 0.75
            return min(max((CGFloat(bars.max() ?? 0) - dot) / (tallest - dot), 0), 1)
        }
        return (level(heights.prefix(12)), level(heights.suffix(12)))
    }

    /// Reads its words and buttons from its picture.
    nonisolated static func read(_ image: CGImage, accurate: Bool) -> CallPopup {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = accurate ? .accurate : .fast
        request.usesLanguageCorrection = false
        if let supported = try? request.supportedRecognitionLanguages() {
            let wanted = Locale.preferredLanguages.filter(supported.contains)
            request.recognitionLanguages = wanted + ["en-US"]
        }
        try? VNImageRequestHandler(cgImage: image).perform([request])
        let lines = (request.results ?? []).compactMap { result in
            result.topCandidates(1).first.map { Line(text: $0.string, box: result.boundingBox) }
        }
        let words = words(in: lines)
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let found: (red: CGPoint?, green: CGPoint?) = pixels.withUnsafeMutableBytes { raw in
            guard
                let context = CGContext(
                    data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return (nil, nil) }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return buttons(pixels: UnsafeBufferPointer(raw.bindMemory(to: UInt8.self)), width: width, height: height)
        }
        return CallPopup(name: words.name, detail: words.detail, red: found.red, green: found.green)
    }
}

/// Pictures of the popup, from Notification Center's window. Only that window is ever captured, and
/// only while a call's popup is up, and nothing is kept.
@MainActor
enum CallPopupCamera {
    static func window() async -> SCWindow? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) else { return nil }
        return content.windows.filter { $0.owningApplication?.bundleIdentifier == CallBanners.center }
            .max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
    }

    /// A part of the screen, as that window draws it, wherever the window is.
    static func picture(of rect: CGRect, in window: SCWindow) async -> CGImage? {
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = rect.offsetBy(dx: -window.frame.minX, dy: -window.frame.minY)
        configuration.width = Int(rect.width * 2)
        configuration.height = Int(rect.height * 2)
        configuration.showsCursor = false
        return try? await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: configuration)
    }
}

/// The popup's own waveform as it moves, which shows both voices with nothing else listened to: only
/// ever a small strip of that one window, a few times a second, read for how tall its bars are.
final class CallPopupWave: NSObject, SCStreamOutput, @unchecked Sendable {
    private let queue = DispatchQueue(label: "Glance.CallPopupWave")
    private var stream: SCStream?
    private let heard: @Sendable (CGFloat, CGFloat) -> Void

    init(heard: @escaping @Sendable (CGFloat, CGFloat) -> Void) {
        self.heard = heard
    }

    @MainActor
    var running: Bool { stream != nil }

    @MainActor
    func start(window: SCWindow, popup: CGRect) async {
        guard stream == nil else { return }
        let configuration = SCStreamConfiguration()
        let wave = CGRect(
            x: popup.minX + popup.width * CallPopup.wave.minX - window.frame.minX,
            y: popup.minY + popup.height * CallPopup.wave.minY - window.frame.minY,
            width: (popup.width * CallPopup.wave.width).rounded(), height: (popup.height * CallPopup.wave.height).rounded())
        configuration.sourceRect = wave
        // Any other shape would be fitted in with an edge.
        configuration.preservesAspectRatio = false
        configuration.width = Int(wave.width * 2)
        configuration.height = Int(wave.height * 2)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 20)
        configuration.queueDepth = 3
        configuration.showsCursor = false
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.colorSpaceName = CGColorSpace.displayP3
        let made = SCStream(filter: SCContentFilter(desktopIndependentWindow: window), configuration: configuration, delegate: nil)
        guard (try? made.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)) != nil else { return }
        stream = made
        do {
            try await made.startCapture()
        } catch {
            stream = nil
        }
    }

    @MainActor
    func stop() {
        guard let stream else { return }
        self.stream = nil
        Task { try? await stream.stopCapture() }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid, let buffer = sampleBuffer.imageBuffer else { return }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        let pixels = UnsafeBufferPointer(start: base.assumingMemoryBound(to: UInt8.self), count: rowBytes * height)
        let levels = CallPopup.levels(pixels: pixels, width: width, height: height, rowBytes: rowBytes)
        heard(levels.theirs, levels.yours)
    }
}
