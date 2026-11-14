import AppKit
import CoreAudio
import Testing

@testable import Glance

@Suite("AppKit Sound menu", .serialized)
@MainActor
struct SoundOutputMenuTests {
    /// Swift Testing's executor does not reliably service AppKit animation callbacks while asleep.
    /// Drive only this process's run loop; the test window remains hidden and non-key.
    private func advanceWindowAnimations() {
        RunLoop.main.run(until: Date.now + 0.02)
    }

    private func waitForWindowAnimation(_ finished: () -> Bool) async throws {
        for _ in 0..<80 {
            if finished() { return }
            advanceWindowAnimations()
            try await Task.sleep(for: .milliseconds(10))
        }
    }
    private let speakers = AudioOutput.Device(id: 10001, name: "MacBook Pro Speakers", symbol: "macbook.gen2", transport: kAudioDeviceTransportTypeBuiltIn)
    private let headphones = AudioOutput.Device(id: 10002, name: "AirPods Pro", symbol: "airpods.pro.gen1", transport: kAudioDeviceTransportTypeBluetooth)

    @Test("The menu contains the real slider and inline actions")
    func contentsAndActions() throws {
        _ = NSApplication.shared
        var selected: AudioDeviceID?
        var settings = false
        let menu = SoundOutputMenu(devices: [headphones, speakers], current: speakers.id, volume: nil, batteries: [:], choose: { selected = $0.id }, settings: { settings = true })
        let sliders = menu.items.compactMap { $0.view as? VolumeMenuSlider }
        #expect(sliders.count == 1)
        #expect(sliders.first?.level === menu.level)
        #expect(menu.items.allSatisfy { $0.submenu == nil })
        let outputs = menu.items.filter { $0.tag > 0 }
        #expect(outputs.map(\.title) == [speakers.name, headphones.name])
        #expect(outputs.first?.state == .on)
        let target = try #require(outputs.last)
        menu.performActionForItem(at: menu.index(of: target))
        #expect(selected == headphones.id)
        menu.performActionForItem(at: menu.numberOfItems - 1)
        #expect(settings)
    }

    @Test("Idle menus retain the volume control without changing audio")
    func idleVolume() throws {
        _ = NSApplication.shared
        let volume = AppVolume.shared
        try #require(volume.app == nil)
        let menu = SoundOutputMenu(devices: [speakers], current: speakers.id, volume: volume, batteries: [:], choose: { _ in }, settings: {})
        #expect(menu.items.compactMap { $0.view as? VolumeMenuSlider }.count == 1)
        let before = menu.level.value
        #expect(!menu.adjustVolume(by: -0.2))
        #expect(menu.level.value == before)
    }

    @Test("Device updates preserve a slider edit and update the selected row")
    func updatesKeepSlider() throws {
        _ = NSApplication.shared
        let menu = SoundOutputMenu(devices: [speakers], current: speakers.id, volume: nil, batteries: [:], choose: { _ in }, settings: {})
        let slider = try #require(menu.items.compactMap { $0.view as? VolumeMenuSlider }.first)
        let speakerRow = try #require(menu.items.first { $0.tag == Int(speakers.id) })
        menu.highlight(speakerRow)
        menu.level.move(to: 0.73)
        menu.refresh(devices: [speakers, headphones], current: headphones.id, batteries: [:])
        #expect(menu.items.contains { $0.view === slider })
        #expect(menu.level.value == 0.73)
        #expect(menu.items.first { $0.tag == Int(speakers.id) } === speakerRow)
        #expect((speakerRow.view as? SoundMenuContentRow)?.rowHighlighted == true)
        #expect(menu.items.first(where: { $0.tag == Int(headphones.id) })?.state == .on)
        menu.refresh(devices: [headphones], current: headphones.id, batteries: [:])
        #expect(!menu.items.contains { $0.tag == Int(speakers.id) })
        #expect(menu.items.contains { $0.view === slider })
    }

    @Test("Long names and batteries grow vertically within the same menu width")
    func longNames() throws {
        _ = NSApplication.shared
        let long = AudioOutput.Device(id: 10003, name: "Living Room Wireless Headphones with a Long Device Name", symbol: "headphones", transport: kAudioDeviceTransportTypeBluetooth)
        let menu = SoundOutputMenu(
            devices: [speakers, long], current: speakers.id, volume: nil,
            batteries: [long.name.lowercased(): .init(levels: .init(main: 75))], choose: { _ in }, settings: {}
        )
        let shortRow = try #require(menu.items.first(where: { $0.tag == Int(speakers.id) })?.view)
        let longRow = try #require(menu.items.first(where: { $0.tag == Int(long.id) })?.view)
        #expect(longRow.frame.height > shortRow.frame.height)
        #expect(longRow.frame.width == shortRow.frame.width)
    }

    @Test("Keyboard volume adjustments stay within the slider range")
    func volumeBounds() {
        _ = NSApplication.shared
        let menu = SoundOutputMenu(devices: [speakers], current: speakers.id, volume: nil, batteries: [:], choose: { _ in }, settings: {})
        #expect(menu.adjustVolume(by: 2))
        #expect(menu.level.value == 1)
        #expect(menu.adjustVolume(by: -2))
        #expect(menu.level.value == 0)
    }

    @Test("Calls share output rows without a slider or settings actions")
    func calls() throws {
        _ = NSApplication.shared
        var selected: AudioDeviceID?
        let menu = SoundOutputMenu(
            devices: [headphones, speakers], current: speakers.id, volume: nil, batteries: [:], withVolume: false, outputsOnly: true, choose: { selected = $0.id },
            settings: { Issue.record("Call outputs must not offer settings") })
        #expect(menu.items.map(\.title) == [speakers.name, headphones.name])
        #expect(!menu.adjustVolume(by: 0.1))
        let row = try #require(menu.items.last?.view)
        #expect(row.accessibilityPerformPress())
        #expect(selected == headphones.id)
    }

    @Test("Mounted rows and native slider keep their actions in a hidden panel")
    func sliderActions() async throws {
        _ = NSApplication.shared
        var selected: AudioDeviceID?
        var openedSettings = false
        let menu = SoundOutputMenu(devices: [speakers], current: speakers.id, volume: nil, batteries: [:], choose: { selected = $0.id }, settings: { openedSettings = true })
        let screen = try #require(
            NSScreen.screens.first {
                guard let id = $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
                return CGDisplayIsBuiltin(id.uint32Value) != 0
            })
        let popover = SoundPopover(menu: menu, maximumHeight: screen.visibleFrame.height - 40)
        let panel = NSWindow(
            contentRect: CGRect(x: screen.visibleFrame.midX, y: screen.visibleFrame.minY + 100, width: popover.contentView.frame.width, height: popover.contentView.frame.height),
            styleMask: [.borderless], backing: .buffered, defer: false)
        panel.contentView = popover.contentView
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) - 1)
        panel.ignoresMouseEvents = true
        panel.orderFrontRegardless()
        defer { panel.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(150))
        func findSlider(_ view: NSView) -> NSSlider? {
            (view as? NSSlider) ?? view.subviews.lazy.compactMap(findSlider).first
        }
        let slider = try #require(panel.contentView.flatMap(findSlider))
        let item = try #require(menu.items.first(where: { $0.tag == Int(speakers.id) }))
        let row = try #require(item.view as? SoundMenuContentRow)
        let surface = try #require(panel.contentView)
        let center = row.convert(NSPoint(x: row.bounds.midX, y: row.bounds.midY), to: surface)
        #expect(surface.hitTest(center) === row)
        menu.highlight(item)
        #expect(row.rowHighlighted)
        menu.highlight(nil)
        #expect(!row.rowHighlighted)
        #expect(row.accessibilityLabel() == speakers.name)
        #expect(row.accessibilityPerformPress())
        #expect(selected == speakers.id)
        #expect(menu.items.last?.view?.accessibilityPerformPress() == true)
        #expect(openedSettings)
        slider.doubleValue = 0.73
        #expect(slider.sendAction(slider.action, to: slider.target))
        #expect(menu.level.value == 0.73)
        let revision = menu.level.revision
        menu.level.show(0.2, since: revision - 1)
        #expect(menu.level.value == 0.73)
    }

    @Test("Connecting and disconnecting devices preserves rows and animates their insertion")
    func deviceTransitions() async throws {
        _ = NSApplication.shared
        // AppKit starts its animation services at launch. This isolated test process cannot
        // activate, so completing that lifecycle does not take focus from the user's apps.
        NSApp.setActivationPolicy(.prohibited)
        NSApp.finishLaunching()
        #expect(!NSApp.isActive)
        let menu = SoundOutputMenu(devices: [speakers], current: speakers.id, volume: nil, batteries: [:], choose: { _ in }, settings: {})
        let popover = SoundPopover(menu: menu, maximumHeight: 700)
        let screen = try #require(
            NSScreen.screens.first {
                guard let id = $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
                return CGDisplayIsBuiltin(id.uint32Value) != 0
            })
        let window = NSWindow(contentRect: CGRect(origin: screen.visibleFrame.origin, size: popover.contentSize), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = popover.contentView
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) - 1)
        window.ignoresMouseEvents = true
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        #expect(popover.popover.behavior == .transient)
        #expect(popover.popover.contentViewController?.view === popover.contentView)
        let speaker = try #require(menu.items.first { $0.tag == Int(speakers.id) }?.view)
        let holder = try #require(speaker.superview)
        let oldHeight = popover.contentSize.height
        menu.refresh(devices: [speakers, headphones], current: headphones.id, batteries: [:])
        popover.reload(animated: true)
        let headphone = try #require(menu.items.first { $0.tag == Int(headphones.id) }?.view)
        let inserted = try #require(headphone.superview as? SoundRowHolder)
        #expect(speaker.superview === holder)
        #expect(popover.contentSize.height == oldHeight + headphone.frame.height)
        #expect(!window.isKeyWindow)
        #expect(popover.popover.contentSize == popover.contentSize)
        // A current-output refresh must not replace or restart the appearing row.
        menu.refresh(devices: [speakers, headphones], current: speakers.id, batteries: [:])
        popover.reload(animated: true)
        #expect(headphone.superview === inserted)
        try await waitForWindowAnimation { inserted.alphaValue == 1 }
        #expect(inserted.alphaValue == 1)
        #expect(popover.contentView.frame.size == popover.contentSize)
        let footer = try #require(menu.items.last?.view)
        #expect(abs(footer.convert(footer.bounds, to: popover.contentView).minY - SoundLook.highlightInset) < 0.01)
        #expect(inserted.layer?.filters?.isEmpty != false)
        menu.refresh(devices: [speakers], current: speakers.id, batteries: [:])
        popover.reload(animated: true)
        #expect(inserted.isRemoving)
        try await waitForWindowAnimation { inserted.superview == nil }
        #expect(inserted.superview == nil)
        #expect(speaker.superview === holder)
        #expect(popover.contentSize.height == oldHeight)
        #expect(popover.popover.contentSize == popover.contentSize)
    }
}
