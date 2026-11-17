//
//  ShortcutLook.swift
//  Glance
//
//  Created by Gaty on 17/11/2026.
//

import AppKit
import Darwin
import SwiftUI

/// A shortcut's own look, as Shortcuts draws it and as the iPhone's Dynamic Island shows a shortcut
/// running: its color and its icon, the rounded square with its glyph. Shortcuts gives its color as
/// the base of its gradient; the island's ring takes the gradient's dark base instead, as iOS 27's
/// `WFApertureIconView` sets its primary color. Without an icon, Shortcuts' own drawer draws one in
/// the shortcut's color with Shortcuts' layers, as a new shortcut has.
struct ShortcutLook: Equatable {
    var color: NSColor?
    var icon: NSImage?

    /// Shortcuts' palette entry for the color, if it's one of the fifteen.
    var paletteEntry: ShortcutPalette.Entry? { color.flatMap(ShortcutPalette.entry(base:)) }

    /// The ring's color, and the square's in it.
    var tint: Color? { tintColor.map { Color(nsColor: $0) } }
    var tintColor: NSColor? { paletteEntry?.darkBase ?? color }

    /// What the opened icon stands on: the tint brought to half luminance and darkened to 30%, opaque;
    /// without one, gray at 40% (iOS 27's `-[WFApertureIconView iconStackPlatterColorForImage:]`).
    var platter: Color {
        guard let tint = tintColor?.usingColorSpace(.sRGB) else { return Color(.sRGB, red: 0.5569, green: 0.5569, blue: 0.5765, opacity: 0.4) }
        let r = tint.redComponent, g = tint.greenComponent, b = tint.blueComponent
        let shift = 0.5 - (0.2126 * r + 0.7152 * g + 0.0722 * b)
        return Color(.sRGB, red: (r + shift) * 0.3, green: (g + shift) * 0.3, blue: (b + shift) * 0.3)
    }

    /// The icon to show: Shortcuts' own, or drawn by Shortcuts' drawer in the shortcut's color.
    var tile: NSImage? { icon ?? ShortcutTileDrawer.tile(rgba: paletteEntry?.stored ?? ShortcutPalette.newShortcut) }

    static func == (a: ShortcutLook, b: ShortcutLook) -> Bool { a.color == b.color && a.icon === b.icon }

    /// For Settings and the activity bench: Gray Green, as the shortcut recorded on the iPhone, drawn
    /// by Shortcuts' drawer.
    static let fixture = ShortcutLook(color: ShortcutPalette.entries[13].base)
    /// A shortcut whose look Shortcuts didn't give: a new shortcut's, Cyan with Shortcuts' layers, as
    /// the island always has a color.
    static let newShortcut = ShortcutLook(color: ShortcutPalette.entries[6].base)
}

/// Shortcuts' fifteen colors, read from macOS 27.3's `WFColor.workflowPalette`: the value a shortcut
/// stores, and its gradient's base, which Shortcuts Events reports, and dark base, which the island's
/// ring takes. sRGB.
enum ShortcutPalette {
    struct Entry {
        let stored: UInt32
        let base: NSColor
        let darkBase: NSColor
    }

    /// A new shortcut's color, Cyan, with Shortcuts' layers.
    static let newShortcut: UInt32 = 0x55DA_E1FF

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: 1) }

    static let entries: [Entry] = [
        Entry(stored: 0xFF43_51FF, base: rgb(0.978600, 0.333499, 0.391445), darkBase: rgb(0.927864, 0.316566, 0.341028)),
        Entry(stored: 0xFD66_31FF, base: rgb(1.000000, 0.484349, 0.362326), darkBase: rgb(0.988095, 0.450974, 0.319034)),
        Entry(stored: 0xFE99_49FF, base: rgb(0.969971, 0.631954, 0.268934), darkBase: rgb(0.951636, 0.599568, 0.213111)),
        Entry(stored: 0xFEC4_18FF, base: rgb(0.980236, 0.722811, 0.001828), darkBase: rgb(0.897096, 0.730925, 0.000000)),
        Entry(stored: 0xFFD4_26FF, base: rgb(0.215214, 0.771536, 0.325157), darkBase: rgb(0.110363, 0.732306, 0.266585)),
        Entry(stored: 0x19BD_03FF, base: rgb(0.000000, 0.794285, 0.653567), darkBase: rgb(0.000000, 0.762437, 0.626271)),
        Entry(stored: 0x55DA_E1FF, base: rgb(0.000000, 0.685697, 0.965631), darkBase: rgb(0.359223, 0.754126, 0.918736)),
        Entry(stored: 0x1B9A_F7FF, base: rgb(0.068440, 0.505683, 1.000000), darkBase: rgb(0.042927, 0.517707, 1.000000)),
        Entry(stored: 0x3871_DEFF, base: rgb(0.229878, 0.360317, 0.746518), darkBase: rgb(0.229878, 0.360317, 0.746518)),
        Entry(stored: 0x7B72_E9FF, base: rgb(0.499276, 0.292209, 0.746371), darkBase: rgb(0.450515, 0.253248, 0.681929)),
        Entry(stored: 0xDB49_D8FF, base: rgb(0.712540, 0.442525, 0.888154), darkBase: rgb(0.660802, 0.391164, 0.836632)),
        Entry(stored: 0xED46_94FF, base: rgb(0.960760, 0.514166, 0.822486), darkBase: rgb(0.909810, 0.449266, 0.767531)),
        Entry(stored: 0x0000_00FF, base: rgb(0.493575, 0.538678, 0.580744), darkBase: rgb(0.466100, 0.511223, 0.553281)),
        Entry(stored: 0xB4B2_A9FF, base: rgb(0.532129, 0.638464, 0.554531), darkBase: rgb(0.532129, 0.638464, 0.554531)),
        Entry(stored: 0xA9A9_A9FF, base: rgb(0.653433, 0.540871, 0.415317), darkBase: rgb(0.703840, 0.596009, 0.470683)),
    ]

    /// The entry whose base the color is, as Shortcuts Events reports it in 16 bits a channel.
    static func entry(base color: NSColor) -> Entry? {
        guard let c = color.usingColorSpace(.sRGB) else { return nil }
        return entries.first { entry in
            guard let e = entry.base.usingColorSpace(.sRGB) else { return false }
            return abs(e.redComponent - c.redComponent) < 0.002 && abs(e.greenComponent - c.greenComponent) < 0.002
                && abs(e.blueComponent - c.blueComponent) < 0.002
        }
    }
}

/// A shortcut's icon drawn by Shortcuts itself, `WFWorkflowIconDrawer` in macOS's WorkflowKit, the
/// drawer the iPhone's Shortcuts uses: the color's gradient, its corners and Shortcuts' layers glyph.
/// Nil where WorkflowKit can't be reached.
enum ShortcutTileDrawer {
    /// Shortcuts' layers, the glyph a new shortcut has.
    static let layersGlyph: UInt16 = 0xF000

    nonisolated(unsafe) private static var drawn: [UInt32: NSImage] = [:]
    private static let lock = NSLock()

    static func tile(rgba: UInt32, glyph: UInt16 = layersGlyph) -> NSImage? {
        lock.lock()
        defer { lock.unlock() }
        if let image = drawn[rgba] { return image }
        guard let image = draw(rgba: rgba, glyph: glyph) else { return nil }
        drawn[rgba] = image
        return image
    }

    private static func draw(rgba: UInt32, glyph: UInt16) -> NSImage? {
        guard dlopen("/System/Library/PrivateFrameworks/WorkflowKit.framework/WorkflowKit", RTLD_NOW) != nil,
            let colorClass = NSClassFromString("WFColor") as? NSObject.Type,
            let drawerClass = NSClassFromString("WFWorkflowIconDrawer") as? NSObject.Type
        else { return nil }
        let colorWithValue = NSSelectorFromString("colorWithRGBAValue:")
        let setBackground = NSSelectorFromString("setBackgroundColor:")
        let setGlyph = NSSelectorFromString("setGlyphCharacter:")
        let imageWithSize = NSSelectorFromString("imageWithSize:")
        let cgImage = NSSelectorFromString("CGImage")
        let drawer = drawerClass.init()
        guard colorClass.responds(to: colorWithValue), let colorIMP = colorClass.method(for: colorWithValue),
            drawer.responds(to: setBackground), drawer.responds(to: setGlyph), drawer.responds(to: imageWithSize),
            let glyphIMP = drawer.method(for: setGlyph), let sizeIMP = drawer.method(for: imageWithSize)
        else { return nil }
        // As `-[WFWorkflowIconDrawer setIcon:]` sets them from a shortcut's icon.
        typealias ColorWithValue = @convention(c) (AnyClass, Selector, UInt32) -> Unmanaged<AnyObject>?
        guard let color = unsafeBitCast(colorIMP, to: ColorWithValue.self)(colorClass, colorWithValue, rgba)?.takeUnretainedValue() else { return nil }
        drawer.perform(setBackground, with: color)
        typealias SetGlyph = @convention(c) (AnyObject, Selector, UInt16) -> Void
        unsafeBitCast(glyphIMP, to: SetGlyph.self)(drawer, setGlyph, glyph)
        typealias ImageWithSize = @convention(c) (AnyObject, Selector, CGSize) -> Unmanaged<AnyObject>?
        guard let image = unsafeBitCast(sizeIMP, to: ImageWithSize.self)(drawer, imageWithSize, CGSize(width: 256, height: 256))?.takeUnretainedValue() as? NSObject,
            image.responds(to: cgImage), let cgIMP = image.method(for: cgImage)
        else { return nil }
        typealias GetCGImage = @convention(c) (AnyObject, Selector) -> Unmanaged<CGImage>?
        guard let cg = unsafeBitCast(cgIMP, to: GetCGImage.self)(image, cgImage)?.takeUnretainedValue() else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}

/// Each shortcut's look, read once from Shortcuts through its scripting (`Shortcuts Events`), which
/// macOS asks the user to allow the first time. Read off the main thread, as Shortcuts Events may
/// take a moment to start. A shortcut that can't be read, or a refusal, isn't asked about again
/// until Glance next starts.
@MainActor
final class ShortcutLooks {
    static let shared = ShortcutLooks()

    private var known: [UUID: ShortcutLook] = [:]
    private var asked: Set<UUID> = []
    private let queue = DispatchQueue(label: "Glance.ShortcutLooks", qos: .utility)

    func look(for id: UUID) -> ShortcutLook? { known[id] }

    /// Reads the shortcut's look if it hasn't been, then calls back on the main actor.
    func load(_ id: UUID, then: @escaping @MainActor () -> Void) {
        guard !asked.contains(id) else { return }
        asked.insert(id)
        queue.async {
            let read = Self.read(id)
            Task { @MainActor in
                guard let read else { return }
                self.known[id] = ShortcutLook(
                    color: read.color.map { NSColor(srgbRed: $0.0, green: $0.1, blue: $0.2, alpha: 1) },
                    icon: read.icon.flatMap(NSImage.init(data:)))
                then()
            }
        }
    }

    private struct Read: Sendable {
        var color: (CGFloat, CGFloat, CGFloat)?
        var icon: Data?
    }

    nonisolated private static func read(_ id: UUID) -> Read? {
        let source = """
            tell application "Shortcuts Events"
                set found to shortcut id "\(id.uuidString)"
                return {color of found, icon of found}
            end tell
            """
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        guard error == nil, result.numberOfItems == 2 else { return nil }
        var read = Read()
        if let color = result.atIndex(1), color.numberOfItems == 3 {
            let parts = (1...3).compactMap { color.atIndex($0)?.int32Value }.map { CGFloat($0) / 65535 }
            if parts.count == 3 { read.color = (parts[0], parts[1], parts[2]) }
        }
        if let icon = result.atIndex(2)?.data, !icon.isEmpty { read.icon = icon }
        return read.color == nil && read.icon == nil ? nil : read
    }
}
