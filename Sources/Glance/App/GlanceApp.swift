//
//  GlanceApp.swift
//  Glance
//
//  Created by Gaty on 07/10/2026.
//

import AppKit
import Quartz

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
    private let nowPlaying = ActivityBench.scenes.contains(.music) ? NowPlaying.demo(.tour) : NowPlaying()
    private lazy var notches = NotchManager(nowPlaying: nowPlaying)
    private let settings = SettingsWindowController()
    private let onboarding = OnboardingWindowController()
    private var statusBar: StatusBarController?
    private var settingsWatch: [NSKeyValueObservation] = []
    private let trayService = TrayService()

    func applicationDidFinishLaunching(_ notification: Notification) {
        quitOnSignals()
        watchMainThread()
        ActivityBench.shared.isolate()
        NSApp.mainMenu = makeMainMenu()
        nowPlaying.start()
        Updater.shared.start()
        let statusBar = StatusBarController()
        statusBar.onOpenSettings = { [settings] in settings.show() }
        settings.nowPlaying = nowPlaying
        notches.contextMenu = statusBar.menu
        statusBar.putAway = (title: { [notches] in notches.putAwayTitle }, action: { [notches] in notches.putAway() })
        notches.start()
        Tray.shared.start()
        NSApp.servicesProvider = trayService
        NSUpdateDynamicServices()
        trayService.start()
        SystemDevices.prepare()
        Activities.shared.start()
        ActivityBench.shared.start()
        NotchSwipes.shared.onSwipe = { [notches] motion in notches.swipe(motion) }
        NotchSwipes.shared.start()
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

    /// However Glance is quit (its menus, Command-Q, Activity Monitor's Quit, a script, logging out,
    /// or Terminal), the notch closes away first, as it does when it's turned off, and Glance quits
    /// once it has.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !closingAway else { return .terminateNow }
        let time = notches.closeAway()
        guard time > 0 else { return .terminateNow }
        closingAway = true
        // On the run loop, which goes on while Glance waits to quit, as the main queue may not.
        let reply = Timer(timeInterval: time, repeats: false) { _ in
            MainActor.assumeIsolated { NSApp.reply(toApplicationShouldTerminate: true) }
        }
        RunLoop.main.add(reply, forMode: .common)
        RunLoop.main.add(reply, forMode: .modalPanel)
        return .terminateLater
    }
    private var closingAway = false

    /// Terminal's `kill`, `pkill` and `killall`, and Control-C, ask for an ordinary quit, so the
    /// notch closes away first. Should Glance not have quit a few seconds later, it stops there and
    /// then, as those would have stopped it. Force Quit and `kill -9` can't be answered at all.
    private func quitOnSignals() {
        signalSources = [SIGTERM, SIGINT, SIGHUP].map { number in
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
            source.setEventHandler {
                // Through the run loop: from the main queue, the main queue would be held up until
                // Glance quit, and with it what closes the notch.
                NSApplication.shared.performSelector(
                    onMainThread: #selector(NSApplication.terminate(_:)), with: nil, waitUntilDone: false, modes: [RunLoop.Mode.common.rawValue])
                DispatchQueue.global().asyncAfter(deadline: .now() + 3) { exit(0) }
            }
            source.resume()
            return source
        }
    }
    private var signalSources: [DispatchSourceSignal] = []

    /// Should the main thread stop answering for ten seconds, Glance stops itself. Frozen with a menu
    /// open, as it once was while its volume slider was dragged, it held the pointer and the keyboard,
    /// and neither Quit nor Force Quit could be reached. Never while a debugger holds it.
    private func watchMainThread() {
        let watch = MainThreadWatch()
        Thread.detachNewThread {
            while true {
                watch.ask()
                Thread.sleep(forTimeInterval: 2)
                guard watch.silent > MainThreadWatch.limit, !MainThreadWatch.debugged else { continue }
                NSLog("Glance stopped itself: its main thread hadn't answered for %.0f seconds", watch.silent)
                kill(getpid(), SIGKILL)
            }
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
            watch(\.notchHiddenDisplays) { notches.reload() },
            watch(\.hideInFullScreen) { notches.reload() },
            watch(\.sameLookEverywhere) { notches.reload() },
            // Turned off and on from the menu bar: the notches close away and come back.
            watch(\.notchEnabled) { notches.reload(switching: true) },
            watch(\.musicLayout) { notches.relayout() },
            // Its shortcut comes and goes with the tray.
            watch(\.tray) { Shortcuts.shared.register() },
        ]
    }

    @objc private func goBack() { SettingsCommands.shared.go?(-1) }
    @objc private func goForward() { SettingsCommands.shared.go?(1) }
    @objc private func searchSettings() { SettingsCommands.shared.search?() }
    @objc private func showPane(_ item: NSMenuItem) {
        guard let pane = (item.representedObject as? String).flatMap(SettingsPane.init) else { return }
        SettingsCommands.shared.show?(pane)
    }
    @objc private func openHelp() {
        if let manual = URL(string: "https://github.com/imgaty/Glance/blob/main/docs/USER-MANUAL.md") { NSWorkspace.shared.open(manual) }
    }

    @objc private func openSettings() {
        settings.show()
    }

    // Quick Look, for the tray's items: Glance takes charge of the panel, and the tray gives it what
    // to show.
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = TrayQuickLook.shared
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
    }

    /// The menu bar while Settings or the welcome tour is open: Apple's standard menus, in their
    /// order, with what those windows can use of them.
    func makeMainMenu() -> NSMenu {
        let app = NSMenu()
        app.addItem(withTitle: String(localized: "About Glance"), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: String(localized: "Settings…"), action: #selector(openSettings), keyEquivalent: ",").target = self
        app.addItem(.separator())
        let services = NSMenu(title: String(localized: "Services"))
        app.addItem(withTitle: String(localized: "Services"), action: nil, keyEquivalent: "").submenu = services
        NSApp.servicesMenu = services
        app.addItem(.separator())
        app.addItem(withTitle: String(localized: "Hide Glance"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(withTitle: String(localized: "Hide Others"), action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
            .keyEquivalentModifierMask = [.command, .option]
        app.addItem(withTitle: String(localized: "Show All"), action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: String(localized: "Quit Glance"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // Closing a window is the File menu's, not the Window menu's.
        let file = NSMenu(title: String(localized: "File"))
        file.addItem(withTitle: String(localized: "Close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let edit = NSMenu(title: String(localized: "Edit"))
        edit.addItem(withTitle: String(localized: "Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: String(localized: "Redo"), action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: String(localized: "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: String(localized: "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: String(localized: "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: String(localized: "Delete"), action: #selector(NSText.delete(_:)), keyEquivalent: "")
        edit.addItem(withTitle: String(localized: "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        // Minimize and Zoom even for one window, so the keyboard reaches them with Full Keyboard
        // Access; macOS adds its own tiling items and the windows' names below.
        let window = NSMenu(title: String(localized: "Window"))
        window.addItem(withTitle: String(localized: "Minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: String(localized: "Zoom"), action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        window.addItem(.separator())
        window.addItem(withTitle: String(localized: "Bring All to Front"), action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        NSApp.windowsMenu = window

        // Every command in the Settings window's toolbar, and every page, from the keyboard too.
        let view = NSMenu(title: String(localized: "View"))
        view.addItem(withTitle: String(localized: "Back"), action: #selector(goBack), keyEquivalent: "[").target = self
        view.addItem(withTitle: String(localized: "Forward"), action: #selector(goForward), keyEquivalent: "]").target = self
        view.addItem(.separator())
        view.addItem(withTitle: String(localized: "Search"), action: #selector(searchSettings), keyEquivalent: "f").target = self
        view.addItem(.separator())
        for pane in SettingsPane.allCases {
            let item = view.addItem(withTitle: pane.title, action: #selector(showPane), keyEquivalent: "")
            item.target = self
            item.representedObject = pane.rawValue
        }

        let help = NSMenu(title: String(localized: "Help"))
        help.addItem(withTitle: String(localized: "Glance Help"), action: #selector(openHelp), keyEquivalent: "?").target = self
        NSApp.helpMenu = help

        let main = NSMenu()
        for menu in [app, file, edit, view, window, help] {
            let item = NSMenuItem()
            item.submenu = menu
            main.addItem(item)
        }
        return main
    }
}

/// The View menu works on the Settings window, while it's open.
extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        let commands = SettingsCommands.shared
        switch item.action {
        case #selector(goBack): return commands.canGoBack
        case #selector(goForward): return commands.canGoForward
        case #selector(searchSettings): return commands.search != nil
        case #selector(showPane):
            item.state = commands.shown?.rawValue == item.representedObject as? String ? .on : .off
            return commands.show != nil
        default: return true
        }
    }
}

enum Preferences {
    /// Settings whose first value has changed, with what it was before, by the change that made
    /// it. Someone who had Glance already keeps what they had, chosen or not; only a new install
    /// starts with the new value.
    static let earlierDefaults: [Int: [String: Any]] = [
        1: [musicBackground: MusicBackground.replaceGlass.rawValue],
        2: [musicAccentTimeline: true, musicAppBadge: false],
    ]
    /// The last change of first values this install has been through, so each is done once.
    static let defaultsVersion = "defaultsVersion"

    /// Writes down, for someone who had Glance before, the first value of each setting that has
    /// since changed and that they never set, so a new first value doesn't change it under them.
    /// It goes by what's stored in `domain` alone, as the values registered at launch would hide
    /// which were never set. Someone had Glance before if the welcome tour was closed once, or a
    /// display's look was kept, which every launch does.
    static func keepEarlierDefaults(_ defaults: UserDefaults = .standard, domain: String? = Bundle.main.bundleIdentifier) {
        guard let domain else { return }
        let stored = defaults.persistentDomain(forName: domain) ?? [:]
        let done = stored[defaultsVersion] as? Int ?? 0
        let latest = earlierDefaults.keys.max() ?? 0
        guard done < latest else { return }
        if stored[onboardingDone] != nil || stored.keys.contains(where: { $0.hasPrefix(glassDarkness + ":") }) {
            for (version, values) in earlierDefaults where version > done {
                for (key, value) in values where stored[key] == nil { defaults.set(value, forKey: key) }
            }
        }
        defaults.set(latest, forKey: defaultsVersion)
    }

    /// What each setting is until it's changed.
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            showOnExternalDisplays: true,
            liveActivity: true,
            musicBackground: MusicBackground.none.rawValue,
            musicAnimatedArtwork: true,
            musicShowsNewApps: true,
            musicAppBadge: true,
            musicAccentTimeline: false,
            musicTrackPop: true,
            notchEnabled: true,
            swipeToOpen: true,
            swipeToSkip: true,
            lyrics: true,
            musicLayout: PlayerLayout.top.rawValue,
            musicDJButton: true,
            openTrigger: OpenTrigger.both.rawValue,
            hoverDelay: 0.2,
            clickDelay: 0.0,
            haptics: false,
            hideInFullScreen: true,
            tray: true,
            trayClipboard: true,
            trayClipboardKeep: ClipboardKeep.eightHours.rawValue,
            trayDragOut: TrayDragOut.keep.rawValue,
            trayScreenshots: true,
            activityCharging: true,
            activityLowBattery: true,
            activityDevices: true,
            activityCalls: true,
            activityAirDrop: true,
            activityClockTimers: true,
            // Off: macOS keeps its timer out of the menu bar once it's taken out, after Glance is gone.
            clockTimerHidesMenuBar: false,
            activityStopwatch: true,
            activityScreenRecording: true,
            activityVoiceMemos: true,
            hideMenuBarLiveActivities: true,
            swipeToSwitch: true,
        ])
    }

    /// The key from when this meant every display without a notch, so the choice carries over.
    static let showOnExternalDisplays = "showOnDisplaysWithoutNotch"
    /// External displays the notch is kept off, one by one, comma separated.
    static let notchHiddenDisplays = "notchHiddenDisplays"
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
    static let musicDJButton = "musicDJButton"
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

    /// Whether the notch hides in full screen on a display: its own choice, or until it makes one,
    /// the choice from when there was one for every display.
    static func hidesInFullScreen(_ display: String) -> Bool {
        let defaults = UserDefaults.standard
        return defaults.object(forKey: key(hideInFullScreen, for: display)) as? Bool ?? defaults.bool(forKey: hideInFullScreen)
    }

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
    /// The trackpad gestures: two fingers down and up to open and close the notch, sideways to
    /// change songs.
    static let swipeToOpen = "swipeToOpen"
    static let swipeToSkip = "swipeToSkip"
    static let onboardingDone = "onboardingDone"
    /// The Settings page last shown (a SettingsPane).
    static let settingsPane = "settingsPane"
    static let openTrigger = "openTrigger"
    static let hoverDelay = "hoverDelay"
    static let clickDelay = "clickDelay"
    static let haptics = "haptics"
    static let hideInFullScreen = "hideInFullScreen"
    /// The shortcuts that open the player and the tray, when they aren't the ones Glance came with:
    /// a KeyCombo, as JSON.
    static let shortcutMusic = "shortcutMusic"
    static let shortcutTray = "shortcutTray"
    /// The tray: on, keeping what's copied and screenshots, and for how long (a ClipboardKeep).
    static let tray = "tray"
    static let trayClipboard = "trayClipboard"
    static let trayClipboardKeep = "trayClipboardKeep"
    static let trayDragOut = "trayDragOut"
    static let trayScreenshots = "trayScreenshots"
    /// Apps whose copies are never kept, comma separated (see TrayApps).
    static let trayIgnoredApps = "trayIgnoredApps"
    /// What the Mac announces beside the camera (see Activities): plugged in, low on battery, a
    /// device connecting or the sound going to AirPlay; and files coming in over AirDrop.
    static let activityCharging = "activityCharging"
    static let activityLowBattery = "activityLowBattery"
    static let activityDevices = "activityDevices"
    static let activityCalls = "activityCalls"
    static let activityAirDrop = "activityAirDrop"
    /// Clock's timers show (see ClockActivity), and while one does, the menu bar's own is taken out;
    /// and Clock's stopwatch shows.
    static let activityClockTimers = "activityClockTimers"
    static let clockTimerHidesMenuBar = "clockTimerHidesMenuBar"
    /// macOS's own Live Activities turned off in Menu Bar settings (see `MenuBarLiveActivities`).
    static let hideMenuBarLiveActivities = "hideMenuBarLiveActivities"
    static let activityStopwatch = "activityStopwatch"
    /// The screen being recorded, and a voice memo being recorded, show (see `ScreenRecordingWatch`
    /// and `VoiceMemoWatch`).
    static let activityScreenRecording = "activityScreenRecording"
    static let activityVoiceMemos = "activityVoiceMemos"
    /// Three fingers sideways on the open notch, or scrolling with Shift held, switches between the
    /// player and the tray.
    static let swipeToSwitch = "swipeToSwitch"
}

/// The settings that are watched by their keys.
extension UserDefaults {
    @objc dynamic var showOnDisplaysWithoutNotch: Bool { bool(forKey: Preferences.showOnExternalDisplays) }
    @objc dynamic var notchHiddenDisplays: String? { string(forKey: Preferences.notchHiddenDisplays) }
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
        case .hover: String(localized: "Hover")
        case .click: String(localized: "Click")
        case .both: String(localized: "Hover or click")
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

    /// A display that takes a finger: a MacBook Pro's with Touch, or an iPad's over Sidecar.
    var takesTouch: Bool {
        guard #available(macOS 27, *) else { return false }
        return touchCapabilities.contains(.multiTouch)
    }
}

/// Owns one notch per display and feeds them pointer events.
@MainActor
final class NotchManager {
    private let nowPlaying: NowPlaying

    init(nowPlaying: NowPlaying) {
        self.nowPlaying = nowPlaying
    }

    /// Shown when the notch is right-clicked, or touched and held.
    var contextMenu: NSMenu?

    private var controllers: [NotchController] = []
    /// The notch a three-finger swipe is going on.
    private var swiped: NotchController?
    private var monitors: [Any] = []

    /// The displays the notches were last made for, and how each one's top is laid out.
    private var madeFor = ""
    private var fullScreenTimer: Timer?

    func start() {
        Preferences.keepEarlierDefaults()
        Preferences.registerDefaults()
        reload()
        Activities.shared.holding = { [weak self] in self?.controllers.contains(where: \.holdsAlert) == true }

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

        // Entering full screen makes a new Space; apps that fill the screen without one are caught
        // by a slow check, which costs a window list every second and a half. A Space is told at
        // once, so the notch hides and comes back with full screen, and again a moment later, once
        // the windows have settled.
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateFullScreen() }
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
            NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
                MainActor.assumeIsolated { self?.pressed(event.type == .leftMouseDown) }
            },
            NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
                MainActor.assumeIsolated { self?.pressed(event.type == .leftMouseDown) }
                return event
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
        let onExternal = UserDefaults.standard.bool(forKey: Preferences.showOnExternalDisplays)
        controllers.forEach { $0.tearDown(collapsing: switching) }
        guard UserDefaults.standard.bool(forKey: Preferences.notchEnabled) else {
            controllers = []
            return
        }
        NSScreen.screens.forEach { Preferences.seed($0.notchID) }
        madeFor = Self.displays
        let hidden = (UserDefaults.standard.string(forKey: Preferences.notchHiddenDisplays) ?? "").split(separator: ",")
        controllers = NSScreen.screens.compactMap { screen in
            NotchController(screen: screen, onExternal: onExternal && !hidden.contains(Substring(screen.notchID)), nowPlaying: nowPlaying)
        }
        // Never leave the user with no notch at all.
        if controllers.isEmpty, let main = NSScreen.main, let fallback = NotchController(screen: main, onExternal: true, nowPlaying: nowPlaying) {
            controllers = [fallback]
        }
        for controller in controllers {
            controller.contextMenu = { [weak self] in self?.contextMenu }
            controller.show(expanding: switching)
        }
        updateFullScreen()
        pointerMoved()
    }

    /// Every notch closes away, for Glance quitting; how long that takes, none if there's no notch.
    func closeAway() -> TimeInterval {
        guard !controllers.isEmpty else { return 0 }
        controllers.forEach { $0.tearDown(collapsing: true) }
        controllers = []
        return NotchController.closeAwayTime
    }

    /// Each display, where it is, and its notch's resting place and size.
    private static var displays: String {
        NSScreen.screens.map { screen in
            let resting = NotchController.resting(on: screen)
            return "\(screen.notchID) \(screen.frame) \(resting.size) \(resting.centerX)"
        }
        .joined(separator: "; ")
    }

    /// Hides each notch while a full-screen app covers its display, if the user chose that. While
    /// macOS is still sliding into or out of the full-screen Space, the change waits for the slide
    /// to end, or the notch would fold away unseen and simply vanish; `late` stops waiting.
    private func updateFullScreen(late: Bool = false) {
        let covered = Self.fullScreenDisplays()
        var sliding: [String] = []
        for controller in controllers {
            let hides = controller.hidesInFullScreen && covered.contains(controller.screenFrame)
            guard hides != controller.fullScreen else { continue }
            if !late, NotchSpace.isSwitching(controller.screenID) {
                sliding.append(controller.screenID)
                continue
            }
            controller.fullScreen = hides
        }
        guard !sliding.isEmpty, slideWait == nil else { return }
        // Checked every frame, on the run loop: a block on the main queue can be held up while the
        // slide runs. A slide takes about half a second; past a second and a half, it's let go.
        let since = Date()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let late = Date().timeIntervalSince(since) > 1.5
                guard late || !sliding.contains(where: NotchSpace.isSwitching) else { return }
                self.slideWait?.invalidate()
                self.slideWait = nil
                self.updateFullScreen(late: late)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        slideWait = timer
    }

    /// Waiting for macOS to finish sliding between Spaces (see `updateFullScreen`).
    private var slideWait: Timer?

    /// Displays showing a full-screen app: in a Space of its own, as WindowServer tells, where on a
    /// display with a camera it sits below the housing; or, for apps that fill the screen without
    /// one, with another app's window exactly the display's size. Window positions and sizes are
    /// readable without any permission.
    private static func fullScreenDisplays() -> [CGRect] {
        let spaces = NotchSpace.fullScreenDisplays()
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let me = Int(ProcessInfo.processInfo.processIdentifier)
        let appWindows = windows.compactMap { info -> CGRect? in
            guard info[kCGWindowLayer as String] as? Int == 0, info[kCGWindowOwnerPID as String] as? Int != me,
                let bounds = info[kCGWindowBounds as String]
            else { return nil }
            return CGRect(dictionaryRepresentation: bounds as! CFDictionary)
        }
        return NSScreen.screens.filter { screen in
            if spaces.contains(screen.notchID) { return true }
            // Window bounds have their origin at the top left of the main display.
            let frame = screen.frame
            return appWindows.contains(CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height))
        }
        .map(\.frame)
    }

    private func pointerMoved() {
        let location = NSEvent.mouseLocation
        // However the drag ended, it has once the button is up.
        if dragging, NSEvent.pressedMouseButtons & 1 == 0 { dragging = false }
        // A drag that's just begun: what it carries is on the drag pasteboard, newly changed.
        if !dragging, NSEvent.pressedMouseButtons & 1 != 0, Tray.isOn, !Tray.shared.draggingOut {
            let board = NSPasteboard(name: .drag)
            if board.changeCount != dragChange {
                dragChange = board.changeCount
                dragging = Tray.accepts(board)
            }
        }
        for controller in controllers {
            controller.pointerMoved(to: location)
            controller.dragMoved(to: location, carrying: dragging)
        }
    }

    /// A drag from another app carrying something the tray takes, under way.
    private var dragging = false
    private var dragChange = NSPasteboard(name: .drag).changeCount

    /// The button down: whatever drag follows is new. Up: it's over.
    private func pressed(_ down: Bool) {
        guard down else {
            guard dragging else { return }
            dragging = false
            let location = NSEvent.mouseLocation
            controllers.forEach { $0.dragMoved(to: location, carrying: false) }
            return
        }
        dragChange = NSPasteboard(name: .drag).changeCount
    }

    /// A three-finger swipe, on the open notch under the pointer where it began.
    func swipe(_ motion: NotchSwipes.Motion) {
        if motion == .began {
            let location = NSEvent.mouseLocation
            swiped = controllers.first { $0.takesSwipe(at: location) }
        }
        swiped?.swipe(motion)
        if case .ended = motion { swiped = nil }
    }

    /// A shortcut: the notch on the display under the pointer, or the first one.
    /// The notch the pointer's on, or the first: the one its menu was opened from.
    private var pointed: NotchController? {
        let location = NSEvent.mouseLocation
        return controllers.first { $0.screenFrame.contains(location) } ?? controllers.first
    }

    /// What the menu offers to put away on that notch, and putting it away.
    var putAwayTitle: String? { pointed?.putAwayTitle }
    func putAway() { pointed?.putAway() }

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

/// When the main thread last answered, asked from another thread. Time stands still while the Mac
/// sleeps, as `DispatchTime` does, so waking isn't taken for silence.
final class MainThreadWatch: @unchecked Sendable {
    static let limit: TimeInterval = 10
    private let lock = NSLock()
    private var answered = DispatchTime.now()

    func ask() {
        DispatchQueue.main.async { [self] in lock.withLock { answered = .now() } }
    }

    /// Seconds since the main thread last answered.
    var silent: TimeInterval {
        let last = lock.withLock { answered }
        return Double(DispatchTime.now().uptimeNanoseconds - last.uptimeNanoseconds) / 1e9
    }

    /// Glance is being debugged, and stopped at a breakpoint is no reason to quit.
    static var debugged: Bool {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&name, 4, &info, &size, nil, 0) == 0 else { return false }
        return info.kp_proc.p_flag & P_TRACED != 0
    }
}
