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
    /// The items just copied back, for a moment, to show they were.
    @Published private(set) var justCopied: Set<UUID> = []
    /// Items chosen together, with ⌘ or Shift, to copy, drag, share or remove at once.
    @Published private(set) var selection: Set<UUID> = []
    private var anchor: UUID?
    /// Items are being dragged out of the tray: the AirDrop well shows, to drop them on.
    @Published var draggingOut = false

    static let didPaste = Notification.Name("TrayDidPaste")
    /// The most of either kind kept: the oldest goes first.
    static let limit = 200

    let folder: URL
    private let pasteboard: NSPasteboard
    private var watchTimer: Timer?
    private var purgeTimer: Timer?
    private var changeCount: Int
    /// What Glance itself put on the pasteboard, which isn't a new copy.
    private var ownChange: Int?
    private var copiedTask: Task<Void, Never>?

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
        purge(checkingFiles: true)
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
        guard app != Bundle.main.bundleIdentifier, let capture = TrayCapture.make(from: pasteboard, kept: false, app: app) else { return }
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

    /// New at the front; the same thing again moves to the front instead, kept if either was.
    func add(_ capture: TrayCapture) {
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
        add(capture)
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
        add(
            TrayCapture(
                item: TrayItem(
                    id: id, added: .now, kind: .files, kept: true, bookmarks: [bookmark], names: [url.lastPathComponent],
                    fingerprint: "files:" + url.path, source: .dropped),
                data: []))
    }

    func remove(_ id: UUID) {
        remove([id])
    }

    func remove(_ ids: Set<UUID>) {
        let gone = items.filter { ids.contains($0.id) }
        guard !gone.isEmpty else { return }
        gone.forEach(discard)
        items.removeAll { ids.contains($0.id) }
        selection.subtract(ids)
        store()
    }

    /// Everything, kept or copied. Files stay where they are.
    func clear() {
        items.forEach(discard)
        items = []
        selection = []
        store()
    }

    // MARK: Choosing several

    /// A click on an item with ⌘ adds it to the chosen ones or takes it out; with Shift, chooses
    /// every item from the last one chosen to it, as Finder does; with neither, chooses it alone.
    func choose(_ id: UUID, toggling: Bool = false, extending: Bool = false, in order: [TrayItem]? = nil) {
        let order = order ?? items
        if extending, let anchor, let from = order.firstIndex(where: { $0.id == anchor }),
            let to = order.firstIndex(where: { $0.id == id })
        {
            selection = Set(order[min(from, to)...max(from, to)].map(\.id))
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
        guard !selection.isEmpty else { return }
        selection = []
        anchor = nil
    }

    /// What an action on an item covers: every chosen item, when it's one of them; otherwise it
    /// alone. In the tray's order.
    func targets(of item: TrayItem) -> [TrayItem] {
        selection.contains(item.id) ? items.filter { selection.contains($0.id) } : [item]
    }

    var chosen: [TrayItem] { items.filter { selection.contains($0.id) } }

    /// Copies older than chosen go, and, when asked, files that are gone, which takes looking for
    /// each one.
    func purge(now: Date = .now, checkingFiles: Bool = false) {
        let keep = ClipboardKeep.current
        let gone = items.filter { $0.expired(at: now, keep: keep) || (checkingFiles && $0.kind == .files && urls(of: $0).isEmpty) }
        guard !gone.isEmpty else { return }
        let ids = Set(gone.map(\.id))
        gone.forEach(discard)
        items.removeAll { ids.contains($0.id) }
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
        item.bookmarks.compactMap { bookmark in
            var stale = false
            return try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting], bookmarkDataIsStale: &stale)
        }
        .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Where one of what the app gave is kept.
    func file(_ name: String, of item: TrayItem) -> URL {
        folder.appending(path: item.id.uuidString).appending(path: name)
    }

    /// What goes on a pasteboard for the item: its files, or each version the app gave of it.
    func writers(for item: TrayItem) -> [NSPasteboardWriting] {
        if item.kind == .files { return urls(of: item).map { $0 as NSURL } }
        let entry = NSPasteboardItem()
        for (type, name) in zip(item.types, item.files) {
            if let data = try? Data(contentsOf: file(name, of: item)) { entry.setData(data, forType: .init(type)) }
        }
        return [entry]
    }

    /// Back on the clipboard, as it was copied. It's not added again.
    func copy(_ item: TrayItem) {
        copy([item])
    }

    /// Several at once, as Finder copies several files.
    func copy(_ items: [TrayItem]) {
        guard !items.isEmpty else { return }
        pasteboard.clearContents()
        pasteboard.writeObjects(items.flatMap(writers))
        ownChange = pasteboard.changeCount
        changeCount = pasteboard.changeCount
        copiedTask?.cancel()
        justCopied = Set(items.map(\.id))
        copiedTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            self?.justCopied = []
        }
    }

    /// What the share menu and AirDrop are given for items: files as themselves, a picture as the
    /// file it's kept in, a link as its address, text as itself.
    func shareable(_ items: [TrayItem]) -> [Any] {
        items.flatMap { item -> [Any] in
            switch item.kind {
            case .files: urls(of: item)
            case .image: item.files.first.map { [file($0, of: item)] } ?? []
            case .link: item.text.flatMap(URL.init(string:)).map { [$0] } ?? []
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
        copy(item)
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
