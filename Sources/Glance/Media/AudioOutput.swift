//
//  AudioOutput.swift
//  Glance
//
//  Created by Gaty on 07/10/2026.
//

import AppKit
import Carbon.HIToolbox
import Combine
import CoreAudio
import SwiftUI

/// The Mac's sound output: which device is playing, and a menu to switch to another.
@MainActor
final class AudioOutput: NSObject, ObservableObject {
    static let shared = AudioOutput()

    /// An SF Symbol for the current device, such as AirPods Pro or the built-in speakers.
    @Published private(set) var symbol = "speaker.wave.2.fill"
    /// Only the laptop speaker uses a variable symbol; other outputs keep their model's image.
    @Published private(set) var speakerLevel: Double?
    var buttonSymbol: String {
        guard let speakerLevel else { return symbol }
        return speakerLevel > 0 ? "speaker.wave.3.fill" : "speaker.slash.fill"
    }
    @Published private(set) var devices: [Device] = []
    @Published private(set) var current = AudioDeviceID(0)
    private var appVolumeWatch: AnyCancellable?
    private var watchedOutput = AudioDeviceID(0)
    private var volumeWatches: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    private override init() {
        super.init()
        refresh()
        var address = AudioProperty.address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectAddPropertyListenerBlock(AudioProperty.system, &address, .main) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        address = AudioProperty.address(kAudioHardwarePropertyDevices)
        AudioObjectAddPropertyListenerBlock(AudioProperty.system, &address, .main) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        appVolumeWatch = AppVolume.shared.$level.removeDuplicates().sink { [weak self] level in
            self?.refreshSymbol(appLevel: level)
        }
    }

    /// As the Mac's Sound menu: Sound, the playing app's volume, then every output, each in a circle,
    /// the one playing in the accent color, and AirPods with each earbud's and their case's
    /// battery, then Sound Settings. Its arrow points to the button center.
    /// `withVolume` false leaves the playing app's volume out, where it isn't what's heard, as on a
    /// call.
    /// `outputsOnly`, as a call's own: the outputs alone, with no words or settings around them.
    private var callMenu: SoundOutputMenu?

    func showMenu(at point: CGPoint? = nil, withVolume: Bool = true, outputsOnly: Bool = false) {
        callMenu?.dismiss()
        let point = point ?? NSEvent.mouseLocation
        guard let anchor = NSApp.windows.first(where: { $0 is NotchPanel && $0.isVisible && $0.frame.contains(point) })?.contentView else { return }
        let menu = menu(withVolume: withVolume, outputsOnly: outputsOnly)
        callMenu = menu
        menu.present(from: anchor, pointer: point) { [weak self, weak menu] in
            guard self?.callMenu === menu else { return }
            self?.callMenu = nil
        }
    }

    func soundMenu() -> SoundOutputMenu { menu() }

    func refreshDevices() { refresh() }

    func chooseOutput(_ device: Device) { Self.use(device.id) }

    /// Calls and the player share their rows, glass and interaction. A call retains its temporary
    /// output choice through automatic headphone switching.
    func menu(withVolume: Bool = true, outputsOnly: Bool = false) -> SoundOutputMenu {
        refreshDevices()
        let menu = SoundOutputMenu(
            devices: devices, current: current, volume: AppVolume.shared,
            withVolume: withVolume, outputsOnly: outputsOnly,
            choose: { [weak self] device in
                if outputsOnly { self?.chooseForCall(device.id) } else { self?.chooseOutput(device) }
            }, settings: openSoundSettings)
        menu.follow(self)
        return menu
    }

    @objc fileprivate func openSoundSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") { NSWorkspace.shared.open(url) }
    }

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
    nonisolated static let modelRetries: [Double] = [0, 1, 2, 3, 5, 8]

    /// On a call, the choice is kept through AirPods' automatic switching, which takes the sound
    /// back to AirPods being worn while a call plays on them, as it can't tell the choice was made
    /// by hand: the call's app takes a second or so to follow the Mac's output, and its sound left on
    /// the AirPods until then is what brings them back. Put back at most twice, for a few seconds,
    /// so it never keeps on against anything else.
    private func chooseForCall(_ id: AudioDeviceID) {
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
        devices = Self.outputs()
        self.current = current
        watchVolume(of: current)
        refreshSymbol(appLevel: AppVolume.shared.level)
        let device = devices.first { $0.id == current }
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

    /// Device changes rebuild the volume listeners; volume changes only redraw the symbol.
    private func watchVolume(of device: AudioDeviceID) {
        guard device != watchedOutput else { return }
        for (var address, listener) in volumeWatches {
            AudioObjectRemovePropertyListenerBlock(watchedOutput, &address, .main, listener)
        }
        volumeWatches.removeAll()
        watchedOutput = device
        guard device != 0 else { return }
        for selector in [kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute] {
            for channel: AudioObjectPropertyElement in [kAudioObjectPropertyElementMain, 1, 2] {
                var address = AudioProperty.address(selector, scope: kAudioObjectPropertyScopeOutput)
                address.mElement = channel
                guard AudioObjectHasProperty(device, &address) else { continue }
                let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                    MainActor.assumeIsolated {
                        self?.refreshSymbol(appLevel: AppVolume.shared.level)
                    }
                }
                if AudioObjectAddPropertyListenerBlock(device, &address, .main, listener) == noErr {
                    volumeWatches.append((address, listener))
                }
            }
        }
    }

    private func refreshSymbol(appLevel: Double) {
        let device = devices.first { $0.id == current }
        let hardware = Self.outputLevel(of: current)
        symbol = Self.controlSymbol(device: device, appLevel: appLevel, outputLevel: hardware.level, muted: hardware.muted)
        speakerLevel = symbol.hasPrefix("speaker.") ? (hardware.muted ? 0 : min(max(appLevel * hardware.level, 0), 1)) : nil
    }

    nonisolated static func speakerSymbol(level: Double, muted: Bool) -> String {
        if muted || level <= 0 { return "speaker.slash.fill" }
        if level <= 1.0 / 3.0 { return "speaker.wave.1.fill" }
        if level <= 2.0 / 3.0 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    static func controlSymbol(device: Device?, appLevel: Double, outputLevel: Double, muted: Bool) -> String {
        let level = appLevel * outputLevel
        guard let device else { return speakerSymbol(level: level, muted: muted) }
        if device.transport == kAudioDeviceTransportTypeBuiltIn, device.symbol != "headphones" {
            return speakerSymbol(level: level, muted: muted)
        }
        return device.model?.symbol ?? device.symbol
    }

    private static func outputLevel(of device: AudioDeviceID) -> (level: Double, muted: Bool) {
        func value<T: BitwiseCopyable>(_ selector: AudioObjectPropertySelector, channel: AudioObjectPropertyElement, initial: T) -> T? {
            var address = AudioProperty.address(selector, scope: kAudioObjectPropertyScopeOutput)
            address.mElement = channel
            var result = initial
            var size = UInt32(MemoryLayout<T>.size)
            guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &result) == noErr else { return nil }
            return result
        }
        let main = value(kAudioDevicePropertyVolumeScalar, channel: kAudioObjectPropertyElementMain, initial: Float32(1))
        let channels = [1, 2].compactMap { value(kAudioDevicePropertyVolumeScalar, channel: $0, initial: Float32(1)) }
        let level = main.map(Double.init) ?? (channels.isEmpty ? 1 : Double(channels.reduce(0, +)) / Double(channels.count))
        let muted = value(kAudioDevicePropertyMute, channel: kAudioObjectPropertyElementMain, initial: UInt32(0)) == 1
        return (min(max(level, 0), 1), muted)
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
            .filter { id in
                var alive: UInt32 = 1, eligible: UInt32 = 1, hidden: UInt32 = 0
                _ = AudioProperty.read(id, kAudioDevicePropertyDeviceIsAlive, &alive)
                _ = AudioProperty.read(id, kAudioDevicePropertyDeviceCanBeDefaultDevice, scope: kAudioObjectPropertyScopeOutput, &eligible)
                _ = AudioProperty.read(id, kAudioDevicePropertyIsHidden, &hidden)
                return alive != 0 && eligible != 0 && hidden == 0
            }
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

/// An AppKit slider handles clicks, drags and accessibility through the native control, with
/// a revisioned value so an asynchronous volume read cannot undo an edit.
final class VolumeMenuSlider: NSView {
    let level: VolumeSlider.Level
    private var volumeWatch: AnyCancellable?

    init(volume: AppVolume?, level: VolumeSlider.Level? = nil) {
        let inset = SoundLook.inset
        self.level = level ?? VolumeSlider.Level(volume?.level ?? 0.5) { [weak volume] in volume?.set($0) }
        super.init(frame: NSRect(x: 0, y: 0, width: SoundLook.width, height: SoundLook.sliderHeight))
        autoresizingMask = [.width]
        let host = NSHostingView(rootView: VolumeSlider(volume: volume, level: self.level).environment(\.controlActiveState, .key))
        if let volume {
            volumeWatch = volume.objectWillChange.sink { [weak self, weak host] in
                Task { @MainActor in
                    guard let self else { return }
                    host?.rootView = VolumeSlider(volume: volume, level: self.level).environment(\.controlActiveState, .key)
                }
            }
        }
        host.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            host.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
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
            HStack(spacing: 4) {
                Image(systemName: "speaker.fill")
                    .resizable().scaledToFit()
                    .font(.system(size: 12, weight: .medium))
                    .soundInk(.speaker)
                    .frame(width: 16, height: 14)
                    .offset(x: -1.5)
                NativeSoundSlider(level: level, enabled: volume?.canChange != false)
                    .frame(height: 16)
                Image(systemName: "speaker.wave.3.fill")
                    .resizable().scaledToFit()
                    .font(.system(size: 12, weight: .medium))
                    .soundInk(.speaker)
                    // The wave symbol has half a point more internal vertical padding.
                    .frame(width: 26, height: 14.5)
                    .offset(x: 2)
            }
            .task {
                guard let volume else { return }
                let revision = level.revision
                await volume.refresh()
                level.show(volume.level, since: revision)
            }
        }
    }
}

/// One set of output items for the player and calls, presented in a glass popover.
/// NSMenu holds the item actions and selected states; it is never opened for tracking.
@MainActor
final class SoundOutputMenu: NSMenu, NSMenuDelegate {
    static let didOpen = Notification.Name("GlanceSoundMenuDidOpen")
    static let didClose = Notification.Name("GlanceSoundMenuDidClose")
    let level: VolumeMenuSlider.VolumeSlider.Level
    private let volume: AppVolume?
    private let choose: (AudioOutput.Device) -> Void
    private let settings: () -> Void
    private var devices: [AudioOutput.Device] = []
    private var batteries: [String: DeviceWatch.BluetoothInfo]
    private var deviceItems: [NSMenuItem] = []
    private var deviceStart = 0
    private var outputWatch: AnyCancellable?
    private var popover: SoundPopover?
    private var focusedItem: NSMenuItem?
    private let withVolume: Bool
    private var tracking = false

    init(
        devices: [AudioOutput.Device], current: AudioDeviceID, volume: AppVolume?,
        batteries: [String: DeviceWatch.BluetoothInfo]? = nil,
        withVolume: Bool = true, outputsOnly: Bool = false,
        choose: @escaping (AudioOutput.Device) -> Void, settings: @escaping () -> Void
    ) {
        self.volume = volume
        self.withVolume = withVolume && !outputsOnly
        self.choose = choose
        self.settings = settings
        self.batteries = batteries ?? AudioOutput.bluetooth
        level = .init(volume?.level ?? 0.5) { [weak volume] in volume?.set($0) }
        super.init(title: String(localized: "Sound"))
        autoenablesItems = false
        showsStateColumn = false
        minimumWidth = SoundLook.width
        delegate = self
        if !outputsOnly {
            append(
                String(localized: "Sound"),
                view: SoundMenuPiece.view(height: SoundLook.titleHeight) {
                    Text("Sound").font(.system(size: 13, weight: .semibold)).soundInk(.primary)
                        .padding(.leading, SoundLook.inset).padding(.top, SoundLook.titleTop)
                })
            if withVolume { append(String(localized: "Volume"), view: VolumeMenuSlider(volume: volume, level: level), enabled: true) }
            append("", view: SoundMenuPiece.divider(height: SoundLook.upperDivider))
            append(
                String(localized: "Output"),
                view: SoundMenuPiece.view(height: SoundLook.headingHeight) {
                    Text("Output").font(.system(size: 12, weight: .semibold)).soundInk(.heading)
                        .padding(.leading, SoundLook.inset).padding(.top, SoundLook.headingTop)
                })
        }
        deviceStart = numberOfItems
        if !outputsOnly {
            append("", view: SoundMenuPiece.divider(height: SoundLook.lowerDivider))
            let footer = append(
                String(localized: "Sound Settings…"),
                view: SoundMenuContentRow {
                    Text("Sound Settings…")
                        .font(.system(size: 13))
                        .soundInk(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, SoundLook.inset - SoundLook.highlightInset)
                        .offset(y: -1)
                        .frame(height: SoundLook.actionHeight)
                }, enabled: true
            )
            footer.target = self
            footer.action = #selector(openSettings)
        }
        refresh(devices: devices, current: current, batteries: self.batteries)
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func follow(_ output: AudioOutput) {
        outputWatch = output.$devices.combineLatest(output.$current).sink { [weak self] devices, current in
            self?.refresh(devices: devices, current: current, batteries: AudioOutput.bluetooth)
        }
    }

    /// Retain the slider and its edit revision while device rows or the selected output change.
    func refresh(devices: [AudioOutput.Device], current: AudioDeviceID, batteries: [String: DeviceWatch.BluetoothInfo]) {
        let ordered = devices.filter { $0.transport == kAudioDeviceTransportTypeBuiltIn } + devices.filter { $0.transport != kAudioDeviceTransportTypeBuiltIn }
        self.devices = ordered
        self.batteries = batteries
        if deviceItems.map(\.tag) != ordered.map({ Int($0.id) }) {
            for item in deviceItems { removeItem(item) }
            deviceItems = ordered.enumerated().map { index, device in
                let item = NSMenuItem(title: device.name, action: #selector(selectOutput(_:)), keyEquivalent: "")
                item.target = self
                item.tag = Int(device.id)
                item.view = SoundMenuContentRow { outputLabel(device, playing: device.id == current) }
                (item.view as? SoundMenuContentRow)?.item = item
                insertItem(item, at: deviceStart + index)
                return item
            }
        }
        for (item, device) in zip(deviceItems, ordered) {
            item.title = device.name
            item.state = device.id == current ? .on : .off
            (item.view as? SoundMenuContentRow)?.replace { outputLabel(device, playing: device.id == current) }
        }
        update()
        popover?.reload()
    }

    private func outputLabel(_ device: AudioOutput.Device, playing: Bool) -> some View {
        SoundOutputLabel(device: device, playing: playing, levels: batteries[device.name.lowercased()]?.levels)
    }

    @discardableResult
    private func append(_ title: String, view: NSView, enabled: Bool = false) -> NSMenuItem {
        view.setFrameSize(NSSize(width: SoundLook.width, height: view.frame.height))
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = enabled
        item.view = view
        (view as? SoundMenuContentRow)?.item = item
        addItem(item)
        return item
    }

    @objc private func selectOutput(_ item: NSMenuItem) {
        guard let device = devices.first(where: { Int($0.id) == item.tag }) else { return }
        choose(device)
    }

    @objc private func openSettings() { settings() }

    @discardableResult
    func adjustVolume(by change: Double) -> Bool {
        guard withVolume, volume?.canChange != false else { return false }
        level.move(to: min(max(level.value + change, 0), 1))
        return true
    }

    func menuWillOpen(_ menu: NSMenu) {
        tracking = true
        guard volume != nil else { return }
        Task { [weak self] in
            await AudioOutput.readBluetooth()
            guard let self, self.tracking else { return }
            let current = deviceItems.first(where: { $0.state == .on }).map { AudioDeviceID($0.tag) } ?? 0
            refresh(devices: devices, current: current, batteries: AudioOutput.bluetooth)
        }
    }

    func highlight(_ item: NSMenuItem?) {
        focusedItem = item
        for candidate in items {
            (candidate.view as? SoundMenuContentRow)?.highlighted = item != nil && candidate === item
        }
    }

    func activate(_ item: NSMenuItem) {
        guard item.isEnabled, item.action != nil else { return }
        let index = index(of: item)
        dismiss()
        performActionForItem(at: index)
    }

    func present(from anchor: NSView, pointer: CGPoint?, dismissed: @escaping () -> Void) {
        dismiss()
        guard let screen = anchor.window?.screen else {
            dismissed()
            return
        }
        let popover = SoundPopover(menu: self, maximumHeight: max(40, screen.visibleFrame.height - 40))
        self.popover = popover
        // Retain the menu until dismissal, even if its SwiftUI anchor goes away.
        // SoundPopover clears this callback before calling it, breaking the temporary ownership.
        popover.onDismiss = { [self, weak popover] in
            guard self.popover === popover else { return }
            self.popover = nil
            self.menuDidClose(self)
            NotificationCenter.default.post(name: Self.didClose, object: self)
            dismissed()
        }
        menuWillOpen(self)
        NotificationCenter.default.post(name: Self.didOpen, object: self)
        popover.show(from: anchor, pointer: pointer)
    }

    func dismiss() { popover?.dismiss() }

    func handleKey(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
        switch Int(event.keyCode) {
        case kVK_Escape: dismiss()
        case kVK_LeftArrow: return adjustVolume(by: -0.05)
        case kVK_RightArrow: return adjustVolume(by: 0.05)
        case kVK_UpArrow, kVK_DownArrow, kVK_Tab:
            let rows = items.filter { $0.isEnabled && $0.action != nil }
            guard !rows.isEmpty else { return false }
            let backward = Int(event.keyCode) == kVK_UpArrow || (Int(event.keyCode) == kVK_Tab && event.modifierFlags.contains(.shift))
            let old = focusedItem.flatMap { rows.firstIndex(of: $0) }
            let next = old.map { ($0 + (backward ? -1 : 1) + rows.count) % rows.count } ?? (backward ? rows.count - 1 : 0)
            highlight(rows[next])
            if let view = rows[next].view {
                view.scrollToVisible(view.bounds)
                NSAccessibility.post(element: view, notification: .focusedUIElementChanged)
            }
        case kVK_Return, kVK_Space:
            guard let focusedItem else { return false }
            activate(focusedItem)
        default: return false
        }
        return true
    }

    func menuDidClose(_ menu: NSMenu) {
        tracking = false
        outputWatch = nil
        highlight(nil)
    }
}

/// The system slider retains its own pointer tracking and accessibility actions.
struct NativeSoundSlider: NSViewRepresentable {
    @ObservedObject var level: VolumeMenuSlider.VolumeSlider.Level
    @Environment(\.colorScheme) private var colorScheme
    let enabled: Bool

    final class Control: NSSlider {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }

    final class Coordinator: NSObject {
        var level: VolumeMenuSlider.VolumeSlider.Level
        init(_ level: VolumeMenuSlider.VolumeSlider.Level) { self.level = level }
        @objc func moved(_ slider: NSSlider) { level.move(to: slider.doubleValue) }
    }

    func makeCoordinator() -> Coordinator { Coordinator(level) }
    func makeNSView(context: Context) -> Control {
        let slider = Control(value: level.value, minValue: 0, maxValue: 1, target: context.coordinator, action: #selector(Coordinator.moved(_:)))
        slider.isContinuous = true
        slider.controlSize = .regular
        slider.tintProminence = .primary
        slider.setAccessibilityLabel(String(localized: "Volume"))
        slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return slider
    }
    func updateNSView(_ slider: Control, context: Context) {
        context.coordinator.level = level
        slider.doubleValue = level.value
        slider.isEnabled = enabled
        slider.trackFillColor = colorScheme == .dark ? .white : .controlAccentColor
    }
}

/// The popover handles selection and keyboard navigation; this view draws the rich row, and
/// its highlight a little way in from the menu's sides, as tall as the row.
final class SoundMenuContentRow: NSView {
    // Reparenting a menu item's view into a panel clears NSView.enclosingMenuItem.
    // Keep the action's identity explicitly; the menu owns both the item and this view.
    weak var item: NSMenuItem?
    private var hover: NSTrackingArea?
    private let host: NSHostingView<AnyView>
    private var content: AnyView
    var highlighted = false { didSet { needsDisplay = true } }

    init<Content: View>(@ViewBuilder content: () -> Content) {
        self.content = AnyView(content())
        host = NSHostingView(rootView: Self.root(self.content, width: SoundLook.width))
        super.init(frame: NSRect(x: 0, y: 0, width: SoundLook.width, height: ceil(host.fittingSize.height)))
        autoresizingMask = [.width]
        addSubview(host)
        layoutHost()
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { bounds.contains(convert(point, from: superview)) ? self : nil }

    func replace<Content: View>(@ViewBuilder content: () -> Content) {
        self.content = AnyView(content())
        host.rootView = Self.root(self.content, width: bounds.width)
        setFrameSize(NSSize(width: bounds.width, height: ceil(host.fittingSize.height)))
        needsDisplay = true
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = newSize.width != frame.width
        super.setFrameSize(newSize)
        if widthChanged {
            // AppKit can widen custom menu items; a long name then wraps at the new width.
            host.rootView = Self.root(content, width: newSize.width)
            super.setFrameSize(NSSize(width: newSize.width, height: ceil(host.fittingSize.height)))
        }
        layoutHost()
    }

    private func layoutHost() {
        host.frame = bounds.insetBy(dx: SoundLook.highlightInset, dy: 0)
    }

    private static func root(_ view: AnyView, width: CGFloat) -> AnyView {
        AnyView(view.frame(width: width - SoundLook.highlightInset * 2).environment(\.controlActiveState, .key).accessibilityHidden(true))
    }

    override func draw(_ dirtyRect: NSRect) {
        guard highlighted else { return }
        let shape = RoundedRectangle(cornerRadius: SoundLook.highlightRadius, style: .continuous)
        SoundMenu.highlightColor.setFill()
        NSBezierPath(cgPath: shape.path(in: host.frame).cgPath).fill()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hover { removeTrackingArea(hover) }
        let area = NSTrackingArea(rect: host.frame, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        hover = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) { (item?.menu as? SoundOutputMenu)?.highlight(item) }
    override func mouseExited(with event: NSEvent) {
        if highlighted { (item?.menu as? SoundOutputMenu)?.highlight(nil) }
    }

    override func accessibilityLabel() -> String? { item?.title }
    override func accessibilityValue() -> Any? { item?.state == .on ? String(localized: "Selected") : nil }
    override func accessibilityPerformPress() -> Bool {
        guard let item, let menu = item.menu as? SoundOutputMenu, item.isEnabled else { return false }
        menu.activate(item)
        return true
    }

    override func mouseUp(with event: NSEvent) {
        guard host.frame.contains(convert(event.locationInWindow, from: nil)) else { return }
        _ = accessibilityPerformPress()
    }

}

/// The player's Sound menu as the Mac's own Sound menu measures, read from its Accessibility
/// frames and a capture of it on macOS 27.3: everything fourteen points in from the sides, the
/// highlight five, each output thirty-two points tall with its picture in a circle of twenty-six.
enum SoundLook {
    static let radius: CGFloat = 16
    static let edge: CGFloat = 5
    static let width: CGFloat = 308
    static let inset: CGFloat = 14
    static let highlightInset: CGFloat = 5
    static let highlightRadius: CGFloat = 11
    /// Sound, its words' frame so far below the menu's first row.
    static let titleHeight: CGFloat = 26.5
    static let titleTop: CGFloat = 8
    static let sliderHeight: CGFloat = 30
    /// The line under the slider, three points into its seven; the one above Sound Settings, in
    /// the middle of its eleven.
    static let upperDivider: CGFloat = 7
    static let lowerDivider: CGFloat = 11
    static let headingHeight: CGFloat = 24
    static let headingTop: CGFloat = 5.5
    static let rowHeight: CGFloat = 32
    static let circle: CGFloat = 26
    static let gap: CGFloat = 8
    static let glyph: CGFloat = 13.5
    static let batteryLift: CGFloat = -2
    static let actionHeight: CGFloat = 22
}

/// Measured on the built-in display, with the desktop behind the glass and in window captures.
/// Fills, headings and symbols add light in dark appearance and subtract it in light appearance;
/// primary and secondary text use ordinary alpha blending.
enum SoundInk {
    case primary, secondary, heading, symbol, speaker, fill

    func color(dark: Bool) -> Color {
        switch (self, dark) {
        case (.primary, true): Color(.sRGB, white: 1, opacity: 0.905)
        case (.primary, false): Color(.sRGB, white: 0, opacity: 0.85)
        case (.secondary, true): Color(.sRGB, white: 1, opacity: 0.47)
        case (.secondary, false): Color(white: 0, opacity: 0.45)
        case (.heading, true): Color(.sRGB, white: 77.0 / 255, opacity: 1)
        case (.symbol, true): Color(.sRGB, white: 76.0 / 255, opacity: 1)
        case (.heading, false): Color(.sRGB, white: 148.0 / 255, opacity: 1)
        case (.symbol, false): Color(.sRGB, white: 142.0 / 255, opacity: 1)
        case (.speaker, false): Color(.sRGB, white: 123.0 / 255, opacity: 1)
        case (.speaker, true): Color(.sRGB, white: 124.0 / 255, opacity: 1)
        case (.fill, true): Color(.sRGB, white: 20.0 / 255, opacity: 1)
        case (.fill, false): Color(.sRGB, white: 235.0 / 255, opacity: 1)
        }
    }

    func blend(dark: Bool) -> BlendMode {
        switch self {
        case .primary, .secondary: .normal
        case .heading, .symbol, .speaker, .fill: dark ? .plusLighter : .plusDarker
        }
    }
}

private struct SoundInkStyle: ViewModifier {
    let ink: SoundInk
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content.foregroundStyle(ink.color(dark: scheme == .dark)).blendMode(ink.blend(dark: scheme == .dark))
    }
}

extension View {
    func soundInk(_ ink: SoundInk) -> some View { modifier(SoundInkStyle(ink: ink)) }
}

/// A part of the Sound menu that only shows: a heading, or the line between two parts.
private enum SoundMenuPiece {
    @MainActor static func view<Content: View>(height: CGFloat, @ViewBuilder content: () -> Content) -> NSView {
        let host = NSHostingView(
            rootView: content().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).accessibilityHidden(true))
        host.sizingOptions = []
        host.frame = NSRect(x: 0, y: 0, width: SoundLook.width, height: height)
        host.autoresizingMask = [.width]
        return host
    }

    /// The line a point tall, in the middle of `height`, as far in as the headings.
    @MainActor static func divider(height: CGFloat, inset: CGFloat = SoundLook.inset) -> NSView {
        view(height: height) {
            Rectangle().soundInk(.fill).frame(height: 1)
                .padding(.horizontal, inset).padding(.top, (height - 1) / 2)
        }
    }
}

private struct SoundOutputLabel: View {
    let device: AudioOutput.Device
    let playing: Bool
    let levels: DeviceWatch.Levels?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: SoundLook.gap) {
            ZStack {
                if playing {
                    Circle().fill(Color(nsColor: .controlAccentColor))
                } else {
                    Circle().soundInk(.fill)
                }
                picture
            }
            .frame(width: SoundLook.circle, height: SoundLook.circle)
            // The batteries a little way up under the name, as the Mac sets the two lines.
            VStack(alignment: .leading, spacing: levels == nil ? 0 : SoundLook.batteryLift) {
                Text(device.name).font(.system(size: 13)).soundInk(.primary).fixedSize(horizontal: false, vertical: true)
                if let levels {
                    SoundBatteryLabel(levels: levels, symbols: device.model, dark: colorScheme == .dark)
                        .fixedSize()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, SoundLook.inset - SoundLook.highlightInset)
        // As tall as the Mac's rows; taller only for a name that wraps.
        .frame(minHeight: SoundLook.rowHeight)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var picture: some View {
        let image = Image(systemName: device.pictured)
            .font(.system(size: SoundLook.glyph, weight: .regular))
            .symbolRenderingMode(.hierarchical)
        if playing { image.foregroundStyle(.white) } else { image.soundInk(.symbol) }
    }
}

private struct SoundBatteryLabel: NSViewRepresentable {
    let levels: DeviceWatch.Levels
    let symbols: DeviceSymbols?
    let dark: Bool

    func makeNSView(context: Context) -> NSTextField { NSTextField(labelWithString: "") }
    func updateNSView(_ view: NSTextField, context: Context) {
        NSAppearance(named: dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
            view.attributedStringValue = SoundBatteryText.text(levels, symbols: symbols)
        }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextField, context: Context) -> CGSize? { nsView.intrinsicContentSize }
}

private enum SoundMenu {
    private static func shade(dark: CGFloat, light: CGFloat) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 1, alpha: dark) : NSColor(white: 0, alpha: light)
        }
    }
    static let highlightColor = shade(dark: 0.1, light: 0.055)
    static let batteryGray = shade(dark: 0.45, light: 0.45)
}

private enum SoundBatteryText {
    /// Each earbud's level and the case's, in the shapes macOS gives this model, the earbuds as one
    /// pair when they're level, or the one battery's, each after its symbol.
    fileprivate static func text(_ levels: DeviceWatch.Levels, symbols: DeviceSymbols?) -> NSAttributedString {
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
            let size: CGFloat = symbol.contains("chargingcase") ? 10.5 : 11
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
