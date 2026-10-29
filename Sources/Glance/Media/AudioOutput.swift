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

    /// As the Mac's Sound menu: the playing app's volume first, then every output with the current
    /// one checked, at the pointer.
    func showMenu() {
        let menu = NSMenu()
        let volume = AppVolume.shared
        var slider: NSView?
        if let app = volume.app {
            menu.addItem(.sectionHeader(title: MusicApps.name(of: app)))
            let item = NSMenuItem()
            item.view = VolumeMenuSlider(volume: volume)
            slider = item.view
            menu.addItem(item)
            menu.addItem(.separator())
            menu.addItem(.sectionHeader(title: "Output"))
        }
        let current = Self.defaultOutput
        for device in Self.outputs() {
            let item = NSMenuItem(title: device.name, action: #selector(choose(_:)), keyEquivalent: "")
            item.target = self
            item.tag = Int(device.id)
            item.image = NSImage(systemSymbolName: device.symbol, accessibilityDescription: nil)
            item.state = device.id == current ? .on : .off
            menu.addItem(item)
        }
        // The whole menu's width, which its longest device name may set, so the slider is centered.
        if let slider { slider.setFrameSize(NSSize(width: max(slider.frame.width, menu.size.width), height: slider.frame.height)) }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

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

    /// Where a menu with check marks starts and ends its titles, headings and separators, in from
    /// its sides, measured from the Mac's own.
    private static let column = (leading: CGFloat(28), trailing: CGFloat(14))

    private static func speaker(_ symbol: String) -> NSImageView {
        let image = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
        image.contentTintColor = .secondaryLabelColor
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

    static func read<T: BitwiseCopyable>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ value: inout T) -> Bool {
        var address = address(selector)
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
        // Up to the knob while it shows; with it hidden, in proportion to the whole track, so the
        // loudest fills it to the end.
        let opacity = (controlView as? NeutralSlider)?.knobOpacity ?? 1
        let fraction = maxValue > minValue ? (doubleValue - minValue) / (maxValue - minValue) : 0
        let toKnob = knobRect(flipped: flipped).midX - track.minX, toValue = track.width * fraction
        filled.size.width = max(toKnob * opacity + toValue * (1 - opacity), track.height)
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
