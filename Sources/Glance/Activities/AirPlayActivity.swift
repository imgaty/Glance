//
//  AirPlayActivity.swift
//  Glance
//
//  Created by Gaty on 24/10/2026.
//

import AppKit
import CoreAudio
import SwiftUI

/// Where the Mac's sound is playing over AirPlay: the speaker or TV, by its name and the symbol of
/// what it is.
struct AirPlayRoute: Equatable {
    let name: String
    let symbol: String
    var outputID: AudioDeviceID? = nil
    var canStop = true
    var stopFailed = false

    var stopTitle: String {
        if !canStop { return String(localized: "No Local Output") }
        return stopFailed ? String(localized: "Try Again") : String(localized: "Stop AirPlay")
    }

    var stopSpoken: String {
        stopFailed ? String(localized: "Couldn't change output. Try stopping AirPlay again.") : stopTitle
    }

    /// What the device is: as macOS pictures its model, if it says which; otherwise, by its name,
    /// as the iPhone draws it: a MacBook, another Mac, a TV, a HomePod, or a speaker.
    @MainActor static func symbol(for device: AudioOutput.Device) -> String {
        device.model?.symbol ?? symbol(for: device.name)
    }

    static func symbol(for name: String) -> String {
        let name = name.lowercased()
        let candidates: [String] =
            if name.contains("homepod mini") {
                ["homepodmini", "homepod"]
            } else if name.contains("homepod") {
                ["homepod"]
            } else if name.contains("apple tv") {
                ["appletv", "tv"]
            } else if name.contains("tv") {
                ["tv"]
            } else if name.contains("macbook") {
                ["macbook", "laptopcomputer"]
            } else if name.contains("imac") || name.contains("mac mini") || name.contains("mac studio") || name.contains("mac pro") {
                ["desktopcomputer"]
            } else {
                ["hifispeaker"]
            }
        return candidates.first { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil } ?? "hifispeaker"
    }

    /// A screen's own symbol draws its screen in gray inside the white, as the iPhone's does.
    var hasScreen: Bool { ["macbook", "laptopcomputer", "tv", "desktopcomputer", "imac"].contains { symbol.hasPrefix($0) } }
}

/// The Mac's sound going to AirPlay, as the iPhone's Dynamic Island shows Screen Mirroring: beside
/// the camera the whole time it plays there, AirPlay's symbol at one end and what it plays on at
/// the other; opened, with a button to stop it, which sends the sound back to where it played
/// before. It goes once the sound plays anywhere else.
@MainActor
final class AirPlayWatch: ObservableObject {
    static let shared = AirPlayWatch()

    @Published private(set) var route: AirPlayRoute?
    /// The last output that wasn't AirPlay, which Stop goes back to.
    private var lastLocal: AudioDeviceID?
    /// Shown, as set in Settings with the devices.
    private var enabled = false
    private var started = false
    private let outputs: @MainActor () -> [AudioOutput.Device]
    private let currentOutput: @MainActor () -> AudioDeviceID
    private let setOutput: @MainActor (AudioDeviceID) -> OSStatus
    private let routeSymbol: @MainActor (AudioOutput.Device) -> String
    private let isEnabled: @MainActor () -> Bool

    init(
        outputs: @escaping @MainActor () -> [AudioOutput.Device] = { AudioOutput.outputs() },
        currentOutput: @escaping @MainActor () -> AudioDeviceID = { AudioOutput.defaultOutput },
        setOutput: @escaping @MainActor (AudioDeviceID) -> OSStatus = { output in
            var id = output
            var address = AudioProperty.address(kAudioHardwarePropertyDefaultOutputDevice)
            return AudioObjectSetPropertyData(AudioProperty.system, &address, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &id)
        },
        routeSymbol: @escaping @MainActor (AudioOutput.Device) -> String = { AirPlayRoute.symbol(for: $0) },
        isEnabled: @escaping @MainActor () -> Bool = { UserDefaults.standard.bool(forKey: Preferences.activityDevices) }
    ) {
        self.outputs = outputs
        self.currentOutput = currentOutput
        self.setOutput = setOutput
        self.routeSymbol = routeSymbol
        self.isEnabled = isEnabled
    }

    func start() {
        guard !started else { return }
        started = true
        for selector in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDevices] {
            var address = AudioProperty.address(selector)
            AudioObjectAddPropertyListenerBlock(AudioProperty.system, &address, .main) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, UserDefaults.standard.bool(forKey: Preferences.activityDevices) != self.enabled else { return }
                self.refresh()
            }
        }
        refresh()
    }

    /// Read again, as the output changes: shown while it's an AirPlay device, unless turned off in
    /// Settings.
    func refresh() {
        guard ActivityBench.scene == nil else { return }
        enabled = isEnabled()
        let id = currentOutput()
        let available = outputs()
        let device = available.first { $0.id == id }
        let airPlay = device.map { $0.transport == kAudioDeviceTransportTypeAirPlay } ?? false
        if !airPlay, device != nil { lastLocal = id }
        let canStop = Self.returnOutput(in: available, previous: lastLocal) != nil
        let next =
            airPlay && enabled
            ? device.map {
                AirPlayRoute(
                    name: $0.name, symbol: routeSymbol($0), outputID: id, canStop: canStop,
                    stopFailed: canStop && route?.outputID == id && route?.stopFailed == true)
            } : nil
        if next != route { route = next }
    }

    /// What's shown at the bench (see `ActivityBench`).
    func bench(_ fake: AirPlayRoute?) {
        route = fake
    }

    /// The sound back where it played before AirPlay, or on the Mac's own speakers.
    @discardableResult
    func stop(expectedOutput: AudioDeviceID? = nil) -> Bool {
        guard ActivityBench.scene == nil else {
            ActivityBench.shared.stopped(.airplay)
            return true
        }
        guard let expected = expectedOutput ?? route?.outputID, route?.canStop == true else { return false }
        let current = currentOutput()
        let available = outputs()
        guard current == expected,
            available.first(where: { $0.id == current })?.transport == kAudioDeviceTransportTypeAirPlay,
            let target = Self.returnOutput(in: available, previous: lastLocal)
        else {
            refresh()
            return false
        }
        let succeeded = setOutput(target.id) == noErr
        refresh()
        if var shown = route, shown.outputID == expected, shown.canStop, shown.stopFailed != !succeeded {
            shown.stopFailed = !succeeded
            route = shown
        }
        return succeeded
    }

    /// Restore the previous local route if it still exists, then prefer the Mac's own speakers.
    static func returnOutput(in outputs: [AudioOutput.Device], previous: AudioDeviceID?) -> AudioOutput.Device? {
        let local = outputs.filter { $0.transport != kAudioDeviceTransportTypeAirPlay }
        return local.first(where: { $0.id == previous })
            ?? local.first(where: { $0.transport == kAudioDeviceTransportTypeBuiltIn }) ?? local.first
    }
}

/// AirPlay as the iPhone's Screen Mirroring, measured from it, by the island's height: its symbol in
/// the iPhone's muted blue, what it plays on in white, and a wide button in navy with blue words.
/// The Display P3 palette follows the iPhone, with readable button text at Mac sizes.
enum AirPlayLayout {
    static let tint = Color.p3(0x3B, 0x69, 0xB4)
    static let buttonFill = Color.p3(0x12, 0x20, 0x3B)
    /// At least 4.5:1 against the opaque hovered fill for the small button text.
    static let buttonWords = Color.p3(0x50, 0x85, 0xF6)
    // Beside the camera: the symbol and the device, each as far in from its end.
    /// As tall in ink as every other activity's mark beside the camera.
    static let symbol: CGFloat = 0.585
    static let symbolEdge: CGFloat = 0.144
    static let device: CGFloat = 0.4
    static let deviceEdge: CGFloat = 0.23
    // Opened.
    static let wide: CGFloat = 10.2
    static let bigSymbol: CGFloat = 0.95
    /// The room each symbol has beside it in its font, which the padding takes the place of.
    static let bigSymbolMargin: CGFloat = 0.078
    static let symbolGap: CGFloat = 0.53
    static let bigDevice: CGFloat = 0.67
    static let bigDeviceMargin: CGFloat = 0.094
    /// The title and the name close together, as the iPhone sets them.
    static let header: CGFloat = 0.9
    static let buttonGap: CGFloat = 0.4

    /// Opened, its header just below the camera, the button under it.
    static func height(_ h: CGFloat) -> CGFloat {
        (h + LiveActivityView.cameraGap + h * (header + buttonGap) + TimerLayout.content(h) + PlayerLayout.padding).rounded()
    }
}

/// What AirPlay plays on, in white; a screen's own drawn in gray inside.
struct AirPlayDevice: View {
    let route: AirPlayRoute
    let size: CGFloat

    var body: some View {
        Image(systemName: route.symbol)
            .font(.system(size: size, weight: .regular))
            .symbolRenderingMode(route.hasScreen ? .hierarchical : .monochrome)
            .foregroundStyle(.white)
    }
}

/// AirPlay beside the camera, as the iPhone's Screen Mirroring: its symbol at the left end, what it
/// plays on at the right, each as far in from its end.
struct AirPlayMark: View {
    let route: AirPlayRoute
    let restingHeight: CGFloat
    /// Only the symbol, with another activity detached (see `SystemActivityView.leadingOnly`).
    var leadingOnly = false

    var body: some View {
        let h = restingHeight
        ZStack {
            Image(systemName: "airplay.audio")
                .font(.system(size: h * AirPlayLayout.symbol, weight: .regular))
                .foregroundStyle(AirPlayLayout.tint)
                .padding(.leading, h * AirPlayLayout.symbolEdge)
                .frame(maxWidth: .infinity, alignment: .leading)
            AirPlayDevice(route: route, size: h * AirPlayLayout.device)
                .padding(.trailing, h * AirPlayLayout.deviceEdge)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .islandFade(!leadingOnly)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("AirPlay, output: \(route.name)")
    }
}

/// Opened, as the iPhone's Screen Mirroring expands: AirPlay's symbol, large, then AirPlay and the
/// device's name, what it is at the right end; under them, a wide button to stop it, which sends
/// the sound back to where it played before.
struct ExpandedAirPlayView: View {
    let route: AirPlayRoute
    let restingHeight: CGFloat
    let width: CGFloat
    /// The notch is open to it.
    var revealed = true
    /// How wide the notch is closed, if it shows beside the camera there, and grows out of that.
    var closedWidth: CGFloat? = nil
    /// How far below its middle at rest the closed notch's middle was, swollen under the pointer.
    var closedDrop: CGFloat = 0
    var stop: (AudioDeviceID?) -> Bool = { AirPlayWatch.shared.stop(expectedOutput: $0) }
    @Environment(\.activityBubbleCenter) private var bubbleCenter
    @State private var hovering = false
    @Environment(\.trailingGrows) private var trailingGrows

    var body: some View {
        let h = restingHeight
        let layout = AirPlayLayout.self
        let out = revealed || closedWidth == nil && bubbleCenter == nil
        let rise = h / 2 + closedDrop - (h + LiveActivityView.cameraGap + h * layout.header / 2)
        let spread = ((closedWidth ?? width) - width) / 2
        // From each frame's edge here to its edge beside the camera, the room the large symbols have
        // beside their ink included, so they start exactly where they were.
        let symbolFrom = CGSize(
            width: bubbleCenter.map { $0 + width / 2 - (PlayerLayout.padding - h * layout.bigSymbolMargin) - h * 0.5 / 2 }
                ?? (h * layout.symbolEdge - (PlayerLayout.padding - h * layout.bigSymbolMargin) - spread), height: rise)
        let deviceFrom = CGSize(width: spread - h * layout.deviceEdge + (PlayerLayout.padding - h * layout.bigDeviceMargin), height: rise)
        VStack(spacing: h * AirPlayLayout.buttonGap) {
            HStack(spacing: 0) {
                Image(systemName: "airplay.audio")
                    .font(.system(size: h * AirPlayLayout.bigSymbol, weight: .regular))
                    .foregroundStyle(AirPlayLayout.tint)
                    .modifier(GrowsOut(out: out, scale: (bubbleCenter == nil ? layout.symbol : 0.5) / layout.bigSymbol, anchor: .leading, from: symbolFrom))
                    .modifier(GrownFade(shown: revealed, grows: closedWidth != nil || bubbleCenter != nil))
                    .padding(.leading, PlayerLayout.padding - h * AirPlayLayout.bigSymbolMargin)
                    .padding(.trailing, h * AirPlayLayout.symbolGap)
                VStack(alignment: .leading, spacing: 0) {
                    Text("AirPlay")
                        .font(NotchType.title)
                        .foregroundStyle(.white)
                    Text(route.name)
                        .font(NotchType.detail)
                        .foregroundStyle(NotchType.detailColor)
                }
                .lineLimit(1)
                .truncationMode(.tail)
                .modifier(IslandReveal(hidden: !revealed))
                Spacer(minLength: h * 0.3)
                AirPlayDevice(route: route, size: h * AirPlayLayout.bigDevice)
                    .modifier(GrowsOut(out: out || !trailingGrows, scale: layout.device / layout.bigDevice, anchor: .trailing, from: deviceFrom))
                    .modifier(GrownFade(shown: revealed, grows: closedWidth != nil && trailingGrows))
                    .padding(.trailing, PlayerLayout.padding - h * AirPlayLayout.bigDeviceMargin)
            }
            .frame(height: h * AirPlayLayout.header)
            Button {
                performStop()
            } label: {
                VStack(spacing: 1) {
                    Text(route.stopTitle)
                        .font(NotchType.title)
                    if route.stopFailed {
                        Text("Couldn't change output")
                            .font(.system(size: 11))
                            .foregroundStyle(.white)
                    }
                }
                .foregroundStyle(route.canStop ? AirPlayLayout.buttonWords : NotchType.detailColor)
                .frame(maxWidth: .infinity)
                .frame(height: TimerLayout.content(h))
                .background(route.canStop ? AirPlayLayout.buttonFill.opacity(hovering ? 1 : 0.85) : Color.white.opacity(0.06), in: Capsule())
                .contentShape(Capsule())
            }
            .disabled(!route.canStop)
            .buttonStyle(IslandPress(highlight: false, contactSize: nil))
            .onHover { hovering = $0 && route.canStop }
            .notchControl()
            .accessibilityLabel(route.stopSpoken)
            .keyControl(.activityFirst, in: Capsule(), outset: CGSize(width: 3, height: 3), spoken: route.stopSpoken) { performStop() }
            .padding(.horizontal, PlayerLayout.padding)
            .modifier(IslandReveal(hidden: !revealed))
        }
        .padding(.top, h + LiveActivityView.cameraGap)
        .padding(.bottom, PlayerLayout.padding)
        .frame(width: width, height: AirPlayLayout.height(h), alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("AirPlay, output: \(route.name)")
    }

    @discardableResult
    func performStop() -> Bool {
        guard revealed, route.canStop else { return false }
        return stop(route.outputID)
    }

    /// As wide as the iPhone's, or as AirPlay and the device's name need.
    @MainActor
    static func width(for route: AirPlayRoute, restingHeight h: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: NotchType.size, weight: .semibold)
        let name = ceil((route.name as NSString).size(withAttributes: [.font: font]).width)
        let needs =
            PlayerLayout.padding * 2 + h * (AirPlayLayout.bigSymbol * 1.05 + AirPlayLayout.symbolGap + 0.3 + AirPlayLayout.bigDevice * 1.45) + name
        return min(max(h * AirPlayLayout.wide, needs), h * 14)
    }
}
