//
//  AudioOutput.swift
//  Glance
//
//  Created by Gaty on 07/10/2026.
//

import AppKit
import CoreAudio
import SwiftUI

/// The Mac's sound output: which device is playing, and a menu to switch to another.
@MainActor
final class AudioOutput: NSObject, ObservableObject {
    static let shared = AudioOutput()

    /// An SF Symbol for the current device, such as AirPods Pro or the built-in speakers.
    @Published private(set) var symbol = "speaker.wave.2.fill"
    @Published private(set) var popoverShown = false
    private let soundPanel = StatusPanel()

    private override init() {
        super.init()
        refresh()
        var address = AudioProperty.address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectAddPropertyListenerBlock(AudioProperty.system, &address, .main) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    /// As the Mac's Sound menu: Sound, the playing app's volume, then every output, each in a circle,
    /// the one playing in the accent color, and AirPods with each earbud's and their case's
    /// battery, then Sound Settings. At the pointer, or from the keyboard, under the button.
    /// `withVolume` false leaves the playing app's volume out, where it isn't what's heard, as on a
    /// call.
    /// `outputsOnly`, as a call's own: the outputs alone, with no words or settings around them.
    func showMenu(at point: CGPoint? = nil, withVolume: Bool = true, outputsOnly: Bool = false) {
        if withVolume, !outputsOnly { return showPopover(at: point ?? NSEvent.mouseLocation) }
        menu(withVolume: withVolume, outputsOnly: outputsOnly).popUp(positioning: nil, at: point ?? NSEvent.mouseLocation, in: nil)
    }

    private func showPopover(at point: CGPoint) {
        let devices = Self.outputs().sorted { ($0.transport == kAudioDeviceTransportTypeBuiltIn ? 0 : 1) < ($1.transport == kAudioDeviceTransportTypeBuiltIn ? 0 : 1) }
        let content = SoundOutputView(
            devices: devices, current: Self.defaultOutput, volume: AppVolume.shared,
            resize: { [weak self] height in self?.soundPanel.resize(contentHeight: height) },
            choose: { [weak self] device in
                Self.use(device.id)
                self?.soundPanel.close()
            },
            headphoneSettings: { [weak self] device in
                self?.soundPanel.close()
                HeadphoneSettings.open(named: device.name)
            },
            settings: { [weak self] in
                self?.soundPanel.close()
                self?.openSoundSettings()
            })
        let width = max(Self.menuWidth, devices.map { OutputRow(device: $0, playing: false).fittingWidth }.max() ?? 0)
        soundPanel.onClose = { [weak self] _ in self?.popoverShown = false }
        soundPanel.close()
        popoverShown = true
        soundPanel.show(at: point, content: content.frame(width: width).modifier(SoundMenuSurface()))
        popoverShown = soundPanel.isShown
    }

    func menu(withVolume: Bool = true, outputsOnly: Bool = false) -> NSMenu {
        let menu = NSMenu()
        // No check marks: the output playing is filled in.
        menu.showsStateColumn = false
        let volume = AppVolume.shared
        var views: [NSView] = outputsOnly ? [] : [SoundMenuHeading(title: String(localized: "Sound"), main: true)]
        if withVolume, volume.app != nil { views.append(VolumeMenuSlider(volume: volume)) }
        for view in views {
            let item = NSMenuItem()
            item.view = view
            menu.addItem(item)
        }
        if !outputsOnly {
            views.append(Self.addDivider(to: menu, height: 7))
            let heading = NSMenuItem.sectionHeader(title: String(localized: "Output"))
            heading.view = SoundMenuHeading(title: String(localized: "Output"), main: false)
            views.append(heading.view!)
            menu.addItem(heading)
        }
        let current = Self.defaultOutput
        var rows: [OutputRow] = []
        // The Mac's own first, as the Mac's Sound menu lists them.
        let outputs = Self.outputs()
        let builtIn = outputs.filter { $0.transport == kAudioDeviceTransportTypeBuiltIn }
        for device in builtIn + outputs.filter({ $0.transport != kAudioDeviceTransportTypeBuiltIn }) {
            let row = OutputRow(device: device, playing: device.id == current)
            let item = NSMenuItem(title: device.name, action: outputsOnly ? #selector(chooseForCall(_:)) : #selector(choose(_:)), keyEquivalent: "")
            item.target = self
            item.tag = Int(device.id)
            item.state = device.id == current ? .on : .off
            item.view = row
            menu.addItem(item)
            rows.append(row)
        }
        if !outputsOnly {
            views.append(Self.addDivider(to: menu, height: 11))
            let settings = NSMenuItem(title: String(localized: "Sound Settings…"), action: #selector(openSoundSettings), keyEquivalent: "")
            settings.target = self
            settings.view = SoundMenuRow(title: settings.title)
            views.append(settings.view!)
            menu.addItem(settings)
        }
        // As wide as the longest name needs, and every row as wide, so the slider is centered.
        let width = max(Self.menuWidth, rows.map(\.fittingWidth).max() ?? 0)
        for view in views + rows { view.setFrameSize(NSSize(width: width, height: view.frame.height)) }
        // The models and batteries, which System Information takes a moment to tell; kept for next time.
        Task { [weak self] in
            await Self.readBluetooth()
            guard self != nil else { return }
            for row in rows { row.reload() }
        }
        return menu
    }

    /// A line between the menu's parts, as the Mac's Sound menu draws one, in the middle of `height`.
    private static func addDivider(to menu: NSMenu, height: CGFloat) -> NSView {
        let item = NSMenuItem()
        item.view = SoundMenuDivider(height: height)
        item.isEnabled = false
        menu.addItem(item)
        return item.view!
    }

    @objc private func openSoundSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") { NSWorkspace.shared.open(url) }
    }

    /// As wide as the Mac's Sound menu.
    private static let menuWidth: CGFloat = 308
    /// Each Bluetooth device as last read, by its name in lowercase.
    fileprivate static var bluetooth: [String: DeviceWatch.BluetoothInfo] = [:]

    fileprivate static func readBluetooth() async {
        bluetooth.merge(await DeviceWatch.bluetoothReport(), uniquingKeysWith: kept)
    }

    /// A device's latest report, keeping its model from an earlier one: macOS can list a pair
    /// that's just connected before it tells what model they are.
    nonisolated static func kept(_ old: DeviceWatch.BluetoothInfo, _ new: DeviceWatch.BluetoothInfo) -> DeviceWatch.BluetoothInfo {
        var info = new
        info.product = new.product ?? old.product
        info.vendor = new.vendor ?? old.vendor
        info.kind = new.kind ?? old.kind
        return info
    }

    /// While a Bluetooth output's model isn't known yet, the report is read again, as macOS lists a
    /// pair a moment after its sound goes to them, and their model sometimes later still.
    private var modelTask: Task<Void, Never>?
    static let modelRetries: [Double] = [0, 1, 2, 3, 5, 8]

    @objc private func choose(_ item: NSMenuItem) {
        Self.use(AudioDeviceID(item.tag))
    }

    /// On a call, the choice is kept through AirPods' automatic switching, which takes the sound
    /// back to AirPods being worn while a call plays on them, as it can't tell the choice was made
    /// by hand: the call's app takes a second or so to follow the Mac's output, and its sound left on
    /// the AirPods until then is what brings them back. Put back at most twice, for a few seconds,
    /// so it never keeps on against anything else.
    @objc private func chooseForCall(_ item: NSMenuItem) {
        let id = AudioDeviceID(item.tag)
        chosen = Choice(device: id, at: .now, left: Choice.putBacks)
        Self.use(id)
    }

    struct Choice: Equatable {
        var device: AudioDeviceID
        var at: Date
        var left: Int
        static let putBacks = 2
        static let keptFor: TimeInterval = 6

        /// Whether the output's having changed to `current` is taken back to the choice.
        func putsBack(_ current: AudioDeviceID, at now: Date) -> Bool {
            current != device && left > 0 && now.timeIntervalSince(at) < Self.keptFor
        }
    }

    private var chosen: Choice?

    private static func use(_ device: AudioDeviceID) {
        var id = device
        var address = AudioProperty.address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectSetPropertyData(AudioProperty.system, &address, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &id)
    }

    private func refresh() {
        let current = Self.defaultOutput
        if var choice = chosen {
            if choice.putsBack(current, at: .now), Self.outputs().contains(where: { $0.id == choice.device }) {
                choice.left -= 1
                chosen = choice
                Self.use(choice.device)
                return
            }
            if current != choice.device || Date.now.timeIntervalSince(choice.at) >= Choice.keptFor { chosen = nil }
        }
        let device = Self.outputs().first { $0.id == current }
        symbol = device?.model?.symbol ?? device?.symbol ?? "speaker.wave.2.fill"
        // Bluetooth headphones are pictured as their model once System Information has told it,
        // which can take a few seconds after they've connected.
        modelTask?.cancel()
        guard let device, DeviceWatch.isBluetooth(device.transport), device.model == nil else { return }
        modelTask = Task { [weak self] in
            for wait in Self.modelRetries {
                try? await Task.sleep(for: .seconds(wait))
                guard !Task.isCancelled, Self.defaultOutput == device.id else { return }
                await Self.readBluetooth()
                guard !Task.isCancelled else { return }
                if let model = Self.outputs().first(where: { $0.id == device.id })?.model {
                    self?.symbol = model.symbol
                    return
                }
            }
        }
    }

    // MARK: Core Audio

    /// A place the sound can go, with its symbol, and how it's connected.
    struct Device: Equatable {
        let id: AudioDeviceID
        let name: String
        let symbol: String
        let transport: UInt32

        /// How macOS pictures this very model, once it's known: Bluetooth headphones by what System
        /// Information reports of them, anything else that names its model by that.
        @MainActor var model: DeviceSymbols? {
            if DeviceWatch.isBluetooth(transport) {
                return AudioOutput.bluetooth[name.lowercased()]?.modelSymbols
            }
            return AudioProperty.modelUID(of: id).flatMap(SystemDevices.symbols(model:))
        }

        /// As the Mac's Sound menu pictures it: the Mac itself for its own speakers, the model
        /// macOS knows it as, a display or a TV for one, otherwise what it is, outlined.
        @MainActor var pictured: String {
            let builtIn = transport == kAudioDeviceTransportTypeBuiltIn && !name.lowercased().contains("headphone")
            if builtIn { return SystemDevices.thisMac.symbol }
            if let model { return model.symbol }
            switch transport {
            case kAudioDeviceTransportTypeHDMI: return "tv"
            case kAudioDeviceTransportTypeDisplayPort: return "display"
            default: return symbol.replacingOccurrences(of: ".fill", with: "")
            }
        }
    }

    static var defaultOutput: AudioDeviceID {
        var id = AudioDeviceID(0)
        _ = AudioProperty.read(AudioProperty.system, kAudioHardwarePropertyDefaultOutputDevice, &id)
        return id
    }

    static func outputs() -> [Device] {
        AudioProperty.readArray(AudioProperty.system, kAudioHardwarePropertyDevices)
            .filter { AudioProperty.size(of: $0, kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput) > 0 }
            .filter { !(AudioProperty.uid(of: $0)?.hasPrefix(AudioProperty.ownDevicePrefix) ?? false) }
            // macOS's own hidden aggregate, made while an app records and plays at once, isn't a place to play.
            .filter { !Self.isSystemAggregate(uid: AudioProperty.uid(of: $0)) }
            .map { id in
                var name: Unmanaged<CFString>?
                var transport: UInt32 = 0
                _ = AudioProperty.read(id, kAudioObjectPropertyName, &name)
                _ = AudioProperty.read(id, kAudioDevicePropertyTransportType, &transport)
                let title = name?.takeRetainedValue() as String? ?? String(localized: "Output")
                return Device(id: id, name: title, symbol: symbol(name: title, transport: transport), transport: transport)
            }
    }

    nonisolated static func isSystemAggregate(uid: String?) -> Bool {
        uid?.hasPrefix("CADefaultDeviceAggregate") == true
    }

    /// What it is, until macOS says which model (see `Device.model`).
    static func symbol(name: String, transport: UInt32) -> String {
        if name.lowercased().contains("headphone") { return "headphones" }
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn: return "speaker.wave.2.fill"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return "headphones"
        case kAudioDeviceTransportTypeAirPlay: return "airplayaudio"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: return "tv"
        default: return "hifispeaker.fill"
        }
    }
}

/// A single glass surface, sized like the sound menu, outside menu event tracking.
private struct SoundMenuSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: SoundMenu.radius, style: .continuous))
            .shadow(color: .black.opacity(0.16), radius: 12, y: 5)
    }
}

/// The system's SwiftUI slider, with a white track and no custom pointer handling.
final class VolumeMenuSlider: NSView {
    init(volume: AppVolume) {
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 30))
        autoresizingMask = [.width]
        let level = VolumeSlider.Level(volume.level) { [weak volume] in volume?.set($0) }
        let host = NSHostingView(rootView: VolumeSlider(volume: volume, level: level))
        host.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: leadingAnchor, constant: SoundMenu.inset),
            host.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -SoundMenu.inset),
            host.topAnchor.constraint(equalTo: topAnchor), host.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }

    struct VolumeSlider: View {
        let volume: AppVolume?
        @ObservedObject var level: Level

        /// The binding's value and a revision, so a read begun before an edit cannot undo it.
        final class Level: ObservableObject {
            @Published private(set) var value: Double
            private let moved: (Double) -> Void
            private(set) var revision = 0

            init(_ value: Double, moved: @escaping (Double) -> Void) {
                self.value = value
                self.moved = moved
            }

            func move(to value: Double) {
                guard value != self.value else { return }
                self.value = value
                revision += 1
                moved(value)
            }

            func show(_ value: Double, since revision: Int) {
                guard revision == self.revision else { return }
                self.value = value
            }
        }

        var body: some View {
            Slider(value: Binding(get: { level.value }, set: level.move), in: 0...1) {
                Text("Sound")
            } minimumValueLabel: {
                Image(systemName: "speaker.fill").font(.system(size: 12))
            } maximumValueLabel: {
                Image(systemName: "speaker.wave.3.fill").font(.system(size: 12))
            }
            .labelsHidden()
            .tint(.white)
            .disabled(volume?.canChange == false)
            .task {
                guard let volume else { return }
                let revision = level.revision
                await volume.refresh()
                level.show(volume.level, since: revision)
            }
        }
    }
}

/// An arrowless native panel, outside NSMenu's tracking loop, so the system slider receives
/// ordinary events in its own key window. The surrounding rows keep the sound outputs' pictures and batteries.
private struct SoundOutputView: View {
    @State private var devices: [AudioOutput.Device]
    @State private var current: AudioDeviceID
    let volume: AppVolume?
    let choose: (AudioOutput.Device) -> Void
    let settings: () -> Void
    let headphoneSettings: (AudioOutput.Device) -> Void
    let resize: (CGFloat) -> Void
    @State private var expanded: AudioDeviceID?
    @State private var modes: [AudioDeviceID: ListeningMode.Snapshot] = [:]
    @State private var changing = false
    @State private var failed = false
    @StateObject private var level: VolumeMenuSlider.VolumeSlider.Level
    @State private var refreshed = false
    @State private var hovered: AudioDeviceID?
    @State private var settingsHovered = false

    init(
        devices: [AudioOutput.Device], current: AudioDeviceID, volume: AppVolume?, resize: @escaping (CGFloat) -> Void, choose: @escaping (AudioOutput.Device) -> Void,
        headphoneSettings: @escaping (AudioOutput.Device) -> Void, settings: @escaping () -> Void
    ) {
        _devices = State(initialValue: devices)
        _current = State(initialValue: current)
        _modes = State(initialValue: Self.listeningModes(for: devices))
        self.resize = resize
        self.volume = volume
        self.choose = choose
        self.settings = settings
        self.headphoneSettings = headphoneSettings
        _level = StateObject(wrappedValue: .init(volume?.level ?? 1) { [weak volume] in volume?.set($0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Sound").font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, SoundMenu.inset).padding(.vertical, 8)
            if volume?.app != nil {
                VolumeMenuSlider.VolumeSlider(volume: volume, level: level)
                    .padding(.horizontal, SoundMenu.inset).frame(height: 20)
            }
            Divider().padding(.horizontal, SoundMenu.inset).padding(.vertical, 5)
            Text("Output").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, SoundMenu.inset).padding(.top, 6).padding(.bottom, 4)
            ForEach(devices, id: \.id) { device in
                HStack(spacing: 0) {
                    Button {
                        choose(device)
                    } label: {
                        SoundOutputRow(device: device, playing: device.id == current, refreshed: refreshed)
                            .id(device.name + (device.id == current ? "selected" : ""))
                            .frame(height: SoundMenu.rowHeight).allowsHitTesting(false)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(device.name)
                    .accessibilityAddTraits(device.id == current ? .isSelected : [])
                    if modes[device.id] != nil {
                        Button {
                            expanded = expanded == device.id ? nil : device.id
                            failed = false
                        } label: {
                            Image(systemName: expanded == device.id ? "chevron.down" : "chevron.right")
                                .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                                .frame(width: 30, height: SoundMenu.rowHeight).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(device.name + ", " + SoundSystemResources.text("Listening Mode", table: "ListeningMode"))
                        .accessibilityValue(expanded == device.id ? String(localized: "Expanded") : String(localized: "Collapsed"))
                        .padding(.trailing, 5)
                    }
                }
                .background {
                    RoundedRectangle(cornerRadius: SoundMenu.highlightRadius)
                        .fill(.quaternary.opacity(hovered == device.id ? 1 : 0))
                        .padding(.horizontal, SoundMenu.highlightInset)
                }
                .onHover { hovered = $0 ? device.id : nil }
                if expanded == device.id, let snapshot = modes[device.id] {
                    listeningControls(device: device, snapshot: snapshot)
                }
            }
            Divider().padding(.horizontal, SoundMenu.highlightInset).padding(.top, 6).padding(.bottom, 1)
            if modes[current] != nil, let device = devices.first(where: { $0.id == current }) {
                Button {
                    headphoneSettings(device)
                } label: {
                    Text(String(format: SoundSystemResources.text("%@ Settings…"), device.name))
                        .font(.system(size: 13)).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, SoundMenu.inset).padding(.vertical, 5).contentShape(Rectangle())
                }
                .buttonStyle(SoundChoiceStyle())
            }
            Button(action: settings) {
                Text("Sound Settings…").font(.system(size: 13))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, SoundMenu.inset).padding(.vertical, 5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background {
                RoundedRectangle(cornerRadius: SoundMenu.highlightRadius)
                    .fill(.quaternary.opacity(settingsHovered ? 1 : 0))
                    .padding(.horizontal, SoundMenu.highlightInset)
            }
            .onHover { settingsHovered = $0 }
        }
        .padding(.vertical, 5)
        .onGeometryChange(for: CGFloat.self) {
            $0.size.height
        } action: {
            resize($0)
        }
        .task {
            await AudioOutput.readBluetooth()
            refreshed = true
            while !Task.isCancelled {
                let devices = AudioOutput.outputs().sorted { ($0.transport == kAudioDeviceTransportTypeBuiltIn ? 0 : 1) < ($1.transport == kAudioDeviceTransportTypeBuiltIn ? 0 : 1) }
                if self.devices != devices { self.devices = devices }
                current = AudioOutput.defaultOutput
                let latest = Self.listeningModes(for: devices)
                if latest != modes { modes = latest }
                if let expanded, latest[expanded] == nil { self.expanded = nil }
                try? await Task.sleep(for: .seconds(1))
                if !AudioOutput.shared.popoverShown { return }
            }
        }
    }

    private static func listeningModes(for devices: [AudioOutput.Device]) -> [AudioDeviceID: ListeningMode.Snapshot] {
        var states: [AudioDeviceID: ListeningMode.Snapshot] = [:]
        for device in devices where DeviceWatch.isBluetooth(device.transport) {
            if let state = ListeningMode.read(device.id) { states[device.id] = state }
        }
        return states
    }

    private func listeningControls(device: AudioOutput.Device, snapshot: ListeningMode.Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(SoundSystemResources.text("Listening Mode", table: "ListeningMode"))
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, SoundMenu.inset).padding(.top, 12).padding(.bottom, 4)
            ForEach(snapshot.available, id: \.rawValue) { mode in
                Button {
                    changing = true
                    failed = false
                    Task {
                        let success = await ListeningMode.change(device.id, to: mode)
                        if let state = ListeningMode.read(device.id) { modes[device.id] = state }
                        changing = false
                        failed = !success
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark").font(.system(size: 12, weight: .medium))
                            .opacity(snapshot.current == mode ? 1 : 0).frame(width: 26)
                        Image(nsImage: SoundSystemResources.image(mode.symbol))
                            .resizable().scaledToFit().frame(width: 16, height: 16)
                        Text(mode.title).font(.system(size: 13))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, SoundMenu.inset).frame(height: 24).contentShape(Rectangle())
                }
                .buttonStyle(SoundChoiceStyle())
                .disabled(changing || !snapshot.writable)
                .accessibilityAddTraits(snapshot.current == mode ? .isSelected : [])
            }
            if failed {
                Text(String(localized: "Couldn’t change listening mode. Try again."))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .padding(.horizontal, SoundMenu.inset).padding(.top, 6)
            }
        }
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5))
    }

}

private struct SoundChoiceStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SoundChoiceLabel(configuration: configuration)
    }

    private struct SoundChoiceLabel: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovered = false
        var body: some View {
            configuration.label
                .background {
                    RoundedRectangle(cornerRadius: SoundMenu.highlightRadius)
                        .fill(.quaternary.opacity(hovered || configuration.isPressed ? 1 : 0))
                        .padding(.horizontal, SoundMenu.highlightInset)
                }
                .onHover { hovered = $0 }
        }
    }
}

private struct SoundOutputRow: NSViewRepresentable {
    let device: AudioOutput.Device
    let playing: Bool
    let refreshed: Bool

    func makeNSView(context: Context) -> OutputRow { OutputRow(device: device, playing: playing) }
    func updateNSView(_ view: OutputRow, context: Context) { view.reload() }
}

/// The sound output menu's measures, as the Mac's Sound menu has them: no check marks, its
/// headings, rows and separators the same way in from both sides.
private enum SoundMenu {
    /// The menu's corners, as macOS draws them: it keeps its own outline, whatever's asked of its glass.
    static let radius: CGFloat = 16
    static let inset: CGFloat = 14
    /// Each output's circle, and between it and its name.
    static let circle: CGFloat = 26
    static let gap: CGFloat = 8
    static let rowHeight: CGFloat = 32
    /// A row under the pointer: lighter, in from the menu's sides, its corners as much rounder
    /// than the menu's as they're inset.
    static let highlightInset: CGFloat = 5
    static let highlightRadius = radius - highlightInset

    static func drawHighlight(in bounds: NSRect) {
        highlightColor.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: highlightInset, dy: 0), xRadius: highlightRadius, yRadius: highlightRadius).fill()
    }

    /// White in the dark menu, black in the light one.
    private static func shade(dark: CGFloat, light: CGFloat) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 1, alpha: dark) : NSColor(white: 0, alpha: light)
        }
    }

    private static let highlightColor = shade(dark: 0.1, light: 0.055)
    /// An output's circle: light gray, or for the one playing, the accent color made a little
    /// lighter, as the Mac's Sound menu has them.
    static let circleGray = shade(dark: 0.22, light: 0.08)
    static var circlePlaying: NSColor { NSColor.controlAccentColor.blended(withFraction: 0.15, of: .white) ?? .controlAccentColor }
    /// The Output heading, the slider's speakers, and an AirPods' batteries, as light as the Mac's
    /// draw them.
    static let headingGray = shade(dark: 0.45, light: 0.5)
    static let speakerGray = shade(dark: 0.62, light: 0.5)
    static let batteryGray = shade(dark: 0.5, light: 0.45)
}

/// A line between the sound output menu's parts, as far in from both sides as everything else.
private final class SoundMenuDivider: NSView {
    init(height: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: height))
        autoresizingMask = [.width]
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.setFill()
        NSRect(x: SoundMenu.inset, y: (bounds.height - 1) / 2, width: bounds.width - SoundMenu.inset * 2, height: 1).fill()
    }
}

/// A plain row in the sound output menu, as Sound Settings is in the Mac's: its title, highlighted
/// under the pointer as the outputs are; clicking it does what it says.
private final class SoundMenuRow: NSView {
    private let label: NSTextField

    init(title: String) {
        label = NSTextField(labelWithString: title)
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: 22))
        autoresizingMask = [.width]
        label.font = .systemFont(ofSize: 13)
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: SoundMenu.inset),
            label.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -1),
        ])
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        if enclosingMenuItem?.isHighlighted == true { SoundMenu.drawHighlight(in: bounds) }
    }

    override func mouseUp(with event: NSEvent) {
        guard let item = enclosingMenuItem, let menu = item.menu else { return }
        menu.cancelTracking()
        menu.performActionForItem(at: menu.index(of: item))
    }
}

/// A heading in the sound output menu: Sound, bold, at the top; or Output, smaller, in gray. Each
/// sits as far below the one before as in the Mac's Sound menu.
private final class SoundMenuHeading: NSView {
    private let main: Bool

    init(title: String, main: Bool) {
        self.main = main
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: main ? 26.5 : 24))
        autoresizingMask = [.width]
        let label = NSTextField(labelWithString: title)
        label.font = main ? .systemFont(ofSize: 13, weight: .semibold) : .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = main ? .labelColor : SoundMenu.headingGray
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: SoundMenu.inset),
            label.centerYAnchor.constraint(equalTo: centerYAnchor, constant: main ? 2.75 : 1),
        ])
    }

    required init?(coder: NSCoder) { nil }
}

/// An output in the sound output menu, as the Mac's Sound menu shows it: its symbol in a circle,
/// light gray with the symbol gray, or the accent color with the symbol white for the one playing,
/// beside its name, and under it, for AirPods, each earbud's battery and the case's, or the one
/// battery of other headphones. AirPods are drawn as the Mac draws them there, their two earbuds
/// side by side. Highlighted under the pointer; clicking it chooses it.
private final class OutputRow: NSView {
    let device: AudioOutput.Device
    private let playing: Bool
    private let symbol = NSImageView()
    private let name = NSTextField(labelWithString: "")
    private let battery = NSTextField(labelWithString: "")

    /// Pictures it and tells its batteries as they're known now.
    func reload() {
        let color: NSColor = playing ? .white : .labelColor
        symbol.image = Self.picture(device.pictured, color: color)
        let levels = AudioOutput.bluetooth[device.name.lowercased()]?.levels
        battery.attributedStringValue = levels.map { Self.text($0, symbols: device.model) } ?? NSAttributedString()
        battery.isHidden = battery.attributedStringValue.length == 0
        needsLayout = true
    }

    init(device: AudioOutput.Device, playing: Bool) {
        self.device = device
        self.playing = playing
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: SoundMenu.rowHeight))
        autoresizingMask = [.width]
        symbol.contentTintColor = playing ? .white : .labelColor
        name.stringValue = device.name
        name.font = .systemFont(ofSize: 13)
        name.textColor = .labelColor
        name.lineBreakMode = .byTruncatingTail
        battery.font = .systemFont(ofSize: 11, weight: .medium)
        battery.textColor = SoundMenu.batteryGray
        for view in [symbol, name, battery] { addSubview(view) }
        defer { reload() }
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        // Symbols created before this view joins the panel otherwise retain the old appearance.
        effectiveAppearance.performAsCurrentDrawingAppearance { reload() }
    }

    /// Wide enough for its name and its batteries in full.
    var fittingWidth: CGFloat {
        let widest = Self.text(DeviceWatch.Levels(left: 100, right: 100, chargingCase: 100), symbols: device.model)
        let text = max(name.intrinsicContentSize.width, widest.size().width)
        return SoundMenu.inset + SoundMenu.circle + SoundMenu.gap + ceil(text) + SoundMenu.inset + 4
    }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let textX = SoundMenu.inset + SoundMenu.circle + SoundMenu.gap
        let textWidth = bounds.width - textX - SoundMenu.inset
        // Half a point above the circle's middle, as the Mac sets its pictures.
        symbol.frame = circleRect.offsetBy(dx: 0, dy: -0.5)
        // At the far end of the row from the circle, right to left.
        func placed(_ rect: NSRect) -> NSRect {
            userInterfaceLayoutDirection == .leftToRight ? rect : NSRect(x: bounds.width - rect.maxX, y: rect.minY, width: rect.width, height: rect.height)
        }
        let nameHeight = name.intrinsicContentSize.height, batteryHeight = battery.intrinsicContentSize.height
        // By their text, which starts a little way into a label's frame.
        if battery.isHidden {
            name.frame = name.frame(forAlignmentRect: placed(NSRect(x: textX, y: (bounds.height - nameHeight) / 2, width: textWidth, height: nameHeight)))
        } else {
            // Name and batteries together, centered on the circle.
            let top = (bounds.height - nameHeight - batteryHeight) / 2
            name.frame = name.frame(forAlignmentRect: placed(NSRect(x: textX, y: top, width: textWidth, height: nameHeight)))
            battery.frame = battery.frame(forAlignmentRect: placed(NSRect(x: textX, y: top + nameHeight, width: textWidth, height: batteryHeight)))
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        if enclosingMenuItem?.isHighlighted == true { SoundMenu.drawHighlight(in: bounds) }
        (playing ? SoundMenu.circlePlaying : SoundMenu.circleGray).setFill()
        NSBezierPath(ovalIn: circleRect).fill()
    }

    private var circleRect: NSRect {
        let circle = SoundMenu.circle
        let x = userInterfaceLayoutDirection == .leftToRight ? SoundMenu.inset : bounds.width - SoundMenu.inset - circle
        return NSRect(x: x, y: (bounds.height - circle) / 2, width: circle, height: circle)
    }

    /// Chooses it, as the menu's own items are chosen: the menu closes, then it plays there.
    override func mouseUp(with event: NSEvent) {
        guard let item = enclosingMenuItem, let menu = item.menu else { return }
        menu.cancelTracking()
        menu.performActionForItem(at: menu.index(of: item))
    }

    /// The device's picture in its circle, as large as the Mac's Sound menu has them, its parts in
    /// shades of `color`, as the Mac draws a laptop's screen and an earbud's tip.
    private static func picture(_ symbol: String, color: NSColor) -> NSImage? {
        (NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: "speaker.wave.2", accessibilityDescription: nil))?
            .withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: 14, weight: .regular).applying(.init(hierarchicalColor: color)))
    }

    /// Each earbud's level and the case's, in the shapes macOS gives this model, the earbuds as one
    /// pair when they're level, or the one battery's, each after its symbol.
    private static func text(_ levels: DeviceWatch.Levels, symbols: DeviceSymbols?) -> NSAttributedString {
        let parts: [(String, Int?)] =
            if let left = levels.left, left == levels.right {
                [(symbols?.symbol ?? "airpods", left), (symbols?.chargingCase ?? "airpods.chargingcase.fill", levels.chargingCase)]
            } else if levels.left != nil || levels.right != nil {
                [
                    (symbols?.left ?? "airpod.left", levels.left), (symbols?.right ?? "airpod.right", levels.right),
                    (symbols?.chargingCase ?? "airpods.chargingcase.fill", levels.chargingCase),
                ]
            } else {
                [(Self.batterySymbol(levels.main ?? 0), levels.main)]
            }
        let text = NSMutableAttributedString()
        let font = NSFont.systemFont(ofSize: 11, weight: .medium)
        for (symbol, level) in parts {
            guard let level else { continue }
            if text.length > 0 { text.append(NSAttributedString(string: "  ", attributes: [.font: font, .kern: 0.5])) }
            // Each earbud and the case with its tip or lid a lighter shade, as the Mac draws them.
            let size: CGFloat = symbol.contains("chargingcase") ? 12 : 11
            if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(
                    NSImage.SymbolConfiguration(pointSize: size, weight: .medium).applying(.init(hierarchicalColor: SoundMenu.batteryGray)))
            {
                let attachment = NSTextAttachment()
                attachment.image = image
                text.append(NSAttributedString(attachment: attachment))
                // As far from its level as the Mac's.
                text.append(NSAttributedString(string: " ", attributes: [.font: font, .kern: 0.5]))
            }
            text.append(NSAttributedString(string: level.formatted(.percent), attributes: [.font: font]))
        }
        text.addAttribute(.foregroundColor, value: SoundMenu.batteryGray, range: NSRange(location: 0, length: text.length))
        return text
    }

    private static func batterySymbol(_ level: Int) -> String {
        switch level {
        case 88...: "battery.100percent"
        case 63...: "battery.75percent"
        case 38...: "battery.50percent"
        case 13...: "battery.25percent"
        default: "battery.0percent"
        }
    }
}

/// Reading Core Audio's properties, for the sound output, the waveform's tap and the app volume.
enum AudioProperty {
    static let system = AudioObjectID(kAudioObjectSystemObject)

    /// The start of the identifier of each device Glance makes for itself: the private devices its
    /// audio taps run through, for the waveform and the volume slider. macOS shows them to no other
    /// app, but does to Glance, which leaves them out of the outputs it lists.
    static let ownDevicePrefix = "dev.vibe.Glance."

    static func uid(of device: AudioObjectID) -> String? {
        var uid: Unmanaged<CFString>?
        guard read(device, kAudioDevicePropertyDeviceUID, &uid) else { return nil }
        return uid?.takeRetainedValue() as String?
    }

    /// The model a device says it is, for those that say.
    static func modelUID(of device: AudioObjectID) -> String? {
        var uid: Unmanaged<CFString>?
        guard read(device, kAudioDevicePropertyModelUID, &uid) else { return nil }
        return uid?.takeRetainedValue() as String?
    }

    static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func read<T: BitwiseCopyable>(
        _ object: AudioObjectID, _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        _ value: inout T
    ) -> Bool {
        var address = address(selector, scope: scope)
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr
    }

    static func readArray(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
        var address = address(selector)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &objects) == noErr else { return [] }
        return objects
    }

    /// How long after a device is handed sound it's heard, in seconds: what it says it takes, its
    /// stream's, its margin and its buffer. A moment on the Mac's speakers; on AirPods, a sixth of
    /// a second or so.
    static func outputLatency(of device: AudioObjectID) -> TimeInterval {
        let output = kAudioObjectPropertyScopeOutput
        var latency: UInt32 = 0, safety: UInt32 = 0, buffer: UInt32 = 0, stream: UInt32 = 0, rate: Float64 = 0
        guard read(device, kAudioDevicePropertyNominalSampleRate, &rate), rate > 0 else { return 0 }
        _ = read(device, kAudioDevicePropertyLatency, scope: output, &latency)
        _ = read(device, kAudioDevicePropertySafetyOffset, scope: output, &safety)
        _ = read(device, kAudioDevicePropertyBufferFrameSize, scope: output, &buffer)
        var address = address(kAudioDevicePropertyStreams, scope: output)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var first = AudioObjectID(0)
        if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &first) == noErr, first != 0 {
            _ = read(first, kAudioStreamPropertyLatency, &stream)
        }
        return Double(latency + safety + buffer + stream) / rate
    }

    /// The property's size in bytes, 0 if it has none.
    static func size(of object: AudioObjectID, _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope) -> UInt32 {
        var address = address(selector, scope: scope)
        var size: UInt32 = 0
        AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size)
        return size
    }

    /// Every audio process an app is responsible for: browsers play through helper processes, so
    /// the process Now Playing names is matched by who is responsible for it, too.
    static func processes(of pid: pid_t) -> [AudioObjectID] {
        let owner = responsible(for: pid)
        let matches = readArray(system, kAudioHardwarePropertyProcessObjectList).filter { object in
            var processPID: pid_t = -1
            guard read(object, kAudioProcessPropertyPID, &processPID), processPID > 0 else { return false }
            return processPID == pid || responsible(for: processPID) == owner
        }
        if !matches.isEmpty { return matches }
        var pid = pid
        var object = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = address(kAudioHardwarePropertyTranslatePIDToProcessObject)
        let status = AudioObjectGetPropertyData(system, &address, UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object)
        return status == noErr && object != 0 ? [object] : []
    }

    /// The app answerable for a process (Safari for its WebKit helpers), from libSystem.
    static func responsible(for pid: pid_t) -> pid_t {
        typealias Responsible = @convention(c) (pid_t) -> pid_t
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid")
        else { return pid }
        let owner = unsafeBitCast(symbol, to: Responsible.self)(pid)
        return owner > 0 ? owner : pid
    }
}
