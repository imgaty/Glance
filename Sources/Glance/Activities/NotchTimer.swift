//
//  NotchTimer.swift
//  Glance
//
//  Created by Gaty on 16/10/2026.
//

import Foundation

/// A timer, as macOS's own counts down beside the camera as the iPhone's does in the Dynamic Island
/// (see `ClockActivity`): how it stands, and how its time is written and said.
enum NotchTimer {
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

    /// As a clock shows a length of time: 4:59, or 1:04:59 for an hour or more.
    static func format(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds.rounded(.up))
        let hours = whole / 3600, minutes = whole / 60 % 60, rest = whole % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%d:%02d", minutes, rest)
    }

    /// As the Dynamic Island counts down beside the camera: under ten minutes, its minutes and
    /// seconds, 4:49; from ten minutes, whole minutes gone by, 14m; past an hour, 1h 5m.
    static func condensed(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds.rounded(.up))
        if whole < 600 { return format(seconds) }
        let minutes = whole / 60
        guard minutes >= 60 else { return "\(minutes)m" }
        return minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(minutes % 60)m"
    }

    /// As VoiceOver says it: its name, what's left in words, and that it's paused: "Timer, 4 minutes,
    /// 57 seconds left, paused".
    static func spoken(_ state: State, name: String = "Timer", at date: Date = .now) -> String {
        let left = words(state.left(at: date).rounded(.up)) ?? format(state.left(at: date))
        return "\(name), \(left) left" + (state.isRunning ? "" : ", paused")
    }

    /// A length in words: "4 minutes, 57 seconds".
    static func words(_ seconds: TimeInterval) -> String? {
        let words = DateComponentsFormatter()
        words.unitsStyle = .full
        words.allowedUnits = [.hour, .minute, .second]
        return words.string(from: seconds)
    }

    /// A timer's length, as its preset is named: 5 Minutes, 1 Hour, 1 Minute, 30 Seconds.
    static func length(_ seconds: TimeInterval) -> String {
        (words(seconds.rounded()) ?? format(seconds)).capitalized
    }
}

/// Clock's stopwatch, as macOS keeps it: running, from a moment, or stopped with time on it. Reset,
/// it isn't shown.
enum Stopwatch: Equatable {
    case running(since: Date)
    case stopped(elapsed: TimeInterval)

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    func elapsed(at date: Date = .now) -> TimeInterval {
        switch self {
        case .running(let since): max(date.timeIntervalSince(since), 0)
        case .stopped(let elapsed): elapsed
        }
    }

    /// From what macOS keeps of it: running, from when it last started less what was on it then,
    /// its laps' and the lap it was on; stopped, with that much on it.
    static func current(in kept: [[String: Any]]) -> Stopwatch? {
        for entry in kept {
            guard let watch = entry["$MTStopwatch"] as? [String: Any] else { continue }
            let laps = watch["MTStopwatchPreviousLapsTotalInterval"] as? TimeInterval ?? 0
            let lap = watch["MTStopwatchOffset"] as? TimeInterval ?? 0
            switch watch["MTStopwatchState"] as? Int {
            case 2:
                guard let start = watch["MTStopwatchStartDate"] as? Date else { continue }
                return .running(since: start - laps - lap)
            case 1:
                guard laps + lap > 0 else { continue }
                return .stopped(elapsed: laps + lap)
            default: continue
            }
        }
        return nil
    }

    /// As Clock shows it: 0:07, 12:07, 1:02:07; opened, to the hundredth, 0:07.41.
    static func format(_ seconds: TimeInterval, hundredths: Bool = false) -> String {
        let whole = Int(seconds)
        let hours = whole / 3600, minutes = whole / 60 % 60, rest = whole % 60
        let shown = hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%d:%02d", minutes, rest)
        guard hundredths else { return shown }
        let hundredth = min(Int((seconds - Double(whole)) * 100), 99)
        return shown + (Locale.current.decimalSeparator ?? ".") + String(format: "%02d", hundredth)
    }

    /// As VoiceOver says it: "Stopwatch, 1 minute, 7 seconds, stopped".
    static func spoken(_ watch: Stopwatch, at date: Date = .now) -> String {
        let time = NotchTimer.words(watch.elapsed(at: date).rounded(.down)) ?? format(watch.elapsed(at: date))
        return "Stopwatch, \(time)" + (watch.isRunning ? "" : ", stopped")
    }
}
