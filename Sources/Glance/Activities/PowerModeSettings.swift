//
//  PowerModeSettings.swift
//  Glance
//
//  Created by Gaty on 10/11/2026.
//

import AppKit
import PowerControlInterface
import ServiceManagement
import os

/// Direct power control after the user approves Glance's narrowly scoped helper. No Battery
/// pane, policy menu, Accessibility action, or authentication window is used for normal toggles.
@MainActor
enum PowerModeSettings {
    private static let service = SMAppService.daemon(plistName: PowerControlIdentity.plist)
    private static let log = Logger(subsystem: "dev.vibe.Glance", category: "power")
    static var isReady: Bool { service.status == .enabled }

    /// Registration is an explicit setup action. Merely starting Glance or reviewing permissions
    /// never registers a privileged service or opens System Settings.
    static func requestAuthorization() {
        guard !isReady else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "Power control")
        alert.informativeText = String(
            localized: "Approve Glance's helper in Login Items. It can only change Low Power Mode.")
        alert.addButton(withTitle: String(localized: "Continue"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            log.notice("Power helper setup status: \(service.status.rawValue, privacy: .public)")
            if service.status != .requiresApproval { try service.register() }
            log.notice("Power helper registration status: \(service.status.rawValue, privacy: .public)")
            if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch {
            // macOS can register the item, then report that starting it is not permitted until
            // the administrator approves it. That is the normal setup step, not a failure.
            if service.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            } else {
                let failure = NSAlert()
                failure.messageText = String(localized: "Power control")
                failure.informativeText = error.localizedDescription
                failure.runModal()
            }
        }
        Permissions.shared.refresh()
    }

    /// Removes the approved service without changing either power source's current policy.
    static func removeAuthorization() {
        Task {
            do {
                try await service.unregister()
            } catch {
                let alert = NSAlert()
                alert.messageText = String(localized: "Power control")
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
            Permissions.shared.refresh()
        }
    }

    static func set(_ on: Bool) async -> Bool {
        guard isReady else {
            requestAuthorization()
            return false
        }
        guard let requirement = PowerControlIdentity.requirement(for: PowerControlIdentity.helper) else { return false }
        let started = ProcessInfo.processInfo.systemUptime
        let request = Request(requirement: requirement)
        guard await request.send(on) else {
            log.error("Power control helper did not complete the request")
            return false
        }
        // A successful command can precede ProcessInfo's power-state notification briefly.
        for _ in 0..<20 {
            if ProcessInfo.processInfo.isLowPowerModeEnabled == on {
                log.notice("Low Power Mode changed to \(on, privacy: .public) in \(ProcessInfo.processInfo.systemUptime - started, privacy: .public) seconds")
                return true
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return false
    }

    private final class Request {
        private let connection = NSXPCConnection(machServiceName: PowerControlIdentity.helper, options: .privileged)
        private var continuation: CheckedContinuation<Bool, Never>?
        private var timeout: Task<Void, Never>?

        init(requirement: String) {
            connection.setCodeSigningRequirement(requirement)
            connection.remoteObjectInterface = NSXPCInterface(with: PowerControlProtocol.self)
        }

        func send(_ on: Bool) async -> Bool {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                connection.interruptionHandler = { [weak self] in Task { @MainActor in self?.finish(false) } }
                connection.invalidationHandler = { [weak self] in Task { @MainActor in self?.finish(false) } }
                connection.resume()
                timeout = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(6))
                    guard !Task.isCancelled else { return }
                    self?.finish(false)
                }
                let proxy = connection.remoteObjectProxyWithErrorHandler { [weak self] _ in Task { @MainActor in self?.finish(false) } }
                guard let helper = proxy as? PowerControlProtocol else {
                    finish(false)
                    return
                }
                helper.setLowPowerMode(on) { [weak self] result in Task { @MainActor in self?.finish(result == 0) } }
            }
        }

        private func finish(_ success: Bool) {
            guard let continuation else { return }
            self.continuation = nil
            timeout?.cancel()
            timeout = nil
            connection.interruptionHandler = nil
            connection.invalidationHandler = nil
            connection.invalidate()
            continuation.resume(returning: success)
        }
    }
}
