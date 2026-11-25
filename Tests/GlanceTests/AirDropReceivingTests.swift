import Foundation
import Testing

@testable import Glance

@Suite("AirDrop receiving")
struct AirDropReceivingTests {
    private static let movie = URL(fileURLWithPath: "/fixture/Downloads/movie.mov")
    private static let photo = URL(fileURLWithPath: "/fixture/Downloads/photo.heic")

    private static func reading(
        _ file: URL = movie, operation: String? = AirDropReceipts.receiving, total: Int64 = 1000, completed: Int64 = 0, cancellable: Bool = true
    )
        -> AirDropReceipts.Reading
    {
        AirDropReceipts.Reading(file: file, operation: operation, total: total, completed: completed, cancellable: cancellable)
    }

    @Test("Only a file being received is followed, not a download or a copy into Downloads")
    func receivingOnly() {
        var receipts = AirDropReceipts()
        let followed1 = receipts.published(1, Self.reading(operation: Progress.FileOperationKind.downloading.rawValue))
        #expect(!followed1)
        let followed2 = receipts.published(2, Self.reading(operation: Progress.FileOperationKind.copying.rawValue))
        #expect(!followed2)
        let followed3 = receipts.published(3, Self.reading(operation: nil))
        #expect(!followed3)
        #expect(receipts.shown { _ in nil } == nil)
        let followed4 = receipts.published(4, Self.reading())
        #expect(followed4)
        #expect(receipts.shown { _ in nil }?.file == "movie.mov")
    }

    @Test("Coming in shows how far along it is, short of full until macOS says it's in")
    func fraction() throws {
        var receipts = AirDropReceipts()
        let followed5 = receipts.published(1, Self.reading(completed: 0))
        #expect(followed5)
        receipts.updated(1, Self.reading(completed: 400))
        let shown = try #require(receipts.shown { _ in nil })
        #expect(isClose(shown.fraction, 0.4))
        #expect(!shown.sending && !shown.asking && !shown.done)
        receipts.updated(1, Self.reading(completed: 1000))
        #expect(try #require(receipts.shown { _ in nil }).fraction <= 0.99)
        receipts.unpublished(1)
        let done = try #require(receipts.shown { _ in nil })
        #expect(done.fraction == 1 && done.done && !done.offersStop)
        #expect(receipts.finished(1))
        receipts.forget(1)
        #expect(receipts.shown { _ in nil } == nil)
    }

    @Test("A stopped or failed transfer goes at once, never shown full")
    func stopped() {
        var receipts = AirDropReceipts()
        let followed6 = receipts.published(1, Self.reading(completed: 300))
        #expect(followed6)
        var cancelled = Self.reading(completed: 300)
        cancelled.cancelled = true
        receipts.updated(1, cancelled)
        #expect(receipts.shown { _ in nil }?.offersStop == false)
        receipts.unpublished(1)
        #expect(!receipts.finished(1))
        #expect(receipts.shown { _ in nil } == nil)
    }

    @Test("Several files in one AirDrop show as one, counting all their bytes")
    func severalFiles() throws {
        var receipts = AirDropReceipts()
        let followed7 = receipts.published(1, Self.reading(total: 1000, completed: 1000))
        #expect(followed7)
        let followed8 = receipts.published(2, Self.reading(Self.photo, total: 3000, completed: 1000))
        #expect(followed8)
        let shown = try #require(receipts.shown { _ in nil })
        #expect(isClose(shown.fraction, 0.5))
        #expect(shown.file == "movie.mov")
        #expect(receipts.under(way: shown.id) == [1, 2])
        // The first file in: the AirDrop is still coming, as the same one.
        receipts.unpublished(1)
        let after = try #require(receipts.shown { _ in nil })
        #expect(after.id == shown.id && !after.done)
        #expect(receipts.under(way: shown.id) == [2])
        receipts.updated(2, Self.reading(Self.photo, total: 3000, completed: 3000))
        receipts.unpublished(2)
        #expect(try #require(receipts.shown { _ in nil }).done)
    }

    @Test("A second AirDrop waits for the first, then shows as its own")
    func secondAirDrop() throws {
        var receipts = AirDropReceipts()
        let followed9 = receipts.published(1, Self.reading(completed: 100))
        #expect(followed9)
        let first = try #require(receipts.shown { _ in nil })
        receipts.unpublished(1)
        receipts.forget(1)
        let followed10 = receipts.published(2, Self.reading(Self.photo, completed: 100))
        #expect(followed10)
        let second = try #require(receipts.shown { _ in nil })
        #expect(second.id != first.id && second.file == "photo.heic")
    }

    @Test("Stop is offered only while every file still coming in can be cancelled")
    func stop() throws {
        var receipts = AirDropReceipts()
        let followed11 = receipts.published(1, Self.reading(cancellable: true))
        #expect(followed11)
        #expect(try #require(receipts.shown { _ in nil }).offersStop)
        let followed12 = receipts.published(2, Self.reading(Self.photo, cancellable: false))
        #expect(followed12)
        #expect(try !#require(receipts.shown { _ in nil }).offersStop)
    }

    @Test("An unknown size never claims progress")
    func unknownSize() throws {
        var receipts = AirDropReceipts()
        let followed13 = receipts.published(1, Self.reading(total: -1, completed: 5000))
        #expect(followed13)
        #expect(try #require(receipts.shown { _ in nil }).fraction == 0)
        receipts.unpublished(1)
        #expect(receipts.shown { _ in nil } == nil)
    }

    @Test("Without a sender's name, the opened notch and VoiceOver name the file instead")
    func namedByFile() {
        let receiving = AirDropShown(id: "fixture", sender: "", fraction: 0.4, file: "movie.mov")
        #expect(ExpandedAirDropView.from(receiving) == "movie.mov")
        #expect(ExpandedAirDropView.spoken(receiving).contains("movie.mov"))
        let told = AirDropShown(id: "fixture", sender: "Phone", fraction: 0.4)
        #expect(ExpandedAirDropView.from(told).contains("Phone"))
    }

    @Test("A progress published by another app carries its file and operation only in its user info")
    func readingFromUserInfo() {
        let progress = Progress(totalUnitCount: 0)
        progress.setUserInfoObject(Self.movie, forKey: .fileURLKey)
        progress.setUserInfoObject(AirDropReceipts.receiving, forKey: .fileOperationKindKey)
        let reading = AirDropReceiveWatch.reading(progress)
        #expect(reading.file == Self.movie)
        #expect(AirDropReceipts.isReceiving(reading))
    }

    @Test("A progress is read for its file, operation and counts")
    func reading() {
        let progress = Progress(totalUnitCount: 2000)
        progress.kind = .file
        progress.fileURL = Self.movie
        progress.fileOperationKind = .receiving
        progress.completedUnitCount = 500
        progress.cancellationHandler = {}
        let reading = AirDropReceiveWatch.reading(progress)
        #expect(reading.file == Self.movie)
        #expect(AirDropReceipts.isReceiving(reading))
        #expect(reading.total == 2000 && reading.completed == 500 && reading.cancellable && !reading.cancelled)
    }

    /// A progress published for a file in a folder of the test's own, as macOS publishes one for a
    /// file AirDrop is receiving into Downloads: followed, shown, stopped through it, and gone.
    @MainActor
    @Test("A published progress is followed, and Stop cancels it at its source", .timeLimit(.minutes(1)))
    func published() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "AirDropReceiving-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "movie.mov")
        let watch = AirDropReceiveWatch(folder: folder)
        var shown: AirDropShown?
        watch.changed = { shown = $0 }
        watch.start()
        defer { watch.end() }

        let progress = Progress(totalUnitCount: 1000)
        progress.kind = .file
        progress.fileURL = file
        progress.fileOperationKind = .receiving
        nonisolated(unsafe) var stopped = false
        progress.cancellationHandler = { stopped = true }
        progress.publish()
        defer { progress.unpublish() }
        try await settle("The published progress was never followed") { shown?.file == "movie.mov" }
        progress.completedUnitCount = 250
        try await settle("Its progress never came through") { shown.map { isClose($0.fraction, 0.25) } ?? false }
        #expect(shown?.offersStop == true)
        watch.stop()
        try await settle("Stop never reached the publisher") { stopped }
        progress.unpublish()
        try await settle("A stopped transfer stayed") { shown == nil }
    }
}
