//
//  DevicePictures.swift
//  Glance
//
//  Created by Gaty on 16/10/2026.
//

import AppKit

/// AirPods as macOS pictures them in their settings: rendered as they look, each earbud on its own,
/// or the headphones whole. They're macOS's own, read from where its headphone settings keep them,
/// never copied into Glance; a model they don't cover, or a macOS that keeps them elsewhere, gets
/// its symbol instead.
@MainActor
enum DevicePictures {
    private static let bundle = Bundle(path: "/System/Library/PrivateFrameworks/HeadphoneAssets.framework")
    private static var cache: [String: NSImage] = [:]

    /// The pictures of a model, by its product ID: the left and right earbuds, or the headphones.
    static func names(product: Int) -> [String] {
        switch product {
        // AirPods Pro, and AirPods Pro 2 with Lightning or USB-C, which look alike.
        case 0x200E, 0x2014, 0x2024: ["airpod_left", "airpod_right"]
        // AirPods Pro 3.
        case 0x2027: ["B788_airpod_left", "B788_airpod_right"]
        // AirPods Max, with Lightning or USB-C.
        case 0x200A, 0x201F: ["B515d-Default"]
        // AirPods Max 2.
        case 0x202D: ["B518-Default"]
        default: []
        }
    }

    static func image(_ name: String) -> NSImage? {
        if let image = cache[name] { return image }
        guard let image = bundle?.image(forResource: name) else { return nil }
        cache[name] = image
        return image
    }

    /// Every one of them, or none: half a pair would look broken.
    static func images(_ names: [String]) -> [NSImage]? {
        let images = names.compactMap(image)
        return images.isEmpty || images.count != names.count ? nil : images
    }
}
