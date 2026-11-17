//
//  ShortcutProgress.swift
//  Glance
//
//  Created by Gaty on 17/11/2026.
//

import Foundation
import ObjectiveC

/// How far each running shortcut has got, as Shortcuts publishes it for its own Dynamic Island: every
/// run's `NSProgress` goes out under one category, its shortcut's identifier in its `userInfo`, and
/// iOS 27's ShortcutsUI subscribes to that category (`-[WFWorkflowRunningContext
/// addProgressSubscriberUsingPublishingHandler:]`). macOS publishes the same way, and an app needs no
/// permission to listen.
@MainActor
final class ShortcutProgressWatch {
    static let shared = ShortcutProgressWatch()

    static let category = "com.apple.shortcuts.progress"

    /// A run's progress came out, changed, or went away (nil).
    var changed: (_ publication: Int, _ shortcut: UUID, _ fraction: Double?) -> Void = { _, _, _ in }

    private var subscriber: AnyObject?
    private var watched: [Int: (shortcut: UUID, observation: NSKeyValueObservation)] = [:]
    private var count = 0

    func start() {
        guard subscriber == nil else { return }
        let selector = NSSelectorFromString("_addSubscriberForCategory:usingPublishingHandler:")
        guard let method = class_getClassMethod(Progress.self, selector) else { return }
        typealias Unpublished = @convention(block) () -> Void
        typealias Published = @convention(block) (Progress) -> AnyObject?
        let published: Published = { progress in
            let shortcut = (progress.userInfo[ProgressUserInfoKey("workflowIdentifier")] as? String).flatMap(UUID.init(uuidString:))
            let begin = { MainActor.assumeIsolated { ShortcutProgressWatch.shared.began(progress, shortcut: shortcut) } }
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

    private func began(_ progress: Progress, shortcut: UUID?) -> Int {
        count += 1
        let publication = count
        guard let shortcut else { return publication }
        changed(publication, shortcut, progress.fractionCompleted)
        let observation = progress.observe(\.fractionCompleted) { progress, _ in
            let fraction = progress.fractionCompleted
            DispatchQueue.main.async {
                MainActor.assumeIsolated { ShortcutProgressWatch.shared.changed(publication, shortcut, fraction) }
            }
        }
        watched[publication] = (shortcut, observation)
        return publication
    }

    private func ended(_ publication: Int) {
        guard let watch = watched.removeValue(forKey: publication) else { return }
        watch.observation.invalidate()
        changed(publication, watch.shortcut, nil)
    }
}
