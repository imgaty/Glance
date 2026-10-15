//
//  TrayService.swift
//  Glance
//
//  Created by Gaty on 15/10/2026.
//

import AppKit

/// Add to Glance Tray, in every app's Services menu and in Finder's: what's chosen there is kept in
/// the tray, as if it were dropped on the notch (see NSServices in Info.plist).
@MainActor
final class TrayService: NSObject {
    let tray: Tray

    init(tray: Tray? = nil) {
        self.tray = tray ?? .shared
    }

    @objc func addToTray(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard Tray.isOn else {
            error.pointee = "The tray is turned off in Glance's settings." as NSString
            return
        }
        if !tray.drop(pasteboard) { error.pointee = "The tray can't keep what's chosen." as NSString }
    }
}
