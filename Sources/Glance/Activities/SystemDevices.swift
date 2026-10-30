//
//  SystemDevices.swift
//  Glance
//
//  Created by Gaty on 30/10/2026.
//

import AppKit
import UniformTypeIdentifiers

/// How macOS pictures a device: its symbol, and for earbuds, each earbud's and their case's.
struct DeviceSymbols: Equatable, Sendable {
    let symbol: String
    var left: String? = nil
    var right: String? = nil
    var chargingCase: String? = nil
}

/// What macOS itself says about every model of Mac, AirPods, Beats, HomePod, Apple TV and more, so
/// nothing here is a list of ours and a model newer than Glance is pictured as macOS pictures it. Each
/// model is a type macOS declares in CoreTypes, found by its model name or Bluetooth IDs, a kind of
/// the model before it, so AirPods Pro 2 are a kind of AirPods Pro and every notched MacBook a kind
/// of notched laptop, and a model with no picture of its own has the one it inherits.
enum SystemDevices {
    private static let modelCode = UTTagClass(rawValue: "com.apple.device-model-code")
    private static let bluetoothIDs = UTTagClass(rawValue: "public.bluetooth-vendor-product-id")
    /// Apple's Bluetooth company ID, which Beats use too.
    private static let apple = 76

    /// A declared type: what it's a kind of, nearest first, and its symbols, if it has its own.
    private struct Declared {
        let kindOf: [String]
        let symbols: DeviceSymbols?
    }

    /// Every type CoreTypes declares, by identifier in lowercase, read once: macOS adds newer models
    /// in bundles of their own inside it.
    private static let declared: [String: Declared] = {
        let root = URL(fileURLWithPath: "/System/Library/CoreServices/CoreTypes.bundle/Contents")
        let more = (try? FileManager.default.contentsOfDirectory(at: root.appending(path: "Library"), includingPropertiesForKeys: nil)) ?? []
        var found: [String: Declared] = [:]
        for bundle in [root] + more.map({ $0.appending(path: "Contents") }) {
            guard let data = try? Data(contentsOf: bundle.appending(path: "Info.plist")),
                let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            else { continue }
            for key in ["UTExportedTypeDeclarations", "UTImportedTypeDeclarations"] {
                for type in info[key] as? [[String: Any]] ?? [] {
                    guard let identifier = type["UTTypeIdentifier"] as? String else { continue }
                    let parents = type["UTTypeConformsTo"]
                    found[identifier.lowercased()] = Declared(
                        kindOf: (parents as? String).map { [$0] } ?? parents as? [String] ?? [],
                        symbols: symbols(in: type["UTTypeIcons"] as? [String: Any]))
                }
            }
        }
        return found
    }()

    private static func symbols(in icons: [String: Any]?) -> DeviceSymbols? {
        guard let symbol = icons?["UTTypeSymbolName"] as? String else { return nil }
        let variants = icons?["UTTypeSymbolVariantNames"] as? [String: String]
        return DeviceSymbols(symbol: symbol, left: variants?["left"], right: variants?["right"], chargingCase: variants?["chargingcase"])
    }

    /// Reads them away from the main thread, so the first device doesn't wait for it.
    static func prepare() {
        Task.detached(priority: .utility) { _ = declared.count }
    }

    /// The type and everything it's a kind of, nearest first.
    private static func lineage(of type: UTType?) -> [String] {
        guard let type, !type.isDynamic else { return [] }
        var lineage: [String] = [], waiting = [type.identifier.lowercased()]
        while !waiting.isEmpty {
            let identifier = waiting.removeFirst()
            guard !lineage.contains(identifier) else { continue }
            lineage.append(identifier)
            waiting += (declared[identifier]?.kindOf ?? []).map { $0.lowercased() }
        }
        return lineage
    }

    private static func symbols(in lineage: [String]) -> DeviceSymbols? {
        lineage.lazy.compactMap { declared[$0]?.symbols }.first { NSImage(systemSymbolName: $0.symbol, accessibilityDescription: nil) != nil }
    }

    /// A model of Apple's or Beats', by its Bluetooth product ID, from the most particular type on.
    /// Most are declared by their IDs, some only by a model name made from the product ID.
    static func lineage(product: Int) -> [String] {
        let byIDs = lineage(of: UTType(tag: "\(apple):\(product)", tagClass: bluetoothIDs, conformingTo: nil))
        return byIDs.isEmpty ? lineage(of: UTType(tag: "Device1,\(product)", tagClass: modelCode, conformingTo: nil)) : byIDs
    }

    static func symbols(product: Int) -> DeviceSymbols? {
        symbols(in: lineage(product: product))
    }

    /// An accessory by the IDs it gives over Bluetooth.
    static func symbols(vendor: Int, product: Int) -> DeviceSymbols? {
        symbols(in: lineage(of: UTType(tag: "\(vendor):\(product)", tagClass: bluetoothIDs, conformingTo: nil)))
    }

    /// A device by its model name, such as a Mac's or a HomePod's.
    static func symbols(model: String) -> DeviceSymbols? {
        symbols(in: lineage(of: UTType(tag: model, tagClass: modelCode, conformingTo: nil)))
    }

    /// This Mac, by its own model. A model macOS doesn't list is pictured by what it is.
    @MainActor static let thisMac: DeviceSymbols = {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var name = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &name, &size, nil, 0)
        return symbols(model: String(cString: name))
            ?? symbols(in: [BatteryWatch.hasBattery ? "com.apple.mac.notchless-laptop" : "com.apple.mac"])
            ?? DeviceSymbols(symbol: "desktopcomputer")
    }()
}
