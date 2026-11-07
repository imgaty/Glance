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
    nonisolated static let nameKey = "web-player.your-dj.jumpbutton.tooltip.hover"
    /// Its Previous button's, which finds the player bar in any language.
    nonisolated static let previousKey = "playback-control.skip-back"
    nonisolated private static let bundle = "/Applications/Spotify.app/Contents/Resources/Apps/xpui.spa"

    /// How the button is told from the rest: Spotify 1.3.8 gives it no name, only its round DJ-blue
    /// look, so it's known by the class its stylesheet gives that look, read from Spotify itself, so
    /// it follows Spotify's updates; or by its name, where a Spotify gives it one.
    struct Mark: Sendable {
        let names: Set<String>
        let style: String?
    }
    private static var mark: Mark?
    private static var previousNames: Set<String>?
    /// The way to Spotify's now playing bar (the song, its controls, and while the DJ chooses the
    /// music, the DJ's button, before Lyrics), as indexes from its windows down, and what the bar
    /// is called. Spotify's elements themselves aren't kept: once Spotify draws them again, one kept
    /// from before can keep a reader waiting for minutes. Followed afresh, the way costs a few reads.
    struct Way: Sendable {
        let path: [Int]
        let label: String
    }
    private static var way: Way?
    private static var lastSearch = Date.distantPast
    /// Between one search for the bar and the next, when the way to it is lost: Spotify draws its
    /// bar anew as another playlist starts, and a search takes a moment of its own.
    static let searchPause: TimeInterval = 1
    /// Whether the running Spotify, by its process, was started with the switch.
    private static var switchChecked: (pid: pid_t, has: Bool)?

    /// Whether Spotify's own bar shows its DJ button, as it does only while the DJ chooses the music;
    /// nil where Spotify doesn't show its controls to Accessibility. Spotify's scripting can't say.
    static func djInBar() async -> Bool? {
        guard AXIsProcessTrusted(), let spotify = running, !lacksSwitch, let mark = await loadMark() else { return nil }
        if previousNames == nil { previousNames = await Task.detached { Self.readNames(key: previousKey) }.value }
        guard let previousNames, !previousNames.isEmpty else { return nil }
        let pid = spotify.processIdentifier
        if let way, let shown = await Task.detached(operation: { Self.follow(way, in: Self.app(pid)).flatMap { Self.shows(mark, in: $0) } }).value {
            return shown
        }
        // Looked for again, but not on every check.
        guard Date.now.timeIntervalSince(lastSearch) > Self.searchPause else { return nil }
        lastSearch = .now
        guard let found = await Task.detached(operation: { Self.findBar(in: Self.app(pid), previous: previousNames) }).value else { return nil }
        way = found.way
        return await Task.detached { Self.shows(mark, in: found.bar) }.value
    }

    nonisolated private static func app(_ pid: pid_t) -> AXUIElement {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1)
        return app
    }

    /// The bar, by the way to it, if it's still there.
    nonisolated private static func follow(_ way: Way, in app: AXUIElement) -> AXUIElement? {
        guard let first = way.path.first, let windows = SystemNotices.value(app, kAXWindowsAttribute) as? [AXUIElement], first < windows.count else {
            return nil
        }
        var element = windows[first]
        for index in way.path.dropFirst() {
            AXUIElementSetMessagingTimeout(element, 0.5)
            guard let children = SystemNotices.value(element, kAXChildrenAttribute) as? [AXUIElement], index < children.count else { return nil }
            element = children[index]
        }
        AXUIElementSetMessagingTimeout(element, 0.5)
        return SystemNotices.value(element, kAXDescriptionAttribute) as? String == way.label ? element : nil
    }

    /// The button's marks, read once.
    private static func loadMark() async -> Mark? {
        if mark == nil { mark = await Task.detached { Mark(names: Self.readNames(key: nameKey), style: Self.readStyle()) }.value }
        guard let mark, mark.style != nil || !mark.names.isEmpty else { return nil }
        return mark
    }

    /// Whether an element is the DJ's button.
    nonisolated static func isJump(_ element: AXUIElement, _ mark: Mark) -> Bool {
        guard SystemNotices.value(element, kAXRoleAttribute) as? String == kAXButtonRole as String else { return false }
        if let style = mark.style, (SystemNotices.value(element, "AXDOMClassList") as? [String])?.contains(style) == true { return true }
        return [kAXDescriptionAttribute, kAXTitleAttribute, kAXHelpAttribute].contains { mark.names.contains(SystemNotices.value(element, $0) as? String ?? "") }
    }

    /// The class Spotify's stylesheet gives the DJ's button: round, in the DJ's blue.
    nonisolated static func style(in stylesheet: String) -> String? {
        let pattern = #"\.([A-Za-z0-9_-]+)\{cursor:pointer;background:#0a59b8;border:none;border-radius:50%"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
            let match = expression.firstMatch(in: stylesheet, range: NSRange(stylesheet.startIndex..., in: stylesheet)),
            let range = Range(match.range(at: 1), in: stylesheet)
        else { return nil }
        return String(stylesheet[range])
    }

    nonisolated private static func readStyle() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", bundle, "xpui-snapshot.css"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return style(in: String(decoding: data, as: UTF8.self))
    }

    /// Whether the bar holds the DJ's button; nil if it can't be read. A bar Spotify has since drawn
    /// again can keep a reader waiting, so it's given only a moment.
    nonisolated private static func shows(_ mark: Mark, in bar: AXUIElement) -> Bool? {
        jump(in: bar, mark).map { $0 != nil }
    }

    /// The DJ's button among the bar's controls: nil if the bar can't be read, nil inside if it isn't there.
    nonisolated private static func jump(in bar: AXUIElement, _ mark: Mark) -> AXUIElement?? {
        AXUIElementSetMessagingTimeout(bar, 0.25)
        guard let children = SystemNotices.value(bar, kAXChildrenAttribute) as? [AXUIElement], !children.isEmpty else { return nil }
        return .some(
            children.first { child in
                AXUIElementSetMessagingTimeout(child, 0.25)
                return isJump(child, mark)
            })
    }

    /// The now playing bar: what holds the controls Spotify's Previous button is among. A page's
    /// carousels have Previous buttons too, each beside only its Next.
    nonisolated private static func findBar(in app: AXUIElement, previous: Set<String>) -> (bar: AXUIElement, way: Way)? {
        var seen = 0
        // Down to Previous, then up two: its controls, then the bar that holds them.
        func walk(_ element: AXUIElement, _ path: [Int]) -> (bar: AXUIElement, way: Way)? {
            seen += 1
            guard path.count < 60, seen < 30_000 else { return nil }
            let children = SystemNotices.value(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
            // Holding Previous among four or more controls, this is the controls; the bar holds them.
            if children.count >= 4, path.count >= 2,
                children.contains(where: { child in
                    SystemNotices.value(child, kAXRoleAttribute) as? String == kAXButtonRole as String
                        && [kAXDescriptionAttribute, kAXTitleAttribute, kAXHelpAttribute].contains { previous.contains(SystemNotices.value(child, $0) as? String ?? "") }
                })
            {
                return barAbove(element, path)
            }
            for (index, child) in children.enumerated() {
                if let found = walk(child, path + [index]) { return found }
            }
            return nil
        }
        func barAbove(_ controls: AXUIElement, _ path: [Int]) -> (bar: AXUIElement, way: Way)? {
            guard let parent = SystemNotices.value(controls, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else { return nil }
            let bar = parent as! AXUIElement
            return (bar, Way(path: Array(path.dropLast()), label: SystemNotices.value(bar, kAXDescriptionAttribute) as? String ?? ""))
        }
        for (index, window) in (SystemNotices.value(app, kAXWindowsAttribute) as? [AXUIElement] ?? []).enumerated() {
            if let found = walk(window, [index]) { return found }
        }
        return nil
    }

    /// Presses Spotify's own button, if Spotify shows it. Whether it did.
    static func press() async -> Bool {
        guard AXIsProcessTrusted(), let spotify = running, let mark = await loadMark() else { return false }
        let pid = spotify.processIdentifier
        let way = way
        // In the bar, where it is, found afresh; or wherever Spotify shows it.
        return await Task.detached {
            let app = Self.app(pid)
            let inBar = way.flatMap { Self.follow($0, in: app) }.flatMap { Self.jump(in: $0, mark) } ?? nil
            guard let button = inBar ?? Self.find(in: app, mark: mark) else { return false }
            return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
        }.value
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
        way = nil
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

    /// The button, among everything Spotify shows.
    nonisolated private static func find(in app: AXUIElement, mark: Mark) -> AXUIElement? {
        var seen = 0
        func walk(_ element: AXUIElement, _ depth: Int) -> AXUIElement? {
            seen += 1
            guard depth < 60, seen < 30_000 else { return nil }
            if isJump(element, mark) { return element }
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

/// Whether Spotify's DJ chooses the music, from what Spotify shows of it. Spotify takes its DJ
/// button out of its bar for a second or two as the DJ finds new picks, once for nearly six,
/// always while the DJ talks over them, measured on Spotify 1.3.8. So while the DJ talks it's the
/// DJ, a click on the notch's button holds it a while, and otherwise the button has to be gone
/// for a few seconds before the DJ is taken to have stopped.
struct DJReading {
    private(set) var on = false
    private var missingSince: Date?
    var heldUntil = Date.distantPast

    /// How long the button may be gone while a song plays.
    static let patience: TimeInterval = 3
    /// Read again this soon while it might be over: the button gone, or the bar not read.
    static let soon: TimeInterval = 0.5
    static let usual: TimeInterval = 2

    /// Thought to be the DJ, with the button seen lately and now gone or unread: whether it's over is
    /// read again soon. Where Spotify's bar can't be read at all, there's nothing to read sooner.
    func unsure(at now: Date) -> Bool { on && now.timeIntervalSince(seenAt) < 10 && (missingSince != nil || unread) }
    private var unread = false
    private var seenAt = Date.distantPast
    /// How long a click on the notch's button holds the DJ, through its talk starting.
    static let afterPress: TimeInterval = 8

    /// `inBar` is nil where Spotify's bar can't be read: then what was thought stays.
    mutating func update(talking: Bool, inBar: Bool?, now: Date) -> Bool {
        unread = inBar == nil
        if inBar == true { seenAt = now }
        if talking || inBar == true {
            on = true
            missingSince = nil
            return on
        }
        guard inBar == false, now >= heldUntil else { return on }
        let since = missingSince ?? now
        missingSince = since
        if now.timeIntervalSince(since) >= Self.patience { on = false }
        return on
    }
}
