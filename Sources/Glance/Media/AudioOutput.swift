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
        menu(withVolume: withVolume, outputsOnly: outputsOnly).popUp(positioning: nil, at: point ?? NSEvent.mouseLocation, in: nil)
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

    private static func readBluetooth() async {
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
    struct Device {
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

/// The playing app's volume in the sound output menu, laid out as the Mac's Sound menu: Apple's own
/// slider, with its Liquid Glass knob, a quiet speaker at the left end, a loud one at the right.
/// SwiftUI draws and animates its own knob, including its pressed glass. AppKit follows the
/// physical pointer; the menu's incorrect SwiftUI positions are ignored while it is held.
final class VolumeMenuSlider: NSView {
    init(volume: AppVolume) {
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 30))
        // As wide as the menu, which widens it to fit, so the slider sits in its middle.
        autoresizingMask = [.width]
        let slider = Hosting(
            rootView: VolumeSlider(volume: volume, level: VolumeSlider.Level(volume.level) { [weak volume] in volume?.set($0) }))
        Hosting.trace("volume row created: can change \(volume.canChange), value \(volume.level)")
        // As the Mac's Sound menu: the speakers at the edges of the menu's own column, in line
        // with its headings and its separators, the slider filling the room between them. Each is
        // centered on the slider's track by its symbol's own alignment box, as the Mac's menus
        // line symbols up with controls.
        let quiet = Self.speaker("speaker.fill"), loud = Self.speaker("speaker.wave.3.fill")
        for view in [quiet, slider, loud] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            quiet.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.column.leading),
            slider.leadingAnchor.constraint(equalTo: quiet.trailingAnchor, constant: 4.5),
            loud.leadingAnchor.constraint(equalTo: slider.trailingAnchor, constant: 4.5),
            loud.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.column.trailing),
            slider.centerYAnchor.constraint(equalTo: centerYAnchor),
            quiet.centerYAnchor.constraint(equalTo: slider.centerYAnchor, constant: -0.5),
            loud.centerYAnchor.constraint(equalTo: slider.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }

    /// Takes the first click while another app is in front. SwiftUI draws the slider in a child;
    /// hit testing keeps the pointer on this plain AppKit view, outside that child's recognizers.
    /// Taken by the knob, it moves from where it was taken; pressed elsewhere, it goes there first.
    final class Hosting: NSView {
        private let content: NSHostingView<VolumeSlider>
        private var forwarding = false
        var rootView: VolumeSlider { content.rootView }

        init(rootView: VolumeSlider) {
            content = NSHostingView(rootView: rootView)
            super.init(frame: .zero)
            content.translatesAutoresizingMaskIntoConstraints = false
            addSubview(content)
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: leadingAnchor),
                content.trailingAnchor.constraint(equalTo: trailingAnchor),
                content.topAnchor.constraint(equalTo: topAnchor),
                content.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }

        required init?(coder: NSCoder) { nil }

        override var intrinsicContentSize: NSSize { content.intrinsicContentSize }

        // AppKit owns the pointer's position. Original events are also forwarded to the hosted
        // slider for its native interaction state, with its position binding guarded.
        override func hitTest(_ point: NSPoint) -> NSView? {
            super.hitTest(point) == nil ? nil : self
        }

        /// An optional file copy for diagnosing a drag when the unified log cannot be read.
        nonisolated private static let traceFile: String? = {
            let arguments = ProcessInfo.processInfo.arguments
            guard let index = arguments.firstIndex(of: "--volume-log"), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }()

        nonisolated static func trace(_ message: String) {
            AppVolume.log.notice("\(message, privacy: .public)")
            guard let path = traceFile else { return }
            if !FileManager.default.fileExists(atPath: path) {
                FileManager.default.createFile(atPath: path, contents: nil)
            }
            guard let file = FileHandle(forWritingAtPath: path) else { return }
            defer { try? file.close() }
            _ = try? file.seekToEnd()
            try? file.write(contentsOf: Data("\(Date.now.timeIntervalSince1970) \(ProcessInfo.processInfo.processName) pid=\(getpid()) \(message)\n".utf8))
        }

        /// Where the pointer is across the slider, from its left end, and whether the button is
        /// still down: asked of the Mac itself, as a menu gives its events in terms of their own.
        var pointer: (Hosting) -> CGFloat? = { view in
            guard let window = view.window else { return nil }
            return view.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil).x - view.bounds.minX
        }
        var held: () -> Bool = { NSEvent.pressedMouseButtons & 1 != 0 }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            guard !forwarding else { return }
            Self.trace(
                "press: event=\(event.type.rawValue) window=\(event.windowNumber) location=\(event.locationInWindow) local=\(convert(event.locationInWindow, from: nil)) bounds=\(bounds) buttons=\(NSEvent.pressedMouseButtons)"
            )
            guard let pressed = pointer(self) else { return }
            guard rootView.canChange else { return }
            // Let the real control see the real press, so it owns its pressed appearance. Its
            // binding is already guarded before it can misread the menu's event coordinates.
            rootView.level.held = true
            defer { rootView.level.letGo() }
            forward(event)
            followPointer(from: pressed, input: forward)
        }

        override func mouseUp(with event: NSEvent) { forward(event) }

        /// Only original physical events reach the hosted control. If an unhandled one comes
        /// back through the responder chain, stop there rather than forwarding it in a circle.
        private func forward(_ event: NSEvent) {
            guard !forwarding else { return }
            forwarding = true
            let level = rootView.level
            let wasHeld = level.held
            level.held = true
            defer {
                level.held = wasHeld
                forwarding = false
            }
            switch event.type {
            case .leftMouseDown: content.mouseDown(with: event)
            case .leftMouseDragged: content.mouseDragged(with: event)
            case .leftMouseUp: content.mouseUp(with: event)
            default: break
            }
        }

        /// Tracks only the physical pointer. Kept apart from mouseDown so a hidden test can
        /// supply positions without creating or posting mouse events, or changing app volume.
        func followPointer(from pressed: CGFloat, input: ((NSEvent) -> Void)? = nil) {
            let level = rootView.level
            let log = AppVolume.log
            guard rootView.canChange, let window else {
                Self.trace("Press not followed: can change \(rootView.canChange), window \(self.window != nil)")
                return
            }
            let before = level.value
            level.held = true
            defer { level.letGo() }
            let mirrored = userInterfaceLayoutDirection == .rightToLeft
            let grip = Grip(value: before, pressedAt: pressed, width: bounds.width, mirrored: mirrored)
            level.move(to: grip.value(at: pressed))
            log.notice(
                "Press at \(pressed, format: .fixed(precision: 1), privacy: .public) of \(self.bounds.width, format: .fixed(precision: 1), privacy: .public), from \(before, format: .fixed(precision: 3), privacy: .public) to \(level.value, format: .fixed(precision: 3), privacy: .public), by the knob \(grip.offset != 0, privacy: .public), buttons \(NSEvent.pressedMouseButtons, privacy: .public)"
            )
            var drags = 0
            var passes = 0
            // Never waiting on a release the menu keeps: once the button's up, it's over. Nor on a
            // drag it keeps: the pointer is read every frame, whether an event came or not.
            while held(), self.window === window, window.isVisible {
                let next = window.nextEvent(
                    matching: [.leftMouseDragged, .leftMouseUp], until: Date(timeIntervalSinceNow: 1.0 / 120), inMode: .eventTracking, dequeue: true)
                passes += 1
                if let next {
                    input?(next)
                    Self.trace(
                        "tracking: event=\(next.type.rawValue) location=\(next.locationInWindow) local=\(convert(next.locationInWindow, from: nil)) bounds=\(bounds) value=\(level.value) buttons=\(NSEvent.pressedMouseButtons)"
                    )
                }
                if next?.type == .leftMouseDragged { drags += 1 }
                if let x = pointer(self) {
                    let was = level.value
                    level.move(to: grip.value(at: x))
                    if level.value != was || next != nil, passes <= 400 {
                        let said = next.map { convert($0.locationInWindow, from: nil).x - bounds.minX }
                        log.notice(
                            "Drag \(passes, privacy: .public): pointer \(x, format: .fixed(precision: 1), privacy: .public), event \(next.map { "\($0.type.rawValue)" } ?? "none", privacy: .public) said \(said.map { String(format: "%.1f", $0) } ?? "nothing", privacy: .public), to \(level.value, format: .fixed(precision: 3), privacy: .public)"
                        )
                    }
                }
                if next?.type == .leftMouseUp { break }
            }
            Self.trace("released: value=\(level.value) passes=\(passes) drags=\(drags) buttons=\(NSEvent.pressedMouseButtons)")
            log.notice(
                "Let go at \(level.value, format: .fixed(precision: 3), privacy: .public) after \(passes, privacy: .public) passes, \(drags, privacy: .public) drag events, SwiftUI last asked for \(level.unheard.map { String(format: "%.3f", $0) } ?? "nothing", privacy: .public)"
            )
        }

    }

    /// The knob in the pointer's hold: how far from its middle it was taken, kept through the drag.
    /// Measured on macOS 27.3's slider: the knob is 20 points wide, its middle half of that in from
    /// the slider's left end at nothing and from its right end at full.
    struct Grip: Equatable {
        static let knob: CGFloat = 20

        /// From the knob's middle to the pointer; nothing when the press landed off the knob, which
        /// then comes to the pointer.
        let offset: CGFloat
        let width: CGFloat
        /// Right to left: full at the left end.
        let mirrored: Bool

        init(value: Double, pressedAt x: CGFloat, width: CGFloat, mirrored: Bool = false) {
            self.width = width
            self.mirrored = mirrored
            let distance = x - Self.middle(of: value, width: width, mirrored: mirrored)
            offset = abs(distance) <= Self.knob / 2 ? distance : 0
        }

        /// Where the knob's middle is, from the slider's left end.
        static func middle(of value: Double, width: CGFloat, mirrored: Bool = false) -> CGFloat {
            let along = Self.knob / 2 + CGFloat(min(max(value, 0), 1)) * max(width - Self.knob, 0)
            return mirrored ? width - along : along
        }

        /// The volume with the pointer at `x`, from the slider's left end.
        func value(at x: CGFloat) -> Double {
            let middle = x - offset
            let along = mirrored ? width - middle : middle
            return min(max(Double((along - Self.knob / 2) / max(width - Self.knob, 1)), 0), 1)
        }
    }

    /// SwiftUI's own slider, its played part white in a dark menu and the accent color in a light
    /// one, as the Mac's Sound menu has it, and drawn as in the app in front, as a menu is opened
    /// while Glance rarely is: otherwise it's drawn inactive, its played part as gray as the rest.
    struct VolumeSlider: View {
        /// The playing app's volume; none in a test, which never changes a real one.
        let volume: AppVolume?
        @ObservedObject var level: Level

        var canChange: Bool { volume?.canChange ?? true }

        /// Where the knob is, and what moving it does.
        final class Level: ObservableObject {
            @Published private(set) var value: Double
            private let moved: (Double) -> Void
            /// The knob is in the pointer's hold: only the pointer moves it.
            var held = false
            /// What SwiftUI's slider last asked for while it wasn't heard.
            private(set) var unheard: Double?
            /// A refresh begun before a drag must not put its old reading over the new position.
            private(set) var revision = 0

            init(_ value: Double, moved: @escaping (Double) -> Void) {
                self.value = value
                self.moved = moved
            }

            /// The knob moved: the volume follows.
            func move(to value: Double) {
                guard value != self.value else { return }
                self.value = value
                revision += 1
                moved(value)
            }

            /// The volume as the app has it, shown without setting it; left be while the knob's held.
            func show(_ value: Double, since revision: Int? = nil) {
                guard !held, revision == nil || revision == self.revision else { return }
                if value != self.value { self.value = value }
            }

            /// What SwiftUI's slider asks for by itself: heard from the keyboard and from
            /// VoiceOver, never while the pointer holds the knob.
            func asked(_ value: Double) {
                Hosting.trace("SwiftUI asked: value=\(value), before=\(self.value), held=\(held)")
                guard !held else { return unheard = value }
                move(to: value)
            }

            func letGo() {
                held = false
                unheard = nil
            }
        }

        static let fill = Color(
            nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .white : .controlAccentColor
            })

        var body: some View {
            Slider(value: Binding(get: { level.value }, set: level.asked), in: 0...1) { editing in
                Hosting.trace("Native slider editing: \(editing), held=\(level.held), value=\(level.value)")
            }
            .labelsHidden()
            .tint(Self.fill)
            .disabled(!canChange)
            .environment(\.controlActiveState, .key)
            // Music's and Spotify's own volume, read afresh as the menu opens.
            .task {
                guard let volume else { return }
                let revision = level.revision
                await volume.refresh()
                level.show(volume.level, since: revision)
            }
        }
    }

    /// Where the menu starts and ends its headings, rows and separators, in from its sides.
    private static let column = (leading: SoundMenu.inset, trailing: SoundMenu.inset)

    /// The quiet and loud speakers at the slider's ends, as large and as light as the Mac's.
    private static func speaker(_ symbol: String) -> NSImageView {
        let image = NSImageView(
            image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)) ?? NSImage())
        image.contentTintColor = SoundMenu.speakerGray
        image.imageScaling = .scaleProportionallyDown
        image.setContentHuggingPriority(.required, for: .horizontal)
        image.setContentCompressionResistancePriority(.required, for: .horizontal)
        return image
    }

}

/// The sound output menu's measures, as the Mac's Sound menu has them: no check marks, its
/// headings, rows and separators the same way in from both sides.
private enum SoundMenu {
    /// The menu's corners, as macOS draws them: it keeps its own outline, whatever's asked of its glass.
    static let radius: CGFloat = 12
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
        let color: NSColor = playing ? .white : .secondaryLabelColor
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
        symbol.contentTintColor = playing ? .white : .secondaryLabelColor
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
