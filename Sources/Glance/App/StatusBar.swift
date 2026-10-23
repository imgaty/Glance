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

/// The menu bar button. Clicked, it opens a menu made as Control Center's are (the Wi-Fi menu's
/// among them): "Glance" with a switch that turns the notch off on every display (to get it out of
/// the way for a while), then Check for Updates…, Settings and Quit, with Rebuild in builds made
/// from source. The icon gets a slash while the notch is off. Right-clicking the notch shows the
/// same choices as an ordinary menu.
@MainActor
final class StatusBarController: NSObject {
    /// For the notch's right-click.
    let menu = NSMenu()
    var onOpenSettings: (() -> Void)?

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let updatesItem = NSMenuItem(title: "Check for Updates…", action: #selector(updatesFromMenu), keyEquivalent: "")
    private let rebuildItem = NSMenuItem(title: "Rebuild", action: #selector(rebuildFromMenu), keyEquivalent: "")
    private var canCheckWatch: AnyCancellable?
    private var buildProcess: Process?
    private var enabledWatch: NSKeyValueObservation?
    private var icon: StatusIcon?
    private let panel = StatusPanel()
    private let state = StatusMenuState()

    override init() {
        super.init()
        statusItem.button?.toolTip = "Glance"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(clicked)
        if let button = statusItem.button { icon = StatusIcon(button: button, symbol: Self.notchIcon) }

        let settings = NSMenuItem(title: "Glance Settings…", action: #selector(settingsFromMenu), keyEquivalent: "")
        settings.target = self
        updatesItem.target = self
        rebuildItem.target = self
        let quit = NSMenuItem(title: "Quit Glance", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        menu.autoenablesItems = false
        menu.delegate = self
        menu.addItem(updatesItem)
        state.canRebuild = BuildInfo.sourceDirectory != nil
        if state.canRebuild { menu.addItem(rebuildItem) }
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(quit)
        if #available(macOS 27, *) {
            for item in menu.items { item.preferredImageVisibility = .hidden }
        }

        canCheckWatch = Updater.shared.$canCheck.sink { [weak self] can in self?.updatesItem.isEnabled = can }
        panel.onClose = { [weak self] in self?.statusItem.button?.highlight(false) }

        // A slash across the icon while the notch is off.
        enabledWatch = UserDefaults.standard.observe(\.notchEnabled, options: [.initial]) { [weak self] defaults, _ in
            let on = defaults.notchEnabled
            Task { @MainActor in self?.icon?.setSlashed(!on) }
        }
    }

    @objc private func clicked() {
        guard let button = statusItem.button else { return }
        if panel.isShown { return panel.close() }
        button.highlight(true)
        panel.show(
            below: button,
            content: StatusMenu(state: state) { [weak self] action in
                guard let self else { return }
                panel.close()
                switch action {
                case .checkForUpdates: Updater.shared.checkForUpdates()
                case .rebuild: rebuild()
                case .settings: onOpenSettings?()
                case .quit: NSApp.terminate(nil)
                }
            })
    }

    @objc private func updatesFromMenu() { Updater.shared.checkForUpdates() }
    @objc private func pauseOrResumeTimer() { ClockActivity.shared.toggleTimer() }
    @objc private func cancelTimer() { ClockActivity.shared.cancelTimer() }
    @objc private func repeatTimer() { ClockActivity.shared.repeatTimer() }
    @objc private func stopTimer() { ClockActivity.shared.dismissRing() }
    @objc private func startStopStopwatch() { ClockActivity.shared.startStopStopwatch() }
    @objc private func lapResetStopwatch() { ClockActivity.shared.lapResetStopwatch() }
    @objc private func rebuildFromMenu() { rebuild() }
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
        if log != nil { alert.addButton(withTitle: "Open Log") }
        NSApp.activate()
        if alert.runModal() == .alertSecondButtonReturn, let log {
            NSWorkspace.shared.open(log)
        }
    }

    private func setBuilding(_ building: Bool) {
        state.rebuilding = building
        rebuildItem.title = building ? "Rebuilding…" : "Rebuild"
        rebuildItem.isEnabled = !building
        icon?.setSymbol(building ? Self.hammerIcon : Self.notchIcon)
    }

    // MARK: Icon

    /// A screen with its top filled in, the SF Symbol the welcome window shows Glance with. Symbols
    /// follow the menu bar's appearance on their own.
    private static let notchIcon = symbol("rectangle.topthird.inset.filled", "Glance")
    private static let hammerIcon = symbol("hammer", "Rebuilding")

    private static func symbol(_ name: String, _ description: String) -> NSImage {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: description) ?? NSImage()
        return image.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)) ?? image
    }
}

extension StatusBarController: NSMenuDelegate {
    /// The notch's right-click menu starts with Clock's timer and stopwatch, while they show: Pause
    /// and Cancel, or, once the timer has rung, Repeat and Stop; Start or Stop, and Lap or Reset.
    /// Made afresh each time it opens.
    func menuNeedsUpdate(_ menu: NSMenu) {
        for item in menu.items where item.tag == Self.timerItem { menu.removeItem(item) }
        let clock = ClockActivity.shared
        var items: [NSMenuItem] = []
        func add(_ title: String, _ action: Selector) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            items.append(item)
        }
        if let timer = clock.timer {
            add(timer.isRunning ? "Pause Timer" : "Resume Timer", #selector(pauseOrResumeTimer))
            add("Cancel Timer", #selector(cancelTimer))
        } else if clock.rang != nil {
            add("Repeat Timer", #selector(repeatTimer))
            add("Stop Timer", #selector(stopTimer))
        }
        if let watch = clock.stopwatch {
            add(watch.isRunning ? "Stop Stopwatch" : "Start Stopwatch", #selector(startStopStopwatch))
            add(watch.isRunning ? "Lap" : "Reset Stopwatch", #selector(lapResetStopwatch))
        }
        guard !items.isEmpty else { return }
        items.append(.separator())
        for (index, item) in items.enumerated() {
            item.tag = Self.timerItem
            menu.insertItem(item, at: index)
        }
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
        image.accessibilityDescription = slash > 0.5 ? "Glance, off" : "Glance"
        button?.image = image
    }

    private static func ease(_ t: CGFloat) -> CGFloat { t * t * (3 - 2 * t) }
}

/// What the menu shows that changes while it's open.
@MainActor
@Observable
final class StatusMenuState {
    var canRebuild = false
    var rebuilding = false
}

/// The menu itself, as Control Center lays out its menus: the same padding all around, rows 22
/// points tall one after another, lit under the pointer with corners as much rounder than the
/// menu's as they're inset, and a real switch at the top.
private struct StatusMenu: View {
    enum Action {
        case checkForUpdates, rebuild, settings, quit
    }

    let state: StatusMenuState
    let perform: (Action) -> Void
    @ObservedObject private var updater = Updater.shared
    @ObservedObject private var clock = ClockActivity.shared
    @AppStorage(Preferences.notchEnabled) private var enabled = true
    @Environment(\.colorScheme) private var scheme

    static let inset: CGFloat = 7
    static let radius: CGFloat = 16
    /// Room around the menu, in its window, for its shadow.
    static let shadowRoom: CGFloat = 40

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Glance")
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 24)
                Toggle("Glance", isOn: $enabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            .padding(.horizontal, 9)
            .frame(height: 36)
            separator
            if StatusClock.shows(clock) {
                StatusClock()
                separator
            }
            StatusMenuRow(title: "Check for Updates…", enabled: updater.canCheck) { perform(.checkForUpdates) }
            // Only in builds made from source, which know where it is.
            if state.canRebuild {
                StatusMenuRow(title: state.rebuilding ? "Rebuilding…" : "Rebuild", enabled: !state.rebuilding) {
                    perform(.rebuild)
                }
            }
            StatusMenuRow(title: "Glance Settings…") { perform(.settings) }
            separator
            StatusMenuRow(title: "Quit Glance") { perform(.quit) }
        }
        .padding(Self.inset)
        .frame(width: 280)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
        .background { shadow }
    }

    /// Wide and faint, as the Wi-Fi menu's, and only outside the menu, so none of it darkens the
    /// glass. The glass's rim, over it, draws the thin gray line the Wi-Fi menu has around it.
    /// (macOS's own window shadow is tighter, and its line blurry.)
    @ViewBuilder private var shadow: some View {
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        shape
            .fill(.black)
            .shadow(color: .black.opacity(0.07), radius: 22, y: 8)
            .mask {
                Rectangle()
                    .padding(-Self.shadowRoom)
                    .overlay { shape.blendMode(.destinationOut) }
                    .compositingGroup()
            }
    }

    private var separator: some View {
        // A plain color, as the highlight: the glass makes a vibrant one fainter. Measured against
        // the Wi-Fi menu's.
        Rectangle()
            .fill(scheme == .dark ? Color.white.opacity(0.13) : Color.black.opacity(0.1))
            .frame(height: 1)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
    }
}

private struct StatusMenuRow: View {
    let title: String
    var enabled = true
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(title)
            .font(.system(size: 13))
            .foregroundStyle(enabled ? .primary : .tertiary)
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
            .background {
                // A plain color: the glass would make a vibrant one fainter. Measured against the
                // Wi-Fi menu's.
                RoundedRectangle(cornerRadius: StatusMenu.radius - StatusMenu.inset, style: .continuous)
                    .fill(scheme == .dark ? Color.white : Color.black)
                    .opacity(enabled && hovering ? (scheme == .dark ? 0.17 : 0.09) : 0)
            }
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture { if enabled { action() } }
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { if enabled { action() } }
    }
}

/// The window the menu shows in: a panel under the menu bar icon, kept in front without taking the
/// focus from the app in use, and drawn as a window in front, so its switch is in the accent color
/// and its glass is whole. It goes away on a click anywhere else, on Escape, or on the icon again.
@MainActor
final class StatusPanel {
    var onClose: (() -> Void)?
    private var panel: MenuPanel?
    private var monitors: [Any] = []
    /// Glance's window that had the keys before the menu took them (Settings, say), given them back.
    private weak var previousKey: NSWindow?

    var isShown: Bool { panel?.isVisible == true }

    func show(below button: NSStatusBarButton, content: some View) {
        close()
        previousKey = NSApp.keyWindow
        let room = StatusMenu.shadowRoom
        let host = NotchHostingView(rootView: AnyView(content.fixedSize().padding(room)))
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        let menu = CGSize(width: size.width - room * 2, height: size.height - room * 2)
        let panel = MenuPanel(
            contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The menu draws its own shadow.
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        panel.contentView = host
        panel.onCancel = { [weak self] in self?.close() }
        // Under the icon, as menus open from the menu bar: its left edge under the icon's left edge,
        // or, if it wouldn't fit on the screen that way, its right edge under the icon's right edge.
        if let window = button.window, let screen = window.screen {
            let icon = window.convertToScreen(button.convert(button.bounds, to: nil))
            let x = icon.minX + menu.width <= screen.visibleFrame.maxX ? icon.minX : icon.maxX - menu.width
            panel.setFrameOrigin(NSPoint(x: x - room, y: icon.minY - 6 - menu.height - room))
        }
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        monitors = [
            NSEvent.addGlobalMonitorForEvents(matching: clicks) { [weak self] _ in
                MainActor.assumeIsolated { self?.close() }
            },
            NSEvent.addLocalMonitorForEvents(matching: clicks) { [weak self] event in
                MainActor.assumeIsolated {
                    // A click in the menu is the menu's; on the icon, the icon closes it.
                    guard let self, event.window !== self.panel, event.window !== button.window else { return }
                    self.close()
                }
                return event
            },
        ].compactMap { $0 }
    }

    func close() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        guard let panel else { return }
        self.panel = nil
        let previous = previousKey
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated {
                panel.orderOut(nil)
                // Still the app in use, with nothing else in front: the keys go back where they were.
                if NSApp.isActive, NSApp.keyWindow == nil || NSApp.keyWindow === panel, let previous, previous.isVisible {
                    previous.makeKey()
                }
            }
        }
        onClose?()
    }
}

/// Takes the focus for Escape, without making Glance the app in use, and looks like a window in front.
private final class MenuPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }

    /// Private AppKit hooks: drawn as a window in front, so the switch has its color and the glass
    /// isn't the flat look of a window behind.
    @objc func _hasActiveAppearance() -> Bool { true }
    @objc func _hasActiveAppearanceIgnoringKeyFocus() -> Bool { true }
}

/// Clock's timer and stopwatch, as Control Center lays out a module, while they show: each one's name
/// and time, with buttons to pause or resume the timer and cancel it, or to start or stop the
/// stopwatch and lap or reset it; a timer that has rung, with buttons to start it again or stop
/// saying it. They're pressed through Clock (see `ClockActivity`); without Accessibility, the
/// buttons are dimmed, and a press asks for it.
private struct StatusClock: View {
    @ObservedObject var clock = ClockActivity.shared
    /// Between the buttons, as far apart as their bezels need.
    static let spacing: CGFloat = 10

    /// Something of Clock's to show.
    static func shows(_ clock: ClockActivity) -> Bool { clock.timer != nil || clock.rang != nil || clock.stopwatch != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let timer = clock.timer {
                row(clock.timerTitle ?? "Timer") {
                    Self.time(running: timer.isRunning) { NotchTimer.format(timer.left(at: $0)) }
                    buttons {
                        StatusRoundButton(symbol: timer.isRunning ? "pause.fill" : "play.fill", label: timer.isRunning ? "Pause" : "Resume") {
                            clock.toggleTimer()
                        }
                        StatusRoundButton(symbol: "xmark", label: "Cancel") { clock.cancelTimer() }
                    }
                }
            } else if let rang = clock.rang {
                row(rang.title ?? "Timer") {
                    Text("Done").font(.system(size: 13, weight: .medium))
                    buttons {
                        StatusRoundButton(symbol: "arrow.counterclockwise", label: "Repeat") { clock.repeatTimer() }
                        StatusRoundButton(symbol: "stop.fill", label: "Stop") { clock.dismissRing() }
                    }
                }
            }
            if let watch = clock.stopwatch {
                row("Stopwatch") {
                    Self.time(running: watch.isRunning) { Stopwatch.format(watch.elapsed(at: $0)) }
                    buttons {
                        StatusRoundButton(symbol: watch.isRunning ? "pause.fill" : "play.fill", label: watch.isRunning ? "Stop" : "Start") {
                            clock.startStopStopwatch()
                        }
                        StatusRoundButton(symbol: watch.isRunning ? "flag.fill" : "arrow.counterclockwise", label: watch.isRunning ? "Lap" : "Reset") {
                            clock.lapResetStopwatch()
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
    }

    private func row<Trailing: View>(_ name: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: Self.spacing) {
            Text(name)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 8)
            trailing()
        }
    }

    /// Without Accessibility, dimmed; a press asks for it.
    private func buttons<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: Self.spacing) { content() }
            .opacity(clock.canControl ? 1 : 0.45)
            .help(clock.canControl ? "" : "Allow Glance in Accessibility to control Clock")
            .accessibilityHint(clock.canControl ? "" : "Needs Accessibility")
    }

    /// The time, ticking. Paused or stopped, it says so with a symbol before the time, which waits.
    /// In the label's own color, which the glass keeps readable whatever is behind it; an orange
    /// can't be.
    private static func time(running: Bool, reading: @escaping (Date) -> String) -> some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            HStack(spacing: 4) {
                if !running {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .accessibilityLabel("Paused")
                }
                Text(reading(context.date))
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
            }
            .foregroundStyle(.primary)
        }
    }
}

/// A small round button with a symbol, as Control Center's modules have.
private struct StatusRoundButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(StatusTimerButtonStyle(shape: Circle()))
        .accessibilityLabel(label)
    }
}

/// The timer's buttons: a faint fill, fainter at rest than under the pointer or pressed. Buttons of
/// their own, so the keyboard reaches them too.
private struct StatusTimerButtonStyle<S: Shape>: ButtonStyle {
    let shape: S

    func makeBody(configuration: Configuration) -> some View {
        StatusTimerButtonBody(label: configuration.label, pressed: configuration.isPressed, shape: shape)
    }
}

private struct StatusTimerButtonBody<Label: View, S: Shape>: View {
    let label: Label
    let pressed: Bool
    let shape: S
    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        let fill = pressed ? (dark ? 0.28 : 0.18) : hovering ? (dark ? 0.2 : 0.12) : (dark ? 0.1 : 0.06)
        label
            .background(shape.fill(dark ? Color.white : Color.black).opacity(fill))
            .contentShape(shape)
            .onHover { hovering = $0 }
    }
}
