//
//  LocalizationTests.swift
//  GlanceTests
//
//  Created by Gaty on 04/11/2026.
//

import Foundation
import Testing

/// Glance's words, as the String Catalog keeps them.
@Suite("Localization")
struct LocalizationTests {
    /// The languages macOS comes in, as its own apps are translated; other regions of these, such as
    /// Mexican Spanish or Hong Kong Chinese, use the nearest.
    static let languages = [
        "ar", "ca", "cs", "da", "de", "el", "es", "fi", "fr", "he", "hi", "hr", "hu", "id", "it", "ja", "ko", "ms", "nb", "nl", "pl", "pt-BR", "pt-PT",
        "ro", "ru", "sk", "sl", "sv", "th", "tr", "uk", "vi", "zh-Hans", "zh-Hant",
    ]

    static func catalog(_ name: String) throws -> [String: [String: Any]] {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Resources/\(name).xcstrings")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]
        return try #require(json?["strings"] as? [String: [String: Any]])
    }

    /// A translation's values: its one form, or each of its plurals.
    static func values(_ localization: [String: Any]) -> [String] {
        if let plural = (localization["variations"] as? [String: Any])?["plural"] as? [String: [String: Any]] {
            return plural.values.compactMap { ($0["stringUnit"] as? [String: Any])?["value"] as? String }
        }
        return [(localization["stringUnit"] as? [String: Any])?["value"] as? String].compactMap { $0 }
    }

    @Test("Every word is translated into every language macOS comes in", arguments: ["Localizable", "InfoPlist"])
    func complete(name: String) throws {
        for (key, entry) in try Self.catalog(name) where entry["shouldTranslate"] as? Bool != false {
            let localizations = entry["localizations"] as? [String: Any] ?? [:]
            let missing = Self.languages.filter { localizations[$0] == nil }
            #expect(missing.isEmpty, "\(key) has no \(missing.joined(separator: ", "))")
        }
    }

    @Test("A translation takes the same values as the English it replaces")
    func placeholders() throws {
        let placeholder = #/%(?:\d+\$)?(@|lld)/#
        func kinds(_ text: String) -> [String] { text.matches(of: placeholder).map { String($0.output.1) }.sorted() }
        for (key, entry) in try Self.catalog("Localizable") {
            for (language, localization) in entry["localizations"] as? [String: [String: Any]] ?? [:] {
                let isPlural = localization["variations"] != nil
                for value in Self.values(localization) {
                    // One item's form can leave the number out.
                    let same = kinds(value) == kinds(key) || (isPlural && kinds(value).isEmpty)
                    #expect(same, "\(language): \(key) is \(value)")
                }
            }
        }
    }

    @Test("Names stay as they are")
    func names() throws {
        let catalog = try Self.catalog("Localizable")
        for name in ["Glance", "AirDrop", "AirPlay", "Safari"] {
            #expect(catalog[name]?["shouldTranslate"] as? Bool == false)
        }
    }
}
