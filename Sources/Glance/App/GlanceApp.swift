//
//  GlanceApp.swift
//  Glance
//
//  Created by Gaty on 07/10/2026.
//

import AppKit

@main
enum GlanceApp {
    @MainActor
    static func main() {
        // A copy started only to read the permissions afresh; see Permissions.recheck().
        if CommandLine.arguments.contains(Permissions.statusArgument) {
            Permissions.printStatus()
            exit(0)
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // Info.plist keeps the app out of the Dock; this covers runs from Xcode. Only the Settings
        // and onboarding windows bring in a Dock icon and menu bar.
        app.setActivationPolicy(.accessory)
        // NSApplication holds its delegate weakly.
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let nowPlaying = NowPlaying()
    private lazy var notches = NotchManager(nowPlaying: nowPlaying)
    private let settings = SettingsWindowController()
    private let onboarding = OnboardingWindowController()
    private var statusBar: StatusBarController?
    private var settingsWatch: [NSKeyValueObservation] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMainMenu()
        nowPlaying.start()
        Updater.shared.start()
        let statusBar = StatusBarController()
        statusBar.onOpenSettings = { [settings] in settings.show() }
        settings.nowPlaying = nowPlaying
        settings.onShowPermissions = { [onboarding] in onboarding.show(startingAt: .permissions) }
        notches.contextMenu = statusBar.menu
        notches.start()
        Tray.shared.start()
        Shortcuts.shared.onAction = { [notches] action in notches.perform(action) }
        Shortcuts.shared.register()
        self.statusBar = statusBar
        watchSettings()
        // The welcome tour, on first launch, until its window has been closed once.
        // ./build.sh --run (and Rebuild) asks for it with --onboarding, so each new build shows it.
        if !UserDefaults.standard.bool(forKey: Preferences.onboardingDone) || CommandLine.arguments.contains("--onboarding") {
            onboarding.show()
        }
    }

    /// Settings that rebuild the notches or reshape the player when they change.
    private func watchSettings() {
        let notches = notches
        func watch<Value>(_ key: KeyPath<UserDefaults, Value>, _ action: @escaping @MainActor () -> Void) -> NSKeyValueObservation {
            UserDefaults.standard.observe(key) { _, _ in Task { @MainActor in action() } }
        }
        settingsWatch = [
            watch(\.showOnDisplaysWithoutNotch) { notches.reload() },
            watch(\.hideInFullScreen) { notches.reload() },
            watch(\.sameLookEverywhere) { notches.reload() },
            // Turned off and on from the menu bar: the notches close away and come back.
            watch(\.notchEnabled) { notches.reload(switching: true) },
            watch(\.musicLayout) { notches.relayout() },
            // Its shortcut comes and goes with the tray.
            watch(\.tray) { Shortcuts.shared.register() },
        ]
    }

    @objc private func openSettings() {
        settings.show()
    }

    private func makeMainMenu() -> NSMenu {
        let app = NSMenu()
        app.addItem(withTitle: "About Glance", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        app.addItem(.separator())
        app.addItem(withTitle: "Hide Glance", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
            .keyEquivalentModifierMask = [.command, .option]
        app.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Quit Glance", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        NSApp.windowsMenu = window

        let main = NSMenu()
        for menu in [app, edit, window] {
            let item = NSMenuItem()
            item.submenu = menu
            main.addItem(item)
        }
        return main
    }
}

enum Preferences {
    /// What each setting is until it's changed.
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            showOnPlainDisplays: true,
            liveActivity: true,
            musicBackground: MusicBackground.replaceGlass.rawValue,
            musicAnimatedArtwork: true,
            musicShowsNewApps: true,
            musicAppBadge: false,
            musicTrackPop: true,
            notchEnabled: true,
            swipeToOpen: true,
            swipeToSkip: true,
            lyrics: true,
            musicLayout: PlayerLayout.top.rawValue,
            openTrigger: OpenTrigger.both.rawValue,
            hoverDelay: 0.2,
            clickDelay: 0.0,
            haptics: false,
            hideInFullScreen: true,
            tray: true,
            trayClipboard: true,
            trayClipboardKeep: ClipboardKeep.eightHours.rawValue,
        ])
    }

    static let showOnPlainDisplays = "showOnDisplaysWithoutNotch"
    /// Whether the notch's glass is the system's Liquid Glass, as set in Appearance settings,
    /// rather than the darkness and blur below.
    static let glassFollowsSystem = "glassFollowsSystem"
    /// The open notch from completely clear glass (0) to solid black (1).
    static let glassDarkness = "glassDarkness"
    /// How much the glass blurs what's behind it, from none (0) to fully (1).
    static let glassBlur = "glassBlur"
    static let musicAccentTimeline = "musicAccentTimeline"
    static let musicLayout = "musicLayout"
    static let musicAccentSource = "musicAccentSource"
    /// What's on either side of the transport controls (a PlayerSlot), and whether clicking the
    /// waveform opens the lyrics.
    static let musicLeftButton = "musicLeftButton"
    static let musicRightButton = "musicRightButton"
    /// Lyrics, anywhere in the app: from the waveform, a lyrics button, and their lookups.
    static let lyrics = "lyrics"
    static let liveActivity = "liveActivity"
    static let musicBackground = "musicBackground"
    static let musicAnimatedArtwork = "musicAnimatedArtwork"
    /// Apps whose music stays out of the notch and every app that has played something (both comma
    /// separated), and whether an app playing for the first time shows.
    static let musicHiddenApps = "musicHiddenApps"
    static let musicSeenApps = "musicSeenApps"
    static let musicShowsNewApps = "musicShowsNewApps"
    static let musicAppBadge = "musicAppBadge"

    /// The settings each display keeps its own of: how its notch looks.
    static let perDisplay = [glassFollowsSystem, glassDarkness, glassBlur, musicBackground]

    /// No dots: key-value observing reads a dot as a path, so a change to a dotted key can go
    /// unseen by the notch.
    static func key(_ key: String, for display: String) -> String { key + ":" + display }

    /// Every display shares one look instead of keeping its own.
    static let sameLook = "sameLookEverywhere"

    /// Where a display's look is kept: its own, or the shared one while every display looks the same.
    static func lookKey(_ key: String, display: String?) -> String {
        guard let display, !UserDefaults.standard.bool(forKey: sameLook) else { return key }
        return Self.key(key, for: display)
    }

    /// A display seen for the first time takes the settings shared so far.
    static func seed(_ display: String) {
        let defaults = UserDefaults.standard
        for key in perDisplay where defaults.object(forKey: Self.key(key, for: display)) == nil {
            if let shared = defaults.object(forKey: key) { defaults.set(shared, forKey: Self.key(key, for: display)) }
        }
    }
    static let musicTrackPop = "musicTrackPop"
    /// Off, there's no notch on any display until it's turned back on, from the menu bar.
    static let notchEnabled = "notchEnabled"
    /// Per display without a notch (keyed with its ID): a NotchStyle.
    static let notchStyle = "notchStyle"
    /// The trackpad gestures: two fingers down and up to open and close the notch, sideways to
    /// change songs.
    static let swipeToOpen = "swipeToOpen"
    static let swipeToSkip = "swipeToSkip"
    static let onboardingDone = "onboardingDone"
    static let openTrigger = "openTrigger"
    static let hoverDelay = "hoverDelay"
    static let clickDelay = "clickDelay"
    static let haptics = "haptics"
    static let hideInFullScreen = "hideInFullScreen"
    /// The shortcuts that open the player and the tray, when they aren't the ones Glance came with:
    /// a KeyCombo, as JSON.
    static let shortcutMusic = "shortcutMusic"
    static let shortcutTray = "shortcutTray"
    /// The tray: on, keeping what's copied, and for how long (a ClipboardKeep).
    static let tray = "tray"
    static let trayClipboard = "trayClipboard"
    static let trayClipboardKeep = "trayClipboardKeep"
    /// The page the notch was last left on (a NotchPage), which it opens on next.
    static let notchPage = "notchPage"
}

/// The settings that are watched by their keys.
extension UserDefaults {
    @objc dynamic var showOnDisplaysWithoutNotch: Bool { bool(forKey: Preferences.showOnPlainDisplays) }
    @objc dynamic var hideInFullScreen: Bool { bool(forKey: Preferences.hideInFullScreen) }
    @objc dynamic var sameLookEverywhere: Bool { bool(forKey: Preferences.sameLook) }
    @objc dynamic var musicLayout: String? { string(forKey: Preferences.musicLayout) }
    @objc dynamic var notchEnabled: Bool { bool(forKey: Preferences.notchEnabled) }
    @objc dynamic var tray: Bool { bool(forKey: Preferences.tray) }
}

enum OpenTrigger: String, CaseIterable, Identifiable {
    case hover, click, both

    var id: Self { self }
    var title: String {
        switch self {
        case .hover: "Hover"
        case .click: "Click"
        case .both: "Hover or click"
        }
    }
}

extension NSScreen {
    /// Stays the same for a display across restarts and reconnections.
    var notchID: String {
        let number = (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(number)?.takeRetainedValue() else { return localizedName }
        return CFUUIDCreateString(nil, uuid) as String
    }
}

/// Owns one notch per display and feeds them pointer events.
@MainActor
final class NotchManager {
    private let nowPlaying: NowPlaying

    init(nowPlaying: NowPlaying) {
        self.nowPlaying = nowPlaying
    }

    /// Shown when the notch is right-clicked.
    var contextMenu: NSMenu?

    private var controllers: [NotchController] = []
    private var monitors: [Any] = []

    private var styles = ""
    /// The displays the notches were last made for, and how each one's top is laid out.
    private var madeFor = ""
    private var fullScreenTimer: Timer?

    func start() {
        Preferences.registerDefaults()
        reload()

        // Only a change the notches would show: the Dock coming and going with Glance's windows
        // changes the screens' parameters too, and rebuilding for it would make them blink.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, Self.displays != self.madeFor else { return }
                self.reload()
            }
        }
        // A display switched between a notch and a Dynamic Island in Settings.
        styles = NotchStyle.signature
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, NotchStyle.signature != self.styles else { return }
                self.styles = NotchStyle.signature
                self.reload()
            }
        }

        // Entering full screen makes a new Space; apps that fill the screen without one are caught
        // by a slow check, which costs a window list every second and a half.
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    MainActor.assumeIsolated { self?.updateFullScreen() }
                }
            }
        }
        fullScreenTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateFullScreen() }
        }

        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        monitors = [
            NSEvent.addGlobalMonitorForEvents(matching: moves) { [weak self] _ in
                MainActor.assumeIsolated { self?.pointerMoved() }
            },
            NSEvent.addLocalMonitorForEvents(matching: moves) { [weak self] event in
                MainActor.assumeIsolated { self?.pointerMoved() }
                return event
            },
            // Global monitors only see clicks meant for other apps, i.e. clicks off the notch.
            NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                MainActor.assumeIsolated { self?.clickedElsewhere() }
            },
        ].compactMap { $0 }
    }

    /// Every notch switches to the player layout chosen in Settings.
    func relayout() {
        controllers.forEach { $0.relayout() }
    }

    /// Recreates every notch from the current displays and preferences; none while the notch is off.
    /// Switching it off or on, they close away or come back rather than fade.
    func reload(switching: Bool = false) {
        let showOnPlainDisplays = UserDefaults.standard.bool(forKey: Preferences.showOnPlainDisplays)
        controllers.forEach { $0.tearDown(collapsing: switching) }
        guard UserDefaults.standard.bool(forKey: Preferences.notchEnabled) else {
            controllers = []
            return
        }
        NSScreen.screens.forEach { Preferences.seed($0.notchID) }
        madeFor = Self.displays
        controllers = NSScreen.screens.compactMap { NotchController(screen: $0, allowVirtual: showOnPlainDisplays, nowPlaying: nowPlaying) }
        // Never leave the user with no notch at all.
        if controllers.isEmpty, let main = NSScreen.main, let fallback = NotchController(screen: main, allowVirtual: true, nowPlaying: nowPlaying) {
            controllers = [fallback]
        }
        for controller in controllers {
            controller.onContextMenu = { [weak self] event, view in
                guard let menu = self?.contextMenu else { return }
                NSMenu.popUpContextMenu(menu, with: event, for: view)
            }
            controller.show(expanding: switching)
        }
        updateFullScreen()
        pointerMoved()
    }

    /// Each display, where it is, and its notch's resting place and size.
    private static var displays: String {
        NSScreen.screens.map { screen in
            let resting = NotchController.resting(on: screen)
            return "\(screen.notchID) \(screen.frame) \(resting.size) \(resting.centerX)"
        }
        .joined(separator: "; ")
    }

    /// Hides each notch while a full-screen app covers its display, if the user chose that.
    private func updateFullScreen() {
        let covered = UserDefaults.standard.bool(forKey: Preferences.hideInFullScreen) ? Self.fullScreenDisplays() : []
        for controller in controllers {
            controller.fullScreen = covered.contains(controller.screenFrame)
        }
    }

    /// Displays with another app's window exactly their size, which is what full screen looks like
    /// from outside. Window positions and sizes are readable without any permission.
    private static func fullScreenDisplays() -> [CGRect] {
        guard
            let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]],
            let primaryHeight = NSScreen.screens.first?.frame.height
        else { return [] }
        let me = Int(ProcessInfo.processInfo.processIdentifier)
        let appWindows = windows.compactMap { info -> CGRect? in
            guard info[kCGWindowLayer as String] as? Int == 0, info[kCGWindowOwnerPID as String] as? Int != me,
                let bounds = info[kCGWindowBounds as String]
            else { return nil }
            return CGRect(dictionaryRepresentation: bounds as! CFDictionary)
        }
        return NSScreen.screens.map(\.frame).filter { frame in
            // Window bounds have their origin at the top left of the main display.
            let flipped = CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
            return appWindows.contains(flipped)
        }
    }

    private func pointerMoved() {
        let location = NSEvent.mouseLocation
        controllers.forEach { $0.pointerMoved(to: location) }
    }

    /// A shortcut: the notch on the display under the pointer, or the first one.
    func perform(_ action: Shortcuts.Action) {
        let location = NSEvent.mouseLocation
        let controller = controllers.first { $0.screenFrame.contains(location) } ?? controllers.first
        switch action {
        case .music: controller?.toggleFromKeyboard(.player)
        case .tray: controller?.toggleFromKeyboard(.tray)
        }
    }

    private func clickedElsewhere() {
        let location = NSEvent.mouseLocation
        controllers.forEach { $0.clicked(outsideAt: location) }
    }
}
