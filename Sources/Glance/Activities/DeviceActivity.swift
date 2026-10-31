//
//  DeviceActivity.swift
//  Glance
//
//  Created by Gaty on 31/10/2026.
//

import AppKit
import SwiftUI

/// A device extended under the pointer, as the iPhone's AirPods are in the Dynamic Island, measured
/// from it, by the notch's height, as tall as the Alarm: the device at the left end, what's happened
/// and its name beside it, running on under the camera, and its battery at the right end, a ring
/// around its level.
enum ExpandedDeviceLayout {
    /// The device's middle, from the left end, and how tall it stands.
    static let pictureMiddle: CGFloat = 1.267
    static let picture: CGFloat = 0.97
    /// Where the words start, from the left end.
    static let wordsLeft: CGFloat = 2.667
    /// What's happened, in gray, and the device's name under it, each by its size and its baseline.
    static let said: CGFloat = 0.377
    static let saidBaseline: CGFloat = 1.305
    static let name: CGFloat = 0.461
    static let nameBaseline: CGFloat = 1.855
    static let ring: CGFloat = 1.343
    static let ringLine: CGFloat = 0.113
    static let ringEdge: CGFloat = 0.505
    static let number: CGFloat = 0.45
    static let saidColor = Color(.sRGB, red: 0x74 / 255, green: 0x73 / 255, blue: 0x78 / 255)

    /// Each wing: as wide as the device or the ring, the wider against the camera. The words run under
    /// the camera, so they need no room of their own.
    @MainActor
    static func wing(model: Headphones?, pictures: [String], restingHeight h: CGFloat) -> CGFloat {
        let reach = SystemActivityView.deviceReach(model: model, pictures: pictures, layout: DeviceLayout(height: h, extended: true))
        let gap = LiveActivityView.cameraGap
        return max(h * pictureMiddle + reach + gap, gap + h * (ring + ringEdge))
    }
}

/// A device arriving, sized as the Dynamic Island shows AirPods, by the notch's height: the device
/// a little under half of it tall, its battery's ring a little over half of it across. Each is at
/// its end, as far in from it as from the top and bottom: the device as near as it comes as it
/// turns. There's one of each: as the notch extends they grow into their places, as the cover and
/// the waveform grow into theirs as it opens, and the words fade in as the player's do.
struct DeviceActivityView: View, Animatable {
    let symbol: String
    let model: Headphones?
    let pictures: [String]
    let battery: Int?
    let name: String
    /// Running low, its ring a little larger, with its level in numbers in the middle.
    let low: Bool
    let closedWidth: CGFloat
    let restingHeight: CGFloat
    let leaving: Bool
    let extended: Bool
    /// How far it's grown, step by step: 0 in the wings, 1 extended, a little past that as it bounces.
    var grown: CGFloat

    var animatableData: CGFloat {
        get { grown }
        set { grown = newValue }
    }

    private func mix(_ small: CGFloat, _ large: CGFloat) -> CGFloat { small + (large - small) * grown }

    var body: some View {
        let h = restingHeight
        let small = DeviceLayout(height: h, low: low)
        let large = DeviceLayout(height: h, low: low, extended: true)
        let axis = SystemActivityView.deviceAxis(model: model, pictures: pictures, layout: small)
        let reach = SystemActivityView.deviceReach(model: model, pictures: pictures, layout: small)
        let width = SystemActivityView.deviceWidth(model: model, pictures: pictures, layout: large)
        ZStack {
            picture(height: mix(small.picture, large.picture))
                // Its middle as far in from the end as it reaches, turning, or where the iPhone's is.
                .padding(.leading, mix(small.edge + max(reach - axis, 0), h * ExpandedDeviceLayout.pictureMiddle - width / 2))
                .frame(maxWidth: .infinity, alignment: .leading)
            // Its battery as a ring alone, as AirPods' is: a device that doesn't tell it isn't
            // announced (see `DeviceWatch`).
            if let battery {
                BatteryRing(
                    percent: battery, diameter: mix(small.ring, large.ring), line: mix(small.ringLine, large.ringLine),
                    number: mix(small.number, large.number), numberShown: low ? 1 : min(max(grown, 0), 1)
                )
                .modifier(RingArrival(leaving: leaving))
                .padding(.trailing, mix(small.trailing, large.trailing))
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            words.modifier(PageFade(hidden: !extended))
        }
    }

    @ViewBuilder private func picture(height: CGFloat) -> some View {
        if let model, let turn = DeviceTurn.cached(model) {
            TurningDevice(turn: turn, height: height)
        } else if let images = DevicePictures.images(pictures) {
            StillPictures(images: images, height: height)
        } else {
            StillSymbol(symbol: symbol, side: height)
        }
    }

    /// What's happened and its name, laid out at the size they show at, so they never reflow: the
    /// notch's ends uncover them, from over what's there, moving none of it. They stop short of the
    /// ring.
    private var words: some View {
        let h = restingHeight
        let layout = ExpandedDeviceLayout.self
        let wing = layout.wing(model: model, pictures: pictures, restingHeight: h)
        let ring = h * (layout.ring + layout.ringEdge) + LiveActivityView.cameraGap
        return Color.clear.overlay(alignment: .leading) {
            ZStack(alignment: .topLeading) {
                line(low ? "Low Battery" : "Connected", size: h * layout.said, baseline: h * layout.saidBaseline, color: layout.saidColor)
                line(name, size: h * layout.name, baseline: h * layout.nameBaseline, color: .white)
            }
            .padding(.leading, h * layout.wordsLeft)
            .frame(width: closedWidth + wing * 2 - ring, height: TimerLayout.tallHeight(h), alignment: .topLeading)
        }
    }

    /// A line of words, by where its baseline falls.
    private func line(_ text: String, size: CGFloat, baseline: CGFloat, color: Color) -> some View {
        Text(text)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.top, baseline - NSFont.systemFont(ofSize: size, weight: .semibold).ascender)
    }
}
