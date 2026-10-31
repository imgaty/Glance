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
        enabled = UserDefaults.standard.bool(forKey: Preferences.activityDevices)
        let id = AudioOutput.defaultOutput
        let device = AudioOutput.outputs().first { $0.id == id }
        let airPlay = device.map { $0.transport == kAudioDeviceTransportTypeAirPlay } ?? false
        if !airPlay, device != nil { lastLocal = id }
        let next = airPlay && enabled ? device.map { AirPlayRoute(name: $0.name, symbol: AirPlayRoute.symbol(for: $0)) } : nil
        if next != route { route = next }
    }

    /// What's shown at the bench (see `ActivityBench`).
    func bench(_ fake: AirPlayRoute?) {
        route = fake
    }

    /// The sound back where it played before AirPlay, or on the Mac's own speakers.
    func stop() {
        guard ActivityBench.scene == nil else { return ActivityBench.shared.stopped() }
        let outputs = AudioOutput.outputs().filter { $0.transport != kAudioDeviceTransportTypeAirPlay }
        guard
            let target = outputs.first(where: { $0.id == lastLocal })
                ?? outputs.first(where: { $0.transport == kAudioDeviceTransportTypeBuiltIn }) ?? outputs.first
        else { return }
        var id = target.id
        var address = AudioProperty.address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectSetPropertyData(AudioProperty.system, &address, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &id)
    }
}

/// AirPlay as the iPhone's Screen Mirroring, measured from it, by the island's height: its symbol in
/// the iPhone's muted blue, what it plays on in white, and a wide button in navy with blue words.
/// Its colors are the iPhone's own, in Display P3.
enum AirPlayLayout {
    static let tint = Color.p3(0x3B, 0x69, 0xB4)
    static let buttonFill = Color.p3(0x12, 0x20, 0x3B)
    static let buttonWords = Color.p3(0x4B, 0x80, 0xF1)
    static let secondary = Color.p3(0x93, 0x92, 0x98)
    // Beside the camera: the symbol and the device, each as far in from its end.
    static let symbol: CGFloat = 0.6
    static let device: CGFloat = 0.4
    static let edge: CGFloat = 0.23
    // Opened.
    static let wide: CGFloat = 10.2
    static let bigSymbol: CGFloat = 0.95
    static let symbolInset: CGFloat = 0.83
    static let symbolGap: CGFloat = 0.53
    static let bigDevice: CGFloat = 0.67
    static let deviceInset: CGFloat = 0.68
    static let title: CGFloat = 0.48
    /// The title and the name close together, as the iPhone sets them.
    static let lineGap: CGFloat = -0.09
    static let header: CGFloat = 0.9
    static let buttonGap: CGFloat = 0.4
    static let button: CGFloat = 1.2
    static let buttonInset: CGFloat = 0.545
    static let buttonBottom: CGFloat = 0.47
    static let buttonText: CGFloat = 0.48

    /// Opened, its header just below the camera, the button under it.
    static func height(_ h: CGFloat) -> CGFloat {
        (h + LiveActivityView.cameraGap + h * (header + buttonGap + button + buttonBottom)).rounded()
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

    var body: some View {
        let h = restingHeight
        ZStack {
            Image(systemName: "airplay.audio")
                .font(.system(size: h * AirPlayLayout.symbol, weight: .regular))
                .foregroundStyle(AirPlayLayout.tint)
                .padding(.leading, h * AirPlayLayout.edge)
                .frame(maxWidth: .infinity, alignment: .leading)
            AirPlayDevice(route: route, size: h * AirPlayLayout.device)
                .padding(.trailing, h * AirPlayLayout.edge)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("AirPlay, playing on \(route.name)")
    }
}

/// Opened, as the iPhone's Screen Mirroring expands: AirPlay's symbol, large, then AirPlay and the
/// device's name, what it is at the right end; under them, a wide button to stop it, which sends
/// the sound back to where it played before.
struct ExpandedAirPlayView: View {
    let route: AirPlayRoute
    let restingHeight: CGFloat
    let width: CGFloat
    @State private var hovering = false

    var body: some View {
        let h = restingHeight
        VStack(spacing: h * AirPlayLayout.buttonGap) {
            HStack(spacing: 0) {
                Image(systemName: "airplay.audio")
                    .font(.system(size: h * AirPlayLayout.bigSymbol, weight: .regular))
                    .foregroundStyle(AirPlayLayout.tint)
                    .padding(.leading, h * AirPlayLayout.symbolInset)
                    .padding(.trailing, h * AirPlayLayout.symbolGap)
                VStack(alignment: .leading, spacing: h * AirPlayLayout.lineGap) {
                    Text("AirPlay")
                        .foregroundStyle(.white)
                    Text(route.name)
                        .foregroundStyle(AirPlayLayout.secondary)
                }
                .font(.system(size: h * AirPlayLayout.title, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                Spacer(minLength: h * 0.3)
                AirPlayDevice(route: route, size: h * AirPlayLayout.bigDevice)
                    .padding(.trailing, h * AirPlayLayout.deviceInset)
            }
            .frame(height: h * AirPlayLayout.header)
            Button {
                AirPlayWatch.shared.stop()
            } label: {
                Text("Stop AirPlay")
                    .font(.system(size: h * AirPlayLayout.buttonText, weight: .semibold))
                    .foregroundStyle(AirPlayLayout.buttonWords)
                    .frame(maxWidth: .infinity)
                    .frame(height: h * AirPlayLayout.button)
                    .background(AirPlayLayout.buttonFill.opacity(hovering ? 1 : 0.85), in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(IslandPress(highlight: false, contactSize: nil))
            .onHover { hovering = $0 }
            .notchControl()
            .padding(.horizontal, h * AirPlayLayout.buttonInset)
        }
        .padding(.top, h + LiveActivityView.cameraGap)
        .padding(.bottom, h * AirPlayLayout.buttonBottom)
        .frame(width: width, height: AirPlayLayout.height(h), alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("AirPlay, playing on \(route.name)")
    }

    /// As wide as the iPhone's, or as AirPlay and the device's name need.
    @MainActor
    static func width(for route: AirPlayRoute, restingHeight h: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: h * AirPlayLayout.title, weight: .semibold)
        let name = ceil((route.name as NSString).size(withAttributes: [.font: font]).width)
        let needs =
            h
            * (AirPlayLayout.symbolInset + AirPlayLayout.bigSymbol * 1.05 + AirPlayLayout.symbolGap + 0.3
                + AirPlayLayout.bigDevice * 1.45 + AirPlayLayout.deviceInset) + name
        return min(max(h * AirPlayLayout.wide, needs), h * 14)
    }
}
