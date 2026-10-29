//
//  OnboardingWindowController.swift
//  Glance
//
//  Created by Gaty on 07/10/2026.
//

import AppKit
import SwiftUI

/// Where the welcome tour starts: at its beginning, or, from Settings, at the permissions.
enum OnboardingStart {
    case welcome, permissions
}

/// The welcome tour's window: Glance's features one at a time, then the permissions. Shown on first
/// launch, and from Settings.
@MainActor
final class OnboardingWindowController {
    private var window: NSWindow?
    private let permissions = Permissions()

    func show(startingAt start: OnboardingStart = .welcome) {
        let view = OnboardingView(permissions: permissions, start: start) { [weak self] in self?.window?.performClose(nil) }
        // Always the same size, whichever page shows.
        let controller = NSHostingController(rootView: view)
        controller.sizingOptions = []
        if let window {
            // Asked again, perhaps for another start: the tour begins anew.
            window.contentViewController = controller
            window.setContentSize(OnboardingView.size)
        } else {
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: OnboardingView.size), styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered, defer: false)
            window.title = "Welcome to Glance"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false
            // In front of every other window until it's closed or finished.
            window.level = .floating
            // Only a way to close it, as Apple's own welcome windows have.
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.contentViewController = controller
            window.setContentSize(OnboardingView.size)
            window.center()
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
                MainActor.assumeIsolated {
                    // Seen and closed: later launches skip it; Settings can still show it.
                    UserDefaults.standard.set(true, forKey: Preferences.onboardingDone)
                    AppWindows.didClose(window)
                    // A closed window is only hidden: its pictures and song would play on unseen.
                    // Once it's gone, they go too; showing it again builds them anew.
                    DispatchQueue.main.async { if !window.isVisible { window.contentViewController = nil } }
                }
            }
            // Coming back from System Settings, show what changed there.
            NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.permissions.refresh() }
            }
            // Except under System Settings, opened from the permissions, which it would cover.
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
            ) { [weak window] note in
                let app = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
                MainActor.assumeIsolated { window?.level = app == "com.apple.systempreferences" ? .normal : .floating }
            }
            self.window = window
        }
        permissions.refresh()
        if let window { AppWindows.bringForward(window) }
    }
}

/// Settings and onboarding bring in the Dock icon and menu bar, which leave with the last of them.
@MainActor
enum AppWindows {
    /// Shows the window in front of every app's windows, with Glance the app in use. Glance is
    /// rarely the active app (it runs in the background), and asked politely, macOS can take a
    /// second or more to let it come forward, the window drawn behind meanwhile, gray: asked for by
    /// the user, it comes forward at once.
    static func bringForward(_ window: NSWindow) {
        NSApp.setActivationPolicy(.regular)
        window.orderFrontRegardless()
        window.makeKey()
        comeForward()
        // Just after turning into an app with a Dock icon, macOS can let the first request go by.
        DispatchQueue.main.async {
            guard window.isVisible else { return }
            if !NSApp.isActive { comeForward() }
            window.makeKeyAndOrderFront(nil)
        }
    }

    /// Glance made the app in use, whatever app is: only ever for what the user asked for.
    static func comeForward() {
        NSApp.activate(ignoringOtherApps: true)
    }

    static func didClose(_ window: NSWindow) {
        DispatchQueue.main.async {
            let othersOpen = NSApp.windows.contains { $0 !== window && $0.isVisible && $0.styleMask.contains(.titled) }
            if !othersOpen { NSApp.setActivationPolicy(.accessory) }
        }
    }
}
