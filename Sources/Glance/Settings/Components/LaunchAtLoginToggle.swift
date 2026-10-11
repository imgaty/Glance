//
//  LaunchAtLoginToggle.swift
//  Glance
//
//  Created by Gaty on 07/10/2026.
//

import AppKit
import Combine
import ServiceManagement
import SwiftUI

/// Starts Glance when you log in, through macOS's own login items, so it also shows (and can be
/// turned off) in System Settings ▸ General ▸ Login Items & Extensions.
struct LaunchAtLoginToggle: View {
    @ObservedObject private var item = LoginItem.shared

    var body: some View {
        Toggle(isOn: Binding(get: { item.status == .enabled }, set: item.set)) {
            Text("Open at login")
            if item.status == .requiresApproval {
                Text("Requires approval in Login Items & Extensions settings.")
            }
        }
        // Changed in System Settings meanwhile: show what's really set.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in item.refresh() }
    }
}

/// Whether Glance is a login item. Asking macOS takes a moment, so it's asked in the background, once
/// when Settings first needs it and again whenever Glance comes forward, never while a page is drawn.
@MainActor
final class LoginItem: ObservableObject {
    static let shared = LoginItem()
    @Published private(set) var status: SMAppService.Status = .notRegistered

    private init() { refresh() }

    func refresh() {
        Task.detached {
            let status = SMAppService.mainApp.status
            await MainActor.run { LoginItem.shared.status = status }
        }
    }

    func set(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // macOS said no; the toggle shows what it kept.
        }
        status = SMAppService.mainApp.status
        if status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
    }
}
