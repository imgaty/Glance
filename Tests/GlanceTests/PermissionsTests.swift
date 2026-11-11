import AppKit
import Testing

@testable import Glance

@MainActor
@Suite("Remembered automation access")
struct PermissionsTests {
    @Test("Closing a player keeps its last grant across launches")
    func closed() {
        let name = "PermissionsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let first = Permissions(defaults: defaults)
        first.set(Permissions.automationState(noErr), for: PlayerScripting.spotify)
        first.set(Permissions.automationState(OSStatus(procNotFound)), for: PlayerScripting.spotify)
        #expect(first.spotifyControl == .granted)
        let restarted = Permissions(defaults: defaults)
        #expect(restarted.spotifyControl == .granted)
        restarted.set(.denied, for: PlayerScripting.spotify)
        restarted.set(nil, for: PlayerScripting.spotify)
        #expect(restarted.spotifyControl == .denied)
    }

    @Test("A new consent decision replaces remembered access, but a missing process does not")
    func decisions() {
        #expect(Permissions.automationState(OSStatus(errAEEventWouldRequireUserConsent)) == .notDetermined)
        #expect(Permissions.automationState(OSStatus(errAEEventNotPermitted)) == .denied)
        #expect(Permissions.automationState(OSStatus(procNotFound)) == nil)
        let name = "PermissionsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let permissions = Permissions(defaults: defaults)
        permissions.set(nil, for: PlayerScripting.spotify)
        #expect(permissions.spotifyControl == .notDetermined)
        permissions.set(.granted, for: PlayerScripting.spotify)
        permissions.set(.notDetermined, for: PlayerScripting.spotify)
        #expect(Permissions(defaults: defaults).spotifyControl == .notDetermined)
    }
}
