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

    /// What the device is, by its name, as Control Center draws it: a TV, a HomePod, a Mac, or a
    /// speaker.
    static func symbol(for name: String) -> String {
        let name = name.lowercased()
        let candidates: [String] =
            if name.contains("homepod mini") {
                ["homepodmini.fill", "homepod.fill"]
            } else if name.contains("homepod") {
                ["homepod.fill"]
            } else if name.contains("apple tv") {
                ["appletv.fill", "tv"]
            } else if name.contains("tv") {
                ["tv"]
            } else if name.contains("macbook") {
                ["laptopcomputer"]
            } else if name.contains("imac") || name.contains("mac mini") || name.contains("mac studio") || name.contains("mac pro") {
                ["desktopcomputer"]
            } else {
                ["hifispeaker.fill"]
            }
        return candidates.first { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil } ?? "hifispeaker.fill"
    }
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
        enabled = UserDefaults.standard.bool(forKey: Preferences.activityDevices)
        let id = AudioOutput.defaultOutput
        let device = AudioOutput.outputs().first { $0.id == id }
        let airPlay = device.map { $0.transport == kAudioDeviceTransportTypeAirPlay } ?? false
        if !airPlay, device != nil { lastLocal = id }
        let next = airPlay && enabled ? device.map { AirPlayRoute(name: $0.name, symbol: AirPlayRoute.symbol(for: $0.name)) } : nil
        if next != route { route = next }
    }

    /// The sound back where it played before AirPlay, or on the Mac's own speakers.
    func stop() {
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

/// AirPlay as the iPhone's Screen Mirroring, measured from it, by the island's height: AirPlay's
/// symbol in Control Center's blue, the device's in white.
enum AirPlayLayout {
    static let tint = Color.blue
    /// Opened, as wide as the iPhone's, and its header's symbol, title and name.
    static let wide: CGFloat = 10.2
    static let symbol: CGFloat = 0.95
    static let deviceSymbol: CGFloat = 0.8
    static let title: CGFloat = 0.464
    static let header: CGFloat = 1.15
    static let headerInset: CGFloat = 0.8
    static let titleGap: CGFloat = 0.36
    /// Its button: as tall as the iPhone's, a capsule.
    static let button: CGFloat = 1.18
    static let buttonGap: CGFloat = 0.25
    static let buttonText: CGFloat = 0.5

    /// How far in the button sits from the sides and the bottom: the same, so its round ends are
    /// concentric with the notch's round corners, as the timer's buttons are.
    static func buttonEdge(_ h: CGFloat) -> CGFloat { TimerLayout.cornerEdge(h, button) }

    /// Opened, its header just below the camera, the button under it.
    static func height(_ h: CGFloat) -> CGFloat {
        (h + LiveActivityView.cameraGap + h * (header + buttonGap + button) + buttonEdge(h)).rounded()
    }
}

/// AirPlay beside the camera: its symbol at the left end, what it plays on at the right, each as
/// far in from its end as from the top and bottom, as the cover is.
struct AirPlayMark: View {
    let route: AirPlayRoute
    let restingHeight: CGFloat
    let island: Bool

    var body: some View {
        let side = SystemActivityView.side(restingHeight, island)
        let edge = LiveActivityView.edgeInset(island: island, restingHeight: restingHeight)
        ZStack {
            Image(systemName: "airplay.audio")
                .font(.system(size: side * 0.82, weight: .semibold))
                .foregroundStyle(AirPlayLayout.tint)
                .frame(width: side, height: side)
                .padding(.leading, edge)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: route.symbol)
                .font(.system(size: side * 0.7, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: side, height: side)
                .padding(.trailing, edge)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("AirPlay, playing on \(route.name)")
    }
}

/// Opened, as the iPhone's Screen Mirroring expands: AirPlay's symbol, large, then AirPlay and the
/// device's name, what it is at the right end; under them, a wide button to stop it, in AirPlay's
/// blue, which sends the sound back to where it played before.
struct ExpandedAirPlayView: View {
    let route: AirPlayRoute
    let restingHeight: CGFloat
    let width: CGFloat
    @State private var hovering = false

    var body: some View {
        let h = restingHeight
        VStack(spacing: h * AirPlayLayout.buttonGap) {
            HStack(spacing: h * AirPlayLayout.titleGap) {
                Image(systemName: "airplay.audio")
                    .font(.system(size: h * AirPlayLayout.symbol, weight: .regular))
                    .foregroundStyle(AirPlayLayout.tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text("AirPlay")
                        .font(.system(size: h * AirPlayLayout.title, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(route.name)
                        .font(.system(size: h * AirPlayLayout.title, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .lineLimit(1)
                .truncationMode(.tail)
                Spacer(minLength: 0)
                Image(systemName: route.symbol)
                    .font(.system(size: h * AirPlayLayout.deviceSymbol, weight: .medium))
                    .foregroundStyle(.white)
            }
            .frame(height: h * AirPlayLayout.header)
            .padding(.horizontal, h * AirPlayLayout.headerInset)
            Button {
                AirPlayWatch.shared.stop()
            } label: {
                Text("Stop AirPlay")
                    .font(.system(size: h * AirPlayLayout.buttonText, weight: .semibold))
                    .foregroundStyle(AirPlayLayout.tint)
                    .frame(maxWidth: .infinity)
                    .frame(height: h * AirPlayLayout.button)
                    .background(AirPlayLayout.tint.opacity(hovering ? 0.3 : 0.22), in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(IslandPress(highlight: false, contactSize: nil))
            .onHover { hovering = $0 }
            .notchControl()
            .padding(.horizontal, AirPlayLayout.buttonEdge(h))
        }
        .padding(.top, h + LiveActivityView.cameraGap)
        .padding(.bottom, AirPlayLayout.buttonEdge(h))
        .frame(width: width, height: AirPlayLayout.height(h), alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("AirPlay, playing on \(route.name)")
    }

    /// As wide as the iPhone's, or as its title and the device's name need.
    @MainActor
    static func width(for route: AirPlayRoute, restingHeight h: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: h * AirPlayLayout.title, weight: .semibold)
        let name = ceil((route.name as NSString).size(withAttributes: [.font: font]).width)
        let needs = h * (AirPlayLayout.headerInset * 2 + AirPlayLayout.symbol * 1.3 + AirPlayLayout.titleGap * 2 + AirPlayLayout.deviceSymbol * 1.3) + name
        return min(max(h * AirPlayLayout.wide, needs), h * 14)
    }
}
