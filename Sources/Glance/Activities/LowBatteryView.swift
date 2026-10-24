//
//  LowBatteryView.swift
//  Glance
//
//  Created by Gaty on 24/10/2026.
//

import AppKit
import SwiftUI

/// Low Power Mode, which Low Battery's button turns on, as the iPhone's does: through macOS's own
/// switch, the one Control Center and Battery settings use, which has no public way in, and read
/// back from macOS. Should macOS not turn it on, Battery settings open, where it can be.
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

    func turnOn() {
        guard !ProcessInfo.processInfo.isLowPowerModeEnabled else { return }
        Self.setPowerMode(1)
        Task {
            try? await Task.sleep(for: .seconds(2))
            guard !ProcessInfo.processInfo.isLowPowerModeEnabled else { return }
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

/// Low Battery as the iPhone's Dynamic Island shows it, measured from it, by the island's height:
/// as tall as the Alarm, its level and an offer to turn on Low Power Mode at the left end, and at
/// the right a capsule holding a large battery, a ring pulsing around its level. Red, and green
/// once Low Power Mode is on.
enum LowBatteryLayout {
    static let words: CGFloat = 0.425
    /// Between the level and the offer, as the iPhone sets them.
    static let lineGap: CGFloat = 0.055
    static let capsule = CGSize(width: 2.32, height: 1.55)
    static let body = CGSize(width: 1.06, height: 0.64)
    static let bodyCorner: CGFloat = 0.135
    /// The level inside the body, never narrower than at 10%, as the iPhone's.
    static let levelInset: CGFloat = 0.1
    static let levelTop: CGFloat = 0.09
    static let leastLevel: CGFloat = 0.21
    static let capGap: CGFloat = 0.2
    static let cap = CGSize(width: 0.055, height: 0.23)
    static let ring: CGFloat = 1.0
    static let ringLine: CGFloat = 0.036
    /// How long the ring takes to pulse, in seconds; and how long, arriving, it takes to settle
    /// from its reddish yellow into red.
    static let pulse = 1.2
    static let warmUp = 2.4

    static let red = Color(red: 0.94, green: 0.34, blue: 0.3)
    static let redLevel = Color(red: 1, green: 0x72 / 255, blue: 0x84 / 255)
    static let amber = Color(red: 1, green: 0.62, blue: 0.24)
    static let amberLevel = Color(red: 1, green: 0.84, blue: 0.56)
    static let green = Color(red: 0.3, green: 0.85, blue: 0.42)
    static let greenLevel = Color(red: 0.64, green: 0.95, blue: 0.7)

    /// The capsule as far in from the right end as from the top and bottom, concentric with it; the
    /// words as far in from the left.
    static func edge(_ h: CGFloat) -> CGFloat { LiveActivityView.concentric(h * capsule.height, in: TimerLayout.tallHeight(h)) }

    /// Each wing: as wide as the wider side, the words or the capsule, each from its end.
    @MainActor
    static func wing(percent: Int, restingHeight h: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: h * words, weight: .semibold)
        let widest = [LowBatteryView.title(percent), LowBatteryView.offer, LowBatteryView.done]
            .map { ceil(($0 as NSString).size(withAttributes: [.font: font]).width) }.max() ?? 0
        let gap = LiveActivityView.cameraGap
        return max(edge(h) + widest + gap, gap + h * capsule.width + edge(h))
    }
}

/// Low Battery, as tall as the Alarm, as the iPhone's: its level and an offer to turn on Low Power
/// Mode at the left end, and the battery, large, in a capsule at the right, a ring pulsing around
/// its level, settling from a reddish yellow into red; clicked, Low Power Mode comes on, everything
/// turns green and stops pulsing, and it says so. With Reduce Motion on, it's red at once and
/// doesn't pulse.
struct LowBatteryView: View {
    let percent: Int
    let restingHeight: CGFloat
    /// Each wing's width beside the camera (see `LowBatteryLayout.wing`).
    var wing: CGFloat = 0
    /// The pointer is on the capsule.
    let hovered: Bool
    @ObservedObject private var lowPower = LowPowerMode.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// When it showed, which its colors settle from.
    @State private var shownAt = Date.now

    static func title(_ percent: Int) -> String { "\(percent)% Battery" }
    static let offer = "Click to turn on Low Power Mode"
    static let done = "Low Power Mode On"

    var body: some View {
        let h = restingHeight
        let on = lowPower.isOn
        let edge = LowBatteryLayout.edge(h)
        let gap = LiveActivityView.cameraGap
        ZStack {
            VStack(alignment: .leading, spacing: h * LowBatteryLayout.lineGap) {
                Text(Self.title(percent))
                    .foregroundStyle(.white)
                // One blurring into the other, as the island's words change.
                Group {
                    if on {
                        Text(Self.done).foregroundStyle(LowBatteryLayout.green)
                    } else {
                        Text(Self.offer).foregroundStyle(.white.opacity(0.5))
                    }
                }
                .transition(.blurReplace)
            }
            .font(.system(size: h * LowBatteryLayout.words, weight: .semibold))
            .lineLimit(1)
            .frame(width: max(wing - edge - gap, 0), alignment: .leading)
            .padding(.leading, edge)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            capsule(h, on: on)
                .reportsFrame(.lowPower)
                .spokenButton(on ? Self.done : "Turn on Low Power Mode") { LowPowerMode.shared.turnOn() }
                .padding(.trailing, edge)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.3), value: on)
    }

    /// The battery, large, in its capsule: the body faint, the level bright and glowing, the cap
    /// apart, and the ring around the level. Arriving, it pulses from a reddish yellow into a soft
    /// red, as the iPhone's does, and goes on breathing.
    private func capsule(_ h: CGFloat, on: Bool) -> some View {
        let body = LowBatteryLayout.body, cap = LowBatteryLayout.cap
        let inner = body.width - LowBatteryLayout.levelInset * 2
        let level = max(inner * CGFloat(percent) / 100, LowBatteryLayout.leastLevel)
        let levelHeight = body.height - LowBatteryLayout.levelTop * 2
        // The ring's middle, from the battery's left end: the level's.
        let ringMiddle = LowBatteryLayout.levelInset + level / 2
        return TimelineView(.animation(paused: on || reduceMotion)) { context in
            let t = context.date.timeIntervalSince(shownAt)
            let warm = reduceMotion ? 1 : Self.warming(after: t)
            let pulse = on || reduceMotion ? 1 : Self.pulse(at: context.date)
            // Each beat brightens it, less as it settles into red.
            let beat = on || reduceMotion ? 0 : (1 - pulse) * (1 - warm * 0.6)
            let tint = on ? LowBatteryLayout.green : LowBatteryLayout.amber.mix(with: LowBatteryLayout.red, by: warm)
            let bright = on ? LowBatteryLayout.greenLevel : LowBatteryLayout.amberLevel.mix(with: LowBatteryLayout.redLevel, by: warm)
            HStack(spacing: h * LowBatteryLayout.capGap) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: h * LowBatteryLayout.bodyCorner, style: .continuous)
                        .fill(tint.opacity(0.45 + 0.1 * beat))
                    Capsule()
                        .fill(bright)
                        .frame(width: h * level, height: h * levelHeight)
                        .shadow(color: bright.opacity(0.7), radius: h * 0.08)
                        .padding(.leading, h * LowBatteryLayout.levelInset)
                }
                .frame(width: h * body.width, height: h * body.height)
                // Over the battery, outside its layout, so it never sizes it.
                .overlay(alignment: .leading) {
                    Circle()
                        .fill(tint.opacity(0.08))
                        .strokeBorder(tint.opacity(0.45), lineWidth: h * LowBatteryLayout.ringLine)
                        .frame(width: h * LowBatteryLayout.ring, height: h * LowBatteryLayout.ring)
                        .scaleEffect(0.92 + 0.1 * pulse)
                        .opacity(on ? 0 : 0.6 + 0.4 * pulse)
                        .offset(x: h * (ringMiddle - LowBatteryLayout.ring / 2))
                }
                Capsule()
                    .fill(tint.opacity(0.45))
                    .frame(width: h * cap.width, height: h * cap.height)
            }
            .frame(width: h * LowBatteryLayout.capsule.width, height: h * LowBatteryLayout.capsule.height)
            .background(Capsule().fill(tint.opacity((hovered ? 0.34 : 0.26) + 0.12 * beat)))
        }
        .animation(.easeOut(duration: 0.15), value: hovered)
    }

    /// From its reddish yellow, 0, to its soft red, 1, over its first pulses, easing in and out.
    static func warming(after t: TimeInterval) -> CGFloat {
        let x = min(max(t / LowBatteryLayout.warmUp, 0), 1)
        return x * x * (3 - 2 * x)
    }

    /// 0 to 1 and back, gently, once a pulse.
    static func pulse(at date: Date) -> CGFloat {
        (1 + cos(date.timeIntervalSinceReferenceDate * 2 * .pi / LowBatteryLayout.pulse)) / 2
    }
}
