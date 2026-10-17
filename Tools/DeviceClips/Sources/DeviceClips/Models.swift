//
//  Models.swift
//  DeviceClips
//
//  Created by Gaty on 17/10/2026.
//

import Foundation

/// A device Glance shows turning as it connects, and where its maker's own 3D model is.
struct Model {
    /// The clip's name in Resources/Headphones, as Glance asks for it.
    let name: String
    let url: URL
    let kind: Kind
    /// How bright its middle tones are, of 255: as the iPhone shows white AirPods, or, black, as
    /// bright as reads on the black notch while still black.
    let brightness: CGFloat?
    /// How close a pair's earbuds stand, of how far apart the model stands them: as the iPhone shows
    /// AirPods, or further for earbuds with wings that would touch.
    var spacing: Double = 0.83

    enum Kind {
        /// Two earbuds, taken from beside their case, side by side, facing you.
        case pair
        /// Two earbuds made of one of them and its mirror image, for a model that shows the other one
        /// lying in its case.
        case mirrored(left: Bool)
        /// The whole thing, as it stands: headphones, a neckband, a speaker.
        case whole
    }
}

private let apple = "https://www.apple.com/105/media/us"
/// Black devices' middle tones, of 255: black, but readable on the black notch.
private let black: CGFloat = 70
private let beats = "https://www.beatsbydre.com/content/dam/beats/web/product"

private func model(_ name: String, _ url: String, _ kind: Model.Kind, brightness: CGFloat? = nil, spacing: Double = 0.83) -> Model {
    Model(name: name, url: URL(string: url)!, kind: kind, brightness: brightness, spacing: spacing)
}

let models: [Model] = [
    // Apple's, from the AirPods pages' "View in AR".
    model("airpods-pro", "\(apple)/airpods-pro/2021/8d0b339b-f0f9-4522-aaa5-e047097ea8ec/ar/airpods_pro_ios15.usdz", .pair, brightness: 198),
    model(
        "airpods-pro-2", "\(apple)/airpods-pro/2022/d2deeb8e-83eb-48ea-9721-f567cf0fffa8/ar/airpods_pro_with_magsafe_charging_case_ios15.usdz",
        .pair, brightness: 198),
    model("airpods-pro-3", "\(apple)/airpods-pro/2025/7acffb13-4adb-40b1-9393-8f1c99bc6c90/ar/airpods-pro.usdz", .pair, brightness: 198),
    model(
        "airpods-3", "\(apple)/airpods-3rd-generation/2021/3c0b27aa-a5fe-4365-a9ae-83c28d10fa21/ar/airpods_magsafe_charging_ios15.usdz", .pair,
        brightness: 198),
    model("airpods-4", "\(apple)/airpods-5/2026/1bae77a6-82ef-46c2-875f-571e880dbfe2/ar/airpods-mid.usdz", .pair, brightness: 198),
    // Beats', from their product pages' 3D views, in black.
    model("beats-solo-buds", "\(beats)/earbuds/solo-buds/global/3d/solobuds_black.usdz", .pair, brightness: black),
    model("beats-studio-buds-plus", "\(beats)/earbuds/studio-buds-plus/global/3d/studio-buds-plus-blackgold.usdz", .pair, brightness: black),
    model(
        "powerbeats-pro-2", "\(beats)/earbuds/powerbeats-pro-2/pdp/product-carousel/jet-black/3d/pbpro2-jet-black-p02.usdz", .pair,
        brightness: black),
    model(
        "powerbeats-fit", "\(beats)/earbuds/powerbeats-fit/pdp/product-carousel/black/3d/pbfit-black-3d.usdz", .mirrored(left: true),
        brightness: black, spacing: 1.25),
    model("beats-flex", "\(beats)/earbuds/beats-flex/global/3d/flex-white.usdz", .whole, brightness: 198),
    model("beats-solo-4", "\(beats)/headphones/solo4-wireless/global/3d/solo4-matteblack.usdz", .whole, brightness: black),
    model("beats-studio-pro", "\(beats)/headphones/studiopro-wireless/global/3d/studio-pro-black.usdz", .whole, brightness: black),
    model("beats-360", "\(beats)/headphones/beats-360/pdp/product-carousel/black/3d/pc-beats-360-3d.usdz", .whole, brightness: black),
    model("beats-pill", "\(beats)/speakers/beats-pill/global/3d/beats-pill-black.usdz", .whole, brightness: black),
]
