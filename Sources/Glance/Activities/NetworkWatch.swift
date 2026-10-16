//
//  NetworkWatch.swift
//  Glance
//
//  Created by Gaty on 16/10/2026.
//

import Foundation
import Network
import SwiftUI

/// The Mac's connection: lost, after a few seconds without one, and back, as Wi-Fi, Ethernet or an
/// iPhone's Personal Hotspot; and joining a hotspot, which macOS marks as a connection that may
/// cost. A blip, as when moving between networks, isn't worth a word. What the network is called
/// would need Location Services, so it goes unnamed.
@MainActor
final class NetworkWatch {
    /// The connection, as it matters here.
    struct Link: Equatable {
        enum Kind { case wifi, wired, other }
        var online: Bool
        var kind: Kind
        var hotspot: Bool
    }

    /// What's said about a change of connection.
    enum Change: Equatable { case offline, online(Link.Kind), hotspot }

    /// Lost for this long before it's said.
    static let patience: Duration = .seconds(3)

    private let monitor = NWPathMonitor()
    private var last: Link?
    /// Lost, and said so: coming back is said too.
    private var saidOffline = false
    private var pending: Task<Void, Never>?

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            let link = Link(
                online: path.status == .satisfied,
                kind: path.usesInterfaceType(.wifi) ? .wifi : path.usesInterfaceType(.wiredEthernet) ? .wired : .other,
                hotspot: path.isExpensive && path.usesInterfaceType(.wifi))
            Task { @MainActor in self?.changed(to: link) }
        }
        monitor.start(queue: DispatchQueue(label: "Glance.NetworkWatch"))
    }

    private func changed(to link: Link) {
        defer { last = link }
        // The first word, as Glance starts, is only how things are.
        guard let last, link != last else { return }
        if !link.online {
            pending?.cancel()
            pending = Task { [weak self] in
                try? await Task.sleep(for: Self.patience)
                guard let self, !Task.isCancelled, self.last?.online == false else { return }
                self.saidOffline = true
                self.say(.offline)
            }
            return
        }
        pending?.cancel()
        if let change = Self.change(from: last, to: link, saidOffline: saidOffline) { say(change) }
        saidOffline = false
    }

    /// Back after being said to be lost; or onto a hotspot from anything else.
    static func change(from old: Link, to new: Link, saidOffline: Bool) -> Change? {
        guard new.online else { return nil }
        if new.hotspot, !(old.online && old.hotspot) { return .hotspot }
        return saidOffline ? .online(new.kind) : nil
    }

    private func say(_ change: Change) {
        guard UserDefaults.standard.bool(forKey: Preferences.activityConnectivity), !Activities.shared.settling else { return }
        Activities.shared.post(Self.alert(for: change))
    }

    static func alert(for change: Change) -> NotchAlert {
        switch change {
        case .offline:
            NotchAlert(kind: .offline, symbol: "wifi.slash", tint: .red, title: "Offline", detail: "No Internet", seconds: 4)
        case .online(let kind):
            NotchAlert(
                kind: .online, symbol: kind == .wired ? "network" : "wifi", tint: .green,
                title: kind == .wired ? "Ethernet" : kind == .wifi ? "Wi-Fi" : "Online", detail: "Connected")
        case .hotspot:
            NotchAlert(kind: .hotspot, symbol: "personalhotspot", tint: .green, title: "Personal Hotspot", detail: "Connected")
        }
    }
}
