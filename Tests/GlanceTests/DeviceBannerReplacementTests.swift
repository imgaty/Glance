import Testing

@testable import Glance

@Suite("Device banner replacement")
struct DeviceBannerReplacementTests {
    private let supported = DeviceWatch.BluetoothInfo(product: 0x2024, vendor: 0x4C)
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
        #expect(MenuBarBanners.notchShows(["AirPods Pro", "88"], connected: connected))
        #expect(MenuBarBanners.notchShows(["Sam’s AirPods Pro", "88"], connected: connected))
        #expect(!MenuBarBanners.notchShows(["Old AirPods", "88"], connected: connected))
    }

    @Test("Every device named by a combined announcement needs a supported replacement")
    func multipleNamedDevices() {
        let connected = ["AirPods Pro": supported, "Old AirPods": unsupported]
        #expect(!MenuBarBanners.notchShows(["AirPods Pro", "Old AirPods", "88"], connected: connected))
        #expect(!MenuBarBanners.notchShows(["AirPods Pro", "88"], connected: ["AirPods Pro": otherMaker]))
    }
}
