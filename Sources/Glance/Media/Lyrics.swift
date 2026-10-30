//
//  Lyrics.swift
//  Glance
//
//  Created by Gaty on 07/10/2026.
//

import SwiftUI

/// A song's lyrics, timed line by line.
struct TimedLyrics: Equatable {
    enum Item: Equatable {
        /// A line, lit all at once while it's sung.
        case line(String)
        /// A pause in the singing, shown as three dots that fill.
        case interlude
        /// After the last line: who wrote the song, and where the lyrics came from.
        case credits
    }

    struct Entry: Equatable {
        let start: Double
        /// When the line has been sung, or the pause ends.
        let end: Double
        let item: Item
    }

    let entries: [Entry]

    /// Reads LRC: lines of text, each after one or more [mm:ss.xx] times. Times some lyrics put
    /// before each word, <mm:ss.xx>, are left out. An empty line marks where the singing stops.
    init?(lrc: String, duration: Double) {
        var lines: [(time: Double, text: String)] = []
        for raw in lrc.components(separatedBy: .newlines) {
            var rest = Substring(raw)
            var times: [Double] = []
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                if let time = Self.seconds(rest[rest.index(after: rest.startIndex)..<close]) { times.append(time) }
                rest = rest[rest.index(after: close)...]
            }
            let text = String(rest)
                .replacingOccurrences(of: #"<\d+:\d+(\.\d+)?>"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            lines += times.map { ($0, text) }
        }
        lines.sort { $0.time < $1.time }
        guard lines.contains(where: { !$0.text.isEmpty }) else { return nil }

        let songEnd = duration > 0 ? duration : lines[lines.count - 1].time + 6
        var entries: [Entry] = []
        for (index, line) in lines.enumerated() where !line.text.isEmpty {
            let next = index + 1 < lines.count ? lines[index + 1].time : max(songEnd, line.time + 4)
            // About when the line has been sung, to tell a pause after it: never past the next line
            // or a marked stop.
            let natural = Double(line.text.count) * 0.065 + 0.5
            let end = line.time + min((next - line.time) * 0.9, natural * 1.5)

            let nextSung = lines[(index + 1)...].first { !$0.text.isEmpty }?.time
            if entries.isEmpty, line.time >= 4 {
                entries.append(Entry(start: 0.5, end: line.time, item: .interlude))
            }
            entries.append(Entry(start: line.time, end: end, item: .line(line.text)))
            if let nextSung, nextSung - end >= 5 {
                entries.append(Entry(start: end + 0.6, end: nextSung, item: .interlude))
            }
        }
        self.entries = entries
    }

    /// When the first line starts.
    var firstLineStart: Double? {
        entries.first { if case .line = $0.item { true } else { false } }?.start
    }

    /// When the last line starts.
    var lastLineStart: Double? {
        entries.last { if case .line = $0.item { true } else { false } }?.start
    }

    /// "mm:ss.xx" as seconds; tags like [ar:Artist] aren't times.
    private static func seconds(_ tag: Substring) -> Double? {
        let parts = tag.split(separator: ":")
        guard parts.count == 2, let minutes = Double(parts[0]), let seconds = Double(parts[1]) else { return nil }
        return minutes * 60 + seconds
    }
}

/// Whether a lyrics record is for the song playing. Another song's lyrics are worse than none, so
/// everything has to agree: the title (leaving out what versions add, like "(Remastered)" or
/// "(feat. …)"), at least one of the artists, and, when the player says how long the song is, the
/// length to within a few seconds. Without an artist nothing matches: a title alone, like
/// "Untitled", could be any song.
enum LyricsMatch {
    /// How far apart the player's and the record's lengths may be, in seconds.
    static let lengthTolerance: Double = 3

    static func matches(
        title: String, artist: String, duration: Double,
        recordTitle: String?, recordArtist: String?, recordDuration: Double?
    ) -> Bool {
        let wantedTitle = core(title), wantedArtists = artists(artist)
        guard !wantedTitle.isEmpty, !wantedArtists.isEmpty,
            let recordTitle, core(recordTitle) == wantedTitle,
            let recordArtist, !artists(recordArtist).isDisjoint(with: wantedArtists)
        else { return false }
        guard duration > 0 else { return true }
        guard let recordDuration else { return false }
        return abs(recordDuration - duration) <= lengthTolerance
    }

    /// The title without what versions add to it: "Song - Remastered 2011" and "Song (feat.
    /// Someone)" are both "song".
    static func core(_ title: String) -> String {
        var plain = title
        if let dash = plain.range(of: " - ") { plain = String(plain[..<dash.lowerBound]) }
        if let bracket = plain.firstIndex(where: { $0 == "(" || $0 == "[" }) { plain = String(plain[..<bracket]) }
        return normalized(plain)
    }

    /// Every artist named, and the whole name too: "A feat. B", "A & B", "A, B", "A x B" and
    /// "A with B" are A and B.
    static func artists(_ text: String) -> Set<String> {
        var parts = [text.lowercased()]
        for separator in [" feat. ", " feat ", " ft. ", " featuring ", " & ", " x ", " with ", ", ", "; ", " / "] {
            parts = parts.flatMap { $0.components(separatedBy: separator) }
        }
        return Set((parts + [text]).map(normalized).filter { !$0.isEmpty })
    }

    /// Lowercased, without accents or punctuation, "and", "&" and "+" all left out: "Don't Stop",
    /// "dont stop" and "Simon & Garfunkel", "Simon and Garfunkel" match.
    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .filter { $0 != "'" && $0 != "\u{2019}" }
            .map { $0.isLetter || $0.isNumber ? $0 : " " }
            .reduce(into: "") { $0.append($1) }
            .split(separator: " ")
            .filter { $0 != "and" }
            .joined(separator: " ")
    }
}

/// Finds lyrics on LRCLIB (lrclib.net), a free, open lyrics database, as each song starts, so they're
/// ready the moment they're shown. Only the song's title, artist, album and length are sent, and
/// nothing with Lyrics turned off in Settings.
@MainActor
final class LyricsStore: ObservableObject {
    static let shared = LyricsStore()

    /// Holds the made-up song's lyrics, for the welcome tour, and looks nothing up.
    private var isDemo = false

    init() {}

    init(demo lyrics: TimedLyrics, credits: Credits) {
        isDemo = true
        content = .timed(lyrics)
        self.credits = credits
    }

    enum Content: Equatable {
        case none
        case loading
        case timed(TimedLyrics)
        /// Lyrics without times, which can only be read through.
        case plain([String])
        case instrumental
        case unavailable
    }

    /// Who wrote the song, and where that came from, shown after the last line.
    struct Credits: Equatable {
        var writers: String?
        var source: String?
    }

    /// Where the lyrics come from.
    static let lyricsSource = "LRCLIB"

    @Published private(set) var content = Content.none
    @Published private(set) var credits = Credits()
    private var track = ""
    private var cache: [String: Content] = [:]
    private var creditsCache: [String: Credits] = [:]
    private var task: Task<Void, Never>?
    private var creditsTask: Task<Void, Never>?
    /// A song LRCLIB didn't answer for, and when to ask again: every report of it would otherwise.
    private var unanswered: (track: String, retry: Date)?
    private static let retryAfter: TimeInterval = 20

    /// `composer` is who the playing app says wrote the song (Music says); otherwise Apple Music's
    /// page for the song is asked. Nothing is looked up without an artist: a title alone, like
    /// "Untitled", could be any song.
    func load(title: String, artist: String, album: String, duration: Double, composer: String, app: String?) {
        guard !isDemo else { return }
        // Versions of a song differ in length, and in timing: each is its own.
        let track = [title, artist, String(Int(duration.rounded()))].joined(separator: "\u{1F}")
        let due = unanswered.map { $0.track == track && Date.now >= $0.retry } ?? false
        guard track != self.track || due else { return }
        self.track = track
        unanswered = nil
        task?.cancel()
        creditsTask?.cancel()
        let identifiable = !title.isEmpty && !artist.isEmpty
        if !composer.isEmpty {
            credits = Credits(writers: composer, source: app == PlayerScripting.music ? "Apple Music" : nil)
        } else if let cached = creditsCache[track] {
            credits = cached
        } else {
            credits = Credits()
            if identifiable {
                creditsTask = Task {
                    let writers = await MotionArtworkStore.songwriters(title: title, artist: artist, album: album)
                    guard !Task.isCancelled, self.track == track else { return }
                    let found = Credits(writers: writers, source: writers == nil ? nil : "Apple Music")
                    creditsCache[track] = found
                    credits = found
                }
            }
        }
        guard identifiable else {
            content = title.isEmpty ? .none : .unavailable
            return
        }
        if let cached = cache[track] {
            content = cached
            return
        }
        content = .loading
        task = Task {
            let found = await Self.find(title: title, artist: artist, album: album, duration: duration)
            guard !Task.isCancelled, self.track == track else { return }
            content = found ?? .unavailable
            // A song with no lyrics isn't asked about again; one LRCLIB was too busy to answer is,
            // after a moment.
            if let found { cache[track] = found } else { unanswered = (track, .now + Self.retryAfter) }
        }
    }

    private struct Record: Decodable {
        let trackName: String?
        let artistName: String?
        let albumName: String?
        let duration: Double?
        let instrumental: Bool?
        let plainLyrics: String?
        let syncedLyrics: String?
    }

    /// LRCLIB's search: by title and artist, then without extras in the title like
    /// "- Remastered 2011" or "(feat. …)", then by both as words, with only the first artist. Its
    /// exact lookup isn't used: when no record has the album and length the player gives, which is
    /// often, it looks elsewhere and is usually too busy to answer. nil if LRCLIB couldn't be reached.
    nonisolated private static func find(title: String, artist: String, album: String, duration: Double) async -> Content? {
        let plain = simplified(title) ?? title
        var queries = [["track_name": title, "artist_name": artist]]
        if plain != title { queries.append(["track_name": plain, "artist_name": artist]) }
        queries.append(["q": [firstArtist(artist), plain].filter { !$0.isEmpty }.joined(separator: " ")])
        let answer = await firstAnswer(
            queries.map { query in
                { @Sendable in
                    guard let results: [Record]? = await request("search", query) else { return .unreachable }
                    return best(of: results ?? [], title: title, artist: artist, album: album, duration: duration).map(Answer.found) ?? .nothing
                }
            }, patience: patience)
        switch answer {
        case .found(let content): return content
        case .nothing: return .unavailable
        case .unreachable: return nil
        }
    }

    /// What one way of asking came back with.
    enum Answer: Sendable {
        case unreachable, nothing
        case found(Content)
    }

    /// How long a song's lyrics are looked for, in seconds, however slow LRCLIB is.
    private static let patience = 8.0

    /// Asks every way at once, so one slow answer holds up nothing, and takes the first in order that
    /// finds something, once those before it have come back with nothing. After `patience`, what's
    /// been found so far, or nothing.
    nonisolated static func firstAnswer(_ asks: [@Sendable () async -> Answer], patience: Double) async -> Answer {
        await withTaskGroup(of: (index: Int, answer: Answer)?.self) { group in
            for (index, ask) in asks.enumerated() {
                group.addTask { (index, await ask()) }
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(patience))
                return nil
            }
            var answers = [Answer?](repeating: nil, count: asks.count)
            defer { group.cancelAll() }
            for await reply in group {
                guard let reply else { break }
                answers[reply.index] = reply.answer
                for answer in answers {
                    guard let answer else { break }
                    if case .found = answer { return answer }
                }
                if !answers.contains(where: { $0 == nil }) { break }
            }
            for case .found(let content)? in answers { return .found(content) }
            let reached = answers.contains { if case .nothing? = $0 { true } else { false } }
            return reached ? .nothing : .unreachable
        }
    }

    /// Only records for this very song count (see `LyricsMatch`): never another song's lyrics, even
    /// if that means none. Of those, timed lyrics from the same album first, then any timed, then
    /// untimed; each closest in length first, since other versions of a song are timed differently.
    nonisolated private static func best(of records: [Record], title: String, artist: String, album: String, duration: Double) -> Content? {
        let matching =
            records
            .filter {
                LyricsMatch.matches(
                    title: title, artist: artist, duration: duration,
                    recordTitle: $0.trackName, recordArtist: $0.artistName, recordDuration: $0.duration)
            }
            .sorted { abs(($0.duration ?? 0) - duration) < abs(($1.duration ?? 0) - duration) }
        let sameAlbum = album.isEmpty ? [] : matching.filter { LyricsMatch.normalized($0.albumName ?? "") == LyricsMatch.normalized(album) }
        let timed = { (records: [Record]) in records.filter { $0.syncedLyrics?.isEmpty == false } }
        let ranked = timed(sameAlbum) + timed(matching) + matching
        return ranked.lazy.compactMap { content(of: $0, duration: duration) }.first
    }

    nonisolated private static func content(of record: Record, duration: Double) -> Content? {
        if record.instrumental == true { return .instrumental }
        if let synced = record.syncedLyrics, let lyrics = TimedLyrics(lrc: synced, duration: duration) {
            // Lines timed after the song ends belong to a longer version of it.
            guard duration <= 0 || (lyrics.lastLineStart ?? 0) <= duration + 2 else { return nil }
            return .timed(lyrics)
        }
        if let plain = record.plainLyrics, !plain.isEmpty { return .plain(plain.components(separatedBy: .newlines)) }
        return nil
    }

    /// "Song - Remastered 2011" or "Song (feat. Someone)" as "Song".
    nonisolated private static func simplified(_ title: String) -> String? {
        var plain = title
        if let dash = plain.range(of: " - ") { plain = String(plain[..<dash.lowerBound]) }
        if let bracket = plain.firstIndex(where: { $0 == "(" || $0 == "[" }) { plain = String(plain[..<bracket]) }
        plain = plain.trimmingCharacters(in: .whitespaces)
        return plain.isEmpty ? nil : plain
    }

    /// "Artist feat. Other", "Artist & Other" or "Artist, Other" as "Artist".
    nonisolated private static func firstArtist(_ artist: String) -> String {
        var first = artist
        for separator in [" feat. ", " ft. ", " featuring ", " & ", " x ", ", "] {
            if let range = first.range(of: separator, options: .caseInsensitive) { first = String(first[..<range.lowerBound]) }
        }
        return first.trimmingCharacters(in: .whitespaces)
    }

    /// The decoded reply; .some(nil) when LRCLIB has nothing; nil when it couldn't be reached. It's
    /// often briefly too busy to answer, so a request is tried a few times before giving up.
    nonisolated private static func request<T: Decodable>(_ endpoint: String, _ query: [String: String]) async -> T?? {
        var components = URLComponents(string: "https://lrclib.net/api/" + endpoint)!
        components.queryItems = query.filter { !$0.value.isEmpty }.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 5)
        // LRCLIB asks apps to say who they are.
        request.setValue("Glance for macOS", forHTTPHeaderField: "User-Agent")
        for wait in [0, 0.6, 1.5] {
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            if Task.isCancelled { return nil }
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                let status = (response as? HTTPURLResponse)?.statusCode
            else { continue }
            if status == 404 { return .some(nil) }
            // Busy, or limiting how often it's asked: worth another try. Anything else isn't.
            guard status == 200 else { if status == 429 || status >= 500 { continue } else { return nil } }
            return .some(try? JSONDecoder().decode(T.self, from: data))
        }
        return nil
    }
}

/// The lyrics beside the player, in Apple Music's style: large bold lines, the one being sung lit,
/// the others dimmed and softly blurred, and the lines gliding up one after another as the song
/// moves on. Click a line to jump to it.
struct LyricsView: View {
    @EnvironmentObject private var nowPlaying: NowPlaying
    @ObservedObject var store: LyricsStore

    let isVisible: Bool
    /// Where the line being sung is centered, from this view's top: level with the notch's middle.
    let middle: CGFloat

    var body: some View {
        let request = isVisible ? [nowPlaying.title, nowPlaying.artist] : []
        // Spotify marks a break in the singing with a note; elsewhere it's Apple Music's dots.
        let notes = nowPlaying.appBundleID == PlayerScripting.spotify
        // Dimmed while the song's paused, whichever way it's shown (see `PausedLook`).
        let kept = nowPlaying.hasMedia && !nowPlaying.isPlaying ? PausedLook.kept : 1
        GeometryReader { proxy in
            Group {
                switch store.content {
                case .timed(let lyrics):
                    TimedLyricsView(
                        lyrics: lyrics, credits: store.credits, isVisible: isVisible, width: proxy.size.width,
                        height: proxy.size.height, anchor: middle, notes: notes)
                case .plain(let lines):
                    PlainLyricsView(lines: lines, credits: store.credits, isVisible: isVisible)
                case .loading where notes:
                    LoadingNote(breathing: isVisible)
                        .position(x: proxy.size.width / 2, y: middle)
                case .loading:
                    InterludeDots(progress: 0, isCurrent: true, breathing: isVisible)
                        .position(x: proxy.size.width / 2, y: middle)
                case .instrumental, .unavailable:
                    message("No lyrics available for this song")
                        .position(x: proxy.size.width / 2, y: middle)
                case .none:
                    Color.clear
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .opacity(kept)
        .animation(.easeInOut(duration: 0.4), value: kept)
        // A little apart from the player, the padding in from the notch's edge.
        .padding(.leading, 12)
        .padding(.trailing, PlayerLayout.padding)
        .onChange(of: request, initial: true) {
            if isVisible { nowPlaying.loadLyrics() }
        }
    }

    /// Centered where the line being sung would be.
    private func message(_ text: String) -> some View {
        Text(text)
            .font(LyricsStyle.font)
            .foregroundStyle(.white.opacity(LyricsStyle.dim))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension NowPlaying {
    /// The welcome tour's song loads its own, once its length is known: asked for sooner, with the
    /// wrong length, the words wouldn't match it.
    func loadLyrics() {
        guard !isDemo else { return }
        lyricsStore.load(
            title: title, artist: artist, album: album, duration: duration,
            composer: composer, app: appBundleID)
    }
}

private enum LyricsStyle {
    /// How far ahead of the song the lyrics run, in seconds: a line is lit just as it starts to be
    /// sung, rather than a beat after.
    static let lead = 0.25
    static let size: CGFloat = 19
    static let font = Font.system(size: size, weight: .bold)
    /// Apple Music leaves a lot of air between lines.
    static let spacing: CGFloat = 16
    /// How bright lines are that aren't being sung.
    static let dim = 0.36
    /// Lines fade in and out softly at the top and bottom edges, over a quarter of the height at
    /// each, and it stays open past the sides, so a blurred letter's soft edge is never cut off.
    static func edges(fadingBottom: Bool) -> some View {
        let stops = (0...12).flatMap { i -> [Gradient.Stop] in
            let t = CGFloat(i) / 12, eased = t * t * (3 - 2 * t)
            return [
                .init(color: .black.opacity(eased), location: 0.25 * t),
                .init(color: .black.opacity(fadingBottom ? 1 - eased : 1), location: 0.75 + 0.25 * t),
            ]
        }
        return LinearGradient(stops: stops.sorted { $0.location < $1.location }, startPoint: .top, endPoint: .bottom)
            .padding(.horizontal, -16)
    }

    /// The lines move with a soft spring, each a moment after the one above it.
    static func glide(delay: Double) -> Animation {
        .spring(response: 0.62, dampingFraction: 0.86).delay(delay)
    }
}

private struct TimedLyricsView: View {
    @EnvironmentObject private var nowPlaying: NowPlaying
    let lyrics: TimedLyrics
    let credits: LyricsStore.Credits
    let isVisible: Bool
    let width: CGFloat
    let height: CGFloat
    /// Where the line being sung is centered, from the top.
    let anchor: CGFloat
    /// Breaks in the singing show as a note, as Spotify does, rather than as dots.
    let notes: Bool
    @State private var heights: [Int: CGFloat] = [:]

    /// The lines, then the credits a moment after the last one has been sung.
    private var entries: [TimedLyrics.Entry] {
        let end = (lyrics.entries.last?.end ?? 0) + 1.5
        return lyrics.entries + [TimedLyrics.Entry(start: end, end: .infinity, item: .credits)]
    }

    var body: some View {
        TimelineView(.animation(paused: !isVisible)) { context in
            let time = nowPlaying.position(at: context.date) + LyricsStyle.lead
            let current = current(at: time)
            let focus = focus(current)
            ZStack(alignment: .topLeading) {
                ForEach(max(focus - 3, 0)..<min(focus + 9, entries.count), id: \.self) { index in
                    let y = offset(of: index, focus: focus, current: current)
                    entry(index, current: current, time: time)
                        .onGeometryChange(for: CGFloat.self) {
                            $0.size.height
                        } action: {
                            heights[index] = $0
                        }
                        .blur(radius: edgeBlur(atY: y + size(index, current: current) / 2))
                        .offset(y: y)
                        .animation(
                            LyricsStyle.glide(delay: min(Double(max(index - focus + 1, 0)) * 0.045, 0.35)),
                            value: current)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        // Nothing follows the credits, so they're never faded.
        .mask { LyricsStyle.edges(fadingBottom: !showsCredits) }
    }

    private var showsCredits: Bool {
        let current = current(at: nowPlaying.position(at: .now) + LyricsStyle.lead)
        guard current >= 0 else { return false }
        if case .credits = entries[current].item { return true }
        return false
    }

    /// The entry being sung, a moment ahead (`LyricsStyle.lead`). A pause shows until the singing
    /// starts again.
    private func current(at time: Double) -> Int {
        entries.lastIndex { $0.start <= time } ?? -1
    }

    /// Apple Music's lyrics: the line being sung bright white; the ones to come soft white, a little
    /// blurred. Nothing sung stays on screen: as the next line starts, the last one blurs and fades
    /// away.
    @ViewBuilder private func entry(_ index: Int, current: Int, time: Double) -> some View {
        let entry = entries[index]
        switch entry.item {
        case .line(let text):
            line(text, index: index, current: current)
                .contentShape(Rectangle())
                .onTapGesture { nowPlaying.seek(to: entry.start) }
                .notchControl(enabled: isVisible)
        case .credits:
            CreditsView(credits: credits)
        case .interlude where notes:
            line("♪", index: index, current: current)
        case .interlude:
            let progress = (time - entry.start) / max(entry.end - entry.start, 0.1)
            InterludeDots(
                progress: progress, isCurrent: index == current, breathing: isVisible && nowPlaying.isPlaying,
                fold: entry.end - time)
        }
    }

    /// Bright while it's sung, dim and a little blurred before; sung, it blurs and fades away as it
    /// moves up.
    private func line(_ text: String, index: Int, current: Int) -> some View {
        Text(text)
            .font(LyricsStyle.font)
            .foregroundStyle(.white.opacity(index == current ? 1 : LyricsStyle.dim))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .blur(radius: index == current ? 0 : index < current ? 8 : min(0.6 + 0.2 * Double(abs(index - current) - 1), 1))
            // Lit at once as it's reached, while it glides into place; the fading of sung lines
            // follows the glide.
            .animation(.easeOut(duration: 0.18), value: current)
            .opacity(index < current ? 0 : 1)
    }

    /// Lines soften as they near the top and bottom edges: no blur until well away from the middle,
    /// up to a point right at the edges, as the fade takes them.
    private func edgeBlur(atY middle: CGFloat) -> CGFloat {
        // Measured from the line being sung down toward the bottom edge.
        guard middle > anchor else { return 0 }
        let fromCenter = (middle - anchor) / max(height - anchor, 1)
        let t = min(max((fromCenter - 0.5) / 0.45, 0), 1)
        return t * t
    }

    /// The entry centered on the anchor: the one being sung, or before the song reaches any, the
    /// first that takes room, so the first line waits in the middle rather than below it.
    private func focus(_ current: Int) -> Int {
        var focus = max(current, 0)
        while focus < entries.count - 1, size(focus, current: current) == 0 { focus += 1 }
        return focus
    }

    /// Apple Music's dots only take room while they're on; Spotify's notes are lines like any other.
    /// A line's height is worked out from its text before it's ever drawn, so nothing jumps when it
    /// appears.
    private func size(_ k: Int, current: Int) -> CGFloat {
        switch entries[k].item {
        case .interlude where notes: return heights[k] ?? Self.measure("♪", width: width)
        case .interlude: return k == current ? InterludeDots.height : 0
        case .credits: return heights[k] ?? 44
        case .line(let text): return heights[k] ?? Self.measure(text, width: width)
        }
    }

    private static func measure(_ text: String, width: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: LyricsStyle.size, weight: .bold)
        return ceil(
            (text as NSString).boundingRect(
                with: CGSize(width: max(width, 1), height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font]
            ).height)
    }

    /// The line being sung is centered on the anchor; the rest stack above and below it.
    private func offset(of index: Int, focus: Int, current: Int) -> CGFloat {
        func size(_ k: Int) -> CGFloat { self.size(k, current: current) }
        func room(_ k: Int) -> CGFloat { size(k) > 0 ? size(k) + LyricsStyle.spacing : 0 }
        // Centered on the anchor, but kept whole inside the space when it's tall, like the credits.
        var y = min(max(anchor - size(focus) / 2, 0), max(height - size(focus), 0))
        if index >= focus {
            for k in focus..<index { y += room(k) }
        } else {
            for k in index..<focus { y -= room(k) }
        }
        return y
    }
}

/// Spotify's note, breathing gently while the lyrics are found.
private struct LoadingNote: View {
    let breathing: Bool

    var body: some View {
        TimelineView(.animation(paused: !breathing)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Text("♪")
                .font(LyricsStyle.font)
                .foregroundStyle(.white.opacity(LyricsStyle.dim + 0.25 * (1 + sin(t * 2 * .pi / 2.4)) / 2))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Three dots that fill one by one through a pause in the singing, breathing gently while the song
/// plays, then fold away just before the next line.
private struct InterludeDots: View {
    static let height: CGFloat = 18
    let progress: Double
    let isCurrent: Bool
    let breathing: Bool
    var fold: Double = .infinity

    var body: some View {
        TimelineView(.animation(paused: !(breathing && isCurrent))) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            // Still while paused: what's around it redraws all the time, so pausing the timeline
            // alone wouldn't hold it.
            let breath = breathing ? 1 + 0.08 * sin(t * 2 * .pi / 2.4) : 1
            let folding = min(max(fold / 0.4, 0), 1)
            HStack(spacing: 7) {
                ForEach(0..<3, id: \.self) { dot in
                    let fill = min(max(progress * 3 - Double(dot), 0), 1)
                    Circle()
                        .fill(.white.opacity(LyricsStyle.dim + (1 - LyricsStyle.dim) * fill))
                        .frame(width: 10, height: 10)
                }
            }
            .scaleEffect(isCurrent ? breath * folding : 0.4, anchor: .leading)
            .animation(.easeOut(duration: 0.3), value: breathing)
            .opacity(isCurrent ? 1 : 0)
            .frame(maxWidth: .infinity, minHeight: Self.height, maxHeight: Self.height, alignment: .leading)
        }
    }
}

/// After the last line, as in Apple Music: "Written By:" in bold, the names after it in regular,
/// a size below the lyrics in their gray; then, the same way, where the lyrics and credits came from,
/// on one line.
private struct CreditsView: View {
    let credits: LyricsStore.Credits

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let writers = credits.writers {
                Text("\(Text("Written By:").fontWeight(.bold)) \(writers)")
            }
            Text("\(Text("Credits To:").fontWeight(.bold)) \(sources)")
        }
        .font(.system(size: 12))
        .foregroundStyle(.white.opacity(0.5))
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    private var sources: String {
        [LyricsStore.lyricsSource, credits.source].compactMap { $0 }.joined(separator: " and ")
    }
}

/// Lyrics without times: read through by scrolling.
private struct PlainLyricsView: View {
    let lines: [String]
    let credits: LyricsStore.Credits
    let isVisible: Bool

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line.isEmpty ? " " : line)
                        .font(LyricsStyle.font)
                        .foregroundStyle(.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
                CreditsView(credits: credits)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 16)
        }
        .mask { LyricsStyle.edges(fadingBottom: true) }
        .notchControl(enabled: isVisible)
    }
}
