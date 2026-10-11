//
//  DisplayMockup.swift
//  Glance
//
//  Created by Gaty on 10/10/2026.
//

import AVFoundation
import AppKit
import SwiftUI

/// Each display's desktop picture, as a still, for Settings' pictures of the desktop. The wallpaper
/// API reports Apple's moving aerials as the default picture, so for an aerial the still is a frame
/// of the video macOS keeps of it (or, until that's downloaded, its thumbnail).
@MainActor
final class Wallpapers: ObservableObject {
    static let shared = Wallpapers()
    @Published private(set) var images: [String: CGImage] = [:]
    /// The displays whose picture is light along the top, where the menu bar's text turns black.
    @Published private(set) var lightTops: Set<String> = []
    private var asked: Set<String> = []

    /// Nil until it's read, in the background; the views asking are drawn again once it is.
    func image(for screen: NSScreen?) -> CGImage? {
        guard let screen else { return nil }
        let id = screen.notchID
        if let image = images[id] { return image }
        guard !asked.contains(id) else { return nil }
        asked.insert(id)
        let picture = NSWorkspace.shared.desktopImageURL(for: screen)
        Task.detached(priority: .userInitiated) {
            let image = await Self.read(display: id, picture: picture)
            let light = image.map(Self.lightAlongTop) ?? false
            await MainActor.run {
                if let image { self.images[id] = image }
                if light { self.lightTops.insert(id) } else { self.lightTops.remove(id) }
            }
        }
        return nil
    }

    /// Whether the menu bar's text is black on this display's picture.
    func lightTop(for screen: NSScreen?) -> Bool {
        guard let screen else { return false }
        _ = image(for: screen)
        return lightTops.contains(screen.notchID)
    }

    /// The picture's brightness under the menu bar: the top twentieth of it, averaged.
    private nonisolated static func lightAlongTop(_ image: CGImage) -> Bool {
        guard let band = image.cropping(to: CGRect(x: 0, y: 0, width: image.width, height: max(image.height / 20, 1))),
            let space = CGColorSpace(name: CGColorSpace.sRGB)
        else { return false }
        let width = 32, height = 2
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.interpolationQuality = .medium
            context.draw(band, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return false }
        var total = 0.0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            total += (0.2126 * Double(pixels[i]) + 0.7152 * Double(pixels[i + 1]) + 0.0722 * Double(pixels[i + 2])) / 255
        }
        return total / Double(width * height) > 0.62
    }

    /// Read afresh the next time, in case the wallpaper was changed meanwhile.
    func forget() {
        asked = []
        StillScreenCache.images = [:]
    }

    private nonisolated static func read(display: String, picture: URL?) async -> CGImage? {
        if let aerial = aerial(display: display) {
            if FileManager.default.fileExists(atPath: aerial.video.path) {
                let generator = AVAssetImageGenerator(asset: AVURLAsset(url: aerial.video))
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 2400, height: 2400)
                if let frame = try? await generator.image(at: .zero) { return frame.image }
            }
            if let image = still(aerial.thumbnail) { return image }
        }
        return picture.flatMap(still)
    }

    private nonisolated static func still(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 2400,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// The aerial chosen for a display in the wallpaper's own settings: the display's own choice if
    /// it has one, else the one for every display. Nil when the wallpaper isn't an aerial.
    private nonisolated static func aerial(display: String) -> (video: URL, thumbnail: URL)? {
        let base = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/com.apple.wallpaper")
        guard let data = try? Data(contentsOf: base.appending(path: "Store/Index.plist")),
            let index = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        let own = (index["Displays"] as? [String: Any])?.first { $0.key.localizedCaseInsensitiveContains(display) }?.value
        guard let entry = (own ?? index["AllSpacesAndDisplays"]) as? [String: Any],
            let content = ((entry["Linked"] ?? entry["Desktop"]) as? [String: Any])?["Content"] as? [String: Any],
            let choice = (content["Choices"] as? [[String: Any]])?.first,
            (choice["Provider"] as? String)?.hasSuffix("aerials") == true,
            let configuration = choice["Configuration"] as? Data,
            let decoded = try? PropertyListSerialization.propertyList(from: configuration, format: nil) as? [String: Any],
            let asset = decoded["assetID"] as? String
        else { return nil }
        return (base.appending(path: "aerials/videos/\(asset).mov"), base.appending(path: "aerials/thumbnails/\(asset).png"))
    }
}

/// A display's own desktop picture filling its frame; Apple Park until it's read.
struct DesktopPicture: View {
    var screen: NSScreen? = NSScreen.main
    @ObservedObject private var wallpapers = Wallpapers.shared

    var body: some View {
        if let image = wallpapers.image(for: screen) {
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
        } else {
            Color.black
        }
    }
}

/// A display as System Settings pictures it above its settings: the built-in display as a MacBook,
/// with the camera housing if it has one, and any other as a display on a stand, each showing an
/// empty desktop with the display's own picture.
struct DisplayMockup: View {
    let screen: NSScreen
    /// The lid's width, or the display's; everything else is in proportion.
    private let width: CGFloat = 100

    var body: some View {
        Group {
            if screen.isBuiltIn { laptop } else { monitor }
        }
        .accessibilityElement()
        .accessibilityLabel(screen.localizedName)
        .accessibilityAddTraits(.isImage)
    }

    private var aspect: CGFloat {
        screen.frame.height > 0 ? screen.frame.width / screen.frame.height : 16 / 10
    }

    /// Measured from System Settings' picture of a 14-inch MacBook Pro, in hundredths of the lid.
    private var laptop: some View {
        let u = width / 100
        let side = 1.3 * u, top = 1.6 * u, chin = 4.6 * u
        let screenSize = CGSize(width: width - side * 2, height: (width - side * 2) / aspect)
        let lid = CGSize(width: width, height: screenSize.height + top + chin)
        let lidShape = UnevenRoundedRectangle(
            topLeadingRadius: 3.4 * u, bottomLeadingRadius: 0.6 * u,
            bottomTrailingRadius: 0.6 * u, topTrailingRadius: 3.4 * u, style: .continuous)
        return VStack(spacing: 0) {
            ZStack(alignment: .top) {
                // The aluminum edge, then the black glass inside it.
                lidShape.fill(LinearGradient(colors: [Color(white: 0.4), Color(white: 0.22)], startPoint: .top, endPoint: .bottom))
                UnevenRoundedRectangle(
                    topLeadingRadius: 3 * u, bottomLeadingRadius: 0.3 * u,
                    bottomTrailingRadius: 0.3 * u, topTrailingRadius: 3 * u, style: .continuous
                )
                .fill(Color(white: 0.03))
                .padding(0.45 * u)
                ZStack(alignment: .top) {
                    DesktopPicture(screen: screen)
                        .frame(width: screenSize.width, height: screenSize.height)
                    if screen.safeAreaInsets.top > 0 {
                        // The camera housing, as wide and tall as the display's own.
                        let housing = CGSize(
                            width: screenSize.width * notchFraction,
                            height: screenSize.height * screen.safeAreaInsets.top / screen.frame.height)
                        UnevenRoundedRectangle(bottomLeadingRadius: 0.8 * u, bottomTrailingRadius: 0.8 * u, style: .continuous)
                            .fill(Color(white: 0.03))
                            .frame(width: housing.width, height: housing.height)
                    }
                }
                .frame(width: screenSize.width, height: screenSize.height)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 2.2 * u, topTrailingRadius: 2.2 * u, style: .continuous))
                .padding(.top, top)
            }
            .frame(width: lid.width, height: lid.height)
            // The keyboard deck seen from the front, under the hinge.
            Trapezoid(inset: 2 * u)
                .fill(Color(white: 0.1))
                .frame(width: width * 1.04, height: 2.2 * u)
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 2.2 * u, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 0.34), Color(white: 0.2)], startPoint: .top, endPoint: .bottom))
                RoundedRectangle(cornerRadius: 2.2 * u, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [Color(white: 0.55), .clear], startPoint: .top, endPoint: .center),
                        lineWidth: 0.35 * u)
                // Where the lid is lifted with a thumb.
                UnevenRoundedRectangle(bottomLeadingRadius: 0.7 * u, bottomTrailingRadius: 0.7 * u, style: .continuous)
                    .fill(Color(white: 0.44))
                    .frame(width: 20 * u, height: 1.2 * u)
            }
            .frame(width: width * 1.32, height: 5.2 * u)
            .background {
                Ellipse()
                    .fill(.black.opacity(0.45))
                    .frame(width: width * 1.2, height: 2.4 * u)
                    .blur(radius: 1.6 * u)
                    .offset(y: 2.8 * u)
            }
        }
    }

    /// Like Studio Display: a thin black border in an aluminum edge, on a stand.
    private var monitor: some View {
        let u = width / 100
        let border = 1.8 * u
        let screenSize = CGSize(width: width - border * 2, height: (width - border * 2) / aspect)
        let panel = CGSize(width: width, height: screenSize.height + border * 2)
        return VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 2.4 * u, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 0.75), Color(white: 0.55)], startPoint: .top, endPoint: .bottom))
                RoundedRectangle(cornerRadius: 2.1 * u, style: .continuous)
                    .fill(Color(white: 0.03))
                    .padding(0.4 * u)
                DesktopPicture(screen: screen)
                    .frame(width: screenSize.width, height: screenSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: 0.8 * u, style: .continuous))
            }
            .frame(width: panel.width, height: panel.height)
            Rectangle()
                .fill(LinearGradient(colors: [Color(white: 0.5), Color(white: 0.72)], startPoint: .top, endPoint: .bottom))
                .frame(width: 15 * u, height: 11 * u)
            Capsule()
                .fill(LinearGradient(colors: [Color(white: 0.8), Color(white: 0.55)], startPoint: .top, endPoint: .bottom))
                .frame(width: 26 * u, height: 1.8 * u)
                .background {
                    Ellipse()
                        .fill(.black.opacity(0.45))
                        .frame(width: 30 * u, height: 2 * u)
                        .blur(radius: 1.4 * u)
                        .offset(y: 1.4 * u)
                }
        }
    }

    /// How much of the top edge the camera housing takes, from the room macOS leaves either side of it.
    private var notchFraction: CGFloat {
        let left = screen.auxiliaryTopLeftArea?.width ?? 0, right = screen.auxiliaryTopRightArea?.width ?? 0
        guard left > 0, right > 0 else { return 0.12 }
        return max(screen.frame.width - left - right, 0) / screen.frame.width
    }
}

/// Wider at the bottom than the top, by an inset at each side.
private struct Trapezoid: Shape {
    let inset: CGFloat

    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX + inset, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

extension NSScreen {
    /// The Mac's own display: a MacBook's.
    var isBuiltIn: Bool {
        let number = (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        return CGDisplayIsBuiltin(number) != 0
    }

    /// The connected display with this id, as `notchID` gives it.
    static func with(id: String) -> NSScreen? {
        screens.first { $0.notchID == id }
    }
}

// MARK: - The top of a display, as it looks on it

/// What a picture of a display's top edge needs to know of the display, in its own points: its
/// size, its menu bar, and the notch at rest there.
struct ScreenTop {
    let screen: NSScreen?
    let size: CGSize
    let menuBar: CGFloat
    let notch: CGSize
    let island: Bool
    /// The notch is a camera housing.
    let camera: Bool
    let builtIn: Bool

    @MainActor init(_ screen: NSScreen?) {
        self.screen = screen
        if let screen {
            let resting = NotchController.resting(on: screen)
            size = screen.frame.size
            menuBar = resting.menuBar
            notch = resting.size
            island = resting.island
            camera = resting.camera
            builtIn = screen.isBuiltIn
        } else {
            // A 14-inch MacBook Pro's.
            size = CGSize(width: 1512, height: 982)
            menuBar = 32
            notch = CGSize(width: 185, height: 32)
            island = false
            camera = true
            builtIn = true
        }
    }

    /// The edge above the screen: a MacBook's black glass, or another display's thin border.
    var edge: CGFloat { builtIn ? 12 : 8 }
}

/// The middle of a display's top edge as it looks on the display itself, in the display's own
/// points: the edge above the screen (a MacBook's black glass, the camera housing hanging from it),
/// the desktop picture, the menu bar with its menus and status icons where they really sit, so
/// around the middle most of them are off the sides, and a window open below the menu bar, which
/// windows never go above. The notch hangs from the top of the screen over it all, as on screen.
struct ScreenPicture<Page: View, Notch: View>: View {
    let top: ScreenTop
    /// How much of the display shows, around the middle of its top edge, the edge above it included.
    let size: CGSize
    /// The edge above the screen, left out of pictures too small for it.
    var edge = true
    /// What's still: the edge, the desktop, the window and the menu bar. Off where it's drawn under
    /// this already, once (see `StillScreen`).
    var still = true
    /// What lives: the notch, and the camera housing over it.
    var live = true
    @ViewBuilder var page: () -> Page
    @ViewBuilder var notch: () -> Notch

    private static var windowWidth: CGFloat { 760 }
    /// How far left of the middle of the screen the window's left edge is.
    private static var windowLeft: CGFloat { 236 }

    var body: some View {
        let edgeHeight = edge ? top.edge : 0
        let visible = CGSize(width: size.width, height: max(size.height - edgeHeight, 0))
        // Windows go as high as the menu bar lets them.
        let windowTop = top.menuBar
        VStack(spacing: 0) {
            if edge {
                // A MacBook's black glass, or another display's border.
                Color.black
                    .frame(width: size.width, height: edgeHeight)
                    .opacity(still ? 1 : 0)
            }
            ZStack(alignment: .top) {
                // Laid out at the display's size, its middle at the middle: only that much shows.
                // None of it takes clicks, as clipping doesn't stop it from.
                if still {
                    Group {
                        DesktopPicture(screen: top.screen)
                            .frame(width: top.size.width, height: top.size.height)
                        // Half the screen wide, its corner with the traffic lights just left of the notch.
                        PageWindow(page: page)
                            .frame(width: Self.windowWidth, height: max(visible.height - windowTop + 40, 120))
                            .padding(.top, windowTop)
                            .padding(.leading, (Self.windowWidth / 2 - Self.windowLeft) * 2)
                        MenuBarPicture(top: top, shown: visible.width)
                    }
                    .frame(width: visible.width, height: visible.height, alignment: .top)
                    .allowsHitTesting(false)
                }
                if live {
                    notch()
                        .frame(width: visible.width, height: visible.height, alignment: .top)
                    if top.camera {
                        CameraHousing(size: top.notch)
                            .allowsHitTesting(false)
                    }
                }
            }
            .frame(width: visible.width, height: visible.height)
            .clipped()
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        // Where the edge meets the screen on a fraction of a pixel, both blend with what's behind,
        // which would show as a thin bright line right above the notch; black behind them, it can't.
        .background { if edge, still { Color.black } }
    }
}

/// The still part of a picture of a display's top, drawn once into an image, at the size it shows:
/// for small pictures that are many, whose notch changes all the time while what's under it never
/// does. Drawn again when the desktop picture has been read, or the system turns light or dark.
struct StillScreen<Page: View>: View {
    let top: ScreenTop
    /// In the display's points, as for `ScreenPicture`, and how large one of them shows.
    let size: CGSize
    let scale: CGFloat
    var edge = true
    @ViewBuilder var page: () -> Page
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @ObservedObject private var wallpapers = Wallpapers.shared
    @State private var image: CGImage?

    var body: some View {
        let read = wallpapers.image(for: top.screen) != nil
        Group {
            if let image {
                Image(decorative: image, scale: displayScale)
                    .resizable()
            } else {
                Color.black
            }
        }
        .frame(width: size.width * scale, height: size.height * scale)
        .task(id: key(read: read)) {
            // Pictures side by side share what's under their notch: it's drawn once for all of them.
            let key = key(read: read)
            if let drawn = StillScreenCache.images[key] {
                image = drawn
                return
            }
            let content = ScreenPicture(top: top, size: size, edge: edge, live: false, page: page) { EmptyView() }
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: size.width * scale, height: size.height * scale, alignment: .topLeading)
                .environment(\.colorScheme, colorScheme)
            let renderer = ImageRenderer(content: content)
            renderer.scale = displayScale
            image = renderer.cgImage
            StillScreenCache.images[key] = image
        }
    }

    private func key(read: Bool) -> String {
        "\(Page.self) \(top.screen?.notchID ?? "") \(read) \(colorScheme) \(size.width)x\(size.height) \(scale) \(displayScale) \(edge)"
    }
}

/// The still parts of pictures already drawn, by what they show.
@MainActor
private enum StillScreenCache {
    static var images: [String: CGImage] = [:]
}

/// A MacBook's camera housing: black, as the notch is at rest.
private struct CameraHousing: View {
    let size: CGSize

    var body: some View {
        UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8, style: .continuous)
            .fill(.black)
            .frame(width: size.width, height: size.height)
    }
}

/// The menu bar as macOS 26 draws it: no bar, only its menus and icons on the desktop picture, in
/// white, or in black on a light picture. Safari's menus from the left edge; Glance's own icon, the
/// system's and the clock from the right.
private struct MenuBarPicture: View {
    let top: ScreenTop
    /// How much of it shows, around its middle. Anything the picture's sides would cut through is
    /// left out, as a photograph would be framed.
    let shown: CGFloat
    @ObservedObject private var wallpapers = Wallpapers.shared

    private static let menus = ["File", "Edit", "View", "History", "Bookmarks", "Window", "Help"]
    nonisolated private static let space = "menuBar"

    var body: some View {
        let light = wallpapers.lightTop(for: top.screen)
        let inside = (top.size.width - shown) / 2 + 2...(top.size.width + shown) / 2 - 2
        HStack(spacing: 0) {
            Group {
                Image(systemName: "applelogo")
                    .font(.system(size: 15))
                    .frame(width: 34)
                Text("Safari")
                    .fontWeight(.bold)
                    .padding(.horizontal, 10)
                ForEach(Self.menus, id: \.self) { menu in
                    Text(menu)
                        .padding(.horizontal, 10)
                }
            }
            .modifier(Framed(inside: inside))
            Spacer(minLength: 0)
            Group {
                Image(systemName: "rectangle.topthird.inset.filled")
                if top.builtIn { Image(systemName: "battery.75percent") }
                Image(systemName: "wifi")
                Image(systemName: "magnifyingglass")
                Image(systemName: "switch.2")
            }
            .font(.system(size: 14))
            .frame(width: 32)
            .modifier(Framed(inside: inside))
            Text(
                Date.now.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
                    .replacingOccurrences(of: ",", with: "")
            )
            .padding(.leading, 8)
            .modifier(Framed(inside: inside))
        }
        .font(.system(size: 13))
        .lineLimit(1)
        .padding(.horizontal, 10)
        .foregroundStyle(light ? Color.black.opacity(0.85) : .white)
        .shadow(color: .black.opacity(light ? 0 : 0.3), radius: 2, y: 0.5)
        .frame(width: top.size.width, height: top.menuBar)
        .coordinateSpace(.named(Self.space))
    }

    /// Shown only if it's wholly inside the picture.
    private struct Framed: ViewModifier {
        let inside: ClosedRange<CGFloat>

        func body(content: Content) -> some View {
            content.visualEffect { [inside] content, proxy in
                let frame = proxy.frame(in: .named(MenuBarPicture.space))
                return content.opacity(inside.contains(frame.minX) && inside.contains(frame.maxX) ? 1 : 0)
            }
        }
    }
}

/// A window as macOS 26 draws one when its page runs right up to its top: rounded, the page
/// filling it, and only the traffic lights floating over the page's top left corner.
struct PageWindow<Page: View>: View {
    @ViewBuilder var page: () -> Page
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        page()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipped()
            .overlay(alignment: .topLeading) {
                HStack(spacing: 9) {
                    TrafficLight(light: .close)
                    TrafficLight(light: .minimize)
                    TrafficLight(light: .zoom)
                }
                .padding(.leading, 14)
                .padding(.top, 14)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(shape)
            .overlay { shape.strokeBorder(colorScheme == .dark ? .white.opacity(0.18) : .black.opacity(0.14), lineWidth: 0.5) }
            .background {
                shape.fill(.black)
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.5 : 0.28), radius: 26, y: 14)
            }
    }
}

/// One of a window's traffic lights as macOS 26 draws them, measured from them: 14 points, the
/// color deepest across the top and lit from below, with a bright rim at the top and bottom edges.
private struct TrafficLight: View {
    let light: Light

    enum Light {
        case close, minimize, zoom

        /// The color, the glow from below, and the rim, in sRGB.
        var colors: (base: Color, glow: Color, rim: Color) {
            func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r / 255, green: g / 255, blue: b / 255) }
            return switch self {
            case .close: (rgb(233, 114, 96), rgb(232, 136, 123), rgb(255, 190, 178))
            case .minimize: (rgb(244, 193, 0), rgb(248, 216, 104), rgb(255, 232, 128))
            case .zoom: (rgb(90, 193, 0), rgb(128, 201, 99), rgb(178, 238, 146))
            }
        }
    }

    static let size: CGFloat = 14

    var body: some View {
        let colors = light.colors
        Circle()
            .fill(colors.base)
            .overlay {
                Circle().fill(
                    RadialGradient(
                        colors: [colors.glow, colors.glow.opacity(0)],
                        center: UnitPoint(x: 0.5, y: 0.82), startRadius: 0, endRadius: Self.size * 0.62))
            }
            .overlay {
                Circle().strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: colors.rim, location: 0),
                            .init(color: colors.rim.opacity(0), location: 0.3),
                            .init(color: colors.rim.opacity(0), location: 0.7),
                            .init(color: colors.rim, location: 1),
                        ],
                        startPoint: .top, endPoint: .bottom),
                    lineWidth: 1)
            }
            .frame(width: Self.size, height: Self.size)
    }
}
