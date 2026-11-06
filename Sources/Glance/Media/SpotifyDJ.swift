//
//  SpotifyDJ.swift
//  Glance
//
//  Created by Gaty on 06/11/2026.
//

import AppKit
import ApplicationServices

/// Spotify's own "Get some different DJ picks" button, pressed through Accessibility, as a person's
/// click does: the DJ jumps to other picks, as only that button can make it. Spotify shows its
/// controls to Accessibility only when started with Chromium's accessibility switch, so the first
/// time it's needed in a Spotify that wasn't, Spotify is started again with it, the DJ goes on, and
/// the button is pressed then.
@MainActor
enum SpotifyDJ {
    /// The switch that shows Spotify's controls to Accessibility.
    static let accessibilitySwitch = "--force-renderer-accessibility"
    /// The button's name in Spotify's own words, under this key, in each of its languages.
    static let nameKey = "web-player.your-dj.jumpbutton.tooltip.hover"
    private static let bundle = "/Applications/Spotify.app/Contents/Resources/Apps/xpui.spa"

    /// Its name in the Mac's languages and in English, as Spotify words it.
    private static var names: Set<String>?
    private static var button: AXUIElement?

    /// Presses Spotify's own button, if Spotify shows it. Whether it did.
    static func press() async -> Bool {
        guard AXIsProcessTrusted(), let spotify = running else { return false }
        if names == nil { names = await Task.detached { Self.readNames() }.value }
        guard let names, !names.isEmpty else { return false }
        if let button, matches(button, names), AXUIElementPerformAction(button, kAXPressAction as CFString) == .success { return true }
        let app = AXUIElementCreateApplication(spotify.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 1)
        button = await Task.detached { Self.find(in: app, names: names) }.value
        guard let button else { return false }
        return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
    }

    /// Spotify was started without the switch, so it shows no controls to Accessibility.
    static var lacksSwitch: Bool {
        guard let spotify = running else { return false }
        return !arguments(of: spotify.processIdentifier).contains(accessibilitySwitch)
    }

    /// Starts Spotify again with the switch, goes on with the DJ, and presses its button once it
    /// shows. Whether it did.
    static func restartAndPress() async -> Bool {
        guard let spotify = running, let url = spotify.bundleURL else { return false }
        spotify.terminate()
        for _ in 0..<50 where !spotify.isTerminated { try? await Task.sleep(for: .milliseconds(100)) }
        guard spotify.isTerminated else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = [accessibilitySwitch]
        configuration.activates = false
        guard (try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)) != nil else { return false }
        button = nil
        // Once it answers, on with the DJ, which goes on with its session.
        for _ in 0..<40 {
            try? await Task.sleep(for: .milliseconds(250))
            if await PlayerScripting.run(PlayerScripting.tell(PlayerScripting.spotify, "play track \"\(PlayerScripting.djAddress)\"")) != nil { break }
        }
        // Its button shows once the DJ plays.
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(500))
            if await press() { return true }
        }
        return false
    }

    private static var running: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: PlayerScripting.spotify).first
    }

    private static func matches(_ element: AXUIElement, _ names: Set<String>) -> Bool {
        [kAXDescriptionAttribute, kAXTitleAttribute, kAXHelpAttribute].contains { names.contains(SystemNotices.value(element, $0) as? String ?? "") }
    }

    /// The button, among everything Spotify shows.
    nonisolated private static func find(in app: AXUIElement, names: Set<String>) -> AXUIElement? {
        var seen = 0
        func walk(_ element: AXUIElement, _ depth: Int) -> AXUIElement? {
            seen += 1
            guard depth < 60, seen < 30_000 else { return nil }
            if SystemNotices.value(element, kAXRoleAttribute) as? String == kAXButtonRole as String,
                [kAXDescriptionAttribute, kAXTitleAttribute, kAXHelpAttribute].contains(where: { names.contains(SystemNotices.value(element, $0) as? String ?? "") })
            {
                return element
            }
            for child in SystemNotices.value(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
                if let found = walk(child, depth + 1) { return found }
            }
            return nil
        }
        for window in SystemNotices.value(app, kAXWindowsAttribute) as? [AXUIElement] ?? [] {
            if let found = walk(window, 0) { return found }
        }
        return nil
    }

    /// The button's name, from Spotify's own word lists for the Mac's languages and English.
    nonisolated private static func readNames() -> Set<String> {
        var languages = Locale.preferredLanguages.flatMap { language -> [String] in
            let base = language.split(separator: "-").first.map(String.init) ?? language
            return [language, base]
        }
        languages.append("en")
        var found: Set<String> = []
        for language in Set(languages) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            process.arguments = ["-p", bundle, "i18n/\(language).json"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { continue }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            if let words = name(in: data) { found.insert(words) }
        }
        return found
    }

    /// The button's name in one of Spotify's word lists.
    nonisolated static func name(in data: Data) -> String? {
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return list[nameKey] as? String
    }

    /// A process's arguments, as `ps` shows them.
    nonisolated private static func arguments(of pid: pid_t) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-o", "args=", "-p", "\(pid)"]
        let pipe = Pipe()
        process.standardOutput = pipe
        guard (try? process.run()) != nil else { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
