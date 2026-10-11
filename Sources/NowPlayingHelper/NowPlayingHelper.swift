//
//  NowPlayingHelper.swift
//  Glance
//
//  Created by Gaty on 07/10/2026.
//

// Runs inside /usr/bin/perl, not the app. Since macOS 15.4, MediaRemote (the system's Now Playing
// service, behind Control Center's media controls) only answers Apple-signed processes. perl is
// one, and it can load this library. The app starts perl, reads what's playing as JSON lines from
// its output, and writes playback commands to its input.

import Foundation

private typealias InfoCallback = @convention(block) (NSDictionary?) -> Void
private typealias GetInfo = @convention(c) (DispatchQueue, @escaping InfoCallback) -> Void
private typealias PlayingCallback = @convention(block) (Bool) -> Void
private typealias GetPlaying = @convention(c) (DispatchQueue, @escaping PlayingCallback) -> Void
private typealias ClientCallback = @convention(block) (AnyObject?) -> Void
private typealias GetClient = @convention(c) (DispatchQueue, @escaping ClientCallback) -> Void
private typealias PIDCallback = @convention(block) (Int32) -> Void
private typealias GetPID = @convention(c) (DispatchQueue, @escaping PIDCallback) -> Void
private typealias ClientString = @convention(c) (AnyObject) -> NSString?
private typealias Register = @convention(c) (DispatchQueue) -> Void
private typealias SendCommand = @convention(c) (Int32, NSDictionary?) -> Bool
private typealias SetElapsed = @convention(c) (Double) -> Void

private let mediaRemote = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY)

private func load<T>(_ name: String, _: T.Type) -> T? {
    guard let mediaRemote, let symbol = dlsym(mediaRemote, name) else { return nil }
    return unsafeBitCast(symbol, to: T.self)
}

/// perl installs this as a subroutine and calls it. It never returns: it reports every change
/// until the app closes its input.
@_cdecl("notch_now_playing_run")
public func notchNowPlayingRun(_ perl: UnsafeMutableRawPointer?, _ cv: UnsafeMutableRawPointer?) {
    guard let register = load("MRMediaRemoteRegisterForNowPlayingNotifications", Register.self),
        let getInfo = load("MRMediaRemoteGetNowPlayingInfo", GetInfo.self),
        let getPlaying = load("MRMediaRemoteGetNowPlayingApplicationIsPlaying", GetPlaying.self),
        let send = load("MRMediaRemoteSendCommand", SendCommand.self),
        let setElapsed = load("MRMediaRemoteSetElapsedTime", SetElapsed.self)
    else {
        FileHandle.standardError.write(Data("MediaRemote is unavailable\n".utf8))
        exit(1)
    }
    let getClient = load("MRMediaRemoteGetNowPlayingClient", GetClient.self)
    let bundleOf = load("MRNowPlayingClientGetBundleIdentifier", ClientString.self)
    // Browsers play through a helper (com.apple.WebKit.GPU); the parent is the real app.
    let parentOf = load("MRNowPlayingClientGetParentAppBundleIdentifier", ClientString.self)
    // The process actually making the sound, which the app taps to move the waveform.
    let getPID = load("MRMediaRemoteGetNowPlayingApplicationPID", GetPID.self)

    var lastArtwork: Data?
    var lastTrack = ""
    var pending = false

    func emit(_ info: NSDictionary?, playing: Bool, app: String?, pid: Int32) {
        let info = info as? [String: Any] ?? [:]
        func number(_ key: String) -> Double? { (info["kMRMediaRemoteNowPlayingInfo" + key] as? NSNumber)?.doubleValue }
        var report: [String: Any] = ["playing": playing]
        report["title"] = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String
        report["artist"] = info["kMRMediaRemoteNowPlayingInfoArtist"] as? String
        report["album"] = info["kMRMediaRemoteNowPlayingInfoAlbum"] as? String
        report["explicit"] = number("IsExplicitTrack").map { $0 != 0 }
        report["composer"] = info["kMRMediaRemoteNowPlayingInfoComposer"] as? String
        // Music, audio, video, podcast: whether it's a song with lyrics at all.
        report["mediaType"] = [info["kMRMediaRemoteNowPlayingInfoMediaType"], info["kMRMediaRemoteNowPlayingInfoStrictMediaType"]]
            .compactMap { $0 as? String }.joined(separator: " ")
        // Music says which album in its catalog is playing, which finds the album's moving cover.
        let albumID = info["kMRMediaRemoteNowPlayingInfoAlbumiTunesStoreAdamIdentifier"]
        report["albumID"] = (albumID as? NSNumber)?.intValue ?? (albumID as? String).flatMap { Int($0) }
        report["duration"] = number("Duration")
        report["elapsed"] = number("ElapsedTime")
        report["rate"] = number("PlaybackRate")
        report["timestamp"] = (info["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date)?.timeIntervalSince1970
        report["app"] = app
        if pid > 0 { report["pid"] = pid }
        // Artwork is large, so it's only sent when it changes; "" clears it. Around play and pause
        // some apps briefly report a track without its artwork; keep it until the track changes.
        let track = [report["title"], report["artist"]].map { $0 as? String ?? "" }.joined(separator: "\u{1F}")
        let artwork = info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data
        if artwork != lastArtwork, artwork != nil || track != lastTrack {
            lastArtwork = artwork
            report["artwork"] = artwork?.base64EncodedString() ?? ""
        }
        lastTrack = track
        guard let line = try? JSONSerialization.data(withJSONObject: report) else { return }
        FileHandle.standardOutput.write(line + Data("\n".utf8))
    }

    func report() {
        // A track change sends several notifications at once; answer them together.
        guard !pending else { return }
        pending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            pending = false
            getInfo(.main) { info in
                getPlaying(.main) { playing in
                    let finish = { (app: String?) in
                        guard let getPID else { return emit(info, playing: playing, app: app, pid: 0) }
                        getPID(.main) { pid in emit(info, playing: playing, app: app, pid: pid) }
                    }
                    guard let getClient else { return finish(nil) }
                    getClient(.main) { client in
                        finish(client.flatMap { parentOf?($0) ?? bundleOf?($0) } as String?)
                    }
                }
            }
        }
    }

    register(.main)
    for name in [
        "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
        "kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
        "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
    ] {
        NotificationCenter.default.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { _ in report() }
    }
    report()

    // One command per line. The app closing the pipe means it quit, so stop too.
    Thread.detachNewThread {
        while let line = readLine() {
            DispatchQueue.main.async {
                let words = line.split(separator: " ")
                switch words.first {
                case "toggle": _ = send(2, nil)
                case "next": _ = send(4, nil)
                case "previous": _ = send(5, nil)
                // Repeat (off 1, one 2, all 3) and shuffle (off 1, songs 3), the way the system's
                // own remote sets them.
                case "repeat", "shuffle":
                    if words.count > 1, let mode = Int(words[1]) {
                        let repeating = words[0] == "repeat"
                        _ = send(repeating ? 25 : 26, [(repeating ? "kMRMediaRemoteOptionRepeatMode" : "kMRMediaRemoteOptionShuffleMode"): NSNumber(value: mode)])
                    }
                case "seek":
                    if words.count > 1, let seconds = Double(words[1]) {
                        setElapsed(seconds)
                        report()
                    }
                default: break
                }
            }
        }
        exit(0)
    }
    CFRunLoopRun()
}
