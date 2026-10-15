//
//  Tray.swift
//  Glance
//
//  Created by Gaty on 12/10/2026.
//

import AppKit
import Carbon.HIToolbox
import Combine

/// The tray: files dropped on the notch, kept until they're removed, and what's been copied and
/// screenshots taken, kept as long as chosen, newest first. It keeps its list, and what it holds
/// that isn't a file, in its own folder, readable only by its owner.
@MainActor
final class Tray: ObservableObject {
    static let shared = Tray(folder: URL.applicationSupportDirectory.appending(path: "dev.vibe.Glance/Tray"))

    @Published private(set) var items: [TrayItem] = []
    /// macOS asks before Glance reads what's copied, or was told not to let it: copies aren't kept
    /// until it's allowed under Paste from Other Apps.
    @Published private(set) var pasteBlocked = false
    /// Items chosen together, with ⌘ or Shift, to copy, drag, share or remove at once.
    @Published private(set) var selection: Set<UUID> = []
    private var anchor: UUID?
    /// Items are being dragged out of the tray, which a drag over the notch from elsewhere isn't.
    @Published var draggingOut = false
    /// Share's picker is up over the notch, which stays open until it's done.
    var sharing = false

    static let didPaste = Notification.Name("TrayDidPaste")
    /// An item was clicked or right-clicked, by the view posted with: its notch takes the keyboard.
    static let didTouch = Notification.Name("TrayDidTouch")
    /// The most of either kind kept: the oldest goes first.
    static let limit = 200

    let folder: URL
    private let pasteboard: NSPasteboard
    private var watchTimer: Timer?
    private var purgeTimer: Timer?
    private var changeCount: Int
    /// What Glance itself put on the pasteboard, which isn't a new copy.
    private var ownChange: Int?

    init(folder: URL, pasteboard: NSPasteboard = .general) {
        self.folder = folder
        self.pasteboard = pasteboard
        changeCount = pasteboard.changeCount
        load()
    }

    nonisolated static var isOn: Bool { UserDefaults.standard.bool(forKey: Preferences.tray) }
    nonisolated static var keepsCopies: Bool { isOn && UserDefaults.standard.bool(forKey: Preferences.trayClipboard) }
    nonisolated static var keepsScreenshots: Bool { isOn && UserDefaults.standard.bool(forKey: Preferences.trayScreenshots) }

    // MARK: Watching what's copied

    /// Watches the pasteboard while copies are kept, and drops copies older than chosen. There's no
    /// word when something's copied: its count of changes is checked twice a second, which reads
    /// nothing that's on it.
    func start() {
        follow()
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.follow() }
        }
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.purge() }
        }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        purgeTimer = timer
        purge()
        dropLeftovers()
        Task { await checkFiles() }
    }

    /// Starts or stops watching as the settings say.
    private func follow() {
        followScreenshots()
        guard Self.keepsCopies != (watchTimer != nil) else { return }
        if Self.keepsCopies {
            changeCount = pasteboard.changeCount
            let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.check() }
            }
            timer.tolerance = 0.25
            RunLoop.main.add(timer, forMode: .common)
            watchTimer = timer
        } else {
            watchTimer?.invalidate()
            watchTimer = nil
        }
        purge()
    }

    private func check() {
        let count = pasteboard.changeCount
        guard count != changeCount else { return }
        changeCount = count
        guard count != ownChange else { return }
        // Reading what's copied may ask first, on every copy: until it's allowed, nothing is read.
        let access = pasteboard.accessBehavior
        let blocked = access == .ask || access == .alwaysDeny
        if pasteBlocked != blocked { pasteBlocked = blocked }
        guard !blocked else { return }
        // Copied on another device: reading it waits for it to arrive, which would hold up the notch.
        guard !(pasteboard.types ?? []).contains(.init("com.apple.is-remote-clipboard")) else { return }
        let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard app != Bundle.main.bundleIdentifier, !TrayApps.ignores(app), let capture = TrayCapture.make(from: pasteboard, kept: false, app: app) else { return }
        add(capture)
    }

    // MARK: Watching for screenshots

    private var screenshots: NSMetadataQuery?

    /// Screenshots, wherever they're saved, as Spotlight finds them: each new one joins the tray as
    /// it's saved. Those taken before aren't added.
    private func followScreenshots() {
        guard Self.keepsScreenshots != (screenshots != nil) else { return }
        guard Self.keepsScreenshots else {
            screenshots?.stop()
            screenshots = nil
            return
        }
        let query = NSMetadataQuery()
        query.predicate = NSPredicate(format: "kMDItemIsScreenCapture == 1")
        query.searchScopes = [NSMetadataQueryUserHomeScope]
        NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidUpdate, object: query, queue: .main) { [weak self] note in
            let added = note.userInfo?[NSMetadataQueryUpdateAddedItemsKey] as? [NSMetadataItem] ?? []
            let paths = added.compactMap { $0.value(forAttribute: NSMetadataItemPathKey) as? String }
            MainActor.assumeIsolated { paths.forEach { self?.addScreenshot(at: $0) } }
        }
        query.start()
        screenshots = query
    }

    private func addScreenshot(at path: String) {
        let url = URL(fileURLWithPath: path)
        guard let bookmark = try? url.bookmarkData() else { return }
        add(
            TrayCapture(
                item: TrayItem(
                    id: UUID(), added: .now, kind: .files, kept: false, bookmarks: [bookmark], names: [url.lastPathComponent],
                    fingerprint: "files:" + path, source: .screenshot),
                data: []))
    }

    // MARK: Adding and removing

    /// Copies and screenshots that came while the pointer was on the tray, held back so the row
    /// doesn't move under it: they join once it leaves. What's dropped on the notch joins at once.
    private var waiting: [TrayCapture] = []
    /// Each notch whose tray the pointer is on.
    private var holders: Set<ObjectIdentifier> = []

    /// A notch's tray under the pointer, or no longer.
    func hold(_ holding: Bool, for holder: AnyObject) {
        let id = ObjectIdentifier(holder)
        guard holders.contains(id) != holding else { return }
        if holding { holders.insert(id) } else { holders.remove(id) }
        guard holders.isEmpty, !waiting.isEmpty else { return }
        let joining = waiting
        waiting = []
        joining.forEach(insert)
    }

    /// Something copied, or a screenshot: new at the front, unless the pointer is on the tray, when
    /// it waits until it's gone.
    func add(_ capture: TrayCapture) {
        guard holders.isEmpty else { return waiting.append(capture) }
        insert(capture)
    }

    /// New at the front; the same thing again moves to the front instead, kept if either was.
    private func insert(_ capture: TrayCapture) {
        var item = capture.item
        if let index = items.firstIndex(where: { $0.fingerprint == item.fingerprint }) {
            let old = items.remove(at: index)
            item = old
            item.added = capture.item.added
            item.kept = old.kept || capture.item.kept
            if capture.item.kind == .files { item.names = capture.item.names }
        } else {
            guard save(capture) else { return }
        }
        items.insert(item, at: 0)
        trim()
        store()
    }

    /// What's dropped on the notch, kept until removed: each file on its own, or a picture, a link
    /// or text. Files that are only promised, as from Photos or Mail, are written into the tray's
    /// folder first. Returns whether anything was taken.
    @discardableResult
    func drop(_ pasteboard: NSPasteboard) -> Bool {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            // In the order they were dragged, the first at the front.
            for url in urls.reversed() { keep(url) }
            return true
        }
        if let promises = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver], !promises.isEmpty {
            prepareFolder()
            for promise in promises {
                // Into a folder of the item's own, which goes when the item does.
                let id = UUID()
                let place = folder.appending(path: id.uuidString)
                try? FileManager.default.createDirectory(at: place, withIntermediateDirectories: true)
                promise.receivePromisedFiles(atDestination: place, options: [:], operationQueue: .main) { [weak self] url, error in
                    // Never written: its folder goes, rather than staying behind, empty, for good.
                    guard error == nil else {
                        try? FileManager.default.removeItem(at: place)
                        return
                    }
                    MainActor.assumeIsolated { self?.addFile(url, id: id) }
                }
            }
            return true
        }
        guard let capture = TrayCapture.make(from: pasteboard, kept: true) else { return false }
        insert(capture)
        return true
    }

    /// Whether a drag holds anything the tray takes.
    static func accepts(_ pasteboard: NSPasteboard) -> Bool {
        let types = Set(pasteboard.types ?? [])
        let wanted: Set<NSPasteboard.PasteboardType> = [.fileURL, .URL, .string, .png, .tiff, .rtf, .html]
        return !types.isDisjoint(with: wanted) || !types.isDisjoint(with: NSFilePromiseReceiver.readableDraggedTypes.map { .init($0) })
    }

    /// A file kept where it is; one in a temporary folder, like a screenshot dragged from its
    /// thumbnail, which goes once it's dropped, is copied into a folder of the item's own first.
    private func keep(_ url: URL) {
        guard Self.isTemporary(url) else { return addFile(url) }
        prepareFolder()
        let id = UUID()
        let place = folder.appending(path: id.uuidString)
        let copy = place.appending(path: url.lastPathComponent)
        do {
            try FileManager.default.createDirectory(at: place, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: copy)
            addFile(copy, id: id)
        } catch {
            try? FileManager.default.removeItem(at: place)
        }
    }

    static func isTemporary(_ url: URL) -> Bool {
        let path = url.resolvingSymlinksInPath().path
        let temporary = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().path
        return path.hasPrefix("/private/var/folders/") || path.hasPrefix("/private/tmp/") || path.contains("/TemporaryItems/")
            || path.hasPrefix(temporary)
    }

    private func addFile(_ url: URL, id: UUID = UUID()) {
        guard let bookmark = try? url.bookmarkData() else { return }
        insert(
            TrayCapture(
                item: TrayItem(
                    id: id, added: .now, kind: .files, kept: true, bookmarks: [bookmark], names: [url.lastPathComponent],
                    fingerprint: "files:" + url.path, source: .dropped),
                data: []))
    }

    func remove(_ id: UUID) {
        remove([id])
    }

    /// Taken out of the tray, as Finder moves a file to the Trash: ⌘Z brings them back, for a
    /// minute, and what they kept goes for good after that.
    func remove(_ ids: Set<UUID>) {
        let gone = items.enumerated().filter { ids.contains($0.element.id) }.map { Removed(index: $0.offset, item: $0.element) }
        guard !gone.isEmpty else { return }
        items.removeAll { ids.contains($0.id) }
        selection.subtract(ids)
        store()
        let batch = UUID()
        removed.append((batch, gone))
        if removed.count > 20 { removed.removeFirst().items.forEach { discard($0.item) } }
        Task { [weak self] in
            try? await Task.sleep(for: Self.undoTime)
            self?.forget(batch)
        }
    }

    /// An item taken out, and where it was in the row.
    private struct Removed {
        let index: Int
        let item: TrayItem
    }

    /// What was last taken out, newest last, until it can't be brought back.
    private var removed: [(id: UUID, items: [Removed])] = []
    static let undoTime: Duration = .seconds(60)

    private func forget(_ batch: UUID) {
        guard let index = removed.firstIndex(where: { $0.id == batch }) else { return }
        removed.remove(at: index).items.forEach { discard($0.item) }
    }

    /// The items last taken out, back where they were and chosen, so it shows what came back.
    /// Returns them, or none if there's nothing to bring back.
    @discardableResult
    func undoRemove() -> [UUID] {
        guard let batch = removed.popLast() else { return [] }
        for entry in batch.items.sorted(by: { $0.index < $1.index }) where !items.contains(where: { $0.id == entry.item.id }) {
            items.insert(entry.item, at: min(entry.index, items.count))
        }
        let ids = batch.items.map(\.item.id)
        selection = Set(ids)
        anchor = ids.first
        lead = ids.first
        store()
        return ids
    }

    /// Copies and screenshots kept until they're removed, as what's dropped on the notch is; or, no
    /// longer, kept as long as copies are from now on. What's dropped is always kept.
    func keep(_ ids: Set<UUID>, _ keeping: Bool = true) {
        var changed = false
        for index in items.indices where ids.contains(items[index].id) && items[index].origin != .dropped {
            guard items[index].kept != keeping else { continue }
            // How it came is noted first: an item from before that was recorded is told apart by
            // whether it's kept.
            items[index].source = items[index].origin
            items[index].kept = keeping
            items[index].released = keeping ? nil : .now
            changed = true
        }
        if changed { store() }
    }

    /// Everything, kept or copied, after asking. Files stay where they are.
    func clear() {
        items.forEach(discard)
        removed.forEach { $0.items.forEach { discard($0.item) } }
        removed = []
        items = []
        selection = []
        store()
    }

    /// What the tray kept for items no longer in it, as when Glance quit within a minute of one
    /// being taken out.
    func dropLeftovers() {
        let ids = Set(items.map(\.id.uuidString))
        let places = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for place in places where UUID(uuidString: place.lastPathComponent) != nil && !ids.contains(place.lastPathComponent) {
            try? FileManager.default.removeItem(at: place)
        }
    }

    // MARK: Choosing several

    /// A click on an item with ⌘ adds it to the chosen ones or takes it out; with Shift, chooses
    /// every item from the last one chosen to it, as Finder does; with neither, chooses it alone.
    func choose(_ id: UUID, toggling: Bool = false, extending: Bool = false) {
        lead = id
        if extending, let anchor, let from = items.firstIndex(where: { $0.id == anchor }),
            let to = items.firstIndex(where: { $0.id == id })
        {
            selection = Set(items[min(from, to)...max(from, to)].map(\.id))
            return
        }
        if toggling {
            if selection.remove(id) == nil { selection.insert(id) }
        } else {
            selection = [id]
        }
        anchor = id
    }

    func choose(all order: [TrayItem]) {
        selection = Set(order.map(\.id))
    }

    func deselect() {
        lead = nil
        guard !selection.isEmpty else { return }
        selection = []
        anchor = nil
    }

    /// The item the keyboard is on: the last one clicked, or moved to with an arrow key.
    private var lead: UUID?

    /// An arrow key, as in Finder's row of icons: the item after the one the keyboard is on, or
    /// before it, chosen alone; with Shift, every item from the first one chosen to it. With none
    /// chosen yet, the first item, or the last. Returns the item moved to.
    @discardableResult
    func move(by step: Int, extending: Bool = false) -> UUID? {
        guard !items.isEmpty else { return nil }
        let current = lead.flatMap { id in items.firstIndex { $0.id == id } }
        let index = current.map { min(max($0 + step, 0), items.count - 1) } ?? (step > 0 ? 0 : items.count - 1)
        let id = items[index].id
        choose(id, extending: extending && anchor != nil)
        return id
    }

    /// What an action on an item covers: every chosen item, when it's one of them; otherwise it
    /// alone. In the tray's order.
    func targets(of item: TrayItem) -> [TrayItem] {
        selection.contains(item.id) ? items.filter { selection.contains($0.id) } : [item]
    }

    var chosen: [TrayItem] { items.filter { selection.contains($0.id) } }

    /// The first item whose name, as the tray shows it, starts with what's typed, as Finder finds a
    /// file by its name typed in a window: whatever the case or accents.
    func first(named typed: String) -> UUID? {
        let options: String.CompareOptions = [.anchored, .caseInsensitive, .diacriticInsensitive]
        return items.first { TrayItemPicture.title(of: $0).range(of: typed, options: options) != nil }?.id
    }

    /// Copies older than chosen go.
    func purge(now: Date = .now) {
        let keep = ClipboardKeep.current
        discard(ids: Set(items.filter { $0.expired(at: now, keep: keep) }.map(\.id)))
    }

    /// The folder each file kept on its own is in, by name, as last looked: for what VoiceOver says
    /// of it.
    @Published private(set) var folders: [UUID: String] = [:]

    /// Files that are gone, as to the Trash, go too. Looking for each file can take a while, on a
    /// slow or sleeping disk, so it's done away from the notch, which never waits for it; the
    /// folder each one is in is noted on the way.
    func checkFiles() async {
        let files = items.filter { $0.kind == .files }.map { (id: $0.id, bookmarks: $0.bookmarks) }
        guard !files.isEmpty else { return }
        let found = await Task.detached(priority: .utility) {
            files.map { file -> (id: UUID, exists: Bool, folder: String?) in
                let urls = Tray.resolve(file.bookmarks)
                let folder = urls.count == 1 ? FileManager.default.displayName(atPath: urls[0].deletingLastPathComponent().path) : nil
                return (file.id, !urls.isEmpty, folder)
            }
        }.value
        var folders = self.folders
        for file in found { folders[file.id] = file.folder }
        if folders != self.folders { self.folders = folders }
        discard(ids: Set(found.filter { !$0.exists }.map(\.id)))
    }

    /// These items go, with what they kept, if they're still here.
    private func discard(ids: Set<UUID>) {
        let gone = items.filter { ids.contains($0.id) }
        guard !gone.isEmpty else { return }
        gone.forEach(discard)
        items.removeAll { ids.contains($0.id) }
        selection.subtract(ids)
        store()
    }

    /// The oldest copies and the oldest kept items past the limit.
    private func trim() {
        for kept in [false, true] {
            let ofKind = items.filter { $0.kept == kept }
            guard ofKind.count > Self.limit else { continue }
            let gone = Set(ofKind.suffix(ofKind.count - Self.limit).map(\.id))
            items.filter { gone.contains($0.id) }.forEach(discard)
            items.removeAll { gone.contains($0.id) }
        }
    }

    // MARK: Using what's in it

    /// The item's files, wherever they are now; any that are gone are left out.
    func urls(of item: TrayItem) -> [URL] {
        Self.resolve(item.bookmarks)
    }

    nonisolated static func resolve(_ bookmarks: [Data]) -> [URL] {
        bookmarks.compactMap { bookmark in
            var stale = false
            return try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting], bookmarkDataIsStale: &stale)
        }
        .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// The files items are, for Quick Look, Open and dragging out: a file's own, wherever it is now,
    /// or the one a picture is kept in. Text and links have none.
    func files(of items: [TrayItem]) -> [URL] {
        items.flatMap { item -> [URL] in
            switch item.kind {
            case .files: urls(of: item)
            case .image: item.files.first.map { [file($0, of: item)] } ?? []
            case .link, .text: []
            }
        }
    }

    /// What opening an item opens: a link's address, or its files.
    func openable(_ item: TrayItem) -> [URL] {
        item.address.map { [$0] } ?? files(of: [item])
    }

    /// Where one of what the app gave is kept.
    func file(_ name: String, of item: TrayItem) -> URL {
        folder.appending(path: item.id.uuidString).appending(path: name)
    }

    /// What goes on a pasteboard for the item: its files, or each version the app gave of it; plain,
    /// only its words, without the style they were copied with.
    func writers(for item: TrayItem, plain: Bool = false) -> [NSPasteboardWriting] {
        if item.kind == .files { return urls(of: item).map { $0 as NSURL } }
        let entry = NSPasteboardItem()
        for (type, name) in zip(item.types, item.files) where !plain || type == NSPasteboard.PasteboardType.string.rawValue {
            if let data = try? Data(contentsOf: file(name, of: item)) { entry.setData(data, forType: .init(type)) }
        }
        return [entry]
    }

    /// Back on the clipboard, as it was copied. It's not added again.
    func copy(_ item: TrayItem) {
        copy([item])
    }

    /// Several at once, as Finder copies several files.
    func copy(_ items: [TrayItem], plain: Bool = false) {
        guard !items.isEmpty else { return }
        pasteboard.clearContents()
        pasteboard.writeObjects(items.flatMap { writers(for: $0, plain: plain) })
        ownChange = pasteboard.changeCount
        changeCount = pasteboard.changeCount
    }

    /// What the share menu and AirDrop are given for items: files as themselves, a picture as the
    /// file it's kept in, a link as its address, text as itself.
    func shareable(_ items: [TrayItem]) -> [Any] {
        items.flatMap { item -> [Any] in
            switch item.kind {
            case .files, .image: files(of: [item])
            case .link: item.address.map { [$0] } ?? []
            case .text: item.text.map { [$0] } ?? []
            }
        }
    }

    /// The AirDrop window, in front, with the items ready to send.
    func airDrop(_ items: [Any]) {
        guard let service = NSSharingService(named: .sendViaAirDrop), !items.isEmpty, service.canPerform(withItems: items) else {
            return NSSound.beep()
        }
        NSApp.activate()
        service.perform(withItems: items)
    }

    /// Copied, and pasted where the cursor is, as Spotlight's clipboard history pastes on a double
    /// click; without Accessibility, only copied.
    func paste(_ item: TrayItem) {
        paste([item])
    }

    /// Several at once, as several files copied in Finder paste together. Plain, as Paste and Match
    /// Style pastes: text takes on the style of where it lands.
    func paste(_ items: [TrayItem], plain: Bool = false) {
        guard !items.isEmpty else { return }
        copy(items, plain: plain)
        guard CGPreflightPostEventAccess() else { return }
        NotificationCenter.default.post(name: Self.didPaste, object: nil)
        // The app the notch floats over still has the keyboard; ⌘V, once the copy has landed.
        Task {
            try? await Task.sleep(for: .milliseconds(80))
            let source = CGEventSource(stateID: .combinedSessionState)
            for down in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: down)
                event?.flags = .maskCommand
                event?.post(tap: .cghidEventTap)
            }
        }
    }

    // MARK: Keeping

    private var index: URL { folder.appending(path: "Tray.json") }

    private func load() {
        guard let data = try? Data(contentsOf: index), let saved = try? JSONDecoder().decode([TrayItem].self, from: data) else { return }
        items = saved
    }

    private func store() {
        prepareFolder()
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: index, options: .atomic)
    }

    private func save(_ capture: TrayCapture) -> Bool {
        guard !capture.data.isEmpty else { return true }
        prepareFolder()
        let place = folder.appending(path: capture.item.id.uuidString)
        do {
            try FileManager.default.createDirectory(at: place, withIntermediateDirectories: true)
            for (name, data) in zip(capture.item.files, capture.data) { try data.write(to: place.appending(path: name)) }
            return true
        } catch {
            try? FileManager.default.removeItem(at: place)
            return false
        }
    }

    /// The item's folder goes with it, with any file it received; files kept where they were stay.
    private func discard(_ item: TrayItem) {
        try? FileManager.default.removeItem(at: folder.appending(path: item.id.uuidString))
    }

    private func prepareFolder() {
        guard !FileManager.default.fileExists(atPath: folder.path) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
}

/// Apps whose copies are never kept, as chosen in Settings: by bundle identifier, comma separated.
enum TrayApps {
    static var ignored: [String] {
        (UserDefaults.standard.string(forKey: Preferences.trayIgnoredApps) ?? "").split(separator: ",").map(String.init)
    }

    static func ignores(_ app: String?) -> Bool {
        app.map(ignored.contains) ?? false
    }

    static func add(_ app: String) {
        set(ignored.filter { $0 != app } + [app])
    }

    static func remove(_ app: String) {
        set(ignored.filter { $0 != app })
    }

    private static func set(_ apps: [String]) {
        UserDefaults.standard.set(apps.joined(separator: ","), forKey: Preferences.trayIgnoredApps)
    }
}
