//
//  AudioOutput.swift
//  Glance
//
//  Created by Gaty on 07/10/2026.
//

import AppKit
import CoreAudio

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
    /// battery, then Sound Settings. At the pointer.
    func showMenu() {
        menu().popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    func menu() -> NSMenu {
        let menu = NSMenu()
        // No check marks: the output playing is filled in.
        menu.showsStateColumn = false
        let volume = AppVolume.shared
        var views: [NSView] = [SoundMenuHeading(title: "Sound", main: true)]
        if volume.app != nil { views.append(VolumeMenuSlider(volume: volume)) }
        for view in views {
            let item = NSMenuItem()
            item.view = view
            menu.addItem(item)
        }
        views.append(Self.addDivider(to: menu, height: 7))
        let heading = NSMenuItem.sectionHeader(title: "Output")
        heading.view = SoundMenuHeading(title: "Output", main: false)
        views.append(heading.view!)
        menu.addItem(heading)
        let current = Self.defaultOutput
        var rows: [OutputRow] = []
        // The Mac's own first, as the Mac's Sound menu lists them.
        let outputs = Self.outputs()
        let builtIn = outputs.filter { $0.transport == kAudioDeviceTransportTypeBuiltIn }
        for device in builtIn + outputs.filter({ $0.transport != kAudioDeviceTransportTypeBuiltIn }) {
            let row = OutputRow(device: device, playing: device.id == current, levels: Self.levels[device.name.lowercased()])
            let item = NSMenuItem(title: device.name, action: #selector(choose(_:)), keyEquivalent: "")
            item.target = self
            item.tag = Int(device.id)
            item.view = row
            menu.addItem(item)
            rows.append(row)
        }
        views.append(Self.addDivider(to: menu, height: 13))
        let settings = NSMenuItem(title: "Sound Settings…", action: #selector(openSoundSettings), keyEquivalent: "")
        settings.target = self
        settings.view = SoundMenuRow(title: settings.title)
        views.append(settings.view!)
        menu.addItem(settings)
        // As wide as the longest name needs, and every row as wide, so the slider is centered.
        let width = max(Self.menuWidth, rows.map(\.fittingWidth).max() ?? 0)
        for view in views + rows { view.setFrameSize(NSSize(width: width, height: view.frame.height)) }
        // The batteries, which System Information takes a moment to tell; kept for next time.
        Task { [weak self] in
            let report = await DeviceWatch.bluetoothReport()
            Self.levels = report.mapValues(\.levels)
            guard self != nil else { return }
            for row in rows { row.levels = Self.levels[row.device.name.lowercased()] }
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
    /// Each Bluetooth device's battery levels as last read, by its name in lowercase.
    private static var levels: [String: DeviceWatch.Levels] = [:]

    @objc private func choose(_ item: NSMenuItem) {
        var id = AudioDeviceID(item.tag)
        var address = AudioProperty.address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectSetPropertyData(AudioProperty.system, &address, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &id)
    }

    private func refresh() {
        let current = Self.defaultOutput
        symbol = Self.outputs().first { $0.id == current }?.symbol ?? "speaker.wave.2.fill"
    }

    // MARK: Core Audio

    /// A place the sound can go, with its symbol, and how it's connected.
    struct Device {
        let id: AudioDeviceID
        let name: String
        let symbol: String
        let transport: UInt32

        /// As the Mac's Sound menu pictures it: the Mac itself for its own speakers, a display or a
        /// TV for one, otherwise the device's own symbol, outlined.
        @MainActor var pictured: String {
            let builtIn = transport == kAudioDeviceTransportTypeBuiltIn && !name.lowercased().contains("headphone")
            if builtIn { return AudioOutput.isLaptop ? "laptopcomputer" : "desktopcomputer" }
            switch transport {
            case kAudioDeviceTransportTypeHDMI: return "tv"
            case kAudioDeviceTransportTypeDisplayPort: return "display"
            default: return symbol.replacingOccurrences(of: ".fill", with: "")
            }
        }
    }

    /// A MacBook, with a battery: its speakers are pictured as a laptop.
    static let isLaptop = BatteryWatch.hasBattery

    static var defaultOutput: AudioDeviceID {
        var id = AudioDeviceID(0)
        _ = AudioProperty.read(AudioProperty.system, kAudioHardwarePropertyDefaultOutputDevice, &id)
        return id
    }

    static func outputs() -> [Device] {
        AudioProperty.readArray(AudioProperty.system, kAudioHardwarePropertyDevices)
            .filter { AudioProperty.size(of: $0, kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput) > 0 }
            .filter { !(AudioProperty.uid(of: $0)?.hasPrefix(AudioProperty.ownDevicePrefix) ?? false) }
            .map { id in
                var name: Unmanaged<CFString>?
                var transport: UInt32 = 0
                _ = AudioProperty.read(id, kAudioObjectPropertyName, &name)
                _ = AudioProperty.read(id, kAudioDevicePropertyTransportType, &transport)
                let title = name?.takeRetainedValue() as String? ?? "Output"
                return Device(id: id, name: title, symbol: symbol(name: title, transport: transport), transport: transport)
            }
    }

    static func symbol(name: String, transport: UInt32) -> String {
        let name = name.lowercased()
        if name.contains("airpods max") { return "airpods.max" }
        if name.contains("airpods pro") { return "airpods.pro" }
        if name.contains("airpods") { return "airpods" }
        if name.contains("beats") { return "beats.headphones" }
        if name.contains("headphone") { return "headphones" }
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn: return "speaker.wave.2.fill"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return "headphones"
        case kAudioDeviceTransportTypeAirPlay: return "airplayaudio"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: return "tv"
        default: return "hifispeaker.fill"
        }
    }
}

/// The playing app's volume in the sound output menu, drawn as the Mac's Sound menu draws its
/// slider: a quiet speaker at the left end, a loud one at the right.
private final class VolumeMenuSlider: NSView {
    private let volume: AppVolume
    private let slider = NeutralSlider(value: 1, minValue: 0, maxValue: 1, target: nil, action: nil)

    init(volume: AppVolume) {
        self.volume = volume
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 30))
        // As wide as the menu, which widens it to fit, so the slider sits in its middle.
        autoresizingMask = [.width]
        slider.target = self
        slider.action = #selector(slide)
        // A finger brings no pointer to show the knob: it shows while the slider's being dragged, and
        // stays after only under the pointer.
        slider.addTarget(self, action: #selector(dragBegan), for: .trackingBegan)
        slider.addTarget(self, action: #selector(dragEnded), for: [.trackingEndedInside, .trackingEndedOutside, .trackingCancelled])
        slider.isContinuous = true
        slider.doubleValue = volume.level
        slider.isEnabled = volume.canChange
        // As the Mac's Sound menu: the speakers at the edges of the menu's own column, in line
        // with its headings and its separators, the slider filling the room between them. Each is
        // centered on the slider's track by its symbol's own alignment box, as the Mac's menus
        // line symbols up with controls.
        let quiet = Self.speaker("speaker.fill"), loud = Self.speaker("speaker.wave.3.fill")
        for view in [quiet, slider, loud] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        let gap: CGFloat = 8
        NSLayoutConstraint.activate([
            quiet.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.column.leading),
            slider.leadingAnchor.constraint(equalTo: quiet.trailingAnchor, constant: gap),
            loud.leadingAnchor.constraint(equalTo: slider.trailingAnchor, constant: gap),
            loud.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.column.trailing),
            slider.centerYAnchor.constraint(equalTo: centerYAnchor),
            quiet.centerYAnchor.constraint(equalTo: slider.centerYAnchor),
            loud.centerYAnchor.constraint(equalTo: slider.centerYAnchor),
        ])
        // Music's and Spotify's own volume, read afresh as the menu opens.
        Task { [weak self] in
            await volume.refresh()
            self?.slider.doubleValue = volume.level
        }
    }

    required init?(coder: NSCoder) { nil }

    // MARK: The knob, under the pointer

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    /// The menu can open with the pointer already over the row.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        slider.knobOpacity = pointerInside ? 1 : 0
    }

    override func mouseEntered(with event: NSEvent) { showKnob(true) }

    /// Kept while it's being dragged, wherever the pointer has gone.
    override func mouseExited(with event: NSEvent) {
        if NSEvent.pressedMouseButtons == 0 { showKnob(false) }
    }

    private var pointerInside: Bool {
        guard let window else { return false }
        return bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }

    private func showKnob(_ shown: Bool) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            slider.animator().knobOpacity = shown ? 1 : 0
        }
    }

    /// Where the menu starts and ends its headings, rows and separators, in from its sides.
    private static let column = (leading: SoundMenu.inset, trailing: SoundMenu.inset)

    /// The quiet and loud speakers at the slider's ends, as large and as light as the Mac's.
    private static func speaker(_ symbol: String) -> NSImageView {
        let image = NSImageView(
            image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)) ?? NSImage())
        image.contentTintColor = SoundMenu.speakerGray
        image.imageScaling = .scaleProportionallyDown
        image.setContentHuggingPriority(.required, for: .horizontal)
        image.setContentCompressionResistancePriority(.required, for: .horizontal)
        return image
    }

    @objc private func slide() {
        volume.set(slider.doubleValue)
    }

    @objc private func dragBegan() { showKnob(true) }

    @objc private func dragEnded() {
        if !pointerInside { showKnob(false) }
    }
}

/// The sound output menu's measures, as the Mac's Sound menu has them: no check marks, its
/// headings, rows and separators the same way in from both sides.
private enum SoundMenu {
    static let inset: CGFloat = 14
    /// Each output's circle, and between it and its name.
    static let circle: CGFloat = 26
    static let gap: CGFloat = 8
    static let rowHeight: CGFloat = 31
    /// A row under the pointer: lighter, in from the menu's sides, its corners rounded.
    static let highlightInset: CGFloat = 5.5
    static let highlightRadius: CGFloat = 7

    static func drawHighlight(in bounds: NSRect) {
        NSColor.labelColor.withAlphaComponent(0.1).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: highlightInset, dy: 0), xRadius: highlightRadius, yRadius: highlightRadius).fill()
    }

    /// An output's circle: light gray, or for the one playing, the accent color made a little
    /// lighter, as the Mac's Sound menu has them.
    static let circleGray = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 1, alpha: 0.22) : NSColor(white: 0, alpha: 0.08)
    }
    static var circlePlaying: NSColor { NSColor.controlAccentColor.blended(withFraction: 0.15, of: .white) ?? .controlAccentColor }
    /// The slider's speakers, and an AirPods' batteries, as light as the Mac's draw them.
    static let speakerGray = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 1, alpha: 0.62) : NSColor(white: 0, alpha: 0.5)
    }
    static let batteryGray = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 1, alpha: 0.5) : NSColor(white: 0, alpha: 0.45)
    }
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
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        autoresizingMask = [.width]
        label.font = .systemFont(ofSize: 13)
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: SoundMenu.inset),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
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
    init(title: String, main: Bool) {
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: main ? 26.5 : 24.25))
        autoresizingMask = [.width]
        let label = NSTextField(labelWithString: title)
        label.font = main ? .systemFont(ofSize: 13, weight: .semibold) : .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = main ? .labelColor : .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: SoundMenu.inset),
            label.centerYAnchor.constraint(equalTo: centerYAnchor, constant: main ? 2.75 : 0),
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

    var levels: DeviceWatch.Levels? {
        didSet {
            battery.attributedStringValue = levels.map { Self.text($0, pro: device.symbol == "airpods.pro") } ?? NSAttributedString()
            battery.isHidden = battery.attributedStringValue.length == 0
            needsLayout = true
        }
    }

    init(device: AudioOutput.Device, playing: Bool, levels: DeviceWatch.Levels?) {
        self.device = device
        self.playing = playing
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: SoundMenu.rowHeight))
        autoresizingMask = [.width]
        symbol.image = Self.picture(device.pictured, color: playing ? .white : .secondaryLabelColor)
        symbol.contentTintColor = playing ? .white : .secondaryLabelColor
        name.stringValue = device.name
        name.font = .systemFont(ofSize: 13)
        name.textColor = .labelColor
        name.lineBreakMode = .byTruncatingTail
        battery.font = .systemFont(ofSize: 11, weight: .medium)
        battery.textColor = SoundMenu.batteryGray
        for view in [symbol, name, battery] { addSubview(view) }
        defer { self.levels = levels }
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { nil }

    /// Wide enough for its name and its batteries in full.
    var fittingWidth: CGFloat {
        let widest = Self.text(DeviceWatch.Levels(left: 100, right: 100, chargingCase: 100), pro: true)
        let text = max(name.intrinsicContentSize.width, widest.size().width)
        return SoundMenu.inset + SoundMenu.circle + SoundMenu.gap + ceil(text) + SoundMenu.inset + 4
    }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let circle = SoundMenu.circle
        let textX = SoundMenu.inset + circle + SoundMenu.gap
        let textWidth = bounds.width - textX - SoundMenu.inset
        symbol.frame = NSRect(x: SoundMenu.inset, y: (bounds.height - circle) / 2, width: circle, height: circle)
        let nameHeight = name.intrinsicContentSize.height, batteryHeight = battery.intrinsicContentSize.height
        if battery.isHidden {
            name.frame = NSRect(x: textX, y: (bounds.height - nameHeight) / 2, width: textWidth, height: nameHeight)
        } else {
            // Name and batteries together, centered on the circle.
            let top = (bounds.height - nameHeight - batteryHeight + 2) / 2
            name.frame = NSRect(x: textX, y: top, width: textWidth, height: nameHeight)
            battery.frame = NSRect(x: textX, y: top + nameHeight - 2, width: textWidth, height: batteryHeight)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        if enclosingMenuItem?.isHighlighted == true { SoundMenu.drawHighlight(in: bounds) }
        (playing ? SoundMenu.circlePlaying : SoundMenu.circleGray).setFill()
        NSBezierPath(ovalIn: symbol.frame).fill()
    }

    /// Chooses it, as the menu's own items are chosen: the menu closes, then it plays there.
    override func mouseUp(with event: NSEvent) {
        guard let item = enclosingMenuItem, let menu = item.menu else { return }
        menu.cancelTracking()
        menu.performActionForItem(at: menu.index(of: item))
    }

    /// The device's picture in its circle, sized as the Mac's Sound menu sizes them: AirPods as their
    /// two earbuds side by side, a little apart, each tip outward and a lighter shade, in `color`;
    /// anything else as its own symbol, tinted by the circle's view.
    private static func picture(_ symbol: String, color: NSColor) -> NSImage? {
        // The right earbud's symbol is the one whose tip points left, so it goes on the left.
        let buds: (String, String)? =
            switch symbol {
            case "airpods.pro": ("airpodpro.right", "airpodpro.left")
            case "airpods", "airpods.gen3", "airpods.gen4": ("airpod.right", "airpod.left")
            default: nil
            }
        guard let buds else {
            return (NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
                ?? NSImage(systemSymbolName: "speaker.wave.2", accessibilityDescription: nil))?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .regular))
        }
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium).applying(.init(hierarchicalColor: color))
        guard let left = NSImage(systemSymbolName: buds.0, accessibilityDescription: nil)?.withSymbolConfiguration(configuration),
            let right = NSImage(systemSymbolName: buds.1, accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
        else { return nil }
        let apart: CGFloat = -2
        let size = NSSize(width: left.size.width + apart + right.size.width, height: max(left.size.height, right.size.height))
        return NSImage(size: size, flipped: false) { _ in
            left.draw(in: NSRect(x: 0, y: (size.height - left.size.height) / 2, width: left.size.width, height: left.size.height))
            right.draw(
                in: NSRect(
                    x: left.size.width + apart, y: (size.height - right.size.height) / 2, width: right.size.width, height: right.size.height))
            return true
        }
    }

    /// Each earbud's level and the case's, AirPods Pro's in their own shapes, or the one battery's,
    /// each after its symbol.
    private static func text(_ levels: DeviceWatch.Levels, pro: Bool) -> NSAttributedString {
        let parts: [(String, Int?)] =
            if levels.left != nil || levels.right != nil {
                pro
                    ? [("airpodpro.left", levels.left), ("airpodpro.right", levels.right), ("airpodspro.chargingcase.wireless.fill", levels.chargingCase)]
                    : [("airpod.left", levels.left), ("airpod.right", levels.right), ("airpods.chargingcase.fill", levels.chargingCase)]
            } else {
                [(Self.batterySymbol(levels.main ?? 0), levels.main)]
            }
        let text = NSMutableAttributedString()
        let font = NSFont.systemFont(ofSize: 11, weight: .medium)
        for (symbol, level) in parts {
            guard let level else { continue }
            if text.length > 0 { text.append(NSAttributedString(string: "   ", attributes: [.font: font])) }
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
                text.append(NSAttributedString(string: " ", attributes: [.font: font, .kern: 2]))
            }
            text.append(NSAttributedString(string: "\(level)%", attributes: [.font: font]))
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

/// The volume slider, drawn by NeutralSliderCell, its knob showing only while the pointer is over
/// its row or it's being dragged, fading in and out.
private final class NeutralSlider: NSSlider {
    override class var cellClass: AnyClass? {
        get { NeutralSliderCell.self }
        set {}
    }

    /// From 0, hidden, to 1; animated through `animator()`.
    @objc dynamic var knobOpacity: CGFloat = 0 {
        didSet { needsDisplay = true }
    }

    override static func defaultAnimation(forKey key: NSAnimatablePropertyKey) -> Any? {
        key == "knobOpacity" ? CABasicAnimation() : super.defaultAnimation(forKey: key)
    }
}

/// Drawn as Control Center draws its sound slider: white where it's filled (dark gray in a light
/// menu), on a gray track, with a white knob, the same whether or not Glance is the app in front. (A menu takes its app's look, so
/// the standard slider turned to the accent color only while Glance happened to be in use.)
private final class NeutralSliderCell: NSSliderCell {
    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let track = NSRect(x: rect.minX, y: rect.midY - 3, width: rect.width, height: 6)
        Self.trackColor.setFill()
        NSBezierPath(roundedRect: track, xRadius: 3, yRadius: 3).fill()
        var filled = track
        // In proportion to the whole track, so the loudest fills it to the end. The same with the
        // knob showing or not: its end is always under the knob, which only fades in over it.
        let fraction = maxValue > minValue ? (doubleValue - minValue) / (maxValue - minValue) : 0
        filled.size.width = max(track.width * fraction, track.height)
        Self.fillColor.setFill()
        NSBezierPath(roundedRect: filled, xRadius: 3, yRadius: 3).fill()
    }

    override func drawKnob(_ knobRect: NSRect) {
        let opacity = (controlView as? NeutralSlider)?.knobOpacity ?? 1
        guard opacity > 0 else { return }
        let knob = NSRect(x: knobRect.midX - 10, y: knobRect.midY - 8, width: 20, height: 16)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.setAlpha(opacity)
        let shadow = NSShadow()
        shadow.shadowColor = .black.withAlphaComponent(0.25)
        shadow.shadowBlurRadius = 2
        shadow.shadowOffset = NSSize(width: 0, height: -0.5)
        shadow.set()
        Self.knobColor.setFill()
        NSBezierPath(roundedRect: knob, xRadius: 8, yRadius: 8).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    /// White, as Control Center's; in a light menu, where white wouldn't show, the menu's text color.
    private static let fillColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .white : .labelColor
    }

    private static let trackColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .quaternaryLabelColor : NSColor(white: 0, alpha: 0.16)
    }

    private static let knobColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 0.94, alpha: 1) : .white
    }
}
