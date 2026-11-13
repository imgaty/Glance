import AppKit
import CoreAudio
import Testing

@testable import Glance

@Suite("AppKit Sound menu", .serialized)
@MainActor
struct SoundOutputMenuTests {
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
        menu.level.move(to: 0.73)
        menu.refresh(devices: [speakers, headphones], current: headphones.id, batteries: [:])
        #expect(menu.items.contains { $0.view === slider })
        #expect(menu.level.value == 0.73)
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
        #expect(row.highlighted)
        menu.highlight(nil)
        #expect(!row.highlighted)
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
}
