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

/// Low Battery as the iPhone's Dynamic Island shows it, by the island's height: taller than the
/// notch, its row just below the camera, a round button with the battery in red at the left, its
/// level and what the button does beside it.
enum LowBatteryLayout {
    static let title: CGFloat = 0.5
    static let subtitle: CGFloat = 0.42
    /// Between the button and the words.
    static let gap: CGFloat = 0.32
    /// The battery in the button, by the notch's height.
    static let battery: CGFloat = 0.36
    /// How long the battery takes to pulse, in seconds.
    static let pulse = 1.6

    /// How far in the button sits from the end and the bottom: the same, so it's concentric with
    /// the round corner, as the timer's buttons are.
    static func edge(_ h: CGFloat) -> CGFloat { h * (TimerLayout.corner - TimerLayout.button / 2) }

    static func height(_ h: CGFloat) -> CGFloat {
        (h + LiveActivityView.cameraGap + h * TimerLayout.button + edge(h)).rounded()
    }

    /// As wide as the iPhone's expanded activities, or as its words need.
    @MainActor
    static func width(percent: Int, restingHeight h: CGFloat) -> CGFloat {
        func width(_ text: String, _ size: CGFloat) -> CGFloat {
            ceil((text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: h * size, weight: .semibold)]).width)
        }
        let words = max(width(LowBatteryView.title(percent), title), width(LowBatteryView.offer, subtitle), width(LowBatteryView.done, subtitle))
        return max(h * TimerLayout.wide, edge(h) * 2 + h * (TimerLayout.button + gap) + words)
    }
}

/// Low Battery, taller than the notch, as the iPhone's: the battery in a round button, red and
/// pulsing, beside its level and an offer to turn on Low Power Mode. Clicked, Low Power Mode comes
/// on, the battery turns green and stops pulsing, and it says so in green. With Reduce Motion on,
/// it doesn't pulse.
struct LowBatteryView: View {
    let percent: Int
    let restingHeight: CGFloat
    /// The pointer is on the button.
    let hovered: Bool
    @ObservedObject private var lowPower = LowPowerMode.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static func title(_ percent: Int) -> String { "\(percent)% Battery" }
    static let offer = "Click to turn on Low Power Mode"
    static let done = "Low Power Mode On"

    var body: some View {
        let h = restingHeight
        let on = lowPower.isOn
        let tint: Color = on ? .green : .red
        let edge = LowBatteryLayout.edge(h)
        HStack(spacing: h * LowBatteryLayout.gap) {
            TimelineView(.animation(paused: on || reduceMotion)) { context in
                let pulse = on || reduceMotion ? 1 : Self.pulse(at: context.date)
                IslandCircle(height: h, tint: tint, highlighted: hovered) {
                    BatteryGlyph(level: BatteryLevel(percent: percent, charging: false), color: tint, height: h * LowBatteryLayout.battery)
                        .opacity(0.5 + 0.5 * pulse)
                }
            }
            .reportsFrame(.lowPower)
            .spokenButton(on ? Self.done : "Turn on Low Power Mode") { LowPowerMode.shared.turnOn() }
            VStack(alignment: .leading, spacing: 1) {
                Text(Self.title(percent))
                    .font(.system(size: h * LowBatteryLayout.title, weight: .semibold))
                    .foregroundStyle(.white)
                // One blurring into the other, as the island's words change.
                Group {
                    if on {
                        Text(Self.done).foregroundStyle(.green)
                    } else {
                        Text(Self.offer).foregroundStyle(.white.opacity(0.5))
                    }
                }
                .font(.system(size: h * LowBatteryLayout.subtitle, weight: .semibold))
                .transition(.blurReplace)
            }
            .lineLimit(1)
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, edge)
        .padding(.top, h + LiveActivityView.cameraGap)
        .padding(.bottom, edge)
        .frame(width: LowBatteryLayout.width(percent: percent, restingHeight: h), height: LowBatteryLayout.height(h), alignment: .top)
        .animation(.easeInOut(duration: 0.3), value: on)
    }

    /// 0 to 1 and back, gently, once a pulse.
    static func pulse(at date: Date) -> CGFloat {
        (1 + cos(date.timeIntervalSinceReferenceDate * 2 * .pi / LowBatteryLayout.pulse)) / 2
    }
}
