//
//  TrayService.swift
//  Glance
//
//  Created by Gaty on 15/10/2026.
//

import AppKit

/// Glance Tray, in every app's Services menu and in Finder's (see NSServices in Info.plist),
/// and in the Share menu, through the GlanceShare extension: what's chosen there is kept in the
/// tray, as if it were dropped on the notch.
@MainActor
final class TrayService: NSObject {
    /// Where the Share extension, which runs apart from Glance, leaves what's shared, and what it and
    /// Glance tell each other (also in ShareViewController).
    static let sharePasteboard = NSPasteboard.Name("dev.vibe.Glance.share")
    static let shared = Notification.Name("dev.vibe.Glance.shared")
    static let taken = Notification.Name("dev.vibe.Glance.sharedTaken")

    let tray: Tray
    private let sharing: NSPasteboard
    private var watch: NSObjectProtocol?

    init(tray: Tray? = nil, sharing: NSPasteboard? = nil) {
        self.tray = tray ?? .shared
        self.sharing = sharing ?? NSPasteboard(name: Self.sharePasteboard)
    }

    @objc func addToTray(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard Tray.isOn else {
            error.pointee = "The tray is turned off in Glance's settings." as NSString
            return
        }
        if !tray.drop(pasteboard) { error.pointee = "The tray can't keep what's chosen." as NSString }
    }

    /// Whether Glance Tray is on in the Share menu. macOS lists a new app's Share extension
    /// turned off, until it's turned on in Login Items & Extensions; pluginkit marks it + once it is.
    /// Without the extension at all, as in a build run from its folder, there's nothing to turn on.
    nonisolated static func shareIsOn() async -> Bool {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
            process.arguments = ["-m", "-i", "dev.vibe.Glance.Share"]
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return true }
            let line = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            process.waitUntilExit()
            let listed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return listed.isEmpty || listed.hasPrefix("+")
        }.value
    }

    static let extensionsSettings = URL(
        string: "x-apple.systempreferences:com.apple.ExtensionsPreferences?extensionPointIdentifier=com.apple.share-services")!

    /// Listens for what's shared, and takes what was shared while Glance wasn't open, which opened it.
    func start() {
        watch = DistributedNotificationCenter.default().addObserver(forName: Self.shared, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.takeShared() }
        }
        takeShared()
    }

    /// Each thing shared, kept on its own, the first at the front; then the extension is told, so it
    /// can finish.
    func takeShared() {
        let entries = sharing.pasteboardItems ?? []
        guard !entries.isEmpty else { return }
        if Tray.isOn {
            for entry in entries.reversed() {
                let one = NSPasteboard.withUniqueName()
                defer { one.releaseGlobally() }
                let copy = NSPasteboardItem()
                for type in entry.types {
                    if let data = entry.data(forType: type) { copy.setData(data, forType: type) }
                }
                one.clearContents()
                one.writeObjects([copy])
                tray.drop(one)
            }
        } else {
            NSSound.beep()
        }
        sharing.clearContents()
        DistributedNotificationCenter.default().postNotificationName(Self.taken, object: nil, userInfo: nil, deliverImmediately: true)
    }
}
