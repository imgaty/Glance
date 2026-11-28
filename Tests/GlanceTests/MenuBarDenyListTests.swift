//
//  MenuBarDenyListTests.swift
//  GlanceTests
//
//  Created by Gaty on 25/11/2026.
//

import Foundation
import Testing

@testable import Glance

@Suite("MenuBarAgent's list of apps it leaves out")
@MainActor
struct MenuBarDenyListTests {
    private static let airDrop = "com.apple.Sharing.AirDropUI"

    @Test("Hiding puts AirDrop on the list and remembers it; turning off takes it off and leaves no list")
    func hideAndRestore() {
        let store = FakeDenyStore()
        let list = MenuBarDenyList(apps: [Self.airDrop], store: store.store)
        list.apply(hiding: true)
        #expect(store.list == [Self.airDrop])
        #expect(store.added == [Self.airDrop])
        list.apply(hiding: false)
        #expect(store.list == nil)
        #expect(store.added.isEmpty)
    }

    @Test("A list the user keeps stays as it was, around what Glance adds")
    func keepsUsersList() {
        let store = FakeDenyStore()
        store.list = ["com.example.app"]
        let list = MenuBarDenyList(apps: [Self.airDrop], store: store.store)
        list.apply(hiding: true)
        #expect(store.list == ["com.example.app", Self.airDrop])
        list.apply(hiding: false)
        #expect(store.list == ["com.example.app"])
    }

    @Test("AirDrop already on the user's own list is never taken off")
    func alreadyListed() {
        let store = FakeDenyStore()
        store.list = [Self.airDrop]
        let list = MenuBarDenyList(apps: [Self.airDrop], store: store.store)
        list.apply(hiding: true)
        list.apply(hiding: false)
        #expect(store.list == [Self.airDrop])
        #expect(store.listWrites == 0)
    }

    @Test("Looking again changes nothing, so it can run on every check")
    func idempotent() {
        let store = FakeDenyStore()
        let list = MenuBarDenyList(apps: [Self.airDrop], store: store.store)
        for _ in 0..<3 { list.apply(hiding: true) }
        #expect(store.listWrites == 1)
        for _ in 0..<3 { list.apply(hiding: false) }
        #expect(store.listWrites == 2)
        #expect(store.list == nil)
    }

    @Test("Taken off the list by someone else while hiding, AirDrop goes back on")
    func putBack() {
        let store = FakeDenyStore()
        let list = MenuBarDenyList(apps: [Self.airDrop], store: store.store)
        list.apply(hiding: true)
        store.list = nil
        list.apply(hiding: true)
        #expect(store.list == [Self.airDrop])
        #expect(store.added == [Self.airDrop])
    }

    @Test("What a Glance that didn't quit cleanly added comes off at the next launch")
    func staleAfterCrash() {
        let store = FakeDenyStore()
        store.list = ["com.example.app", Self.airDrop]
        store.added = [Self.airDrop]
        MenuBarDenyList(apps: [Self.airDrop], store: store.store).apply(hiding: false)
        #expect(store.list == ["com.example.app"])
        #expect(store.added.isEmpty)
    }

    @Test("AirDrop's stays while Glance's own AirDrop switch is off, so a request still shows somewhere")
    func keptWithoutGlancesAirDrop() {
        let suite = "dev.vibe.Glance.tests.deny-list"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        for (hiding, airDrop) in [(true, true), (true, false), (false, true), (false, false)] {
            defaults.set(airDrop, forKey: Preferences.activityAirDrop)
            #expect(MenuBarDenyList.hides(hiding, in: defaults) == (hiding && airDrop), "hiding \(hiding), AirDrop \(airDrop)")
        }
    }

    @Test("Glance hides AirDrop only while the notch shows Live Activities with the switch on", arguments: [false, true])
    func followsSettings(byPlace: Bool) async {
        let fake = DenyListSettings()
        let manager = fake.manager()
        await manager.reconcile()
        #expect(fake.calls.last == true)
        if byPlace { fake.active = false } else { fake.hiding = false }
        await manager.reconcile()
        #expect(fake.calls.last == false)
    }

    @Test("Hiding AirDrop needs no Accessibility, as no System Settings is opened for it")
    func withoutAccessibility() async {
        let fake = DenyListSettings()
        fake.trusted = false
        let manager = fake.manager()
        await manager.reconcile()
        #expect(fake.calls.last == true)
        #expect(fake.opens == 0)
    }

    @Test("Quitting takes AirDrop off the list at once, and nothing after puts it back")
    func quitRestores() async {
        let fake = DenyListSettings()
        let manager = fake.manager()
        await manager.reconcile()
        #expect(fake.calls.last == true)
        // Quitting starts while the notch still shows Live Activities.
        manager.stop()
        let stopped = fake.calls.count
        #expect(fake.calls.last == false)
        await manager.reconcile()
        await manager.finish(within: .milliseconds(500), launchTime: .zero)
        #expect(fake.calls.count > stopped)
        #expect(!fake.calls[stopped...].contains(true))
    }
}

/// MenuBarAgent's list and what Glance remembers adding, kept in memory.
@MainActor
private final class FakeDenyStore {
    var list: [String]?
    var added: [String] = []
    var listWrites = 0

    var store: MenuBarDenyList.Store {
        .init(
            list: { self.list },
            setList: {
                self.list = $0
                self.listWrites += 1
            },
            added: { self.added },
            setAdded: { self.added = $0 })
    }
}

/// The settings the hider reads, with no switch rows, recording what it asks of the list.
@MainActor
private final class DenyListSettings {
    var hiding = true
    var active = true
    var trusted = true
    var opens = 0
    var calls: [Bool] = []

    func manager() -> MenuBarLiveActivities {
        let manager = MenuBarLiveActivities(
            dependencies: .init(
                now: { Date(timeIntervalSince1970: 1000) }, hiding: { self.hiding }, owned: { [] }, saveOwned: { _ in },
                isTrusted: { self.trusted }, kept: { ["Clock"] }, pills: { [] },
                openSettings: {
                    self.opens += 1
                    return .init(rows: [], close: {})
                },
                denyList: { self.calls.append($0) }))
        manager.active = { self.active }
        return manager
    }
}
