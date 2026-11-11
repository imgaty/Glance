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
}
