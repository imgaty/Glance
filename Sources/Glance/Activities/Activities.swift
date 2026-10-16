//
//  Activities.swift
//  Glance
//
//  Created by Gaty on 16/10/2026.
//

import AppKit
import SwiftUI

/// A moment the Mac announces beside the camera, as the iPhone's Dynamic Island does: plugged in,
/// low on battery, headphones or a keyboard connecting, the sound going to AirPlay, the internet
/// lost or back, a timer done. It takes the closed notch's sides over for a few seconds, then
/// whatever was there comes back.
struct NotchAlert: Identifiable, Equatable {
    enum Kind: Equatable {
        case charging, lowBattery, device, output, offline, online, hotspot, timerDone
    }

    let id = UUID()
    let kind: Kind
    /// Beside the camera on the left: a symbol, in its color, then a title.
    var symbol: String?
    var tint: Color = .white
    var title: String
    /// On the right: a few words, or a battery's level.
    var detail: String?
    var detailTint: Color = .white.opacity(0.6)
    var battery: BatteryLevel?
    /// How long it shows; one that stays shows until it's dismissed.
    var seconds: Double = 3
    var stays = false

    static func == (a: NotchAlert, b: NotchAlert) -> Bool { a.id == b.id }
}

/// A battery, as its symbol shows it: how full, and whether it's charging.
struct BatteryLevel: Equatable {
    var percent: Int
    var charging: Bool
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
        let battery = BatteryWatch(), devices = DeviceWatch(), network = NetworkWatch()
        battery.start()
        devices.start()
        network.start()
        watches = [battery, devices, network]
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

    /// One that stays, of this kind, goes; or one waiting.
    func dismiss(_ kind: NotchAlert.Kind) {
        waiting.removeAll { $0.kind == kind }
        guard alert?.kind == kind else { return }
        next()
    }

    private func show(_ alert: NotchAlert) {
        self.alert = alert
        shownTask?.cancel()
        guard !alert.stays else { return }
        shownTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(alert.seconds))
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
