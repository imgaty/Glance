//
//  AirDropReceiving.swift
//  Glance
//
//  Created by Gaty on 25/11/2026.
//

import AppKit
import UniformTypeIdentifiers

/// A file coming in over AirDrop on macOS 27.3 and later. Its new AirDrop service tells only its
/// own AirDropUI, through a channel no other app may join, and no longer the observer `AirDropWatch`
/// listens to. What it still does for everyone is what macOS has long done for a file coming into
/// Downloads: it publishes the file's progress, its operation Receiving, which Finder draws on the
/// file and any app may follow with `Progress.addSubscriber(forFileURL:)`, without a permission. It
/// counts what has been written out of the size the sender announced, and cancelling it stops the
/// transfer, as AirDrop's own Stop does.
@MainActor
final class AirDropReceiveWatch {
    /// Told what's coming in, and nil once nothing is.
    var changed: (AirDropShown?) -> Void = { _ in }

    private var subscriber: Any?
    private var receipts = AirDropReceipts()
    private var progresses: [Int: Progress] = [:]
    private var observations: [Int: [NSKeyValueObservation]] = [:]
    private var count = 0
    private var shown: AirDropShown? {
        didSet { if shown != oldValue { changed(shown) } }
    }
    /// Each file's picture, made once.
    private var pictures: [Int: NSImage] = [:]

    /// Where macOS saves what comes in over AirDrop.
    nonisolated static var downloads: URL { FileManager.default.homeDirectoryForCurrentUser.appending(path: "Downloads", directoryHint: .isDirectory) }

    /// The folder followed: Downloads, or a test's own.
    private let folder: URL

    init(folder: URL = AirDropReceiveWatch.downloads) {
        self.folder = folder
    }

    func start() {
        guard subscriber == nil else { return }
        subscriber = Progress.addSubscriber(forFileURL: folder) { [weak self] progress in
            // Called on a queue of Foundation's own, where the progress changes too.
            nonisolated(unsafe) let progress = progress
            let watch = self
            let publish = { MainActor.assumeIsolated { watch?.published(progress) ?? 0 } }
            let publication = Thread.isMainThread ? publish() : DispatchQueue.main.sync(execute: publish)
            return { [weak watch] in
                DispatchQueue.main.async { MainActor.assumeIsolated { watch?.unpublished(publication) } }
            }
        }
    }

    /// Stops following, as a test ends.
    func end() {
        if let subscriber { Progress.removeSubscriber(subscriber) }
        subscriber = nil
    }

    /// Stops what's coming in, as AirDrop's own Stop does, by cancelling its progress.
    func stop() {
        guard let shown, shown.offersStop else { return }
        for id in receipts.under(way: shown.id) { progresses[id]?.cancel() }
    }

    private func published(_ progress: Progress) -> Int {
        count += 1
        let id = count
        let reading = Self.reading(progress)
        guard receipts.published(id, reading) else { return id }
        progresses[id] = progress
        let read: (Progress) -> Void = { [weak self] progress in
            let reading = Self.reading(progress)
            let watch = self
            DispatchQueue.main.async { MainActor.assumeIsolated { watch?.updated(id, reading) } }
        }
        observations[id] = [
            progress.observe(\.fractionCompleted) { progress, _ in read(progress) },
            progress.observe(\.isCancelled) { progress, _ in read(progress) },
            progress.observe(\.isCancellable) { progress, _ in read(progress) },
        ]
        pictures[id] = Self.picture(progress) ?? reading.file.map { AirDropReceipts.icon($0.lastPathComponent) }
        refresh()
        return id
    }

    private func updated(_ id: Int, _ reading: AirDropReceipts.Reading) {
        receipts.updated(id, reading)
        refresh()
    }

    private func unpublished(_ id: Int) {
        observations[id]?.forEach { $0.invalidate() }
        observations[id] = nil
        progresses[id] = nil
        receipts.unpublished(id)
        refresh()
        // Shown full a moment once it's all in, as macOS says it's in; then gone.
        guard receipts.finished(id) else { return pictures[id] = nil }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard let self else { return }
            self.receipts.forget(id)
            self.pictures[id] = nil
            self.refresh()
        }
    }

    private func refresh() {
        shown = receipts.shown { pictures[$0] }
    }

    // MARK: Reading

    /// What a progress says now: which file, whether it's coming in, and how far along it is.
    nonisolated static func reading(_ progress: Progress) -> AirDropReceipts.Reading {
        let operation = progress.fileOperationKind?.rawValue ?? progress.userInfo[.fileOperationKindKey] as? String
        return AirDropReceipts.Reading(
            file: progress.fileURL ?? progress.userInfo[.fileURLKey] as? URL, operation: operation, total: progress.totalUnitCount, completed: progress.completedUnitCount,
            cancellable: progress.isCancellable,
            cancelled: progress.isCancelled)
    }

    /// The picture macOS gave the file for its animation into Downloads, or its icon. macOS 27.3's
    /// AirDrop gives neither, and the file is empty until it's in: its kind's icon stands in.
    nonisolated private static func picture(_ progress: Progress) -> NSImage? {
        for key in [ProgressUserInfoKey.fileAnimationImageKey, .fileIconKey] {
            switch progress.userInfo[key] {
            case let image as NSImage: return image
            case let url as URL: if let image = NSImage(contentsOf: url) { return image }
            case let data as Data: if let image = NSImage(data: data) { return image }
            default: break
            }
        }
        return nil
    }
}

/// What's coming in over AirDrop, from the progress macOS publishes for each file it receives into
/// Downloads: one AirDrop of several files comes as several at once, shown as one, its fraction what
/// all have written of all they will. A file nobody is receiving, such as a download, is left out.
struct AirDropReceipts {
    /// What one published progress says at a moment.
    struct Reading: Equatable {
        var file: URL?
        var operation: String?
        var total: Int64
        var completed: Int64
        var cancellable = false
        var cancelled = false
    }

    /// Foundation's word for a file coming in from another device, as AirDrop's.
    static let receiving = Progress.FileOperationKind.receiving.rawValue

    private struct Receipt {
        var reading: Reading
        var published: Bool
        /// The AirDrop it came with: the first of those under way when it came.
        var batch: Int
    }
    private var receipts: [Int: Receipt] = [:]

    /// Whether a progress is a file coming in over AirDrop, to be followed.
    static func isReceiving(_ reading: Reading) -> Bool {
        reading.operation == receiving && reading.file != nil
    }

    /// A progress came out: whether it's one to follow.
    mutating func published(_ id: Int, _ reading: Reading) -> Bool {
        guard Self.isReceiving(reading) else { return false }
        let batch = receipts.filter(\.value.published).map(\.value.batch).min() ?? id
        receipts[id] = Receipt(reading: reading, published: true, batch: batch)
        return true
    }

    mutating func updated(_ id: Int, _ reading: Reading) {
        guard receipts[id]?.published == true else { return }
        receipts[id]?.reading = reading
    }

    /// It went: kept, full, if it got all in, until forgotten; dropped if not.
    mutating func unpublished(_ id: Int) {
        guard let receipt = receipts[id] else { return }
        if Self.complete(receipt.reading) {
            receipts[id]?.published = false
        } else {
            receipts[id] = nil
        }
    }

    mutating func forget(_ id: Int) {
        if receipts[id]?.published == false { receipts[id] = nil }
    }

    /// Whether it went with all of it in.
    func finished(_ id: Int) -> Bool { receipts[id].map { !$0.published } ?? false }

    /// The progresses still coming in with the AirDrop shown by this identifier.
    func under(way shown: String) -> [Int] {
        receipts.filter { "airdrop-receive-\($0.value.batch)" == shown && $0.value.published }.keys.sorted()
    }

    static func complete(_ reading: Reading) -> Bool {
        !reading.cancelled && reading.total > 0 && reading.completed >= reading.total
    }

    /// The AirDrop coming in, the first if there are several: its first file's picture and name,
    /// and what all its files have written of all they will. Full only once every file has gone
    /// with all of it in, as macOS says it's in.
    func shown(picture: (Int) -> NSImage?) -> AirDropShown? {
        guard let batch = receipts.values.map(\.batch).min() else { return nil }
        let files = receipts.filter { $0.value.batch == batch }.sorted { $0.key < $1.key }
        guard let first = files.first else { return nil }
        let total = files.reduce(Int64(0)) { $0 + max($1.value.reading.total, 0) }
        let completed = files.reduce(Int64(0)) { $0 + min(max($1.value.reading.completed, 0), max($1.value.reading.total, 0)) }
        let underWay = files.filter(\.value.published)
        let fraction = underWay.isEmpty ? 1 : total > 0 ? min(Double(completed) / Double(total), 0.99) : 0
        let name = first.value.reading.file?.lastPathComponent
        return AirDropShown(
            id: "airdrop-receive-\(batch)", sender: "", preview: picture(first.key), fraction: fraction, file: name,
            canStop: !underWay.isEmpty && underWay.allSatisfy { $0.value.reading.cancellable && !$0.value.reading.cancelled })
    }

    /// The icon of the file's kind, from its name, before the file itself is there to picture.
    static func icon(_ name: String) -> NSImage {
        let type = UTType(filenameExtension: (name as NSString).pathExtension) ?? .data
        return NSWorkspace.shared.icon(for: type)
    }
}
