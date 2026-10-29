//
//  NowPlaying.swift
//  Glance
//
//  Created by Gaty on 07/10/2026.
//

import AppKit
import CoreImage
import SwiftUI

/// Whatever the system is playing, from any app, read through NowPlayingHelper running inside perl.
@MainActor
final class NowPlaying: ObservableObject {
    @Published private(set) var title = ""
    @Published private(set) var artist = ""
    @Published private(set) var album = ""
    /// The album's id in Apple's catalog, when the playing app knows it (Music does).
    @Published private(set) var albumID: Int?
    /// The song is marked explicit, which Music reports.
    @Published private(set) var explicit = false
    /// Who wrote the song, which Music reports.
    @Published private(set) var composer = ""
    /// Something is loaded and it's a song, not a video, a podcast or an audiobook, so it can have
    /// lyrics.
    @Published private(set) var isSong = false
    @Published private(set) var duration: Double = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var artwork: NSImage?
    /// The artwork tiny, blurred and vivid, for the backdrop and the glow. Scaled up it looks like
    /// a huge blur, for almost nothing.
    @Published private(set) var wash: NSImage?
    /// The gradient the waveform shows, made from the artwork's colors (see `WaveformGradient`).
    @Published private(set) var waveformGradient: [Color]?
    @Published private(set) var appIcon: NSImage?
    /// The artwork's colors mixed into one, for the glow and the progress bar.
    @Published private(set) var accent = Color.white
    /// Shuffle, repeat and favorite, where the playing app lets other apps change them.
    @Published private(set) var options = PlaybackOptions()
    /// The playing app, when it's one the user chose to show.
    @Published private(set) var appBundleID: String?
    /// The latest report and artwork, kept so they can be shown again when the chosen sources change.
    private var latest: [String: Any] = [:]
    private var latestArtwork: String?
    private var shownArtwork: String?
    private var shownSources = ""
    /// Music or Spotify, read directly while the system's Now Playing belongs to an app that's off.
    private var directApp: String?
    private var directPoll: Task<Void, Never>?
    private var directArtwork: (track: String, base64: String?)?
    /// The song whose artwork Spotify was last asked for.
    private var spotifyArtworkAsked: String?
    /// Songs Apple's catalog was asked about, and what it said.
    private var explicitAsked: Set<String> = []
    private var catalogExplicit: [String: Bool] = [:]
    private var lastShownApp: String?
    /// The read-back that follows a change to shuffle, repeat or favorite.
    private var settle: Task<Void, Never>?
    private var requestedRepeat: RepeatMode?

    // The position as last reported, which the clock advances while playing.
    private var elapsed: Double = 0
    private var reportedAt = Date()
    private var rate: Double = 1
    /// After a play/pause click, the state it set, held until the helper agrees or briefly
    /// disagrees; reports already on their way would otherwise flip it back and forth.
    private var heldPlaying: (value: Bool, until: Date)?

    /// Plays a made-up song, for the welcome tour's pictures, rather than what the Mac plays.
    private(set) var isDemo = false
    /// Where its lyrics come from: LRCLIB, or for the made-up song, the song itself.
    private(set) var lyricsStore = LyricsStore.shared
    private var demoLoop: Task<Void, Never>?
    private var demoLookup: Task<Void, Never>?

    private var helper: Process?
    private var commands: FileHandle?
    private var buffer = Data()

    var hasMedia: Bool { !title.isEmpty }

    /// The song, as the lookups made for it are kept.
    private var track: String { title + "\u{1F}" + artist }

    func position(at date: Date) -> Double {
        let position = isPlaying ? elapsed + date.timeIntervalSince(reportedAt) * rate : elapsed
        return duration > 0 ? min(max(position, 0), duration) : max(position, 0)
    }

    func togglePlayPause() {
        command("toggle", script: "playpause")
        // Answer the click at once; the helper's report confirms it a moment later.
        elapsed = position(at: .now)
        reportedAt = .now
        isPlaying.toggle()
        heldPlaying = (isPlaying, .now + 1.5)
    }

    func next() { command("next", script: "next track") }
    func previous() { command("previous", script: "previous track") }

    /// To the player shown: through the system's remote, or straight to Music or Spotify while
    /// they're followed directly (the system's remote would reach the app it reports instead).
    private func command(_ remote: String, script: String) {
        guard !isDemo else { return }
        guard let app = directApp else { return send(remote) }
        Task { _ = await PlayerScripting.run(PlayerScripting.tell(app, script)) }
    }

    // MARK: Shuffle, repeat and favorite

    /// Reads them from the app again. The player asks whenever it comes into sight.
    func refreshOptions() {
        guard !isDemo else { return }
        guard let app = appBundleID, let script = PlayerScripting.readScript(for: app) else {
            options = PlaybackOptions()
            return
        }
        Task {
            let reply = await PlayerScripting.run(script)
            guard app == appBundleID else { return }
            var read = reply.map { PlayerScripting.options(from: $0, app: app) } ?? PlaybackOptions()
            // Spotify's scripting only says whether repeat is on. If it's on and the last click
            // asked for one song, that's what it is.
            if app == PlayerScripting.spotify, read.repeatMode == .all, requestedRepeat == .one { read.repeatMode = .one }
            options = read
        }
    }

    /// Set both ways: the app's scripting, and the system's remote command, which is what changes
    /// the queue that's actually playing.
    func toggleShuffle() {
        guard let shuffle = options.shuffle, let app = appBundleID else { return }
        options.shuffle = !shuffle
        readBack(after: PlayerScripting.setShuffle(!shuffle, app: app))
        send("shuffle \(shuffle ? 1 : 3)")
    }

    func cycleRepeat() {
        guard let mode = options.repeatMode, let app = appBundleID else { return }
        let next = mode.next
        // Spotify's scripting only turns repeat on and off. From repeating all, one more press of
        // its own Repeat command (Playback menu) repeats the song, as its button does.
        if app == PlayerScripting.spotify, next == .one {
            guard SpotifyMenu.pressRepeat() else {
                SpotifyMenu.askForPermission()
                return
            }
            options.repeatMode = next
            requestedRepeat = next
            readBack()
            return
        }
        options.repeatMode = next
        requestedRepeat = next
        readBack(after: PlayerScripting.setRepeat(next, app: app))
        send("repeat \(next == .off ? 1 : next == .one ? 2 : 3)")
    }

    func toggleFavorite() {
        guard let favorite = options.favorite, let app = appBundleID else { return }
        options.favorite = !favorite
        readBack(after: PlayerScripting.setFavorite(!favorite, app: app))
    }

    /// Changes a setting, then reads it back so the buttons show what the app really did. Spotify
    /// reports the old value for a moment after a change, so the read waits for it to settle, and
    /// quick clicks (off, all, one) read back once, after the last of them.
    private func readBack(after script: String? = nil) {
        settle?.cancel()
        settle = Task {
            if let script { _ = await PlayerScripting.run(script) }
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            refreshOptions()
        }
    }

    /// Spotify tells Now Playing where it is only now and then, and not exactly, so the clock drifts
    /// from the song; the players' own scripting knows exactly. The player reads it while it shows.
    func syncPosition() async {
        guard !isDemo else { return }
        guard let app = appBundleID, let script = PlayerScripting.positionScript(for: app) else { return }
        let track = title, asked = Date.now
        guard let reply = await PlayerScripting.run(script),
            let milliseconds = Double(reply.trimmingCharacters(in: .whitespaces)),
            app == appBundleID, track == title
        else { return }
        // Halfway through the round trip is about when the player answered.
        let answered = Date.now
        elapsed = milliseconds / 1000 + (isPlaying ? answered.timeIntervalSince(asked) / 2 : 0)
        reportedAt = answered
    }

    func seek(to seconds: Double) {
        command("seek \(seconds)", script: "set player position to \(seconds)")
        elapsed = seconds
        reportedAt = .now
    }

    func openApp() {
        guard let appBundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appBundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: The welcome tour's song

    /// A song for the welcome tour's pictures, always playing, round and round its first verse: the
    /// tour's song, whose cover and words come from Apple Music and LRCLIB as any song's do. If
    /// either can't be had, offline say, it becomes the made-up song.
    static func demo(_ song: FeaturedSong) -> NowPlaying {
        let player = NowPlaying()
        player.isDemo = true
        player.isSong = true
        player.isPlaying = true
        player.options = PlaybackOptions(shuffle: false, repeatMode: .off, favorite: false)
        player.appIcon = NSWorkspace.shared.icon(forApp: PlayerScripting.music)
        player.title = song.title
        player.artist = song.artist
        player.album = song.album
        player.duration = song.length
        player.lyricsStore = LyricsStore()
        player.loop(verse(from: song.firstLine))
        player.demoLookup = Task { [weak player] in
            guard let found = await song.lookUp() else {
                player?.playMadeUp()
                return
            }
            guard let player else { return }
            player.duration = found.duration
            // The cover fades in, and the colors with it, rather than popping in.
            withAnimation(.easeInOut(duration: 0.5)) { player.show(artwork: found.artwork, encoded: nil) }
            guard let lyrics = await player.demoLyrics() else { return player.playMadeUp() }
            // Round the first verse, if the words put it elsewhere than expected.
            if let first = lyrics.firstLineStart, abs(first - song.firstLine) > 1 { player.loop(verse(from: first)) }
        }
        return player
    }

    /// From just before the first line, for most of a verse.
    private static func verse(from firstLine: Double) -> ClosedRange<Double> {
        max(firstLine - 2, 0)...(firstLine + 38)
    }

    /// The tour's song's timed words from LRCLIB, asked for again a couple of times if they don't
    /// come, as when LRCLIB is too busy to answer, before giving up on them.
    private func demoLyrics() async -> TimedLyrics? {
        for attempt in 0..<3 {
            if attempt > 0 { try? await Task.sleep(for: .seconds(2)) }
            guard !Task.isCancelled else { return nil }
            lyricsStore.load(title: title, artist: artist, album: album, duration: duration, composer: "", app: nil)
            answer: for await content in lyricsStore.$content.values {
                switch content {
                case .none, .loading: continue
                case .timed(let lyrics): return lyrics
                case .unavailable: break answer
                // Words without timing, or none to sing, can't play along.
                case .plain, .instrumental: return nil
                }
            }
        }
        return nil
    }

    /// The song made up for the tour, drawn and written here, for when the real one can't be fetched.
    private func playMadeUp(_ song: DemoSong = DemoSong()) {
        title = song.title
        artist = song.artist
        album = song.album
        duration = song.duration
        show(artwork: song.artwork, encoded: nil)
        lyricsStore = LyricsStore(demo: song.lyrics, credits: LyricsStore.Credits(writers: song.artist))
        loop(song.loop)
    }

    /// Plays a stretch of the song, again and again.
    private func loop(_ stretch: ClosedRange<Double>) {
        demoLoop?.cancel()
        demoLoop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                elapsed = stretch.lowerBound
                reportedAt = .now
                try? await Task.sleep(for: .seconds(stretch.upperBound - stretch.lowerBound))
            }
        }
    }

    // MARK: Helper

    func start() {
        // Choosing which apps to show takes effect at once.
        if shownSources.isEmpty {
            shownSources = MusicApps.signature
            NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, MusicApps.signature != self.shownSources else { return }
                    self.shownSources = MusicApps.signature
                    withAnimation(.easeInOut(duration: 0.4)) { self.apply(self.latest) }
                }
            }
        }
        guard helper == nil, let library = Self.helperLibrary else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = ["-e", Self.loader, library.path]
        let output = Pipe(), input = Pipe()
        process.standardOutput = output
        process.standardInput = input
        process.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil }
            // The main queue keeps chunks in order, so lines arrive whole.
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.receive(data) } }
        }
        process.terminationHandler = { [weak self] _ in
            // If the helper ever dies, bring it back.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                MainActor.assumeIsolated {
                    self?.helper = nil
                    // Whatever half a line the old one left would spoil the new one's first.
                    self?.buffer.removeAll()
                    self?.start()
                }
            }
        }
        guard (try? process.run()) != nil else { return }
        helper = process
        commands = input.fileHandleForWriting
    }

    private func send(_ command: String) {
        try? commands?.write(contentsOf: Data((command + "\n").utf8))
    }

    private func receive(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            if var report = try? JSONSerialization.jsonObject(with: line) as? [String: Any] {
                report["app"] = Self.app(of: report)
                if let artwork = report["artwork"] as? String { latestArtwork = artwork }
                latest = report
                apply(report)
            }
        }
    }

    /// The app a report is about. macOS names a browser's video by the helper playing it (WebKit's
    /// GPU process) when it can't tell whose it is; the app answerable for that process is the
    /// browser.
    private static func app(of report: [String: Any]) -> String? {
        guard let app = report["app"] as? String, MusicApps.isHelper(app) else { return report["app"] as? String }
        guard let pid = (report["pid"] as? NSNumber)?.int32Value, pid > 0,
            let owner = NSRunningApplication(processIdentifier: AudioProperty.responsible(for: pid))?.bundleIdentifier
        else { return app }
        return owner
    }

    private func apply(_ report: [String: Any]) {
        // Every app that plays something is listed in Settings, to turn on or off.
        if let app = report["app"] as? String, report["direct"] == nil { MusicApps.remember(app) }
        // The system's Now Playing belongs to an app the user chose not to show: Music and Spotify,
        // if chosen, are asked directly instead.
        guard MusicApps.shows(report["app"] as? String) else { return followDirectly() }
        if report["direct"] == nil { stopFollowingDirectly() }
        lastShownApp = report["app"] as? String
        title = report["title"] as? String ?? ""
        artist = report["artist"] as? String ?? ""
        album = report["album"] as? String ?? ""
        albumID = (report["albumID"] as? NSNumber)?.intValue
        // Spotify doesn't say whether a song is explicit; Apple's catalog does.
        explicit = report["explicit"] as? Bool ?? catalogExplicit[track] ?? false
        composer = report["composer"] as? String ?? ""
        duration = report["duration"] as? Double ?? 0
        let playing = report["playing"] as? Bool ?? false
        // A report sent before the click arrived would undo it; ignore it while the hold lasts.
        let stale = heldPlaying.map { $0.value != playing && Date.now < $0.until } ?? false
        if !stale {
            isPlaying = playing
            heldPlaying = nil
        }
        elapsed = report["elapsed"] as? Double ?? 0
        rate = (report["rate"] as? Double).flatMap { $0 > 0 ? $0 : nil } ?? 1
        reportedAt = (report["timestamp"] as? Double).map(Date.init(timeIntervalSince1970:)) ?? .now
        if let encoded = report["artwork"] as? String ?? latestArtwork, encoded != shownArtwork {
            show(artwork: Data(base64Encoded: encoded).flatMap(NSImage.init(data:)), encoded: encoded)
        }
        // A song, as opposed to a video, a podcast or an audiobook. Music players say what they
        // play; browsers say nothing, so there it takes an album and square artwork, as music on
        // the web has and videos don't. Past twenty minutes it's a mix, a talk or a show.
        let kind = (report["mediaType"] as? String ?? "").lowercased()
        let other = ["video", "podcast", "book"].contains { kind.contains($0) }
        let squareArtwork = artwork.map { abs($0.size.width / max($0.size.height, 1) - 1) < 0.25 } ?? true
        let looksLikeMusic = !kind.isEmpty || (!album.isEmpty && squareArtwork)
        // And it takes an artist: without one, its lyrics can't be told from another song's.
        isSong = !title.isEmpty && !artist.isEmpty && !other && looksLikeMusic && duration <= 20 * 60
        let app = report["app"] as? String
        if app != appBundleID {
            appBundleID = app
            appIcon = app.flatMap(NSWorkspace.shared.icon(forApp:))
        }
        // The waveforms listen to the process making the sound while it plays, and the volume
        // slider turns it up and down.
        let pid = (report["pid"] as? NSNumber)?.int32Value ?? 0
        AudioLevels.shared.follow(pid: pid, playing: isPlaying)
        AppVolume.shared.follow(app: app, pid: pid)
        if artwork == nil, app == PlayerScripting.spotify, hasMedia { askSpotifyForArtwork() }
        if report["explicit"] == nil, isSong { lookUpExplicit() }
    }

    /// Asked once for each song, for players that don't say: Spotify, of Spotify's own page for the
    /// song; others, of Apple's catalog.
    private func lookUpExplicit() {
        let track = track
        guard !explicitAsked.contains(track) else { return }
        explicitAsked.insert(track)
        let (title, artist, album, app) = (title, artist, album, appBundleID)
        Task {
            let marked =
                app == PlayerScripting.spotify
                ? await PlayerScripting.spotifyExplicit()
                : await MotionArtworkStore.isExplicit(title: title, artist: artist, album: album)
            guard let marked else { return }
            catalogExplicit[track] = marked
            if self.track == track { explicit = marked }
        }
    }

    /// Spotify doesn't always give the system's Now Playing a picture (its DJ doesn't); its own
    /// scripting says where the picture is, so it's fetched from there, once for each song.
    private func askSpotifyForArtwork() {
        let track = track
        guard spotifyArtworkAsked != track else { return }
        spotifyArtworkAsked = track
        Task {
            let script = #"tell application "Spotify" to return artwork url of current track"#
            guard let reply = await PlayerScripting.run(script),
                let data = await PlayerScripting.artwork(of: PlayerScripting.spotify, url: reply.trimmingCharacters(in: .whitespacesAndNewlines)),
                let image = NSImage(data: data),
                self.track == track, artwork == nil
            else { return }
            show(artwork: image, encoded: data.base64EncodedString())
        }
    }

    /// The artwork, and the colors taken from it.
    private func show(artwork image: NSImage?, encoded: String?) {
        shownArtwork = encoded
        artwork = image
        accent = image.flatMap(Self.accent(of:)) ?? .white
        wash = image.flatMap(Self.wash(of:))
        waveformGradient = image.flatMap(WaveformGradient.colors(of:))
    }

    // MARK: Following Music and Spotify directly

    /// Reads Music and Spotify, whichever the user chose and is open, once a second while the
    /// system's Now Playing belongs to another app. One that's playing wins; otherwise the one
    /// last shown, paused. With neither, nothing plays.
    private func followDirectly() {
        guard directPoll == nil else { return }
        directPoll = Task { [weak self] in
            while !Task.isCancelled {
                await self?.readDirectly()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func stopFollowingDirectly() {
        directPoll?.cancel()
        directPoll = nil
        directApp = nil
    }

    private func readDirectly() async {
        let candidates = [PlayerScripting.music, PlayerScripting.spotify].filter {
            // Asking an app that isn't open would open it.
            MusicApps.shows($0) && !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty
        }
        var chosen: (app: String, parts: [String])?
        for app in candidates {
            guard let reply = await PlayerScripting.run(PlayerScripting.statusScript(for: app)) else { continue }
            let parts = reply.components(separatedBy: PlayerScripting.separator)
            guard parts.count >= 6 else { continue }
            if parts[0] == "playing" {
                chosen = (app, parts)
                break
            }
            if chosen == nil || app == lastShownApp { chosen = (app, parts) }
        }
        guard directPoll != nil, !Task.isCancelled else { return }
        guard let (app, parts) = chosen else {
            directApp = nil
            return showNothing()
        }
        directApp = app
        let track = parts[1] + "\u{1F}" + parts[2]
        if directArtwork?.track != track {
            directArtwork = (track, nil)
            let artwork = await PlayerScripting.artwork(of: app, url: parts.count > 6 ? parts[6] : nil)
            guard directApp == app else { return }
            directArtwork = (track, artwork?.base64EncodedString() ?? "")
        }
        var report: [String: Any] = [
            "direct": true, "app": app, "playing": parts[0] == "playing",
            "title": parts[1], "artist": parts[2], "album": parts[3],
            "duration": (Double(parts[4]) ?? 0) / 1000, "elapsed": (Double(parts[5]) ?? 0) / 1000,
            "timestamp": Date.now.timeIntervalSince1970, "mediaType": "music",
            "artwork": directArtwork?.base64 ?? "",
        ]
        if let pid = NSRunningApplication.runningApplications(withBundleIdentifier: app).first?.processIdentifier {
            report["pid"] = NSNumber(value: pid)
        }
        apply(report)
    }

    /// What's playing comes from an app the user chose not to show: the player rests, as if nothing played.
    private func showNothing() {
        title = ""
        artist = ""
        album = ""
        albumID = nil
        explicit = false
        composer = ""
        isSong = false
        duration = 0
        isPlaying = false
        heldPlaying = nil
        show(artwork: nil, encoded: nil)
        appBundleID = nil
        appIcon = nil
        options = PlaybackOptions()
        AudioLevels.shared.follow(pid: 0, playing: false)
        AppVolume.shared.follow(app: nil, pid: 0)
    }

    /// The artwork's color, lifted to read on the dark notch. Gray artwork gets a soft white.
    private static func accent(of image: NSImage) -> Color? {
        guard let mixed = mixedColor(of: image) else { return nil }
        guard mixed.saturationComponent > 0.12 else { return Color(white: 0.92) }
        return Color(
            hue: mixed.hueComponent, saturation: min(max(mixed.saturationComponent, 0.45), 0.85),
            brightness: max(mixed.brightnessComponent, 0.9))
    }

    /// Mixes the artwork's colors, weighting vivid pixels, so a white or black border doesn't wash
    /// the color out.
    private static func mixedColor(of image: NSImage) -> NSColor? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let side = 12
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard
            let context = CGContext(
                data: &pixels, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))

        var red = 0.0, green = 0.0, blue = 0.0, total = 0.0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let pixel = NSColor(
                red: CGFloat(pixels[i]) / 255, green: CGFloat(pixels[i + 1]) / 255,
                blue: CGFloat(pixels[i + 2]) / 255, alpha: 1)
            let weight = Double(pixel.saturationComponent * pixel.saturationComponent * pixel.brightnessComponent) + 0.01
            red += Double(pixel.redComponent) * weight
            green += Double(pixel.greenComponent) * weight
            blue += Double(pixel.blueComponent) * weight
            total += weight
        }
        return NSColor(red: red / total, green: green / total, blue: blue / total, alpha: 1)
    }

    private static let imageContext = CIContext()

    private static func wash(of image: NSImage) -> NSImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let input = CIImage(cgImage: cgImage)
        let scale = 64 / max(input.extent.width, input.extent.height, 1)
        let small = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let soft = small.clampedToExtent()
            .applyingGaussianBlur(sigma: 5)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.5])
        guard let output = imageContext.createCGImage(soft, from: small.extent.integral) else { return nil }
        return NSImage(cgImage: output, size: NSSize(width: output.width, height: output.height))
    }

    /// Inside the app bundle, or next to the executable for `swift build` runs.
    private static var helperLibrary: URL? {
        [Bundle.main.privateFrameworksURL, Bundle.main.executableURL?.deletingLastPathComponent()]
            .compactMap { $0?.appending(path: "libGlanceNowPlaying.dylib") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static let loader = """
        use DynaLoader;
        my $library = DynaLoader::dl_load_file($ARGV[0], 0) or die DynaLoader::dl_error();
        my $run = DynaLoader::dl_find_symbol($library, "notch_now_playing_run") or die DynaLoader::dl_error();
        DynaLoader::dl_install_xsub("main::run", $run);
        run();
        """
}
