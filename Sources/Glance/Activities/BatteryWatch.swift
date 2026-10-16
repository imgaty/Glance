//
//  BatteryWatch.swift
//  Glance
//
//  Created by Gaty on 16/10/2026.
//

import Foundation
import IOKit.ps
import SwiftUI

/// A MacBook's battery, as the iPhone's Dynamic Island shows its own: plugged in, its level in
/// green as it charges; running low, at 20% and again at 10%, in red. A Mac without a battery has
/// nothing to say.
@MainActor
final class BatteryWatch {
    /// The battery as last read.
    struct Reading: Equatable {
        var percent: Int
        var onPower: Bool
        var charging: Bool
    }

    /// The levels a low battery is announced at, on the way down.
    static let warnings = [20, 10]

    private var last: Reading?
    private var source: CFRunLoopSource?

    func start() {
        last = Self.read()
        guard last != nil else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard
            let source = IOPSNotificationCreateRunLoopSource(
                { context in
                    guard let context else { return }
                    let watch = Unmanaged<BatteryWatch>.fromOpaque(context).takeUnretainedValue()
                    MainActor.assumeIsolated { watch.changed() }
                }, context)?.takeRetainedValue()
        else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        self.source = source
    }

    private func changed() {
        guard let now = Self.read() else { return }
        defer { last = now }
        guard let last, let alert = Self.alert(from: last, to: now) else { return }
        let key = alert.kind == .charging ? Preferences.activityCharging : Preferences.activityLowBattery
        guard UserDefaults.standard.bool(forKey: key) else { return }
        Activities.shared.post(alert)
    }

    /// What's worth saying about the battery going from one reading to the next: plugged in, or
    /// running down past a warning.
    static func alert(from old: Reading, to new: Reading) -> NotchAlert? {
        let battery = BatteryLevel(percent: new.percent, charging: new.charging)
        if new.onPower, !old.onPower {
            return NotchAlert(
                kind: .charging, title: new.charging ? "Charging" : "Plugged In", detail: "\(new.percent)%", detailTint: .green,
                battery: battery)
        }
        if !new.onPower, warnings.contains(where: { new.percent <= $0 && old.percent > $0 }) {
            return NotchAlert(
                kind: .lowBattery, title: "Low Battery", detail: "\(new.percent)%", detailTint: .red, battery: battery, seconds: 4)
        }
        return nil
    }

    /// The Mac's own battery, if it has one.
    static func read() -> Reading? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                let current = description[kIOPSCurrentCapacityKey] as? Int,
                let max = description[kIOPSMaxCapacityKey] as? Int, max > 0
            else { continue }
            return Reading(
                percent: Int((Double(current) / Double(max) * 100).rounded()),
                onPower: description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
                charging: description[kIOPSIsChargingKey] as? Bool ?? false)
        }
        return nil
    }

    static var hasBattery: Bool { read() != nil }
}
