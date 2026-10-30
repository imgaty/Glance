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

    /// The pictures of a model, by its product ID: the left and right earbuds, or the headphones,
    /// of the model macOS knows it as, or the nearest it's a kind of.
    static func names(product: Int) -> [String] {
        SystemDevices.lineage(product: product).lazy.compactMap { pictures[$0] }.first ?? []
    }

    /// Each set of pictures by the type macOS declares for the model. AirPods Pro 2 are a kind of
    /// AirPods Pro, and look alike; AirPods Max 2024 a kind of AirPods Max.
    private static let pictures: [String: [String]] = [
        "com.apple.airpods-pro": ["airpod_left", "airpod_right"],
        "com.apple.airpods-pro-2025": ["B788_airpod_left", "B788_airpod_right"],
        "com.apple.airpods-max": ["B515d-Default"],
        "com.apple.airpods-max-2": ["B518-Default"],
    ]

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
