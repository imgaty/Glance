//
//  ApplePage.swift
//  Glance
//
//  Created by Gaty on 07/10/2026.
//

import AppKit
import SwiftUI

/// The page in the window under the notch: the one System Settings shows its Liquid Glass over,
/// taken from macOS itself so it's Apple's own and in the user's language, laid out as a web page.
/// Apple Park across the top, then Apple's words about it, its architecture, the Rainbow and the
/// Pond. It scrolls slowly to the end and back up, again and again, so what the glass and the blur
/// do to what moves behind them shows. Its text and background are light or dark with the system.
/// It's drawn once into a picture, which scrolls thirty times a second, under a point at a time:
/// laid out afresh at every frame, its words and photos kept the whole window busy, and every toggle
/// in it waited behind them.
struct ApplePage: View {
    /// Held still where it is, on pages without the preview.
    var scrolls = true
    /// How large it shows, which it's drawn for, so it's never drawn larger than it's seen.
    var scale: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @EnvironmentObject private var preview: SettingsPreview
    @State private var drawn: CGImage?

    var body: some View {
        GeometryReader { proxy in
            let pixels = displayScale * scale
            let travel = max(CGFloat(drawn?.height ?? 0) / pixels - proxy.size.height, 0)
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !scrolls || reduceMotion || drawn == nil)) { context in
                if let drawn {
                    Image(decorative: drawn, scale: pixels)
                        .offset(y: -Self.offset(at: preview.scrollClock.time(at: context.date), travel: travel))
                } else {
                    // Until it's drawn, the page itself, still, which looks the same.
                    Self.article(width: proxy.size.width)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            .task(id: "\(colorScheme) \(proxy.size.width) \(pixels)") {
                drawn = Self.picture(width: proxy.size.width, pixels: pixels, colorScheme: colorScheme)
            }
        }
        .clipped()
        .background(ApplePark.sheet)
        .allowsHitTesting(false)
        // The page's clock keeps time for the whole window, so changing pages never moves it; it
        // holds still while paused, and carries on from there.
        .onChange(of: scrolls && !reduceMotion, initial: true) { _, on in
            on ? preview.scrollClock.resume() : preview.scrollClock.pause()
        }
    }

    /// The top of the page, still, for the pictures of choices: on no clock.
    struct Still: View {
        var body: some View {
            GeometryReader { proxy in
                ApplePage.article(width: proxy.size.width)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            }
            .clipped()
            .background(ApplePark.sheet)
            .allowsHitTesting(false)
        }
    }

    /// The whole page, drawn once for each width, size and look it's shown in: Settings' preview
    /// and the welcome tour's share it.
    private static var pictures: [String: CGImage] = [:]

    private static func picture(width: CGFloat, pixels: CGFloat, colorScheme: ColorScheme) -> CGImage? {
        let key = "\(colorScheme) \(width) \(pixels)"
        if let picture = pictures[key] { return picture }
        let renderer = ImageRenderer(content: article(width: width).environment(\.colorScheme, colorScheme))
        renderer.proposedSize = ProposedViewSize(width: width, height: nil)
        renderer.scale = pixels
        let picture = renderer.cgImage
        pictures[key] = picture
        return picture
    }

    /// Down to the end at about 28 points a second, easing in and out, a pause, back up, a pause.
    private static func offset(at time: Double, travel: CGFloat) -> CGFloat {
        guard travel > 0 else { return 0 }
        let move = Double(travel) / 28, hold = 1.5
        let t = time.truncatingRemainder(dividingBy: 2 * (move + hold))
        func ease(_ x: Double) -> CGFloat {
            let x = min(max(x, 0), 1)
            return CGFloat(x * x * (3 - 2 * x))
        }
        switch t {
        case ..<hold: return 0
        case ..<(hold + move): return travel * ease((t - hold) / move)
        case ..<(2 * hold + move): return travel
        default: return travel * (1 - ease((t - 2 * hold - move) / move))
        }
    }

    /// The photo across the page, then the words in a column down its middle.
    fileprivate static func article(width: CGFloat) -> some View {
        let column = min(width - 64, 560)
        return VStack(spacing: 0) {
            ApplePark.photo("apple-park")
                .frame(width: width, height: min(width * 0.4, 420))
                .clipped()
            VStack(alignment: .leading, spacing: 0) {
                Text(ApplePark.text("Welcome to Apple Park"))
                    .font(.system(size: 30, weight: .bold))
                Text(ApplePark.text("Cupertino, California"))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                Text(ApplePark.text("Learn about the design and history of Apple Park, and discover its unique nature and beauty."))
                    .padding(.top, 14)
                ForEach(ApplePark.sections, id: \.photo) { section in
                    Text(ApplePark.text(section.title))
                        .font(.system(size: 22, weight: .semibold))
                        .padding(.top, 36)
                    ApplePark.photo(section.photo)
                        .frame(width: column, height: column * 0.6)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.top, 12)
                    Text(ApplePark.text(section.text))
                        .foregroundStyle(.secondary)
                        .padding(.top, 12)
                }
            }
            .font(.system(size: 17))
            .frame(width: column, alignment: .leading)
            .padding(.top, 28)
            .padding(.bottom, 48)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: width)
    }
}

/// Apple's Liquid Glass picture, from System Settings' own framework, as measured there.
@MainActor
private enum ApplePark {
    private static let bundle = Bundle(path: "/System/Library/PrivateFrameworks/AppearancePreferencesFramework.framework")
    private static var photos: [String: CGImage] = [:]

    @ViewBuilder static func photo(_ name: String) -> some View {
        if let image = image(name) {
            Image(decorative: image, scale: 2).resizable().aspectRatio(contentMode: .fill)
        } else {
            LinearGradient(
                colors: [Color(red: 0.55, green: 0.72, blue: 0.9), Color(red: 0.3, green: 0.45, blue: 0.28)],
                startPoint: .top, endPoint: .bottom)
        }
    }

    /// Loaded once, and made only as large as the pictures ever show it, so it's drawn at once
    /// rather than shrunk from the full photo every time.
    private static func image(_ name: String) -> CGImage? {
        if let image = photos[name] { return image }
        guard let source = bundle?.image(forResource: name)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        // Across a window's width at the top of the page; in a column below it.
        let scale = min(1, (name == "apple-park" ? 1620 : 1120) / CGFloat(source.width))
        let width = Int(CGFloat(source.width) * scale), height = Int(CGFloat(source.height) * scale)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return source }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        let image = context.makeImage() ?? source
        photos[name] = image
        return image
    }

    static func text(_ key: String) -> String {
        bundle?.localizedString(forKey: key, value: key, table: "Localizable") ?? key
    }

    /// The rest of Apple's page, after its welcome.
    static let sections = [
        (
            title: "The Architecture", photo: "architecture",
            text: "Apple Park was made for walking and exploring. The innovative design elements emphasize openness and connection to nature."
        ),
        (
            title: "The Rainbow", photo: "rainbow",
            text: "One of the most iconic features of Apple Park, the Rainbow brings much joy to all who experience it."
        ),
        (
            title: "The Pond", photo: "pond",
            text: "With gently lapping waves and a surrounding of trees, it\u{2019}s one of the most serene spots on campus."
        ),
    ]

    /// White in light mode; the warm near-black System Settings shows in dark mode.
    static let sheet = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 24 / 255, green: 22 / 255, blue: 19 / 255, alpha: 1) : .white
        })
}
