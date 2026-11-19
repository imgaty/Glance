//
//  ShortcutProgress.swift
//  Glance
//
//  Created by Gaty on 17/11/2026.
//

import Foundation
import ObjectiveC

/// Every shortcut running, wherever it was started, and how far it has got, as Shortcuts publishes it
/// for its own Live Activity: each run's `NSProgress` goes out under one category, which iOS 27's
/// ShortcutsUI subscribes to (`-[WFWorkflowRunningContext addProgressSubscriberUsingPublishingHandler:]`),
/// and an app needs no permission to listen to. Seen on macOS 27.3 for runs from Terminal, from the
/// Shortcuts app and from Shortcuts Events: the progress counts the shortcut's actions and carries only
/// the run's own identifier, not the shortcut's. Which shortcut it is comes from Shortcuts' library,
/// which notes each run as it starts and tells of it in a distributed notification naming the
/// shortcut, within a few milliseconds of the progress. Cancelling the progress stops the run, as
/// Shortcuts' own Stop does.
@MainActor
final class ShortcutProgressWatch {
    static let shared = ShortcutProgressWatch()

    static let category = "com.apple.shortcuts.progress"
    /// Posted by Shortcuts' library (siriactionsd) each time it saves: a run starting updates its
    /// shortcut, `objectType` 0.
    static let librarySaved = Notification.Name("com.apple.shortcuts.WFCoreDataDatabaseContextDidSaveNotification")

    enum Event: Equatable {
        /// A run started: its shortcut, if Shortcuts' library named it, and how far it has got.
        case began(publication: Int, shortcut: UUID?, fraction: Double)
        case progressed(publication: Int, fraction: Double)
        /// It's over: stopped, or not.
        case ended(publication: Int, cancelled: Bool)
    }

    var changed: (Event) -> Void = { _ in }

    private var subscriber: AnyObject?
    private var libraryObserver: NSObjectProtocol?
    private var pairing = ShortcutRunPairing()
    private struct Watched {
        let progress: Progress
        var observation: NSKeyValueObservation?
        var told = false
    }
    private var watched: [Int: Watched] = [:]
    private var count = 0

    func start() {
        guard subscriber == nil else { return }
        libraryObserver = DistributedNotificationCenter.default().addObserver(forName: Self.librarySaved, object: nil, queue: .main) { note in
            let shortcuts = ShortcutRunPairing.shortcuts(updatedIn: note.userInfo)
            guard !shortcuts.isEmpty else { return }
            MainActor.assumeIsolated { ShortcutProgressWatch.shared.saved(shortcuts) }
        }
        let selector = NSSelectorFromString("_addSubscriberForCategory:usingPublishingHandler:")
        guard let method = class_getClassMethod(Progress.self, selector) else { return }
        typealias Unpublished = @convention(block) () -> Void
        typealias Published = @convention(block) (Progress) -> AnyObject?
        let published: Published = { progress in
            let begin = { MainActor.assumeIsolated { ShortcutProgressWatch.shared.began(progress) } }
            let publication = Thread.isMainThread ? begin() : DispatchQueue.main.sync(execute: begin)
            let unpublished: Unpublished = {
                DispatchQueue.main.async { MainActor.assumeIsolated { ShortcutProgressWatch.shared.ended(publication) } }
            }
            return unsafeBitCast(unpublished, to: AnyObject.self)
        }
        typealias Subscribe = @convention(c) (AnyClass, Selector, NSString, Published) -> Unmanaged<AnyObject>?
        let subscribe = unsafeBitCast(method_getImplementation(method), to: Subscribe.self)
        subscriber = subscribe(Progress.self, selector, Self.category as NSString, published)?.takeUnretainedValue()
    }

    /// Stops a run, wherever it was started, as Shortcuts' own Stop does.
    func cancel(_ publication: Int) {
        watched[publication]?.progress.cancel()
    }

    private func began(_ progress: Progress) -> Int {
        count += 1
        let publication = count
        let observation = progress.observe(\.fractionCompleted) { progress, _ in
            let fraction = progress.fractionCompleted
            DispatchQueue.main.async {
                MainActor.assumeIsolated { ShortcutProgressWatch.shared.progressed(publication, fraction: fraction) }
            }
        }
        watched[publication] = Watched(progress: progress, observation: observation)
        // Spotlight's own tool runs publish here too, with no actions to count: not shortcuts, so
        // they never take a shortcut's note.
        guard progress.totalUnitCount > 0 else { return publication }
        if pairing.published(publication, at: .now) != nil {
            tell(publication)
        } else {
            // Its shortcut's name usually follows within milliseconds.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(ShortcutRunPairing.wait))
                ShortcutProgressWatch.shared.tell(publication)
            }
        }
        return publication
    }

    private func saved(_ shortcuts: [UUID]) {
        for publication in pairing.saved(shortcuts, at: .now) { tell(publication) }
    }

    /// Says a run began, once: when its shortcut is known, or once it has been waited for.
    private func tell(_ publication: Int) {
        guard let watch = watched[publication], !watch.told, watch.progress.totalUnitCount > 0 else { return }
        watched[publication]?.told = true
        pairing.stopWaiting(publication)
        changed(.began(publication: publication, shortcut: pairing.shortcut(of: publication), fraction: watch.progress.fractionCompleted))
    }

    private func progressed(_ publication: Int, fraction: Double) {
        guard let watch = watched[publication] else { return }
        if !watch.told {
            // One that counts its actions only later is told then, with no shortcut to name.
            if !pairing.isWaiting(publication) { tell(publication) }
            return
        }
        changed(.progressed(publication: publication, fraction: fraction))
    }

    private func ended(_ publication: Int) {
        guard let watch = watched.removeValue(forKey: publication) else { return }
        watch.observation?.invalidate()
        pairing.forget(publication)
        guard watch.told else { return }
        changed(.ended(publication: publication, cancelled: watch.progress.isCancelled))
    }
}

/// Which shortcut each published run is: the one Shortcuts' library said it updated closest in time
/// to the run's progress coming out, within a second either way, each note given to one run.
struct ShortcutRunPairing {
    /// How far apart a run's progress and its library note may come.
    static let window: TimeInterval = 1
    /// How long a run's progress waits for its note before it's told without its shortcut.
    static let wait: TimeInterval = 0.6

    private var notes: [(shortcut: UUID, at: Date)] = []
    private var waiting: [(publication: Int, at: Date)] = []
    private var paired: [Int: UUID] = [:]

    /// The shortcuts a library save updated, from the notification's `updated` list.
    static func shortcuts(updatedIn userInfo: [AnyHashable: Any]?) -> [UUID] {
        let updated = userInfo?["updated"] as? [Any] ?? []
        return updated.compactMap { item in
            guard let object = item as? [AnyHashable: Any], (object["objectType"] as? NSNumber)?.intValue == 0,
                let identifier = object["identifier"] as? String
            else { return nil }
            return UUID(uuidString: identifier)
        }
    }

    func shortcut(of publication: Int) -> UUID? { paired[publication] }
    func isWaiting(_ publication: Int) -> Bool { waiting.contains { $0.publication == publication } }

    /// A run's progress came out: its shortcut, if a note for one came just before.
    mutating func published(_ publication: Int, at time: Date) -> UUID? {
        expire(before: time)
        let closest = notes.indices.min { abs(notes[$0].at.timeIntervalSince(time)) < abs(notes[$1].at.timeIntervalSince(time)) }
        if let closest, abs(notes[closest].at.timeIntervalSince(time)) <= Self.window {
            paired[publication] = notes.remove(at: closest).shortcut
            return paired[publication]
        }
        waiting.append((publication, time))
        return nil
    }

    /// Shortcuts' library noted these shortcuts: the runs waiting for them that now know theirs,
    /// oldest first.
    mutating func saved(_ shortcuts: [UUID], at time: Date) -> [Int] {
        expire(before: time)
        var told: [Int] = []
        for shortcut in shortcuts {
            if let first = waiting.first {
                waiting.removeFirst()
                paired[first.publication] = shortcut
                told.append(first.publication)
            } else {
                notes.append((shortcut, time))
            }
        }
        return told
    }

    mutating func stopWaiting(_ publication: Int) {
        waiting.removeAll { $0.publication == publication }
    }

    mutating func forget(_ publication: Int) {
        paired[publication] = nil
        waiting.removeAll { $0.publication == publication }
    }

    private mutating func expire(before time: Date) {
        notes.removeAll { time.timeIntervalSince($0.at) > Self.window }
        waiting.removeAll { time.timeIntervalSince($0.at) > Self.window }
    }
}
