//
//  SystemSymbol.swift
//  Glance
//
//  Created by Gaty on 15/11/2026.
//

import AppKit
import SwiftUI

/// An SF Symbol by the name macOS gives it, public or one Apple keeps to itself. macOS's own banners
/// name both kinds: the Work Focus is `person.lanyardcard.fill`, which only the private list has, so
/// asking for it by its public name finds nothing and draws nothing.
@MainActor
enum SystemSymbol {
    private static let privateSelector = NSSelectorFromString("imageWithPrivateSystemSymbolName:accessibilityDescription:")

    static func image(_ name: String) -> NSImage? {
        if let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) { return image }
        let images = NSImage.self as AnyObject
        guard images.responds(to: privateSelector) else { return nil }
        return images.perform(privateSelector, with: name, with: nil)?.takeUnretainedValue() as? NSImage
    }

    static func exists(_ name: String) -> Bool { image(name) != nil }

    /// Drawn as a font would draw it, in the foreground's color.
    @ViewBuilder static func glyph(_ name: String, size: CGFloat, weight: NSFont.Weight = .semibold) -> some View {
        if NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil {
            Image(systemName: name).font(.system(size: size, weight: Font.Weight(weight)))
        } else if let image = image(name)?.withSymbolConfiguration(.init(pointSize: size, weight: weight)) {
            Image(nsImage: image).renderingMode(.template)
        }
    }
}

extension Font.Weight {
    init(_ weight: NSFont.Weight) {
        switch weight {
        case .ultraLight: self = .ultraLight
        case .thin: self = .thin
        case .light: self = .light
        case .medium: self = .medium
        case .semibold: self = .semibold
        case .bold: self = .bold
        case .heavy: self = .heavy
        case .black: self = .black
        default: self = .regular
        }
    }
}
