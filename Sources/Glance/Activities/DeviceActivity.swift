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
    /// How tall the device stands.
    static let picture: CGFloat = 0.97
    /// What's happened, and the device's name under it, by their baselines: just under the camera.
    static let saidBaseline: CGFloat = 1.35
    static let nameBaseline: CGFloat = 1.88
    static let ringLine: CGFloat = 0.113
    static let number: CGFloat = 0.45

    /// A device extended: at its usual height, or shorter if it would otherwise reach, as it turns,
    /// further across than the ring at the other end, which leaves a wide one clear of the words and
    /// the camera.
    @MainActor
    static func layout(model: Headphones?, pictures: [String], low: Bool, restingHeight h: CGFloat) -> DeviceLayout {
        var layout = DeviceLayout(height: h, low: low, extended: true)
        let across = SystemActivityView.deviceReach(model: model, pictures: pictures, layout: layout) * 2
        layout.fit = min(TimerLayout.content(h) / across, 1)
        return layout
    }

    /// Each wing: as wide as the ring or the device, against the camera. The words run under the
    /// camera, so they need no room of their own.
    static func wing(restingHeight h: CGFloat) -> CGFloat {
        LiveActivityView.cameraGap + TimerLayout.content(h) + PlayerLayout.padding
    }
}

/// A device arriving, sized as the Dynamic Island shows AirPods, by the notch's height: the device
/// a little under half of it tall, its battery's ring a little over half of it across. Each is at
/// its end, as far in from it as from the top and bottom: the device as near as it comes as it
/// turns. There's one of each, laid out as it stands extended and drawn smaller and further out in
/// the wings, so that as the notch extends they grow into their places as a picture does, with no
/// layout to land on whole pixels, as the cover and the waveform grow into theirs as it opens; the
/// words fade in as the player's do.
struct DeviceActivityView: View {
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
    /// The size the notch is going to, less its flares.
    let notch: CGSize
    /// Riding out with the wings' ends as it arrives, from the camera's.
    @State private var arrived = false

    /// How far an end of the notch is from its middle.
    private var toEnd: CGFloat { (arrived || extended ? notch.width : closedWidth) / 2 }

    var body: some View {
        let h = restingHeight
        let small = DeviceLayout(height: h, low: low)
        let large = ExpandedDeviceLayout.layout(model: model, pictures: pictures, low: low, restingHeight: h)
        let axis = SystemActivityView.deviceAxis(model: model, pictures: pictures, layout: small)
        let reach = SystemActivityView.deviceReach(model: model, pictures: pictures, layout: small)
        let smallWidth = SystemActivityView.deviceWidth(model: model, pictures: pictures, layout: small)
        let largeWidth = SystemActivityView.deviceWidth(model: model, pictures: pictures, layout: large)
        // Turning about the middle of its place, as wide as the ring's, from the padding.
        let largeAxis = SystemActivityView.deviceAxis(model: model, pictures: pictures, layout: large)
        let middle = PlayerLayout.padding + TimerLayout.content(h) / 2 - (largeAxis - largeWidth / 2)
        let smallMiddle = small.edge + max(reach - axis, 0) + smallWidth / 2
        let ringScale = small.ring / large.ring
        // Hung from the notch's top middle, which never moves, each is moved out to its end, and
        // follows it there on the notch's own spring, with no layout to land on whole pixels.
        Color.clear.overlay(alignment: .top) {
            ZStack {
                picture(height: large.picture)
                    .frame(width: largeWidth, height: large.picture)
                    .scaleEffect(extended ? 1 : small.picture / large.picture)
                    .offset(x: (extended ? middle : smallMiddle) - toEnd, y: notch.height / 2)
                // Its battery as a ring alone, as AirPods' is: a device that doesn't tell it isn't
                // announced (see `DeviceWatch`).
                if let battery {
                    BatteryRing(
                        percent: battery, diameter: large.ring, line: extended ? large.ringLine : small.ringLine / ringScale,
                        number: large.number, numberScale: extended ? 1 : small.number / large.number / ringScale, numberShown: extended || low
                    )
                    .modifier(RingArrival(leaving: leaving))
                    .scaleEffect(extended ? 1 : ringScale)
                    .offset(x: toEnd - (extended ? large.trailing + large.ring / 2 : small.trailing + small.ring / 2), y: notch.height / 2)
                }
                words.modifier(PageFade(hidden: !extended))
            }
            .frame(width: 0, height: 0)
        }
        .onAppear { withAnimation(IslandMotion.open) { arrived = true } }
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
    /// notch's ends uncover them. They stop short of the ring.
    private var words: some View {
        let h = restingHeight
        let layout = ExpandedDeviceLayout.self
        let wing = layout.wing(restingHeight: h)
        let large = DeviceLayout(height: h, low: low, extended: true)
        let width = closedWidth + wing * 2 - large.ring - large.trailing - LiveActivityView.cameraGap
        return ZStack(alignment: .topLeading) {
            line(low ? "Low Battery" : "Connected", font: NotchType.detail, baseline: h * layout.saidBaseline, color: NotchType.detailColor)
            line(name, font: NotchType.title, baseline: h * layout.nameBaseline, color: .white)
        }
        .padding(.leading, AirDropLayout.wordsStart(h))
        .frame(width: width, height: TimerLayout.tallHeight(h), alignment: .topLeading)
        .offset(x: width / 2 - toEnd, y: notch.height / 2)
    }

    /// A line of words, by where its baseline falls.
    private func line(_ text: String, font: Font, baseline: CGFloat, color: Color) -> some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.top, baseline - NSFont.systemFont(ofSize: NotchType.size, weight: .semibold).ascender)
    }
}
