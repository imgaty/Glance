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

    /// At the bench it's only said, and the Mac's stays as it is (see `ActivityBench`).
    func bench(_ on: Bool) {
        isOn = on
    }

    func turnOn() {
        guard ActivityBench.scene == nil else { return bench(true) }
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

/// Low Battery as the iPhone's Dynamic Island shows it, measured from it, by the island's height,
/// as tall as the Alarm, with the room beside the camera put to use and everything as close to it as
/// can be: its level at the left, against the camera, and the offer to turn on Low Power Mode under
/// it, below the camera, the lines as far apart as the iPhone's; at the right, against the camera
/// too, a capsule holding a large battery, a ring pulsing around its level. All of it centered on
/// the middle. Its colors are
/// the iPhone's own, in Display P3: red, from a reddish yellow as it arrives, and green once Low
/// Power Mode is on.
enum LowBatteryLayout {
    /// The level, and the offer a little smaller under it, their baselines as far apart as the
    /// iPhone's.
    static let words: CGFloat = 0.425
    static let offerWords: CGFloat = 0.4
    static let baselines: CGFloat = 0.564
    /// Between the offer and the capsule, at the least.
    static let wordsGap: CGFloat = 0.34
    static let capsule = CGSize(width: 2.35, height: 1.56)
    /// The battery in the capsule, a little right of its middle, as the iPhone sets it.
    static let bodyLeft: CGFloat = 0.54
    static let body = CGSize(width: 1.2, height: 0.645)
    static let bodyCorner: CGFloat = 0.135
    /// The level inside the body, never narrower than at 10%, as the iPhone's.
    static let levelInset: CGFloat = 0.105
    static let levelHeight: CGFloat = 0.45
    static let leastLevel: CGFloat = 0.21
    static let capGap: CGFloat = 0.055
    static let cap = CGSize(width: 0.073, height: 0.22)
    /// Across the ring's line, and the line.
    static let ring: CGFloat = 1.01
    static let ringLine: CGFloat = 0.055
    /// How long the ring takes to pulse, in seconds; and how long, arriving, it takes to settle
    /// from its reddish yellow into red.
    static let pulse = 1.2
    static let warmUp = 2.4

    /// The words under the level, as the iPhone's.
    static let offerColor = Color(white: 0x6B / 255)

    /// Each part's color: the capsule, the battery's body and cap, the level, and the ring's line,
    /// which lets what's under it show through.
    struct Shade {
        let capsule: Color
        let body: Color
        let level: Color
        let ring: Color

        func mix(with other: Shade, by amount: Double) -> Shade {
            Shade(
                capsule: capsule.mix(with: other.capsule, by: amount), body: body.mix(with: other.body, by: amount),
                level: level.mix(with: other.level, by: amount), ring: ring.mix(with: other.ring, by: amount))
        }
    }
    static let red = Shade(capsule: .p3(0x2F, 0x10, 0x0D), body: .p3(0x7D, 0x2B, 0x2D), level: .p3(0xEE, 0x80, 0x8E), ring: .p3(0xE6, 0x57, 0x63))
    static let amber = Shade(capsule: .p3(0x2F, 0x20, 0x0D), body: .p3(0x7D, 0x59, 0x2B), level: .p3(0xEE, 0xBE, 0x80), ring: .p3(0xE6, 0xA8, 0x57))
    static let green = Shade(capsule: .p3(0x0D, 0x2F, 0x14), body: .p3(0x2B, 0x7D, 0x3B), level: .p3(0x80, 0xEE, 0x96), ring: .p3(0x57, 0xE6, 0x74))
    /// The ring's line, over the capsule and the battery.
    static let ringOpacity = 0.37

    /// The capsule as far in from the right end as from the top and bottom, concentric with it.
    static func edge(_ h: CGFloat) -> CGFloat { LiveActivityView.concentric(h * capsule.height, in: TimerLayout.tallHeight(h)) }

    /// From the top to the level's line: the two lines centered, from the level's capitals to the
    /// offer's baseline, on the middle, as the capsule is, as the iPhone's are; lower, should the
    /// offer's letters otherwise come nearer the camera than the least gap.
    @MainActor
    static func wordsTop(_ h: CGFloat) -> CGFloat {
        let level = NSFont.systemFont(ofSize: h * words, weight: .semibold)
        let offerFont = NSFont.systemFont(ofSize: h * offerWords, weight: .semibold)
        let centered = TimerLayout.tallHeight(h) / 2 - (h * baselines - level.capHeight) / 2
        // How far the offer's letters rise above their baseline.
        let rise =
            [LowBatteryView.offer, LowBatteryView.done].map {
                CTLineGetBoundsWithOptions(
                    CTLineCreateWithAttributedString(NSAttributedString(string: $0, attributes: [.font: offerFont])), .useGlyphPathBounds
                ).maxY
            }.max() ?? 0
        let belowCamera = h + LiveActivityView.cameraGap + rise - h * baselines
        return max(centered, belowCamera) - level.ascender
    }

    /// Between the two lines' boxes, for their baselines to be as far apart as the iPhone's.
    static func lineGap(_ h: CGFloat) -> CGFloat {
        let level = NSFont.systemFont(ofSize: h * words, weight: .semibold)
        let offerFont = NSFont.systemFont(ofSize: h * offerWords, weight: .semibold)
        return h * baselines + level.descender - offerFont.ascender
    }

    @MainActor
    static func width(_ text: String, _ size: CGFloat) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: .semibold)]).width)
    }

    /// From where the words start to the camera: the level's width, against it; or further out,
    /// should the offer under the camera otherwise run into the capsule.
    @MainActor
    static func lead(percent: Int, restingHeight h: CGFloat, closedWidth: CGFloat) -> CGFloat {
        let gap = LiveActivityView.cameraGap
        let offer = max(width(LowBatteryView.offer, h * offerWords), width(LowBatteryView.done, h * offerWords))
        return max(width(LowBatteryView.title(percent), h * words) + gap, offer + h * wordsGap - closedWidth - gap)
    }

    /// Each wing: the wider side against the camera, the words as far in from their end as words
    /// beside the camera are, or the capsule concentric with its end.
    @MainActor
    static func wing(percent: Int, restingHeight h: CGFloat, closedWidth: CGFloat) -> CGFloat {
        let words = LiveActivityView.textEdge(restingHeight: h) + lead(percent: percent, restingHeight: h, closedWidth: closedWidth)
        return max(words, LiveActivityView.cameraGap + h * capsule.width + edge(h))
    }
}

/// Low Battery, as the iPhone's, as tall as the Alarm: its level against the camera at the left,
/// an offer to turn on Low Power Mode under it, below the camera, and the battery, large, in a
/// capsule against the camera at the right, a ring pulsing around its level, settling from a
/// reddish yellow into red; clicked, Low Power Mode comes on, everything turns green and stops
/// pulsing, and it says so. With Reduce Motion on, it's red at once and doesn't pulse.
struct LowBatteryView: View {
    let percent: Int
    let restingHeight: CGFloat
    /// Each wing's width beside the camera (see `LowBatteryLayout.wing`).
    var wing: CGFloat = 0
    /// The notch's width at rest, which the offer goes under.
    var closedWidth: CGFloat = 0
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
        let gap = LiveActivityView.cameraGap
        let lead = LowBatteryLayout.lead(percent: percent, restingHeight: h, closedWidth: closedWidth)
        // Each side kept to its own end, so it rides in and out with it, and as far from it as
        // puts it against the camera.
        ZStack {
            VStack(alignment: .leading, spacing: LowBatteryLayout.lineGap(h)) {
                Text(Self.title(percent))
                    .font(.system(size: h * LowBatteryLayout.words, weight: .semibold))
                    .foregroundStyle(.white)
                // One blurring into the other, as the island's words change.
                Group {
                    if on {
                        Text(Self.done).foregroundStyle(LowBatteryLayout.green.level)
                    } else {
                        Text(Self.offer).foregroundStyle(LowBatteryLayout.offerColor)
                    }
                }
                .font(.system(size: h * LowBatteryLayout.offerWords, weight: .semibold))
                .transition(.blurReplace)
            }
            .lineLimit(1)
            .fixedSize()
            .padding(.top, LowBatteryLayout.wordsTop(h))
            .padding(.leading, max(wing - lead, 0))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityElement(children: .combine)
            capsule(h, on: on)
                .reportsFrame(.lowPower)
                .spokenButton(on ? Self.done : "Turn on Low Power Mode") { LowPowerMode.shared.turnOn() }
                .padding(.trailing, max(wing - gap - h * LowBatteryLayout.capsule.width, 0))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.3), value: on)
    }

    /// The battery, large, in its capsule, as the iPhone draws it: the body, the level bright and
    /// glowing a little, the cap apart, and the ring around the level, the battery showing through
    /// its line. Arriving, it pulses from a reddish yellow into a soft red, as the iPhone's does,
    /// and goes on breathing.
    private func capsule(_ h: CGFloat, on: Bool) -> some View {
        let layout = LowBatteryLayout.self
        let inner = layout.body.width - layout.levelInset * 2
        let level = max(inner * CGFloat(percent) / 100, layout.leastLevel)
        // The ring's middle, from the body's left end: the level's.
        let ringMiddle = layout.levelInset + level / 2
        return TimelineView(.animation(paused: on || reduceMotion)) { context in
            let warm = reduceMotion ? 1 : Self.warming(after: context.date.timeIntervalSince(shownAt))
            let pulse = on || reduceMotion ? 1 : Self.pulse(at: context.date)
            let shade = on ? layout.green : layout.amber.mix(with: layout.red, by: warm)
            HStack(spacing: h * layout.capGap) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: h * layout.bodyCorner, style: .continuous)
                        .fill(shade.body)
                    Capsule()
                        .fill(shade.level)
                        .frame(width: h * level, height: h * layout.levelHeight)
                        .shadow(color: shade.level.opacity(0.5), radius: h * 0.04)
                        .padding(.leading, h * layout.levelInset)
                }
                .frame(width: h * layout.body.width, height: h * layout.body.height)
                // Over the battery, outside its layout, so it never sizes it.
                .overlay(alignment: .leading) {
                    Circle()
                        .stroke(shade.ring, lineWidth: h * layout.ringLine)
                        .frame(width: h * layout.ring, height: h * layout.ring)
                        .scaleEffect(0.94 + 0.06 * pulse)
                        .opacity(on ? 0 : layout.ringOpacity * (0.55 + 0.45 * pulse))
                        .offset(x: h * (ringMiddle - layout.ring / 2))
                }
                Capsule()
                    .fill(shade.body)
                    .frame(width: h * layout.cap.width, height: h * layout.cap.height)
            }
            .padding(.leading, h * layout.bodyLeft)
            .frame(width: h * layout.capsule.width, height: h * layout.capsule.height, alignment: .leading)
            .background(Capsule().fill(hovered ? shade.capsule.mix(with: .white, by: 0.08) : shade.capsule))
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
