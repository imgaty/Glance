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
    /// battery, then Sound Settings. At the pointer, or from the keyboard, under the button.
    /// `withVolume` false leaves the playing app's volume out, where it isn't what's heard, as on a
    /// call.
    /// `outputsOnly`, as a call's own: the outputs alone, with no words or settings around them.
    func showMenu(at point: CGPoint? = nil, withVolume: Bool = true, outputsOnly: Bool = false) {
        menu(withVolume: withVolume, outputsOnly: outputsOnly).popUp(positioning: nil, at: point ?? NSEvent.mouseLocation, in: nil)
    }

    func soundMenu() -> SoundOutputMenu {
        refreshDevices()
        let menu = SoundOutputMenu(devices: devices, current: current, volume: AppVolume.shared, choose: chooseOutput, settings: openSoundSettings)
        menu.follow(self)
        return menu
    }

    func refreshDevices() { refresh() }

    func chooseOutput(_ device: Device) { Self.use(device.id) }

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

    @objc fileprivate func openSoundSettings() {
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

/// The system's SwiftUI slider, with a white track and no custom pointer handling.
final class VolumeMenuSlider: NSView {
    let level: VolumeSlider.Level

    init(volume: AppVolume?, level: VolumeSlider.Level? = nil) {
        self.level = level ?? VolumeSlider.Level(volume?.level ?? 0.5) { [weak volume] in volume?.set($0) }
        super.init(frame: NSRect(x: 0, y: 0, width: 308, height: 30))
        autoresizingMask = [.width]
        let host = FirstMouseHostingView(rootView: VolumeSlider(volume: volume, level: self.level).environment(\.controlActiveState, .key))
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
                Image(systemName: "speaker.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
            } maximumValueLabel: {
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
            }
            .labelsHidden()
            .controlSize(.regular)
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

/// AppKit owns the menu surface and tracking; each item supplies its own content view.
@MainActor
final class SoundOutputMenu: NSMenu, NSMenuDelegate {
    let level: VolumeMenuSlider.VolumeSlider.Level
    private let volume: AppVolume?
    private let choose: (AudioOutput.Device) -> Void
    private let settings: () -> Void
    private var devices: [AudioOutput.Device] = []
    private var batteries: [String: DeviceWatch.BluetoothInfo]
    private var deviceItems: [NSMenuItem] = []
    private var deviceStart = 0
    private var outputWatch: AnyCancellable?
    private var keyWatch: Any?
    private var tracking = false

    init(
        devices: [AudioOutput.Device], current: AudioDeviceID, volume: AppVolume?,
        batteries: [String: DeviceWatch.BluetoothInfo]? = nil,
        choose: @escaping (AudioOutput.Device) -> Void, settings: @escaping () -> Void
    ) {
        self.volume = volume
        self.choose = choose
        self.settings = settings
        self.batteries = batteries ?? AudioOutput.bluetooth
        level = .init(volume?.level ?? 0.5) { [weak volume] in volume?.set($0) }
        super.init(title: String(localized: "Sound"))
        autoenablesItems = false
        showsStateColumn = false
        minimumWidth = 308
        delegate = self
        append(String(localized: "Sound"), view: SoundMenuHeading(title: String(localized: "Sound"), main: true))
        if volume == nil || volume?.app != nil {
            append(String(localized: "Volume"), view: VolumeMenuSlider(volume: volume, level: level), enabled: true)
        }
        append("", view: SoundMenuDivider(height: 7))
        append(String(localized: "Output"), view: SoundMenuHeading(title: String(localized: "Output"), main: false))
        deviceStart = numberOfItems
        append("", view: SoundMenuDivider(height: 11))
        let footer = append(
            String(localized: "Sound Settings…"),
            view: SoundMenuContentRow {
                Text("Sound Settings…")
                    .font(.system(size: 13))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, SoundOutputLayout.contentInset)
                    .padding(.vertical, SoundOutputLayout.settingsVerticalInset)
                    .frame(minHeight: SoundOutputLayout.settingsHeight)
            }, enabled: true
        )
        footer.target = self
        footer.action = #selector(openSettings)
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
    }

    private func outputLabel(_ device: AudioOutput.Device, playing: Bool) -> some View {
        SoundOutputLabel(device: device, playing: playing, levels: batteries[device.name.lowercased()]?.levels)
    }

    @discardableResult
    private func append(_ title: String, view: NSView, enabled: Bool = false) -> NSMenuItem {
        view.setFrameSize(NSSize(width: 308, height: view.frame.height))
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = enabled
        item.view = view
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
        guard volume?.canChange != false else { return false }
        level.move(to: min(max(level.value + change, 0), 1))
        return true
    }

    func menuWillOpen(_ menu: NSMenu) {
        tracking = true
        keyWatch = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
            let change: Double
            switch Int(event.keyCode) {
            case kVK_LeftArrow: change = -0.05
            case kVK_RightArrow: change = 0.05
            default: return event
            }
            return self?.adjustVolume(by: change) == true ? nil : event
        }
        guard volume != nil else { return }
        Task { [weak self] in
            await AudioOutput.readBluetooth()
            guard let self, self.tracking else { return }
            let current = deviceItems.first(where: { $0.state == .on }).map { AudioDeviceID($0.tag) } ?? 0
            refresh(devices: devices, current: current, batteries: AudioOutput.bluetooth)
        }
    }

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        for row in items.compactMap({ $0.view as? SoundMenuContentRow }) {
            row.highlighted = row.enclosingMenuItem === item
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        tracking = false
        if let keyWatch { NSEvent.removeMonitor(keyWatch) }
        keyWatch = nil
        outputWatch = nil
    }
}

/// A menu's hosting view accepts the first slider press even though its window is not key.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The native menu handles selection and keyboard navigation; this view draws the rich row.
private final class SoundMenuContentRow: NSView {
    private let host: NSHostingView<AnyView>
    private var content: AnyView
    var highlighted = false { didSet { needsDisplay = true } }

    init<Content: View>(@ViewBuilder content: () -> Content) {
        self.content = AnyView(content())
        host = NSHostingView(rootView: Self.root(self.content, width: 308))
        super.init(frame: NSRect(x: 0, y: 0, width: 308, height: ceil(host.fittingSize.height)))
        autoresizingMask = [.width]
        host.frame = bounds.insetBy(dx: SoundMenu.highlightInset, dy: 0)
        host.autoresizingMask = [.width, .height]
        addSubview(host)
        setAccessibilityElement(false)
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
        guard widthChanged else { return }
        // AppKit can widen custom menu items; keep their content on the same inset as the headings.
        host.rootView = Self.root(content, width: newSize.width)
        super.setFrameSize(NSSize(width: newSize.width, height: ceil(host.fittingSize.height)))
    }

    private static func root(_ view: AnyView, width: CGFloat) -> AnyView {
        AnyView(view.frame(width: width - SoundMenu.highlightInset * 2).environment(\.controlActiveState, .key).accessibilityHidden(true))
    }

    override func draw(_ dirtyRect: NSRect) {
        guard highlighted else { return }
        let shape = RoundedRectangle(cornerRadius: SoundOutputLayout.highlightRadius, style: .continuous)
        SoundMenu.highlightColor.setFill()
        NSBezierPath(cgPath: shape.path(in: bounds.insetBy(dx: SoundMenu.highlightInset, dy: 0)).cgPath).fill()
    }

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)),
            let item = enclosingMenuItem, item.isEnabled, let menu = item.menu
        else { return }
        menu.cancelTracking()
        menu.performActionForItem(at: menu.index(of: item))
    }
}

/// All player menu highlights share one inset curve inside the native frame.
private enum SoundOutputLayout {
    static let contentInset = SoundMenu.inset - SoundMenu.highlightInset
    static let settingsVerticalInset: CGFloat = 3
    /// macOS owns the frame; its observed curve is the reference for every inset row.
    static let menuRadius: CGFloat = 14
    static let highlightRadius = max(0, menuRadius - SoundMenu.highlightInset)
    static let settingsHeight: CGFloat = 26
    static let outputGlyphSize: CGFloat = 13.5
}

private struct SoundOutputLabel: View {
    let device: AudioOutput.Device
    let playing: Bool
    let levels: DeviceWatch.Levels?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: SoundMenu.gap) {
            Image(systemName: device.pictured)
                .font(.system(size: SoundOutputLayout.outputGlyphSize, weight: .regular))
                .imageScale(.medium)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(playing ? .white : Color(nsColor: SoundMenu.speakerGray))
                .offset(y: 0.5)
                .frame(width: SoundMenu.circle, height: SoundMenu.circle)
                .background(playing ? Color(nsColor: .systemBlue) : Color(nsColor: SoundMenu.circleGray), in: Circle())
            VStack(alignment: .leading, spacing: 0) {
                Text(device.name).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                if let levels {
                    SoundBatteryLabel(levels: levels, symbols: device.model, dark: colorScheme == .dark)
                        .fixedSize()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, SoundOutputLayout.contentInset)
        .frame(minHeight: SoundMenu.rowHeight)
        .contentShape(Rectangle())
    }
}

private struct SoundBatteryLabel: NSViewRepresentable {
    let levels: DeviceWatch.Levels
    let symbols: DeviceSymbols?
    let dark: Bool

    func makeNSView(context: Context) -> NSTextField { NSTextField(labelWithString: "") }
    func updateNSView(_ view: NSTextField, context: Context) {
        NSAppearance(named: dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
            view.attributedStringValue = OutputRow.text(levels, symbols: symbols)
        }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextField, context: Context) -> CGSize? { nsView.intrinsicContentSize }
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

    fileprivate static let highlightColor = shade(dark: 0.1, light: 0.055)
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
