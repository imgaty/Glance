//
//  Activities.swift
//  Glance
//
//  Created by Gaty on 16/10/2026.
//

import AppKit
import SwiftUI

/// A moment the Mac announces beside the camera, drawn as the iPhone's Dynamic Island draws its
/// own: plugged in, low on battery, AirPods or a keyboard connecting, a timer done. It takes the closed notch's sides over for a few seconds, then whatever was there
/// comes back.
struct NotchAlert: Identifiable, Equatable {
    enum Kind: Equatable {
        case charging, lowBattery, device, deviceBattery, timerDone
    }

    /// What shows on either side of the camera.
    enum Content: Equatable {
        /// A device connecting, as AirPods do: the device itself turning in on the left, AirPods and
        /// Beats in 3D, others as macOS pictures them, or by their symbol; its battery as a ring on
        /// the right, when it tells it.
        case device(symbol: String, model: Headphones? = nil, pictures: [String] = [], battery: Int?)
        /// The Mac's battery: a word on the left, its level and a battery on the right.
        case battery(title: String, level: BatteryLevel)
        /// The Mac's battery running low, as tall as the Alarm, with a button to turn on Low Power
        /// Mode (see `LowBatteryView`).
        case lowBattery(percent: Int)
        /// A state, as Silent Mode and a Focus are shown: a symbol in its color on the left, a word
        /// or a name on the right.
        case status(symbol: String, tint: Color, text: String)
        /// A timer that's done, as the Alarm goes off: its symbol shaking, its length and its name, and
        /// buttons to start it again or stop it.
        case timerDone(length: TimeInterval, name: String)

        var tint: Color {
            switch self {
            case .device(_, _, _, let battery): battery.map(BatteryRing.color(for:)) ?? .white
            case .battery(_, let level): level.color
            case .lowBattery: .red
            case .status(_, let tint, _): tint
            case .timerDone: .orange
            }
        }
    }

    /// Its color, for the line the Dynamic Island draws around it over a dark background.
    var tint: Color { content.tint }

    /// Taller than the notch, as the Dynamic Island's Alarm is, for what's to be acted on.
    var tall: Bool {
        switch content {
        case .timerDone, .lowBattery: true
        default: false
        }
    }

    let id = UUID()
    let kind: Kind
    let content: Content
    /// What VoiceOver says of it.
    let spoken: String
    /// How long it shows, as long as the Dynamic Island shows AirPods arriving, from when it starts
    /// to open until it starts to fold; one that stays shows until it's dismissed.
    var seconds: Double = 2.82
    var stays = false

    static func == (a: NotchAlert, b: NotchAlert) -> Bool { a.id == b.id }
}

/// A battery, as its symbol shows it: how full, and whether it's charging.
struct BatteryLevel: Equatable {
    var percent: Int
    var charging: Bool
    /// Low Power Mode is on.
    var lowPower = false

    /// Green, or red at 20% and below, charging or not; yellow in Low Power Mode, as the iPhone's.
    var color: Color { lowPower ? .yellow : percent <= 20 ? .red : .green }
}

/// Every display's notch shows what's announced, one thing at a time, in turn: each waits for the
/// one before it. The same kind announced again while it waits takes its place in line rather than
/// showing twice.
@MainActor
final class Activities: ObservableObject {
    static let shared = Activities()

    @Published private(set) var alert: NotchAlert?
    private(set) var waiting: [NotchAlert] = []
    private var shownTask: Task<Void, Never>?
    /// Between one and the next, the notch rests a moment; what's announced then waits its turn.
    private var resting = false
    /// When the Mac last woke: what reconnects as it wakes isn't news, for a little while.
    private(set) var wokeAt = Date.distantPast
    private var watches: [AnyObject] = []

    /// The watches that announce, each following its setting.
    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.wokeAt = .now }
        }
        let battery = BatteryWatch(), devices = DeviceWatch()
        battery.start()
        devices.start()
        watches = [battery, devices]
        AirPlayWatch.shared.start()
        AirDropWatch.shared.start()
    }

    /// Just woken, things reconnecting are expected, not announced.
    var settling: Bool { Date.now.timeIntervalSince(wokeAt) < 10 }

    func post(_ alert: NotchAlert) {
        guard self.alert != nil || resting else { return show(alert) }
        if let index = waiting.firstIndex(where: { $0.kind == alert.kind }) {
            waiting[index] = alert
        } else {
            waiting.append(alert)
        }
        // A short line: older news goes first.
        if waiting.count > 3 { waiting.removeFirst() }
    }

    /// What shows, of this kind, stays a while longer: what was done on it is seen.
    func keep(_ kind: NotchAlert.Kind, for seconds: Double) {
        guard let alert, alert.kind == kind, !alert.stays else { return }
        shownTask?.cancel()
        shownTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds), tolerance: .zero)
            guard !Task.isCancelled else { return }
            self?.next()
        }
    }

    /// One that stays, of this kind, goes; or one waiting.
    func dismiss(_ kind: NotchAlert.Kind) {
        waiting.removeAll { $0.kind == kind }
        guard alert?.kind == kind else { return }
        next()
    }

    private func show(_ alert: NotchAlert) {
        self.alert = alert
        // Said to VoiceOver too, which can't see the notch change.
        NSAccessibility.post(
            element: NSApp as Any, notification: .announcementRequested,
            userInfo: [.announcement: alert.spoken, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        shownTask?.cancel()
        guard !alert.stays else { return }
        shownTask = Task { [weak self] in
            // To the frame, as the Dynamic Island's: the system would otherwise wake it when it suits.
            try? await Task.sleep(for: .seconds(alert.seconds), tolerance: .zero)
            guard !Task.isCancelled else { return }
            self?.next()
        }
    }

    /// The next in line, after a moment with the notch at rest between them.
    private func next() {
        shownTask?.cancel()
        alert = nil
        guard !waiting.isEmpty else { return }
        resting = true
        shownTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.6))
            guard let self, !Task.isCancelled else { return }
            self.resting = false
            if !self.waiting.isEmpty { self.show(self.waiting.removeFirst()) }
        }
    }
}
