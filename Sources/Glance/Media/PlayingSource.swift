//
//  PlayingSource.swift
//  Glance
//
//  Created by Gaty on 23/10/2026.
//

import AppKit
import ApplicationServices

/// Where what's playing comes from, opened as a click on the cover opens it: the browser tab it
/// plays in, the playlist or album Spotify plays it from, the song in the playlist Music plays it
/// from. When that can't be found, the app.
@MainActor
enum PlayingSource {
    static func open(app: String, title: String) {
        Task {
            if await reveal(app: app, title: title) { return }
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app) else { return }
            _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    private static func reveal(app: String, title: String) async -> Bool {
        switch app {
        case PlayerScripting.music:
            // The song Music plays belongs to the playlist it plays from, which it's shown in.
            return await PlayerScripting.run(
                """
                tell application "Music"
                    reveal current track
                    activate
                end tell
                """) != nil
        case PlayerScripting.spotify:
            guard let track = await PlayerScripting.run(#"tell application "Spotify" to return spotify url of current track"#),
                let address = spotifyContext(of: track.trimmingCharacters(in: .whitespacesAndNewlines)) ?? URL(string: track),
                address.scheme == "spotify"
            else { return false }
            return NSWorkspace.shared.open(address)
        default:
            guard !title.isEmpty else { return false }
            if let script = tabScript(app: app, title: title), await PlayerScripting.run(script) == "found" { return true }
            return tab(app: app, title: title)
        }
    }

    // MARK: Spotify

    /// The playlist, album, artist or show Spotify plays the song from. Its scripting doesn't say,
    /// but Spotify keeps every song it has played beside where it was played from, the latest
    /// first, and what was last asked to play.
    static func spotifyContext(of track: String) -> URL? {
        let users = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/Spotify/PersistentCache/Users")
        let folders = (try? FileManager.default.contentsOfDirectory(at: users, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        // The account last used.
        let latest = folders.filter { $0.lastPathComponent.hasSuffix("-user") }.max {
            (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                < (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        }
        guard let latest else { return nil }
        let history = addresses(in: latest.appending(path: "list_player_play_history"))
        let request = addresses(in: latest.appending(path: "list_player_play_request"))
        return context(of: track, history: history, request: request).flatMap(URL.init(string:))
    }

    /// Where the song was played from: after it in the history; otherwise what was last asked to
    /// play, if the song was asked for with it.
    static func context(of track: String, history: [String], request: [String]) -> String? {
        let id = track.split(separator: ":").last.map(String.init) ?? track
        func isSong(_ address: String) -> Bool { address.hasSuffix(":" + id) && !isContext(address) }
        if let index = history.firstIndex(where: isSong), let context = history[(index + 1)...].prefix(1).first(where: isContext) {
            return context
        }
        if request.contains(where: isSong) { return request.first(where: isContext) }
        return nil
    }

    private static func isContext(_ address: String) -> Bool {
        let kind = address.split(separator: ":").dropFirst().first ?? ""
        return !["track", "episode", "media", "local"].contains(kind)
    }

    /// Spotify's addresses written in a file, in order.
    private static func addresses(in file: URL) -> [String] {
        guard let data = try? Data(contentsOf: file), let text = String(data: data, encoding: .isoLatin1) else { return [] }
        let pattern = #/spotify(?::[A-Za-z0-9_.\-]+)+/#
        return text.matches(of: pattern).map { String($0.output) }
    }

    // MARK: Browsers

    /// Browsers that tell their tabs' titles to other apps: Safari's own words, or Chrome's.
    private static let safari = ["com.apple.Safari", "com.apple.SafariTechnologyPreview"]
    private static let chromium = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary",
        "com.brave.Browser", "com.microsoft.edgemac", "com.vivaldi.Vivaldi",
    ]

    /// Switches to the first tab whose title holds what's playing, in whichever window and Space it's
    /// in, and brings it forward.
    static func tabScript(app: String, title: String) -> String? {
        let wanted = title.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        if safari.contains(app) {
            return """
                tell application id "\(app)"
                    repeat with w in windows
                        repeat with t in tabs of w
                            if name of t contains "\(wanted)" then
                                set current tab of w to t
                                set index of w to 1
                                activate
                                return "found"
                            end if
                        end repeat
                    end repeat
                end tell
                return ""
                """
        }
        if chromium.contains(app) {
            return """
                tell application id "\(app)"
                    repeat with w in windows
                        set i to 0
                        repeat with t in tabs of w
                            set i to i + 1
                            if title of t contains "\(wanted)" then
                                set active tab index of w to i
                                set index of w to 1
                                activate
                                return "found"
                            end if
                        end repeat
                    end repeat
                end tell
                return ""
                """
        }
        return nil
    }

    /// Any other browser: its tab bar, through Accessibility, in the windows on this Space.
    private static func tab(app: String, title: String) -> Bool {
        guard AXIsProcessTrusted(), let running = NSRunningApplication.runningApplications(withBundleIdentifier: app).first else { return false }
        let element = AXUIElementCreateApplication(running.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.5)
        func value(_ element: AXUIElement, _ name: String) -> AnyObject? {
            var value: AnyObject?
            return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
        }
        func find(_ element: AXUIElement, depth: Int) -> AXUIElement? {
            let role = value(element, kAXRoleAttribute) as? String ?? ""
            let subrole = value(element, kAXSubroleAttribute) as? String ?? ""
            if role == kAXRadioButtonRole || subrole == "AXTabButton" || role == "AXTab" {
                let name = [kAXTitleAttribute, kAXDescriptionAttribute].compactMap { value(element, $0) as? String }.joined(separator: " ")
                if name.localizedCaseInsensitiveContains(title) { return element }
            }
            guard depth < 12 else { return nil }
            for child in value(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
                if let found = find(child, depth: depth + 1) { return found }
            }
            return nil
        }
        for window in value(element, kAXWindowsAttribute) as? [AXUIElement] ?? [] {
            guard let tab = find(window, depth: 0) else { continue }
            AXUIElementPerformAction(tab, kAXPressAction as CFString)
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            running.activate()
            return true
        }
        return false
    }
}
