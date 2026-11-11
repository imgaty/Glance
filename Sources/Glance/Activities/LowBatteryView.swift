//
//  LowBatteryView.swift
//  Glance
//
//  Created by Gaty on 24/10/2026.
//

import AppKit
import SwiftUI

/// Low Power Mode, changed by the approved power helper and read back from macOS.
@MainActor
final class LowPowerMode: ObservableObject {
    static let shared = LowPowerMode()

    @Published private(set) var isOn = ProcessInfo.processInfo.isLowPowerModeEnabled
    @Published private(set) var isChanging = false
    private var watch: NSObjectProtocol?

    private init() {
        watch = NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.isOn = ProcessInfo.processInfo.isLowPowerModeEnabled }
        }
    }

    /// At the bench it's only said, and the Mac's stays as it is (see `ActivityBench`).
    func bench(_ on: Bool) {
        isOn = on
    }

    func toggle() {
        guard !ActivityBench.fakesPower else { return bench(!isOn) }
        guard !isChanging else { return }
        let on = !ProcessInfo.processInfo.isLowPowerModeEnabled
        Activities.shared.keep(.lowBattery, for: 8)
        isChanging = true
        Task {
            defer { isChanging = false }
            _ = await PowerModeSettings.set(on)
            isOn = ProcessInfo.processInfo.isLowPowerModeEnabled
            Activities.shared.keep(.lowBattery, for: 5)
        }
    }

}

/// Low Battery as the iPhone's Dynamic Island shows it, measured from it, by the island's height,
/// as tall as the Alarm: its level beside the camera and the offer to turn on Low Power Mode under it,
/// and at the right end a capsule holding a large battery, a ripple running out of its level. Its colors are the iPhone's own, in Display P3: red, and yellow
/// once Low Power Mode is on.
enum LowBatteryLayout {
    /// From the left end to the words: their letters as far from it as from the top and bottom.
    static let wordsEdge: CGFloat = 0.75
    /// From the words to the capsule, at the least.
    static let wordsGap: CGFloat = 0.33
    /// As tall as the padding leaves, and as wide for that as the iPhone's.
    static func capsule(_ h: CGFloat) -> CGSize {
        CGSize(width: TimerLayout.content(h) * 1.506, height: TimerLayout.content(h))
    }
    /// Centers the complete battery, including the separated cap, inside its capsule.
    static func bodyLeft(_ h: CGFloat) -> CGFloat {
        (capsule(h).width - h * (body.width + capGap + cap.width)) / 2
    }
    static let body = CGSize(width: 1.2, height: 0.645)
    /// The level inside the body, the same gap on three sides.
    static let levelInset: CGFloat = 0.1075
    static let levelHeight: CGFloat = body.height - levelInset * 2
    /// The body's corners, concentric with the level's at its widest, as the iPhone's are.
    static let bodyCorner: CGFloat = levelInset + level(20) / 2
    static let capGap: CGFloat = 0.055
    static let cap = CGSize(width: 0.073, height: 0.22)
    /// The ripple's line.
    static let ringLine: CGFloat = 0.05
    /// How long a ripple takes, in seconds, one after another; and how far into one it arrives.
    static let ripple = 2.0
    static let rippleStart = 0.3

    /// The ripple, second by second, measured frame by frame from the iPhone. How pale the level is,
    /// 1 at its palest; how much of the line shows; and how far it's gone out from the level's middle,
    /// sideways and up, from around the level to a circle.
    static let pale: [(CGFloat, CGFloat)] = [
        (0, 0.21), (0.1, 0.85), (0.2, 1), (0.7, 1), (0.8, 0.94), (0.9, 0.81), (1, 0.66), (1.1, 0.55), (1.2, 0.43), (1.3, 0.32), (1.4, 0.21),
        (1.5, 0.13), (1.6, 0.04), (1.8, 0), (1.93, 0), (2, 0.21),
    ]
    static let line: [(CGFloat, CGFloat)] = [
        (0, 0), (0.1, 0.8), (0.2, 0.9), (0.3, 1), (0.6, 1), (0.7, 0.8), (0.8, 0.59), (0.9, 0.42), (1, 0.3), (1.1, 0.2), (1.25, 0),
    ]
    static let across: [(CGFloat, CGFloat)] = [
        (0.1, 0.198), (0.2, 0.234), (0.3, 0.27), (0.4, 0.324), (0.5, 0.36), (0.6, 0.396), (0.7, 0.414), (0.8, 0.45), (0.9, 0.477), (1, 0.505),
        (1.1, 0.523), (1.25, 0.55),
    ]
    static let up: [(CGFloat, CGFloat)] = [
        (0.1, 0.306), (0.2, 0.324), (0.3, 0.36), (0.4, 0.378), (0.5, 0.414), (0.6, 0.432), (0.7, 0.45), (0.8, 0.468), (0.9, 0.486), (1, 0.505),
        (1.1, 0.523), (1.25, 0.55),
    ]

    /// Where a curve is at that point of the ripple, in a line between what was measured.
    static func along(_ curve: [(CGFloat, CGFloat)], at time: CGFloat) -> CGFloat {
        guard let last = curve.last, let first = curve.first else { return 0 }
        if time <= first.0 { return first.1 }
        if time >= last.0 { return last.1 }
        let after = curve.firstIndex { $0.0 > time } ?? curve.count - 1
        let (a, b) = (curve[after - 1], curve[after])
        return a.1 + (b.1 - a.1) * (time - a.0) / (b.0 - a.0)
    }

    /// How wide the level is, as the iPhone's are at 10% and at 20%, the only times it shows.
    static func level(_ percent: Int) -> CGFloat { 0.181 + 0.0026 * CGFloat(percent) }

    /// How far into a ripple it is, so long after it showed.
    static func rippleTime(after seconds: TimeInterval) -> CGFloat {
        CGFloat((max(seconds, 0) + rippleStart).truncatingRemainder(dividingBy: ripple))
    }

    /// How the words under the level and the battery change as Low Power Mode is switched: what
    /// shows fades out, and what comes fades in as it goes.
    static let change = AnyTransition.asymmetric(
        insertion: .opacity.animation(.easeOut(duration: 0.25).delay(0.15)),
        removal: .opacity.animation(.easeIn(duration: 0.2)))

    /// The words under the level, as the iPhone's, and once Low Power Mode is on.
    static let offerColor = Color.p3(0x6E, 0x6E, 0x6E)
    static let doneColor = Color.p3(0xE1, 0xC8, 0x78)

    /// Each part's color: the capsule, the battery's body and cap, and the level.
    struct Shade {
        let capsule: Color
        let body: Color
        let level: Color
    }
    static let red = Shade(capsule: .p3(0x2F, 0x10, 0x0F), body: .p3(0x7A, 0x29, 0x2A), level: BatteryColor.red)
    static let yellow = Shade(capsule: BatteryColor.yellow, body: .black, level: BatteryColor.yellow)
    /// The level at its palest, and the ripple's line.
    static let paleLevel = Color.p3(0xEE, 0x8A, 0x9D)
    static let ringColor = Color.p3(0xE1, 0x5E, 0x64)

    @MainActor
    static func width(_ text: String) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: NotchType.size, weight: .semibold)]).width)
    }

    /// Each wing: the capsule, or the level, against the camera, or wider, should the offer, running
    /// on beneath the camera, otherwise reach the capsule.
    @MainActor
    static func wing(percent: Int, restingHeight h: CGFloat, closedWidth: CGFloat) -> CGFloat {
        let right = capsule(h).width + PlayerLayout.padding
        let left = h * wordsEdge + width(LowBatteryView.title(percent))
        let words = max(width(LowBatteryView.offer), width(LowBatteryView.done))
        return max(LiveActivityView.cameraGap + max(left, right), (h * wordsEdge + words + h * wordsGap + right - closedWidth) / 2)
    }
}

/// Low Battery, as the iPhone's, as tall as the Alarm: its level and an offer to turn on Low Power
/// Mode under it, and the battery, large, in a capsule at the right end, a ripple running out of its
/// level every two seconds as the level flashes pale; clicked, Low Power Mode comes on, everything
/// turns yellow and stops, and it says so; clicked again, it goes off. With Reduce Motion on, there's
/// no ripple.
struct LowBatteryView: View {
    let percent: Int
    let restingHeight: CGFloat
    /// The pointer is on the capsule.
    let hovered: Bool
    @ObservedObject private var lowPower = LowPowerMode.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// When it showed, which its ripples count from.
    @State private var shownAt = Date.now

    static func title(_ percent: Int) -> String { String(localized: "\(percent.formatted(.percent)) Battery") }
    static let offer = String(localized: "Click to turn on Low Power Mode")
    static let done = String(localized: "Low Power Mode enabled")

    var body: some View {
        let h = restingHeight
        let on = lowPower.isOn
        let layout = LowBatteryLayout.self
        ZStack {
            VStack(alignment: .leading, spacing: 0) {
                Text(Self.title(percent))
                    .foregroundStyle(.white)
                ZStack(alignment: .leading) {
                    if on {
                        Text(Self.done).foregroundStyle(layout.doneColor).transition(layout.change)
                    } else {
                        Text(Self.offer).foregroundStyle(layout.offerColor).transition(layout.change)
                    }
                }
            }
            .font(NotchType.title)
            .lineLimit(1)
            .fixedSize()
            .padding(.leading, h * layout.wordsEdge)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: TimerLayout.tallHeight(h))
            .accessibilityElement(children: .combine)
            ZStack {
                if on {
                    capsule(h, on: true).transition(layout.change)
                } else {
                    capsule(h, on: false).transition(layout.change)
                }
            }
            .reportsFrame(.lowPower)
            .spokenButton(on ? String(localized: "Turn off Low Power Mode") : String(localized: "Turn on Low Power Mode")) { LowPowerMode.shared.toggle() }
            .disabled(lowPower.isChanging)
            .padding(.trailing, PlayerLayout.padding)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(maxHeight: .infinity)
    }

    /// The battery, large, in its capsule, as the iPhone draws it: the body, the level bright and
    /// glowing a little, the cap apart. Its ripple starts wrapped around the level and runs out into a
    /// circle, fading, past the level, as the level flashes pale and settles back. With Low Power Mode
    /// on it's all still: a yellow capsule, a black battery, a yellow level.
    private func capsule(_ h: CGFloat, on: Bool) -> some View {
        let layout = LowBatteryLayout.self
        let level = layout.level(percent)
        // The ripple's middle, from the body's left end: the level's.
        let ringMiddle = layout.levelInset + level / 2
        let shade = on ? layout.yellow : layout.red
        return TimelineView(.animation(paused: on || reduceMotion)) { context in
            // Between ripples, for what doesn't ripple.
            let time = on || reduceMotion ? 1.8 : layout.rippleTime(after: context.date.timeIntervalSince(shownAt))
            let across = layout.along(layout.across, at: time)
            let fill = on ? shade.level : shade.level.mix(with: layout.paleLevel, by: layout.along(layout.pale, at: time))
            HStack(spacing: h * layout.capGap) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: h * layout.bodyCorner, style: .continuous)
                        .fill(shade.body)
                    Capsule(style: .continuous)
                        .fill(fill)
                        .frame(width: h * level, height: h * layout.levelHeight)
                        .shadow(color: on ? .clear : fill.opacity(0.5), radius: h * 0.04)
                        .padding(.leading, h * layout.levelInset)
                }
                .frame(width: h * layout.body.width, height: h * layout.body.height)
                // Over the battery, outside its layout, so it never sizes it.
                .overlay(alignment: .leading) {
                    Capsule()
                        .stroke(layout.ringColor, lineWidth: h * layout.ringLine)
                        .frame(width: h * across * 2, height: h * layout.along(layout.up, at: time) * 2)
                        .opacity(on ? 0 : layout.along(layout.line, at: time))
                        .offset(x: h * (ringMiddle - across))
                }
                Ellipse()
                    .fill(shade.body)
                    .frame(width: h * layout.cap.width, height: h * layout.cap.height)
            }
            .padding(.leading, layout.bodyLeft(h))
            .frame(width: layout.capsule(h).width, height: layout.capsule(h).height, alignment: .leading)
            .background(Capsule(style: .continuous).fill(hovered ? shade.capsule.mix(with: .white, by: 0.08) : shade.capsule))
        }
        .animation(.easeOut(duration: 0.15), value: hovered)
    }
}
