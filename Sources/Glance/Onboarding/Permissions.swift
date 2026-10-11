//
//  Permissions.swift
//  Glance
//
//  Created by Gaty on 07/10/2026.
//

import AppKit
import SwiftUI

/// The permissions Glance can ask for, read and requested without side effects.
@MainActor
final class Permissions: ObservableObject {
    enum State {
        case granted, denied, notDetermined, notInstalled
    }

    @Published private(set) var audio = State.notDetermined
    @Published private(set) var musicControl = State.notDetermined
    @Published private(set) var spotifyControl = State.notDetermined
    @Published private(set) var accessibility = State.notDetermined

    /// Spotify's one row: control through AppleScript, and Accessibility for Repeat One.
    var spotify: State {
        if spotifyControl == .notInstalled { return .notInstalled }
        if spotifyControl == .granted, accessibility == .granted { return .granted }
        if spotifyControl == .denied || accessibility == .denied { return .denied }
        return .notDetermined
    }

    /// Audio capture (Screen & System Audio Recording), which moves the waveform and turns apps
    /// down. macOS only reports it through the private TCC framework, which keeps its first answer
    /// for as long as the app runs, so a change after that is read by `recheck()`.
    private(set) static var audioCapture = state(preflight(audioService))

    /// Passed to a copy of Glance started only to read the permissions afresh; see `recheck()`.
    nonisolated static let statusArgument = "--privacy-status"

    /// What TCC answers that copy, for audio capture and Accessibility.
    nonisolated static func printStatus() {
        print(preflight(audioService), preflight(accessibilityService))
    }

    /// Reads audio capture and Accessibility again. TCC's answers in this app never change, so it
    /// asks a fresh copy of Glance, which macOS answers as Glance; tests, which can't start one, get
    /// this app's answers. Starts the waveform once audio capture is newly allowed.
    @discardableResult
    static func recheck() async -> (audio: State, accessibility: State) {
        let codes = await freshCodes() ?? (preflight(audioService), preflight(accessibilityService))
        let audio = state(codes.audio)
        if audio != audioCapture {
            audioCapture = audio
            if audio == .granted { AudioLevels.shared.permissionChanged() }
        }
        // Allowed is read live; turned off in Settings only through TCC.
        let accessibility: State = SpotifyMenu.allowed ? .granted : codes.accessibility == 1 ? .denied : .notDetermined
        return (audio, accessibility)
    }

    func refresh() {
        Task {
            let fresh = await Self.recheck()
            audio = fresh.audio
            accessibility = fresh.accessibility
        }
        for app in [PlayerScripting.music, PlayerScripting.spotify] {
            DispatchQueue.global().async {
                let state = Self.automation(app, ask: false)
                DispatchQueue.main.async { MainActor.assumeIsolated { self.set(state, for: app) } }
            }
        }
    }

    /// macOS asks the first time an app starts listening through an audio tap, so this starts one
    /// briefly, then watches for the answer.
    func requestAudio() {
        AudioLevels.shared.requestPermission { [weak self] in self?.refresh() }
    }

    /// Spotify's row asks for both: control first, then Accessibility, for Repeat One.
    func requestSpotify() {
        guard spotifyControl != .granted else { return askForAccessibility() }
        requestControl(of: PlayerScripting.spotify) { [weak self] in
            if self?.spotifyControl == .granted { self?.askForAccessibility() }
        }
    }

    /// macOS shows its prompt only once; after that, Settings is the way.
    private func askForAccessibility() {
        guard accessibility == .notDetermined else { return }
        SpotifyMenu.askForPermission()
    }

    /// Asks to control an app. macOS can only ask while the app runs, so it opens it in the
    /// background first.
    func requestControl(of app: String, then answered: (() -> Void)? = nil) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.hides = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            let state = Self.automation(app, ask: true)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.set(state, for: app)
                    answered?()
                }
            }
        }
    }

    func openSettings(for state: KeyPath<Permissions, State>) {
        let pane = state == \.audio ? "Privacy_ScreenCapture" : state == \.accessibility ? "Privacy_Accessibility" : "Privacy_Automation"
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
    }

    private func set(_ state: State, for app: String) {
        if app == PlayerScripting.music { musicControl = state } else { spotifyControl = state }
    }

    /// Blocks while macOS shows its prompt, so it runs off the main thread.
    nonisolated private static func automation(_ app: String, ask: Bool) -> State {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: app) != nil else { return .notInstalled }
        var target = AEAddressDesc()
        let bytes = Array(app.utf8)
        guard AECreateDesc(typeApplicationBundleID, bytes, bytes.count, &target) == noErr else { return .notDetermined }
        defer { AEDisposeDesc(&target) }
        switch AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, ask) {
        case noErr: return .granted
        case OSStatus(errAEEventNotPermitted): return .denied
        default: return .notDetermined  // not asked yet, or the app isn't running to ask
        }
    }

    nonisolated private static let audioService = "kTCCServiceAudioCapture"
    nonisolated private static let accessibilityService = "kTCCServiceAccessibility"

    private static func state(_ code: Int32) -> State {
        switch code {
        case 0: .granted
        case 1: .denied
        default: .notDetermined
        }
    }

    /// 0 allowed, 1 denied, 2 not asked yet.
    nonisolated private static func preflight(_ service: String) -> Int32 {
        typealias Preflight = @convention(c) (CFString, CFDictionary?) -> Int32
        guard let framework = dlopen("/System/Library/PrivateFrameworks/TCC.framework/TCC", RTLD_LAZY),
            let symbol = dlsym(framework, "TCCAccessPreflight")
        else { return 2 }
        return unsafeBitCast(symbol, to: Preflight.self)(service as CFString, nil)
    }

    /// The codes a fresh copy of Glance prints; nil when this isn't Glance.app, as in tests.
    nonisolated private static func freshCodes() async -> (audio: Int32, accessibility: Int32)? {
        guard Bundle.main.bundleIdentifier == "dev.vibe.Glance", let executable = Bundle.main.executableURL else { return nil }
        let process = Process()
        process.executableURL = executable
        process.arguments = [statusArgument]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        return await withCheckedContinuation { answered in
            process.terminationHandler = { _ in
                let codes = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                    .split(whereSeparator: \.isWhitespace).compactMap { Int32($0) }
                answered.resume(returning: codes.count == 2 ? (codes[0], codes[1]) : nil)
            }
            do { try process.run() } catch { answered.resume(returning: nil) }
        }
    }
}
