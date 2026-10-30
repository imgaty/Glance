//
//  SystemDevicesTests.swift
//  GlanceTests
//
//  Created by Gaty on 30/10/2026.
//

import Foundation
import Testing

@testable import Glance

/// How macOS pictures each model, read from macOS.
@Suite("System devices")
struct SystemDevicesTests {
    @Test("AirPods are pictured by generation, each with its own earbuds and case")
    func airPods() throws {
        let first = try #require(SystemDevices.symbols(product: 0x200E))
        #expect(first.symbol == "airpods.pro.gen1")
        #expect(first.left == "airpods.pro.gen1.left")
        #expect(first.right == "airpods.pro.gen1.right")
        #expect(first.chargingCase == "airpods.pro.gen1.chargingcase.wireless.fill")
        // The second generation has no picture of its own, so it inherits the first's.
        #expect(SystemDevices.symbols(product: 0x2024) == first)
        // The third has its own.
        #expect(SystemDevices.symbols(product: 0x2027)?.symbol == "airpods.pro.gen3")
        #expect(SystemDevices.symbols(product: 0x2013)?.symbol == "airpods.gen3")
        #expect(SystemDevices.symbols(product: 0x2019)?.symbol == "airpods.gen4")
    }

    @Test("Headphones and speakers are pictured as what they are")
    func others() {
        #expect(SystemDevices.symbols(product: 0x200A)?.symbol == "airpodsmax")
        #expect(SystemDevices.symbols(product: 0x2017)?.symbol == "beats.headphones")
        #expect(SystemDevices.symbols(product: 0x201A)?.symbol == "beats.pill.fill")
        #expect(SystemDevices.symbols(model: "AudioAccessory1,1")?.symbol == "homepod")
        #expect(SystemDevices.symbols(model: "AudioAccessory5,1")?.symbol == "homepodmini")
        #expect(SystemDevices.symbols(model: "AppleTV14,1")?.symbol == "appletv")
    }

    @Test("Macs are pictured by their generation")
    func macs() {
        #expect(SystemDevices.symbols(model: "Mac16,1")?.symbol == "macbook.gen2")
        #expect(SystemDevices.symbols(model: "MacBookPro11,1")?.symbol == "macbook.gen1")
        #expect(SystemDevices.symbols(model: "Macmini9,1")?.symbol != SystemDevices.symbols(model: "Mac16,1")?.symbol)
    }

    @Test("A model macOS doesn't know, or another maker's IDs, has no picture")
    func unknown() {
        #expect(SystemDevices.symbols(product: 0x0001) == nil)
        #expect(SystemDevices.symbols(model: "NotAMac1,1") == nil)
        #expect(SystemDevices.symbols(vendor: 1133, product: 45091) == nil)
    }

    @Test("Magic Mouse is known by its Bluetooth IDs")
    func accessories() {
        #expect(SystemDevices.symbols(vendor: 76, product: 781)?.symbol == "magicmouse")
    }

    @MainActor @Test("This Mac has a picture of its own")
    func thisMac() {
        #expect(!SystemDevices.thisMac.symbol.isEmpty)
    }
}
