//
//  ExpandedDevice.swift
//  Glance
//
//  Created by Gaty on 31/10/2026.
//

import AppKit
import SwiftUI

/// A device arriving, extended under the pointer, as the iPhone's AirPods are in the Dynamic Island,
/// measured from it, by the notch's height, as tall as the Alarm: the device at the left end, what's
/// happened and its name beside it, running on under the camera, and its battery at the right end, a
/// ring around its level.
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
    static let green = Color(.sRGB, red: 0x45 / 255, green: 0xE2 / 255, blue: 0x74 / 255)
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

struct ExpandedDeviceView: View {
    let symbol: String
    let model: Headphones?
    let pictures: [String]
    let battery: Int?
    let name: String
    /// What's happened: that it's connected, or running low.
    let said: String
    let restingHeight: CGFloat

    var body: some View {
        let h = restingHeight
        let layout = ExpandedDeviceLayout.self
        let tall = TimerLayout.tallHeight(h)
        ZStack(alignment: .topLeading) {
            picture(h)
                .frame(width: h * layout.pictureMiddle * 2, height: tall)
            words(said, size: h * layout.said, weight: .semibold, baseline: h * layout.saidBaseline, color: layout.saidColor, h)
            words(name, size: h * layout.name, weight: .semibold, baseline: h * layout.nameBaseline, color: .white, h)
            if let battery {
                ring(battery, h)
                    .padding(.trailing, h * layout.ringEdge)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private func picture(_ h: CGFloat) -> some View {
        let height = h * ExpandedDeviceLayout.picture
        if let model, let turn = DeviceTurn.cached(model) {
            TurningDevice(turn: turn, height: height)
        } else if let images = DevicePictures.images(pictures) {
            TurningPictures(images: images, height: height)
        } else {
            TurningSymbol(symbol: symbol, side: height)
        }
    }

    /// A line of words, by where its baseline falls. It stops short of the ring.
    private func words(_ text: String, size: CGFloat, weight: NSFont.Weight, baseline: CGFloat, color: Color, _ h: CGFloat) -> some View {
        let layout = ExpandedDeviceLayout.self
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        return Text(text)
            .font(.system(size: size, weight: weight == .bold ? .bold : .semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.top, baseline - font.ascender)
            .padding(.leading, h * layout.wordsLeft)
            .padding(.trailing, h * (layout.ring + layout.ringEdge) + LiveActivityView.cameraGap)
    }

    /// The ring around its level, as the iPhone's: green, or red at 20% and below.
    private func ring(_ percent: Int, _ h: CGFloat) -> some View {
        let layout = ExpandedDeviceLayout.self
        let side = h * layout.ring, line = h * layout.ringLine
        let color = percent <= 20 ? Color.red : layout.green
        return ZStack {
            Circle().stroke(color.opacity(0.3), lineWidth: line)
            Circle()
                .trim(from: 0, to: CGFloat(percent) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(percent)")
                .font(.system(size: h * layout.number, weight: .heavy))
                .foregroundStyle(color)
        }
        .padding(line / 2)
        .frame(width: side, height: side)
    }
}
