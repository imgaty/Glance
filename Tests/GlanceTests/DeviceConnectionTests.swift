import Foundation
import Testing

@testable import Glance

@MainActor
@Suite("Device connection priority")
struct DeviceConnectionTests {
    private func battery(buds: Int?, chargingCase: Int?) -> DeviceWatch.Battery {
        DeviceWatch.Battery(.init(battery: buds, product: 0x2014, vendor: 0x4c, levels: .init(left: buds, right: buds, chargingCase: chargingCase)))!
    }

    @Test("A case at or below twenty percent replaces the earbuds' connection", arguments: [0, 10, 20])
    func lowCase(percent: Int) throws {
        for buds in [Int?(88), 5, nil] {
            let alert = try #require(DeviceWatch.connection(name: "AirPods Pro", battery: battery(buds: buds, chargingCase: percent)))
            #expect(alert.kind == .caseBattery)
            guard case .device(let model, let level) = alert.content else {
                Issue.record("Expected a case")
                return
            }
            #expect(model == .airpodsPro2Case)
            #expect(level == percent)
        }
    }

    @Test("A healthy or unknown case leaves the earbud level alone")
    func earbuds() throws {
        for chargingCase in [Int?(21), 100, nil] {
            let alert = try #require(DeviceWatch.connection(name: "AirPods Pro", battery: battery(buds: 45, chargingCase: chargingCase)))
            #expect(alert.kind == .device)
            guard case .device(let model, let level) = alert.content else {
                Issue.record("Expected earbuds")
                return
            }
            #expect(model == .airpodsPro2)
            #expect(level == 45)
        }
        #expect(DeviceWatch.connection(name: "AirPods Pro", battery: battery(buds: nil, chargingCase: 80)) == nil)
    }
}
