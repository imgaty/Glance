//
//  main.swift
//  GlancePowerHelper
//
//  Created by Gaty on 11/11/2026.
//

import Foundation
import IOKit.ps
import PowerControlInterface

final class PowerHelper: NSObject, NSXPCListenerDelegate, PowerControlProtocol {
    private let changes = DispatchQueue(label: "dev.vibe.Glance.PowerControl.changes")

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // The listener validates the peer's exact signing identity before reaching this method.
        connection.exportedInterface = NSXPCInterface(with: PowerControlProtocol.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }

    func setLowPowerMode(_ enabled: Bool, reply: @escaping (Int32) -> Void) {
        changes.async {
            guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
                let source = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
            else {
                reply(1)
                return
            }
            let powerSource: PowerControlCommand.Source
            switch source {
            case kIOPSBatteryPowerValue: powerSource = .battery
            case kIOPSACPowerValue: powerSource = .adapter
            default:
                reply(1)
                return
            }
            let command = Process()
            command.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            command.arguments = PowerControlCommand.arguments(enabled: enabled, source: powerSource)
            command.environment = ["PATH": "/usr/bin:/bin", "LC_ALL": "C"]
            command.currentDirectoryURL = URL(fileURLWithPath: "/")
            command.standardOutput = FileHandle.nullDevice
            command.standardError = FileHandle.nullDevice
            do {
                try command.run()
                let timeout = DispatchWorkItem { if command.isRunning { command.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: timeout)
                command.waitUntilExit()
                timeout.cancel()
                reply(command.terminationStatus)
            } catch { reply(1) }
        }
    }
}

// Unsigned development binaries and an ordinary user process must never serve this interface.
guard geteuid() == 0, let requirement = PowerControlIdentity.requirement(for: PowerControlIdentity.app) else { exit(77) }
let delegate = PowerHelper()
let listener = NSXPCListener(machServiceName: PowerControlIdentity.helper)
listener.setConnectionCodeSigningRequirement(requirement)
listener.delegate = delegate
listener.resume()
RunLoop.main.run()
