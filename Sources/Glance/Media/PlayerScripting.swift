//
//  PlayerScripting.swift
//  Glance
//
//  Created by Gaty on 07/10/2026.
//

import AppKit
import ApplicationServices

extension NSWorkspace {
    /// An installed app's icon, by its bundle identifier.
    func icon(forApp bundleID: String) -> NSImage? {
        urlForApplication(withBundleIdentifier: bundleID).map { icon(forFile: $0.path) }
    }
}

enum RepeatMode: String {
    case off, all, one

    /// Off, all, one, as in Music and Spotify.
    var next: RepeatMode {
        switch self {
        case .off: .all
        case .all: .one
        case .one: .off
        }
    }
}

/// Shuffle, repeat and favorite for the playing app; nil where the app doesn't offer it.
struct PlaybackOptions: Equatable {
    var shuffle: Bool?
    var repeatMode: RepeatMode?
    var favorite: Bool?
    /// Spotify's DJ is choosing the music.
    var dj = false
}

/// Spotify's own Playback ▸ Repeat command, which steps through off, all and one like its button;
/// its scripting only turns repeat on and off. Pressing a menu item in another app takes the
/// Accessibility permission.
enum SpotifyMenu {
    static var allowed: Bool { AXIsProcessTrusted() }

    /// macOS shows its own prompt, which leads to Privacy & Security ▸ Accessibility.
    static func askForPermission() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    static func pressRepeat() -> Bool {
        guard allowed, let spotify = NSRunningApplication.runningApplications(withBundleIdentifier: PlayerScripting.spotify).first
        else { return false }
        let app = AXUIElementCreateApplication(spotify.processIdentifier)
        guard let menuBar: AXUIElement = value(of: app, kAXMenuBarAttribute),
            let playback = child(of: menuBar, titled: "Playback"),
            let menu = children(of: playback).first,
            let repeatItem = child(of: menu, titled: "Repeat")
        else { return false }
        return AXUIElementPerformAction(repeatItem, kAXPressAction as CFString) == .success
    }

    private static func value<T>(of element: AXUIElement, _ attribute: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? T
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        value(of: element, kAXChildrenAttribute) ?? []
    }

    private static func child(of element: AXUIElement, titled title: String) -> AXUIElement? {
        children(of: element).first { (value(of: $0, kAXTitleAttribute) as String?) == title }
    }
}

/// The apps whose music can show in the notch, like the list of apps in System Settings'
/// Notifications: every app that has played something, each turned on or off.
enum MusicApps {
    private static var defaults: UserDefaults { .standard }

    /// Kept as comma-separated bundle identifiers, which Settings can watch.
    static var hidden: [String] { list(Preferences.musicHiddenApps) }
    /// Apps only: a helper that once got through in an app's place (see `isHelper`) isn't listed.
    static var seen: [String] { list(Preferences.musicSeenApps).filter { !isHelper($0) } }

    /// A process apps play through rather than an app of its own, such as WebKit's GPU process,
    /// which plays Safari's video: running, it's a service inside a framework (or a helper inside
    /// another app), not an app. WebKit's are known by name too, for when they aren't running.
    static func isHelper(_ app: String) -> Bool {
        if app.hasPrefix("com.apple.WebKit.") { return true }
        guard let url = NSRunningApplication.runningApplications(withBundleIdentifier: app).first?.bundleURL else { return false }
        return url.pathExtension != "app" || url.path.contains(".app/Contents/")
    }

    private static func list(_ key: String) -> [String] {
        (defaults.string(forKey: key) ?? "").split(separator: ",").map(String.init)
    }

    /// On unless turned off, even before the app's defaults are registered.
    static var showsNewApps: Bool { defaults.object(forKey: Preferences.musicShowsNewApps) as? Bool ?? true }

    /// Changes whenever the choice of apps does.
    static var signature: String { hidden.sorted().joined(separator: ",") }

    static func shows(_ app: String?) -> Bool {
        guard let app else { return true }
        return !hidden.contains(app)
    }

    static func set(_ app: String, shown: Bool) {
        var apps = hidden.filter { $0 != app }
        if !shown { apps.append(app) }
        defaults.set(apps.joined(separator: ","), forKey: Preferences.musicHiddenApps)
    }

    /// An app playing for the first time joins the list, off if new apps aren't to show.
    static func remember(_ app: String) {
        guard !isHelper(app), join(app) else { return }
        if !showsNewApps { set(app, shown: false) }
    }

    /// Chosen in Settings before it has played: listed, and on.
    static func add(_ app: String) {
        join(app)
        set(app, shown: true)
    }

    /// Puts it on the list; returns whether it's new there.
    @discardableResult private static func join(_ app: String) -> Bool {
        guard !seen.contains(app) else { return false }
        defaults.set((seen + [app]).joined(separator: ","), forKey: Preferences.musicSeenApps)
        return true
    }

    /// Music and Spotify stay while they're installed; any other app can be taken off the list
    /// (until it plays again).
    static func removable(_ app: String) -> Bool {
        ![PlayerScripting.music, PlayerScripting.spotify].contains(app) || NSWorkspace.shared.urlForApplication(withBundleIdentifier: app) == nil
    }

    static func forget(_ app: String) {
        defaults.set(seen.filter { $0 != app }.joined(separator: ","), forKey: Preferences.musicSeenApps)
        set(app, shown: true)
    }

    /// Music and Spotify, when installed, then every other app that has played, by name.
    static var listed: [String] { listed(seen: seen) }

    static func listed(seen: [String]) -> [String] {
        let players = [PlayerScripting.music, PlayerScripting.spotify].filter {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil || seen.contains($0)
        }
        let others = seen.filter { !players.contains($0) }.sorted { name(of: $0).localizedStandardCompare(name(of: $1)) == .orderedAscending }
        return players + others
    }

    /// An app no longer installed is named from its identifier: com.google.Chrome as Chrome.
    static func name(of app: String) -> String {
        InstalledApps.name(app) ?? app.split(separator: ".").last.map(String.init) ?? app
    }
}

enum PlayerScripting {
    static let music = "com.apple.Music"
    static let spotify = "com.spotify.client"
    private static let queue = DispatchQueue(label: "Glance.PlayerScripting")

    static func readScript(for app: String) -> String? {
        switch app {
        case music: #"tell application "Music" to return (shuffle enabled as text) & "|" & (song repeat as text) & "|" & (favorited of current track as text)"#
        case spotify:
            // Shuffle and repeat aren't offered while the DJ chooses the music, its own words included
            // (a spotify:media: address); that's how the DJ is told apart from a playlist.
            #"""
            tell application "Spotify"
                set trackAddress to ""
                try
                    set trackAddress to spotify url of current track
                end try
                return (shuffling as text) & "|" & (repeating as text) & "|" & (shuffling enabled as text) & "|" & trackAddress
            end tell
            """#
        default: nil
        }
    }

    static func options(from reply: String, app: String) -> PlaybackOptions {
        let parts = reply.components(separatedBy: "|")
        guard parts.count >= 2 else { return PlaybackOptions() }
        if app == spotify {
            // Not offered, as with the DJ or a podcast: shown faint, as Spotify shows them.
            guard parts.count < 4 || parts[2] != "false" else {
                let address = parts[3]
                return PlaybackOptions(dj: address.hasPrefix("spotify:track:") || address.hasPrefix("spotify:media:"))
            }
            return PlaybackOptions(shuffle: parts[0] == "true", repeatMode: parts[1] == "true" ? .all : .off)
        }
        return PlaybackOptions(
            shuffle: parts[0] == "true", repeatMode: RepeatMode(rawValue: parts[1]),
            favorite: parts.count > 2 ? parts[2] == "true" : nil)
    }

    /// In milliseconds, as a whole number, so no locale's decimal comma gets in the way.
    static func positionScript(for app: String) -> String? {
        [music, spotify].contains(app) ? tell(app, "return (player position * 1000) as integer") : nil
    }

    static func setShuffle(_ on: Bool, app: String) -> String? {
        switch app {
        case music: "tell application \"Music\" to set shuffle enabled to \(on)"
        case spotify: "tell application \"Spotify\" to set shuffling to \(on)"
        default: nil
        }
    }

    static func setRepeat(_ mode: RepeatMode, app: String) -> String? {
        switch app {
        case music: "tell application \"Music\" to set song repeat to \(mode.rawValue)"
        case spotify: "tell application \"Spotify\" to set repeating to \(mode != .off)"
        default: nil
        }
    }

    static func setFavorite(_ on: Bool, app: String) -> String? {
        app == music ? "tell application \"Music\" to set favorited of current track to \(on)" : nil
    }

    static let separator = "|~|"

    static func tell(_ app: String, _ command: String) -> String {
        "tell application \"\(app == spotify ? "Spotify" : "Music")\" to \(command)"
    }

    /// State, title, artist, album, length and position (in whole milliseconds, so no locale's
    /// decimal comma gets in), and for Spotify the artwork's address.
    static func statusScript(for app: String) -> String {
        let name = app == spotify ? "Spotify" : "Music"
        let length = app == spotify ? "(duration of t)" : "((duration of t) * 1000) as integer"
        let extra = app == spotify ? " & \"\(separator)\" & (artwork url of t)" : ""
        return """
            tell application "\(name)"
                if player state is stopped then return "stopped"
                set t to current track
                return (player state as text) & "\(separator)" & (name of t) & "\(separator)" & (artist of t) & "\(separator)" & (album of t) & "\(separator)" & (\(length)) & "\(separator)" & ((player position * 1000) as integer)\(extra)
            end tell
            """
    }

    /// Whether the song playing in Spotify is explicit. Its scripting doesn't say, but Spotify's
    /// public page for the song, the one it embeds in other sites, does.
    static func spotifyExplicit() async -> Bool? {
        guard let uri = await run(#"tell application "Spotify" to return id of current track"#),
            let id = spotifyTrackID(uri.trimmingCharacters(in: .whitespacesAndNewlines)),
            let url = URL(string: "https://open.spotify.com/embed/track/" + id)
        else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko)", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
            let page = String(data: data, encoding: .utf8),
            let match = page.range(of: #""isExplicit":(true|false)"#, options: .regularExpression)
        else { return nil }
        return page[match].hasSuffix("true")
    }

    /// "spotify:track:ID" as ID; nil for local files and podcast episodes.
    static func spotifyTrackID(_ uri: String) -> String? {
        let parts = uri.split(separator: ":")
        guard parts.count == 3, parts[0] == "spotify", parts[1] == "track" else { return nil }
        return String(parts[2])
    }

    /// Music hands over the artwork itself; Spotify gives an address to fetch it from.
    static func artwork(of app: String, url: String?) async -> Data? {
        if app == spotify {
            guard let url = url.flatMap(URL.init(string:)),
                let (data, _) = try? await URLSession.shared.data(from: url)
            else { return nil }
            return data
        }
        return await withCheckedContinuation { continuation in
            queue.async {
                var error: NSDictionary?
                let reply = NSAppleScript(source: #"tell application "Music" to get raw data of artwork 1 of current track"#)?
                    .executeAndReturnError(&error)
                continuation.resume(returning: error == nil ? reply?.data : nil)
            }
        }
    }

    /// Runs off the main thread: the first script to an app waits on the permission prompt.
    static func run(_ source: String) async -> String? {
        await withCheckedContinuation { continuation in
            queue.async {
                var error: NSDictionary?
                let reply = compiled(source)?.executeAndReturnError(&error)
                continuation.resume(returning: error == nil ? reply?.stringValue ?? "" : nil)
            }
        }
    }

    /// Scripts compiled once and kept, only ever touched on the queue: compiling is most of what a
    /// script costs, and the same few are run every second while Music or Spotify is followed.
    /// Those that set a value differ each time, so there's a limit on how many are kept.
    nonisolated(unsafe) private static var scripts: [String: NSAppleScript] = [:]

    private static func compiled(_ source: String) -> NSAppleScript? {
        if let script = scripts[source] { return script }
        guard let script = NSAppleScript(source: source) else { return nil }
        if scripts.count >= 32 { scripts.removeAll() }
        scripts[source] = script
        return script
    }
}
