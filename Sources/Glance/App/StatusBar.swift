//
//  StatusBar.swift
//  Glance
//
//  Created by Gaty on 07/10/2026.
//

import AppKit
import Combine
import SwiftUI

/// Facts build.sh stamps into Info.plist, so a running copy knows where it came from.
enum BuildInfo {
    static var sourceDirectory: URL? {
        string("GlanceSourceDirectory").map { URL(fileURLWithPath: $0, isDirectory: true) }
    }
    static var date: String? { string("GlanceBuildDate") }
    static var version: String { string("CFBundleShortVersionString") ?? "1.0" }

    private static func string(_ key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }
}

/// A standard menu shared by the menu bar button and the notch's context menu.
/// AppKit owns its placement, highlighting, keyboard navigation and dismissal.
@MainActor
final class StatusBarController: NSObject {
    /// For the notch's right-click.
    let menu = NSMenu()
    var onOpenSettings: (() -> Void)?
    var canLaunchActivity: (() -> Bool)?
    var onRecognizeMusic: (() -> Void)?
    var onOpenShortcut: ((UUID) -> Void)?
    /// A named command captured from the notch under the pointer when the menu opens.
    var putAway: (() -> (title: String, action: () -> Void)?)?
    private var offeredPutAway: (() -> Void)?
    var activityChoices: (() -> [(title: String, action: () -> Void)])?
    private var offeredActivities: [(title: String, action: () -> Void)] = []

    /// Square, as an icon in the menu bar is: macOS's pill around it comes out the size of the
    /// system's own icons', and the icons beside it as far away. Any wider, the pill is wider still.
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let updatesItem = NSMenuItem(title: String(localized: "Check for Updates…"), action: #selector(updatesFromMenu), keyEquivalent: "")
    private let rebuildItem = NSMenuItem(title: "Rebuild", action: #selector(rebuildFromMenu), keyEquivalent: "")
    private var canCheckWatch: AnyCancellable?
    private var buildProcess: Process?
    private var enabledWatch: NSKeyValueObservation?
    private var icon: StatusIcon?
    private let enabledItem = NSMenuItem(title: String(localized: "Enable Glance"), action: #selector(toggleEnabled), keyEquivalent: "")

    override init() {
        super.init()
        statusItem.button?.toolTip = "Glance"
        statusItem.menu = menu
        if let button = statusItem.button { icon = StatusIcon(button: button, symbol: Self.notchIcon) }
        let settings = NSMenuItem(title: String(localized: "Glance Settings…"), action: #selector(settingsFromMenu), keyEquivalent: "")
        settings.target = self
        updatesItem.target = self
        rebuildItem.target = self
        let quit = NSMenuItem(title: String(localized: "Quit Glance"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        menu.autoenablesItems = false
        menu.delegate = self
        enabledItem.target = self
        menu.addItem(enabledItem)
        menu.addItem(.separator())
        menu.addItem(updatesItem)
        if BuildInfo.sourceDirectory != nil {
            menu.addItem(rebuildItem)
            menu.addItem(benchItem())
        }
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(quit)
        if #available(macOS 27, *) {
            for item in menu.items { item.preferredImageVisibility = .hidden }
        }

        canCheckWatch = Updater.shared.$canCheck.sink { [weak self] can in self?.updatesItem.isEnabled = can }

        // A slash across the icon while the notch is off.
        enabledWatch = UserDefaults.standard.observe(\.notchEnabled, options: [.initial]) { [weak self] defaults, _ in
            let on = defaults.notchEnabled
            Task { @MainActor in
                self?.icon?.setSlashed(!on)
                self?.enabledItem.state = on ? .on : .off
            }
        }
    }

    @objc private func toggleEnabled() {
        UserDefaults.standard.set(!UserDefaults.standard.notchEnabled, forKey: Preferences.notchEnabled)
        enabledItem.state = UserDefaults.standard.notchEnabled ? .on : .off
    }

    @objc private func updatesFromMenu() { Updater.shared.checkForUpdates() }
    @objc private func recognizeMusicFromMenu() {
        guard canLaunchActivity?() == true, UserDefaults.standard.bool(forKey: Preferences.activityRecognition) else { return }
        onRecognizeMusic?()
    }
    @objc private func pauseOrResumeTimer() { ClockActivity.shared.toggleTimer() }
    @objc private func cancelTimer() { ClockActivity.shared.cancelTimer() }
    @objc private func repeatTimer() { ClockActivity.shared.repeatTimer() }
    @objc private func stopTimer() { ClockActivity.shared.dismissRing() }
    @objc private func startStopStopwatch() { ClockActivity.shared.startStopStopwatch() }
    @objc private func resetStopwatch() { ClockActivity.shared.resetStopwatch() }
    @objc private func rebuildFromMenu() { rebuild() }

    /// Each live activity to try alone, in a build from source (see `ActivityBench`), and none.
    private func benchItem() -> NSMenuItem {
        let item = NSMenuItem(title: String(localized: "Try a Live Activity"), action: nil, keyEquivalent: "")
        let scenes = NSMenu()
        scenes.autoenablesItems = false
        func entry(_ title: String, tries chosen: [ActivityBench.Scene], on: Bool) -> NSMenuItem {
            let entry = NSMenuItem(title: title, action: #selector(benchFromMenu), keyEquivalent: "")
            entry.target = self
            entry.representedObject = chosen.map(\.rawValue)
            entry.state = on ? .on : .off
            return entry
        }
        let first = ActivityBench.scene
        // Grouped, each group under its label.
        for (index, group) in ActivityBench.Scene.groups.enumerated() {
            if index > 0 { scenes.addItem(.separator()) }
            scenes.addItem(.sectionHeader(title: group.label))
            for scene in group.scenes { scenes.addItem(entry(scene.title, tries: [scene], on: scene == first)) }
        }
        scenes.addItem(.separator())
        // A second beside the first, the most the notch shows; chosen again, it goes.
        let second = NSMenuItem(title: String(localized: "Add a Second"), action: nil, keyEquivalent: "")
        second.isEnabled = first != nil
        if let first {
            let others = NSMenu()
            others.autoenablesItems = false
            for (index, group) in ActivityBench.Scene.groups.enumerated() {
                let choices = group.scenes.filter { ActivityBench.Scene.seconds.contains($0) && $0 != first }
                guard !choices.isEmpty else { continue }
                if index > 0, !others.items.isEmpty { others.addItem(.separator()) }
                others.addItem(.sectionHeader(title: group.label))
                for scene in choices {
                    let on = ActivityBench.scenes.contains(scene)
                    others.addItem(entry(scene.title, tries: on ? [first] : [first, scene], on: on))
                }
            }
            second.submenu = others
        }
        scenes.addItem(second)
        scenes.addItem(.separator())
        scenes.addItem(entry(String(localized: "None"), tries: [], on: first == nil))
        item.submenu = scenes
        return item
    }

    @objc private func benchFromMenu(_ entry: NSMenuItem) {
        ActivityBench.change(to: (entry.representedObject as? [String] ?? []).compactMap(ActivityBench.Scene.init(rawValue:)))
    }
    @objc private func settingsFromMenu() { onOpenSettings?() }

    // MARK: Rebuild

    /// Runs build.sh --run, which replaces this app with a fresh build and relaunches it.
    /// On success this process is killed by the script; only failures come back here.
    private func rebuild() {
        guard buildProcess == nil, let source = BuildInfo.sourceDirectory else { return }
        let log = source.appending(path: "build/rebuild.log")
        try? FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: log.path, contents: nil)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [source.appending(path: "build.sh").path, "--run"]
        process.currentDirectoryURL = source
        if let output = try? FileHandle(forWritingTo: log) {
            process.standardOutput = output
            process.standardError = output
        }
        process.terminationHandler = { [weak self] finished in
            let status = finished.terminationStatus
            Task { @MainActor in self?.rebuildFinished(status: status, log: log, source: source) }
        }

        do {
            try process.run()
        } catch {
            showFailure(error.localizedDescription, log: nil)
            return
        }
        buildProcess = process
        setBuilding(true)
    }

    private func rebuildFinished(status: Int32, log: URL, source: URL) {
        buildProcess = nil
        setBuilding(false)
        guard status != 0 else { return }

        let text = ((try? String(contentsOf: log, encoding: .utf8)) ?? "")
            .replacingOccurrences(of: "\u{1B}\\[[0-9;]*m", with: "", options: .regularExpression)
            .replacingOccurrences(of: source.path + "/", with: "")
        let lines = text.split(separator: "\n").map(String.init)
        var errors: [String] = []
        for line in lines where line.contains(": error:") && !errors.contains(line) {
            errors.append(line)
        }
        let summary = errors.isEmpty ? lines.suffix(12) : errors.prefix(6)
        showFailure(summary.isEmpty ? "build.sh exited with status \(status)." : summary.joined(separator: "\n"), log: log)
    }

    private func showFailure(_ message: String, log: URL?) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Rebuild failed"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        if log != nil { alert.addButton(withTitle: "Open Log…") }
        NSApp.activate()
        if alert.runModal() == .alertSecondButtonReturn, let log {
            NSWorkspace.shared.open(log)
        }
    }

    private func setBuilding(_ building: Bool) {
        rebuildItem.title = building ? "Rebuilding…" : "Rebuild"
        rebuildItem.isEnabled = !building
        icon?.setSymbol(building ? Self.hammerIcon : Self.notchIcon)
    }

    // MARK: Icon

    /// A screen with its top filled in, the app icon's own shapes in the same proportions, nearly
    /// square. Its outline is 1.5 points, as heavy as the icons beside it in the menu bar read,
    /// and the top sits a point inside it, its corners following the outline's. A template, so it
    /// follows the menu bar's appearance, as symbols do.
    private static let notchIcon: NSImage = {
        let image = NSImage(size: NSSize(width: 17, height: 15), flipped: false) { rect in
            NSColor.black.set()
            let line: CGFloat = 1.5
            let radius: CGFloat = 3
            let screen = NSBezierPath(roundedRect: rect.insetBy(dx: line / 2, dy: line / 2), xRadius: radius, yRadius: radius)
            screen.lineWidth = line
            screen.stroke()
            let inside = line + 1
            let top = radius - line / 2 - 1
            NSBezierPath(roundedRect: NSRect(x: inside, y: rect.maxY - inside - 3, width: rect.width - inside * 2, height: 3), xRadius: top, yRadius: top).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Glance"
        return image
    }()
    private static let hammerIcon = symbol("hammer", "Rebuilding")

    private static func symbol(_ name: String, _ description: String) -> NSImage {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: description) ?? NSImage()
        return image.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)) ?? image
    }
}

extension StatusBarController: NSMenuDelegate {
    /// The notch's right-click menu starts with hiding what it shows, as a swipe up does, then
    /// Clock's timer and stopwatch, while they show: Pause and Cancel, or, once the timer has rung,
    /// Repeat and Stop; Start or Stop, and Lap or Reset. Made afresh each time it opens.
    func menuNeedsUpdate(_ menu: NSMenu) {
        for item in menu.items where item.tag == Self.timerItem { menu.removeItem(item) }
        let clock = ClockActivity.shared
        var items: [NSMenuItem] = []
        func add(_ title: String, _ action: Selector) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            items.append(item)
        }
        let hide = putAway?()
        offeredPutAway = hide?.action
        if let hide { add(hide.title, #selector(putAwayActivity)) }
        offeredActivities = activityChoices?() ?? []
        if !offeredActivities.isEmpty {
            let item = NSMenuItem(title: String(localized: "Live Activities"), action: nil, keyEquivalent: "")
            let choices = NSMenu()
            choices.autoenablesItems = false
            for (index, choice) in offeredActivities.enumerated() {
                let row = NSMenuItem(title: choice.title, action: #selector(openActivityFromMenu), keyEquivalent: "")
                row.target = self
                row.tag = index
                choices.addItem(row)
            }
            item.submenu = choices
            items.append(item)
        }
        let recognize = NSMenuItem(title: String(localized: "Recognize Music"), action: #selector(recognizeMusicFromMenu), keyEquivalent: "")
        recognize.target = self
        recognize.isEnabled = canLaunchActivity?() == true && UserDefaults.standard.bool(forKey: Preferences.activityRecognition)
        items.append(recognize)
        let shortcuts = NSMenuItem(title: String(localized: "Run Shortcut"), action: nil, keyEquivalent: "")
        // Existing invocations stay manageable when their display or the notch is disabled.
        // The submenu revalidates availability only for launching a new shortcut.
        shortcuts.isEnabled = true
        shortcuts.submenu = ShortcutActivity.shared.makeRunMenu(
            canRun: { [weak self] in self?.canLaunchActivity?() == true },
            open: { [weak self] id in self?.onOpenShortcut?(id) }
        )
        items.append(shortcuts)
        if let timer = clock.timer {
            add(timer.isRunning ? String(localized: "Pause Timer") : String(localized: "Resume Timer"), #selector(pauseOrResumeTimer))
            add(String(localized: "Cancel Timer"), #selector(cancelTimer))
        } else if clock.rang != nil {
            add(String(localized: "Repeat Timer"), #selector(repeatTimer))
            add(String(localized: "Stop Timer"), #selector(stopTimer))
        }
        if let watch = clock.stopwatch {
            add(watch.isRunning ? String(localized: "Stop Stopwatch") : String(localized: "Start Stopwatch"), #selector(startStopStopwatch))
            add(watch.isRunning ? String(localized: "Restart Stopwatch") : String(localized: "Reset Stopwatch"), #selector(resetStopwatch))
        }
        guard !items.isEmpty else { return }
        items.append(.separator())
        for (index, item) in items.enumerated() {
            item.tag = Self.timerItem
            menu.insertItem(item, at: index)
        }
    }

    @objc private func putAwayActivity() { offeredPutAway?() }

    @objc private func openActivityFromMenu(_ item: NSMenuItem) {
        guard offeredActivities.indices.contains(item.tag) else { return }
        offeredActivities[item.tag].action()
    }

    /// Marks the timer's items in the menu, to take them out before it's made again.
    private static let timerItem = 7_000
}

/// The menu bar icon, drawn a frame at a time so macOS still colors it as it does every menu bar
/// icon: a new symbol replaces the old one by scaling in as the old one scales out, and turning the
/// notch off draws a slash across it, with a gap cut along the slash, as the Wi-Fi icon's when it's off.
@MainActor
final class StatusIcon {
    private weak var button: NSStatusBarButton?
    private var symbol: NSImage
    private var previous: NSImage?
    /// How far the change of symbol, and the slash, have come, 0 to 1.
    private var swap: CGFloat = 1
    private var slash: CGFloat = 0
    private var slashTarget: CGFloat = 0
    private var timer: Timer?
    /// The first time it's set, as Glance starts, it's drawn at once.
    private var started = false

    init(button: NSStatusBarButton, symbol: NSImage) {
        self.button = button
        self.symbol = symbol
        draw()
    }

    func setSymbol(_ image: NSImage) {
        guard image !== symbol else { return }
        previous = symbol
        symbol = image
        swap = 0
        run()
    }

    func setSlashed(_ slashed: Bool) {
        slashTarget = slashed ? 1 : 0
        if !started {
            started = true
            slash = slashTarget
            draw()
        } else {
            run()
        }
    }

    /// About a quarter of a second for either, eased.
    private func run() {
        guard timer == nil else { return }
        let step: CGFloat = 1 / (60 * 0.28)
        // In the common modes, so it plays while the menu is still open, as the switch is flipped.
        let timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.swap = min(self.swap + step, 1)
                self.slash += max(min(self.slashTarget - self.slash, step), -step)
                self.draw()
                if self.swap >= 1, self.slash == self.slashTarget {
                    self.previous = nil
                    self.timer?.invalidate()
                    self.timer = nil
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func draw() {
        let size = NSSize(width: 20, height: 18)
        let swapEased = Self.ease(swap), slashEased = Self.ease(slash)
        let current = symbol, old = previous
        let image = NSImage(size: size, flipped: false) { rect in
            func place(_ image: NSImage, scale: CGFloat, alpha: CGFloat) {
                let s = NSSize(width: image.size.width * scale, height: image.size.height * scale)
                image.draw(
                    in: NSRect(x: rect.midX - s.width / 2, y: rect.midY - s.height / 2, width: s.width, height: s.height),
                    from: .zero, operation: .sourceOver, fraction: alpha)
            }
            if let old, swapEased < 1 { place(old, scale: 1 - 0.4 * swapEased, alpha: 1 - swapEased) }
            place(current, scale: old == nil ? 1 : 0.6 + 0.4 * swapEased, alpha: old == nil ? 1 : swapEased)
            if slashEased > 0 {
                // From the top left toward the bottom right, as far as it has come.
                let start = NSPoint(x: rect.minX + 3.5, y: rect.maxY - 2.5)
                let end = NSPoint(x: rect.maxX - 3.5, y: rect.minY + 2.5)
                let tip = NSPoint(x: start.x + (end.x - start.x) * slashEased, y: start.y + (end.y - start.y) * slashEased)
                let line = NSBezierPath()
                line.move(to: start)
                line.line(to: tip)
                line.lineCapStyle = .round
                // The gap: the icon cut away on either side of the slash.
                NSGraphicsContext.current?.compositingOperation = .destinationOut
                line.lineWidth = 4.5
                NSColor.black.setStroke()
                line.stroke()
                NSGraphicsContext.current?.compositingOperation = .sourceOver
                line.lineWidth = 1.5
                line.stroke()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = slash > 0.5 ? String(localized: "Glance, off") : "Glance"
        button?.image = image
    }

    private static func ease(_ t: CGFloat) -> CGFloat { t * t * (3 - 2 * t) }
}
