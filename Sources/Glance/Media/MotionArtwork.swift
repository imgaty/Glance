//
//  MotionArtwork.swift
//  Glance
//
//  Created by Gaty on 07/10/2026.
//

import AVFoundation
import AppKit
import SwiftUI

/// Apple Music's moving album covers. Apple only publishes them on Apple Music, so the album's
/// Apple Music page is read for the cover's video, which streams like any web video. Music says
/// which album is playing; for other apps the song is looked up in the iTunes catalog by its
/// title, artist and album, which is all that's sent.
@MainActor
final class MotionArtworkStore: ObservableObject {
    static let shared = MotionArtworkStore()

    @Published private var found: (album: String, video: URL)?
    private var album = ""
    /// Albums already looked up; nil for those without a moving cover.
    private var cache: [String: URL?] = [:]
    private var task: Task<Void, Never>?

    func video(artist: String, album: String) -> URL? {
        found?.album == Self.key(artist, album) ? found?.video : nil
    }

    /// `artwork` is the cover the player shows. Unless Music says exactly which album is playing,
    /// the moving cover is only used if Apple's still cover for its album looks like it: Spotify's
    /// "Special Edition" and Apple's standard edition can have entirely different covers.
    func load(title: String, artist: String, album: String, albumID: Int?, artwork: NSImage?) {
        let key = Self.key(artist, album)
        guard key != self.album else { return }
        // Without the player's cover there's nothing to check against yet; try again once it's in.
        let cover = artwork.flatMap { $0.cgImage(forProposedRect: nil, context: nil, hints: nil) }.map(Self.thumbnail)
        guard albumID != nil || cover != nil else { return }
        self.album = key
        task?.cancel()
        guard !artist.isEmpty, !album.isEmpty else { return }
        if let cached = cache[key] {
            found = cached.map { (key, $0) }
            return
        }
        task = Task {
            let lookup = await Self.find(title: title, artist: artist, album: album, albumID: albumID, cover: cover)
            guard !Task.isCancelled, self.album == key, let lookup else { return }
            cache[key] = lookup
            found = lookup.map { (key, $0) }
        }
    }

    private static func key(_ artist: String, _ album: String) -> String { artist + "\u{1F}" + album }

    private struct Search: Decodable {
        struct Item: Decodable {
            let collectionId: Int?
            let collectionName: String?
            let artistName: String?
            let trackName: String?
            let trackViewUrl: String?
            let collectionViewUrl: String?
            /// "explicit", "cleaned" or "notExplicit".
            let trackExplicitness: String?

            /// The song of that title by that artist (or with them, the first artist named).
            func isSong(_ title: String, by artist: String) -> Bool {
                simplified(trackName ?? "") == simplified(title) && byArtist(artist)
            }

            /// The album of that name, never an EP or single that shares it.
            func isAlbum(_ album: String, by artist: String) -> Bool {
                simplified(collectionName ?? "") == simplified(album) && byArtist(artist)
            }

            /// Never without an artist: any name contains an empty one.
            private func byArtist(_ artist: String) -> Bool {
                let first = simplified(artist.components(separatedBy: ", ")[0])
                return !first.isEmpty && simplified(artistName ?? "").contains(first)
            }
        }
        let results: [Item]
    }

    /// Whether a song is explicit, as Apple's catalog marks it, for players that don't say (Spotify
    /// doesn't); nil if it isn't found there. An album can be listed both clean and explicit, so
    /// the explicit one of the playing album wins, as that's what plays unless asked otherwise.
    nonisolated static func isExplicit(title: String, artist: String, album: String) async -> Bool? {
        for country in Set([storefront, "us"]).sorted() {
            guard let results = await search(title + " " + artist, entity: "song", country: country) else { continue }
            let songs = results.filter { $0.isSong(title, by: artist) && $0.trackExplicitness != nil }
            let sameAlbum = songs.filter { simplified($0.collectionName ?? "") == simplified(album) }
            for candidates in [sameAlbum, songs] where !candidates.isEmpty {
                return candidates.contains { $0.trackExplicitness == "explicit" }
            }
        }
        return nil
    }

    /// Who wrote a song, from its album's page on Apple Music, which lists each track's writers;
    /// nil if the song isn't found there. Apple's search misses some songs, so it also looks in the
    /// US catalog, and then for the album, whose page lists the song too.
    nonisolated static func songwriters(title: String, artist: String, album: String) async -> String? {
        let wanted = simplified(title)
        for country in Set([storefront, "us"]).sorted() {
            if let results = await search(title + " " + artist, entity: "song", country: country),
                let song = results.first(where: { $0.isSong(title, by: artist) }),
                let writers = await composer(of: wanted, onPage: song.trackViewUrl)
            {
                return writers
            }
            if !album.isEmpty,
                let results = await search(artist + " " + album, entity: "album", country: country),
                let match = results.first(where: { $0.isAlbum(album, by: artist) }),
                let writers = await composer(of: wanted, onPage: match.collectionViewUrl)
            {
                return writers
            }
        }
        return nil
    }

    nonisolated private static func composer(of title: String, onPage address: String?) async -> String? {
        guard let page = address.flatMap(URL.init(string:)),
            let html = await fetch(page).flatMap({ String(data: $0, encoding: .utf8) }),
            let json = serverData(in: html)
        else { return nil }
        return composer(of: title, in: json)
    }

    nonisolated private static func composer(of title: String, in value: Any) -> String? {
        if let item = value as? [String: Any] {
            if let composer = item["composer"] as? String, !composer.isEmpty,
                simplified(item["title"] as? String ?? "") == title
            {
                return composer
            }
            return item.values.lazy.compactMap { composer(of: title, in: $0) }.first
        }
        return (value as? [Any])?.lazy.compactMap { composer(of: title, in: $0) }.first
    }

    nonisolated private static var storefront: String { (Locale.current.region?.identifier ?? "US").lowercased() }

    /// The video, .some(nil) if the album has no moving cover or isn't on Apple Music, nil if
    /// Apple couldn't be reached.
    nonisolated private static func find(
        title: String, artist: String, album: String, albumID: Int?,
        cover: [Double]?
    ) async -> URL?? {
        var id = albumID
        if id == nil {
            // Songs find their album far more reliably than album names do. Only the album of the
            // same name counts: never an EP or single that shares it.
            for (term, entity) in [(title + " " + artist, "song"), (artist + " " + album, "album")] {
                guard let results = await search(term, entity: entity) else { return nil }
                id = results.first { $0.isAlbum(album, by: artist) }?.collectionId
                if id != nil { break }
            }
        }
        guard let id, let page = URL(string: "https://music.apple.com/\(storefront)/album/\(id)") else { return .some(nil) }
        guard let html = await fetch(page).flatMap({ String(data: $0, encoding: .utf8) }) else { return nil }
        guard let video = video(in: html) else { return .some(nil) }
        if albumID == nil, let cover {
            // Apple's still cover for the album, small, against the player's.
            guard
                let still = stillArtwork(in: html)?
                    .replacingOccurrences(of: "{w}", with: "32").replacingOccurrences(of: "{h}", with: "32")
                    .replacingOccurrences(of: "{c}", with: "bb").replacingOccurrences(of: "{f}", with: "jpg"),
                let url = URL(string: still)
            else { return .some(nil) }
            guard let data = await fetch(url) else { return nil }
            guard let image = NSImage(data: data)?.cgImage(forProposedRect: nil, context: nil, hints: nil),
                difference(thumbnail(image), cover) < 0.1
            else { return .some(nil) }
        }
        return .some(video)
    }

    /// The image shrunk to 16 by 16, as red, green and blue from 0 to 1.
    nonisolated static func thumbnail(_ image: CGImage) -> [Double] {
        let side = 16
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        guard
            let context = CGContext(
                data: &bytes, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return [] }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        return bytes.enumerated().filter { $0.offset % 4 != 3 }.map { Double($0.element) / 255 }
    }

    /// The average difference per color, 0 for the same picture. The same cover scores about 0; a
    /// different one, 0.2 and up.
    nonisolated private static func difference(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 1 }
        return zip(a, b).map { abs($0 - $1) }.reduce(0, +) / Double(a.count)
    }

    /// The album's still artwork address, from the page's header.
    nonisolated private static func stillArtwork(in html: String) -> String? {
        guard let item = ((header(in: html) as? [String: Any])?["items"] as? [[String: Any]])?.first,
            let artwork = (item["artwork"] as? [String: Any])?["dictionary"] as? [String: Any]
        else { return nil }
        return artwork["url"] as? String
    }

    nonisolated private static func search(_ term: String, entity: String, country: String = storefront) async -> [Search.Item]? {
        var search = URLComponents(string: "https://itunes.apple.com/search")!
        search.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "entity", value: entity),
            URLQueryItem(name: "limit", value: "25"),
            URLQueryItem(name: "country", value: country),
        ]
        guard let url = search.url, let data = await fetch(url) else { return nil }
        return (try? JSONDecoder().decode(Search.self, from: data).results) ?? []
    }

    /// The moving cover, in the album page's header.
    nonisolated private static func video(in html: String) -> URL? {
        header(in: html).flatMap(square(in:)).flatMap(URL.init(string:))
    }

    /// Apple Music's pages carry their data as JSON.
    nonisolated private static func serverData(in html: String) -> Any? {
        guard let start = html.range(of: #"id="serialized-server-data">"#),
            let end = html.range(of: "</script>", range: start.upperBound..<html.endIndex)
        else { return nil }
        return try? JSONSerialization.jsonObject(with: Data(html[start.upperBound..<end.lowerBound].utf8))
    }

    /// An album page's first section: its header, with the cover.
    nonisolated private static func header(in html: String) -> Any? {
        let json = serverData(in: html)
        guard let page = (json as? [[String: Any]])?.first ?? (json as? [String: Any]).flatMap({ ($0["data"] as? [[String: Any]])?.first }),
            let sections = (page["data"] as? [String: Any])?["sections"] as? [Any]
        else { return nil }
        return sections.first
    }

    nonisolated private static func square(in value: Any) -> String? {
        if let dictionary = value as? [String: Any] {
            if let square = dictionary["motionDetailSquare"] as? [String: Any], let video = square["video"] as? String {
                return video
            }
            return dictionary.values.lazy.compactMap(square(in:)).first
        }
        return (value as? [Any])?.lazy.compactMap(square(in:)).first
    }

    /// "Paranoid (Remastered Edition)" as "paranoid". "Slipknot - EP" stays apart from "Slipknot".
    nonisolated private static func simplified(_ name: String) -> String {
        var plain = name.lowercased()
        if let bracket = plain.firstIndex(where: { $0 == "(" || $0 == "[" }) { plain = String(plain[..<bracket]) }
        return plain.filter { $0.isLetter || $0.isNumber || $0 == " " }
            .split(separator: " ").joined(separator: " ")
    }

    nonisolated private static func fetch(_ url: URL) async -> Data? {
        var request = URLRequest(url: url, timeoutInterval: 10)
        // Apple Music's pages are made for browsers.
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
            (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return data
    }
}

/// A moving cover: muted, looping, and only playing while asked to.
struct MotionArtworkView: NSViewRepresentable {
    let url: URL
    let playing: Bool
    /// Whether a frame is ready to show; until then the still artwork shows instead.
    let onReady: (Bool) -> Void

    func makeNSView(context: Context) -> PlayerView { PlayerView(url: url, onReady: onReady) }
    func updateNSView(_ view: PlayerView, context: Context) { view.setPlaying(playing) }
    static func dismantleNSView(_ view: PlayerView, coordinator: ()) { view.stop() }

    final class PlayerView: NSView {
        private let player = AVPlayer()
        private let playerLayer = AVPlayerLayer()
        private var ready: NSKeyValueObservation?
        private var loop: NSObjectProtocol?

        init(url: URL, onReady: @escaping (Bool) -> Void) {
            super.init(frame: .zero)
            let item = AVPlayerItem(url: url)
            // The cover is small: the lighter streams look the same and cost far less.
            item.preferredMaximumResolution = CGSize(width: 480, height: 480)
            player.replaceCurrentItem(with: item)
            player.isMuted = true
            player.actionAtItemEnd = .none
            player.preventsDisplaySleepDuringVideoPlayback = false
            playerLayer.player = player
            playerLayer.videoGravity = .resizeAspectFill
            wantsLayer = true
            loop = NotificationCenter.default.addObserver(
                forName: AVPlayerItem.didPlayToEndTimeNotification,
                object: item, queue: .main
            ) { [weak player] _ in
                player?.seek(to: .zero)
            }
            ready = playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { layer, _ in
                let isReady = layer.isReadyForDisplay
                DispatchQueue.main.async { onReady(isReady) }
            }
        }

        required init?(coder: NSCoder) { nil }

        override func makeBackingLayer() -> CALayer { playerLayer }

        func setPlaying(_ playing: Bool) {
            if playing, player.rate == 0 { player.play() }
            if !playing, player.rate != 0 { player.pause() }
        }

        func stop() {
            player.pause()
            player.replaceCurrentItem(with: nil)
            if let loop { NotificationCenter.default.removeObserver(loop) }
            ready = nil
        }
    }
}
