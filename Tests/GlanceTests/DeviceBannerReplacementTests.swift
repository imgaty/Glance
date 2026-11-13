import Testing

@testable import Glance

@Suite("Device banner replacement")
struct DeviceBannerReplacementTests {
    private let supported = DeviceWatch.BluetoothInfo(product: 0x2024, vendor: 0x4C, levels: .init(main: 88))
    private let unsupported = DeviceWatch.BluetoothInfo(product: 0x200F, vendor: 0x4C)
    private let otherMaker = DeviceWatch.BluetoothInfo(product: 0x2024, vendor: 0x1234)

    @Test("Empty and unrelated reports preserve native announcements")
    func missingMatch() {
        let words = ["AirPods Pro", "88", "Connected"]
        #expect(!MenuBarBanners.notchShows(words, connected: [:]))
        #expect(!MenuBarBanners.notchShows(words, connected: ["Living Room": supported]))
        #expect(!MenuBarBanners.notchShows(words, connected: ["Headphones": otherMaker]))
        #expect(!MenuBarBanners.notchShows([], connected: ["AirPods Pro": supported]))
    }

    @Test("An exact or owner-shortened name matches without relying on unrelated devices")
    func positiveMatch() {
        let connected = ["Sam’s AirPods Pro": supported, "Old AirPods": unsupported]
        #expect(MenuBarBanners.notchShows(["AirPods Pro", "88"], connected: connected, canRender: { _ in true }))
        #expect(MenuBarBanners.notchShows(["Sam’s AirPods Pro", "88"], connected: connected, canRender: { _ in true }))
        #expect(!MenuBarBanners.notchShows(["Old AirPods", "88"], connected: connected))
    }

    @Test("Every device named by a combined announcement needs a supported replacement")
    func multipleNamedDevices() {
        let connected = ["AirPods Pro": supported, "Old AirPods": unsupported]
        #expect(!MenuBarBanners.notchShows(["AirPods Pro", "Old AirPods", "88"], connected: connected, canRender: { _ in true }))
        #expect(!MenuBarBanners.notchShows(["AirPods Pro", "88"], connected: ["AirPods Pro": otherMaker]))
    }

    @Test("Cold or failed clips preserve native feedback even for a known device")
    func unpreparedClip() {
        var requested: [Headphones] = []
        #expect(
            !MenuBarBanners.notchShows(
                ["AirPods Pro", "88"], connected: ["AirPods Pro": supported],
                canRender: {
                    requested.append($0)
                    return false
                }))
        #expect(requested == [.airpodsPro2])
    }

    @Test("Missing or invalid battery data never promises a replacement")
    func missingBattery() {
        for levels in [DeviceWatch.Levels(), .init(chargingCase: 80), .init(main: -1), .init(main: 101)] {
            var info = supported
            info.levels = levels
            #expect(!MenuBarBanners.notchShows(["AirPods Pro", "88"], connected: ["AirPods Pro": info], canRender: { _ in true }))
        }
    }

    @Test("A low case requires its own prepared clip, even when the earbuds are ready")
    func selectedCase() {
        var info = supported
        info.levels = .init(chargingCase: 10)
        let connected = ["AirPods Pro": info]
        #expect(!MenuBarBanners.notchShows(["AirPods Pro", "10"], connected: connected, canRender: { $0 == .airpodsPro2 }))
        #expect(MenuBarBanners.notchShows(["AirPods Pro", "10"], connected: connected, canRender: { $0 == .airpodsPro2Case }))
    }

    @Test("Separate earbuds provide a usable connection level without a main battery")
    func earbudLevels() {
        var info = supported
        info.levels = .init(left: 80, right: 74, chargingCase: 90)
        #expect(MenuBarBanners.notchShows(["AirPods Pro", "74"], connected: ["AirPods Pro": info], canRender: { $0 == .airpodsPro2 }))
    }
}
