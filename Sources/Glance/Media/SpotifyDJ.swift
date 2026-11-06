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
    /// Its Previous button's, which finds the player bar in any language.
    static let previousKey = "playback-control.skip-back"
    private static let bundle = "/Applications/Spotify.app/Contents/Resources/Apps/xpui.spa"

    /// Its name in the Mac's languages and in English, as Spotify words it.
    private static var names: Set<String>?
    private static var previousNames: Set<String>?
    private static var button: AXUIElement?
    /// Spotify's player bar: Previous, Play, Next, and Shuffle, or the DJ's button in its place.
    private static var bar: AXUIElement?
    private static var lastSearch = Date.distantPast
    /// Whether the running Spotify, by its process, was started with the switch.
    private static var switchChecked: (pid: pid_t, has: Bool)?

    /// Whether Spotify's own bar shows its DJ button, as it does only while the DJ chooses the music;
    /// nil where Spotify doesn't show its controls to Accessibility. Spotify's scripting can't say.
    static func djInBar() async -> Bool? {
        guard AXIsProcessTrusted(), let spotify = running, !lacksSwitch else { return nil }
        if names == nil { names = await Task.detached { Self.readNames(key: nameKey) }.value }
        if previousNames == nil { previousNames = await Task.detached { Self.readNames(key: previousKey) }.value }
        guard let names, let previousNames, !names.isEmpty, !previousNames.isEmpty else { return nil }
        if let bar {
            if let shown = await Task.detached(operation: { Self.shows(names, in: bar) }).value { return shown }
            // Spotify redrew its bar, as it does when the music changes: it's found again.
            self.bar = nil
        }
        // Found again, but not on every check.
        guard Date.now.timeIntervalSince(lastSearch) > 5 else { return nil }
        lastSearch = .now
        let app = AXUIElementCreateApplication(spotify.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 1)
        let found = await Task.detached { Self.findBar(in: app, previous: previousNames) }.value
        bar = found
        guard let found else { return nil }
        return await Task.detached { Self.shows(names, in: found) }.value
    }

    /// Whether the bar holds the DJ's button; nil if it can't be read. A bar Spotify has since drawn
    /// again can keep a reader waiting, so it's given only a moment.
    nonisolated private static func shows(_ names: Set<String>, in bar: AXUIElement) -> Bool? {
        AXUIElementSetMessagingTimeout(bar, 0.25)
        guard let children = SystemNotices.value(bar, kAXChildrenAttribute) as? [AXUIElement], !children.isEmpty else { return nil }
        return children.contains { child in
            AXUIElementSetMessagingTimeout(child, 0.25)
            return [kAXDescriptionAttribute, kAXTitleAttribute, kAXHelpAttribute].contains { names.contains(SystemNotices.value(child, $0) as? String ?? "") }
        }
    }

    /// The bar: what holds Spotify's Previous button among its other controls. A page's carousels
    /// have Previous buttons too, each beside only its Next.
    nonisolated private static func findBar(in app: AXUIElement, previous: Set<String>) -> AXUIElement? {
        var seen = 0
        func walk(_ element: AXUIElement, _ depth: Int) -> AXUIElement? {
            seen += 1
            guard depth < 60, seen < 30_000 else { return nil }
            if SystemNotices.value(element, kAXRoleAttribute) as? String == kAXButtonRole as String,
                [kAXDescriptionAttribute, kAXTitleAttribute, kAXHelpAttribute].contains(where: { previous.contains(SystemNotices.value(element, $0) as? String ?? "") }),
                let parent = SystemNotices.value(element, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID(),
                (SystemNotices.value(parent as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement])?.count ?? 0 >= 4
            {
                return (parent as! AXUIElement)
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

    /// Presses Spotify's own button, if Spotify shows it. Whether it did.
    static func press() async -> Bool {
        guard AXIsProcessTrusted(), let spotify = running else { return false }
        if names == nil { names = await Task.detached { Self.readNames(key: nameKey) }.value }
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
        let pid = spotify.processIdentifier
        if let switchChecked, switchChecked.pid == pid { return !switchChecked.has }
        let has = arguments(of: pid).contains(accessibilitySwitch)
        switchChecked = (pid, has)
        return !has
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

    /// Spotify shows its button only while the DJ plays: paused, it's played, and the button pressed
    /// once it shows. Whether it was.
    static func playAndPress() async -> Bool {
        guard await PlayerScripting.run(PlayerScripting.tell(PlayerScripting.spotify, "return player state as text")) != "playing" else { return false }
        guard await PlayerScripting.run(PlayerScripting.tell(PlayerScripting.spotify, "play")) != nil else { return false }
        for _ in 0..<12 {
            try? await Task.sleep(for: .milliseconds(250))
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

    /// A control's name under a key, from Spotify's own word lists for the Mac's languages and English.
    nonisolated private static func readNames(key: String) -> Set<String> {
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
            if let words = name(in: data, key: key) { found.insert(words) }
        }
        return found
    }

    /// The button's name in one of Spotify's word lists.
    nonisolated static func name(in data: Data, key: String = nameKey) -> String? {
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return list[key] as? String
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
