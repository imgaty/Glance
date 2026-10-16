//
//  NotchTimer.swift
//  Glance
//
//  Created by Gaty on 16/10/2026.
//

import AppKit
import SwiftUI

/// A timer, started from Glance in the menu bar, counting down beside the camera as the iPhone's
/// does in the Dynamic Island. Done, it says so there and chimes until the notch is opened or
/// clicked, or it's stopped from the menu; after a minute it stops chiming by itself.
@MainActor
final class NotchTimer: ObservableObject {
    static let shared = NotchTimer()

    /// Counting down to a moment, or paused with some left.
    enum State: Equatable {
        case running(until: Date, total: TimeInterval)
        case paused(left: TimeInterval, total: TimeInterval)

        var total: TimeInterval {
            switch self {
            case .running(_, let total), .paused(_, let total): total
            }
        }

        func left(at date: Date = .now) -> TimeInterval {
            switch self {
            case .running(let until, _): max(until.timeIntervalSince(date), 0)
            case .paused(let left, _): left
            }
        }
    }

    @Published private(set) var state: State?
    /// Done, and still saying so.
    @Published private(set) var ringing = false
    /// The choices in the menu, in minutes, as Clock's own timers start.
    static let presets = [1, 3, 5, 10, 15, 30, 60]

    private let activities: Activities
    /// The system sound it chimes with when it's done; none, silent.
    private let sound: String?
    private var finish: Task<Void, Never>?
    private var chime: Task<Void, Never>?

    init(activities: Activities? = nil, sound: String? = "Glass") {
        self.activities = activities ?? .shared
        self.sound = sound
    }

    func start(seconds: TimeInterval) {
        stop()
        state = .running(until: .now + seconds, total: seconds)
        schedule()
    }

    func pause() {
        guard case .running = state, let state else { return }
        finish?.cancel()
        self.state = .paused(left: state.left(), total: state.total)
    }

    func resume() {
        guard case .paused(let left, let total) = state else { return }
        state = .running(until: .now + left, total: total)
        schedule()
    }

    /// Stopped before it's done.
    func cancel() {
        finish?.cancel()
        state = nil
    }

    /// Done and chiming, it stops; or, asked to stop only once it's done, a timer still going goes on.
    func stop(ifDone: Bool = false) {
        guard !ifDone || ringing else { return }
        cancel()
        guard ringing else { return }
        ringing = false
        chime?.cancel()
        activities.dismiss(.timerDone)
    }

    private func schedule() {
        finish?.cancel()
        guard let state else { return }
        let left = state.left()
        finish = Task { [weak self] in
            try? await Task.sleep(for: .seconds(left))
            guard !Task.isCancelled else { return }
            self?.done()
        }
    }

    /// The time's up: said beside the camera, and heard, every couple of seconds, for a minute.
    func done() {
        finish?.cancel()
        state = nil
        ringing = true
        activities.post(
            NotchAlert(
                kind: .timerDone, symbol: "timer", tint: .orange, title: "Timer", detail: "Done", detailTint: .orange, stays: true))
        chime?.cancel()
        guard let sound else { return }
        chime = Task { [weak self] in
            let start = Date.now
            while !Task.isCancelled, Date.now.timeIntervalSince(start) < 60 {
                NSSound(named: sound)?.play()
                try? await Task.sleep(for: .seconds(2))
            }
            guard !Task.isCancelled else { return }
            // Unheard for a minute, it rests, still saying it's done until it's seen.
            self?.chime = nil
        }
    }

    /// As a clock shows a length of time: 4:59, or 1:04:59 for an hour or more.
    static func format(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds.rounded(.up))
        let hours = whole / 3600, minutes = whole / 60 % 60, rest = whole % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%d:%02d", minutes, rest)
    }

    /// A preset's name in the menu: 1 Minute, 5 Minutes, 1 Hour.
    static func name(minutes: Int) -> String {
        minutes % 60 == 0 ? (minutes == 60 ? "1 Hour" : "\(minutes / 60) Hours") : (minutes == 1 ? "1 Minute" : "\(minutes) Minutes")
    }
}
