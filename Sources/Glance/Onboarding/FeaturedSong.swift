//
//  FeaturedSong.swift
//  Glance
//
//  Created by Gaty on 10/10/2026.
//

import AppKit

/// The real song the welcome tour plays in its pictures. Only its name, its album's number in
/// Apple's catalog and a couple of timings are kept here: the cover comes from Apple and the words
/// from LRCLIB when the tour opens, as they do for any song the Mac plays.
struct FeaturedSong {
    let title: String
    let artist: String
    let album: String
    /// The album in Apple's catalog, asked for directly: Apple's search ranks covers and karaoke
    /// versions above some songs.
    let albumID: Int
    /// Its length and when its first line is sung, as Apple and LRCLIB have them, so the pictures
    /// play from the right place at once, rather than jumping there once they've answered.
    let length: Double
    let firstLine: Double

    /// The song the tour plays.
    static let tour = FeaturedSong(
        title: "Paranoid", artist: "Black Sabbath", album: "Paranoid", albumID: 785232473, length: 168, firstLine: 11.74)

    /// Its cover, large, and its length, from Apple's catalog; nil if it can't be found or reached.
    /// The song is picked from its album's tracks, or, should the album have moved, searched for.
    func lookUp() async -> (artwork: NSImage, duration: Double)? {
        // Kept from the last time, so the tour opening again (as it does with each new build) asks
        // Apple for nothing.
        let folder = URL.cachesDirectory.appending(path: "dev.vibe.Glance/Featured Songs")
        let coverFile = folder.appending(path: "\(albumID).jpg"), lengthFile = folder.appending(path: "\(albumID).txt")
        if let image = (try? Data(contentsOf: coverFile)).flatMap(NSImage.init(data:)),
            let duration = (try? String(contentsOf: lengthFile, encoding: .utf8)).flatMap(Double.init)
        {
            return (image, duration)
        }
        guard let found = await fetchFromApple() else { return nil }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? found.cover.write(to: coverFile)
        try? String(found.duration).write(to: lengthFile, atomically: true, encoding: .utf8)
        return (found.image, found.duration)
    }

    private func fetchFromApple() async -> (image: NSImage, cover: Data, duration: Double)? {
        var song = await Self.items(["id": String(albumID), "entity": "song"], endpoint: "lookup")?.first(where: isThisSong)
        if song == nil {
            song = await Self.items(["term": artist + " " + title, "entity": "song", "limit": "50"])?.first(where: isThisSong)
        }
        guard let song, let duration = song.trackTimeMillis, let small = song.artworkUrl100,
            let address = URL(string: small.replacingOccurrences(of: "100x100bb", with: "600x600bb")),
            let cover = await Self.fetch(address), let image = NSImage(data: cover)
        else { return nil }
        return (image, cover, duration / 1000)
    }

    private struct Item: Decodable {
        let trackName: String?
        let artistName: String?
        let collectionName: String?
        let artworkUrl100: String?
        let trackTimeMillis: Double?
    }

    /// The song itself, from its album rather than a single or a compilation.
    private func isThisSong(_ item: Item) -> Bool {
        LyricsMatch.core(item.trackName ?? "") == LyricsMatch.core(title)
            && !LyricsMatch.artists(item.artistName ?? "").isDisjoint(with: LyricsMatch.artists(artist))
            && LyricsMatch.normalized(item.collectionName ?? "") == LyricsMatch.normalized(album)
    }

    private static func items(_ query: [String: String], endpoint: String = "search") async -> [Item]? {
        struct Reply: Decodable { let results: [Item] }
        var components = URLComponents(string: "https://itunes.apple.com/" + endpoint)!
        components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url, let data = await fetch(url) else { return nil }
        return try? JSONDecoder().decode(Reply.self, from: data).results
    }

    private static func fetch(_ url: URL) async -> Data? {
        guard let (data, response) = try? await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 8)),
            (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return data
    }
}
