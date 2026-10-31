//
//  LowBatteryView.swift
//  Glance
//
//  Created by Gaty on 24/10/2026.
//

import AppKit
import SwiftUI

/// Low Power Mode, which Low Battery's button turns on and off: through macOS's own switch, the one
/// Control Center and Battery settings use, which has no public way in, and read back from macOS.
/// Should macOS not change it, Battery settings open, where it can be.
@MainActor
final class LowPowerMode: ObservableObject {
    static let shared = LowPowerMode()

    @Published private(set) var isOn = ProcessInfo.processInfo.isLowPowerModeEnabled
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
        let on = !ProcessInfo.processInfo.isLowPowerModeEnabled
        Self.setPowerMode(on ? 1 : 0)
        Task {
            try? await Task.sleep(for: .seconds(2))
            guard ProcessInfo.processInfo.isLowPowerModeEnabled != on else { return }
            NSWorkspace.shared.open(Self.settings)
        }
    }

    /// Battery settings, where Low Power Mode is chosen.
    static let settings = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension")!

    /// macOS's own switch, in its Low Power Mode framework: 1 on, 0 off.
    private static func setPowerMode(_ mode: Int) {
        let selector = NSSelectorFromString("setPowerMode:fromSource:withCompletion:")
        guard dlopen("/System/Library/PrivateFrameworks/LowPowerMode.framework/LowPowerMode", RTLD_LAZY) != nil,
            let type = NSClassFromString("_PMLowPowerMode") as? NSObject.Type,
            let shared = type.perform(NSSelectorFromString("sharedInstance"))?.takeUnretainedValue(),
            shared.responds(to: selector), let method = class_getInstanceMethod(type, selector)
        else { return }
        typealias Set = @convention(c) (AnyObject, Selector, Int, NSString, @escaping @convention(block) (Bool, NSError?) -> Void) -> Void
        let set = unsafeBitCast(method_getImplementation(method), to: Set.self)
        set(shared, selector, mode, "Glance", { _, _ in })
    }
}

/// Low Battery as the iPhone's Dynamic Island shows it, measured from it, by the island's height,
/// as tall as the Alarm: its level and the offer to turn on Low Power Mode under it, below the camera,
/// and at the right end a capsule holding a large battery, a ripple running out of its level. Its colors are the iPhone's own, in Display P3: red, and yellow
/// once Low Power Mode is on.
enum LowBatteryLayout {
    /// From the left end to the words, as on the iPhone: they're low enough to meet the corner, and
    /// this leaves them the padding from its curve. And from them to the capsule, at the least.
    static let wordsEdge: CGFloat = 0.88
    static let wordsGap: CGFloat = 0.33
    /// As tall as the padding leaves, and as wide for that as the iPhone's.
    static func capsule(_ h: CGFloat) -> CGSize {
        CGSize(width: TimerLayout.content(h) * 1.506, height: TimerLayout.content(h))
    }
    /// The battery in the capsule, a little right of its middle, as the iPhone sets it.
    static let bodyLeft: CGFloat = 0.54
    static let body = CGSize(width: 1.2, height: 0.645)
    static let bodyCorner: CGFloat = 0.19
    /// The level inside the body.
    static let levelInset: CGFloat = 0.105
    static let levelHeight: CGFloat = 0.45
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

    /// How the words under the level change, and how long it takes.
    static func change(_ h: CGFloat) -> AnyTransition {
        let blur = AnyTransition(.blurReplace)
        return .asymmetric(
            insertion: blur.combined(with: .offset(y: h * 0.3)),
            removal: blur.combined(with: .offset(y: -h * 0.3)))
    }
    static let changeTime = 0.45

    /// The words under the level, as the iPhone's, and once Low Power Mode is on.
    static let offerColor = Color.p3(0x6E, 0x6E, 0x6E)
    static let doneColor = Color.p3(0xE1, 0xC8, 0x78)

    /// Each part's color: the capsule, the battery's body and cap, and the level.
    struct Shade {
        let capsule: Color
        let body: Color
        let level: Color
    }
    static let red = Shade(capsule: .p3(0x2F, 0x10, 0x0F), body: .p3(0x7A, 0x29, 0x2A), level: .p3(0xEB, 0x5B, 0x5F))
    static let yellow = Shade(capsule: .p3(0xF5, 0xC8, 0x51), body: .black, level: .p3(0xF5, 0xC8, 0x51))
    /// The level at its palest, and the ripple's line.
    static let paleLevel = Color.p3(0xEE, 0x8A, 0x9D)
    static let ringColor = Color.p3(0xE1, 0x5E, 0x64)

    /// From the top to the level's line, with its letters just below the camera, as a device's words
    /// are, the offer as far under it.
    static func wordsTop(_ h: CGFloat) -> CGFloat {
        h * ExpandedDeviceLayout.saidBaseline - NSFont.systemFont(ofSize: NotchType.size, weight: .semibold).ascender
    }

    /// Between the two lines' boxes, for their baselines to be as far apart as a device's.
    static func lineGap(_ h: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: NotchType.size, weight: .semibold)
        return h * (ExpandedDeviceLayout.nameBaseline - ExpandedDeviceLayout.saidBaseline) + font.descender - font.ascender
    }

    @MainActor
    static func width(_ text: String) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: NotchType.size, weight: .semibold)]).width)
    }

    /// Each wing: the capsule against the camera, or wider, should the words otherwise run into it.
    @MainActor
    static func wing(percent: Int, restingHeight h: CGFloat, closedWidth: CGFloat) -> CGFloat {
        let right = capsule(h).width + PlayerLayout.padding
        let words = max(width(LowBatteryView.title(percent)), width(LowBatteryView.offer), width(LowBatteryView.done))
        return max(LiveActivityView.cameraGap + right, (h * wordsEdge + words + h * wordsGap + right - closedWidth) / 2)
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

    static func title(_ percent: Int) -> String { "\(percent)% Battery" }
    static let offer = "Click to turn on Low Power Mode"
    static let done = "Low Power Mode enabled"

    var body: some View {
        let h = restingHeight
        let on = lowPower.isOn
        let layout = LowBatteryLayout.self
        ZStack {
            VStack(alignment: .leading, spacing: layout.lineGap(h)) {
                Text(Self.title(percent))
                    .foregroundStyle(.white)
                // One rising into the other's place, each blurred on its way, as the island's words change.
                ZStack(alignment: .leading) {
                    if on {
                        Text(Self.done).foregroundStyle(layout.doneColor).transition(layout.change(h))
                    } else {
                        Text(Self.offer).foregroundStyle(layout.offerColor).transition(layout.change(h))
                    }
                }
                .animation(.easeInOut(duration: layout.changeTime), value: on)
            }
            .font(NotchType.title)
            .lineLimit(1)
            .fixedSize()
            .padding(.top, layout.wordsTop(h))
            .padding(.leading, h * layout.wordsEdge)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: TimerLayout.tallHeight(h), alignment: .top)
            .accessibilityElement(children: .combine)
            capsule(h, on: on)
                .reportsFrame(.lowPower)
                .spokenButton(on ? "Turn off Low Power Mode" : "Turn on Low Power Mode") { LowPowerMode.shared.toggle() }
                .padding(.trailing, PlayerLayout.padding)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.3), value: on)
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
            .padding(.leading, h * layout.bodyLeft)
            .frame(width: layout.capsule(h).width, height: layout.capsule(h).height, alignment: .leading)
            .background(Capsule(style: .continuous).fill(hovered ? shade.capsule.mix(with: .white, by: 0.08) : shade.capsule))
        }
        .animation(.easeOut(duration: 0.15), value: hovered)
    }
}
