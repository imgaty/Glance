//
//  BatteryWatch.swift
//  Glance
//
//  Created by Gaty on 16/10/2026.
//

import Foundation
import IOKit.ps
import SwiftUI
import notify

/// A MacBook's battery, as the iPhone's Dynamic Island shows its own: plugged in, Charging and its
/// level beside a battery; running low, at 20% and again at 10%, Low Battery. Green, or red at 20%
/// and below. A Mac without a battery has nothing to say. macOS warns of a low battery too, at its
/// own moments, in a notification from Control Center: the notch says so then, if it hasn't just,
/// and, while it's on, takes macOS's away (see `SystemNotices`).
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
    private var warningToken: Int32 = 0
    /// When the notch last said the battery is low.
    private var saidLow: Date?

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
        notify_register_dispatch(kIOPSNotifyLowBattery, &warningToken, .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.warned() }
        }
    }

    private func changed() {
        guard let now = Self.read() else { return }
        defer { last = now }
        guard let last, let alert = Self.alert(from: last, to: now) else { return }
        let key = alert.kind == .charging ? Preferences.activityCharging : Preferences.activityLowBattery
        guard UserDefaults.standard.bool(forKey: key) else { return }
        Activities.shared.post(alert)
        if alert.kind == .lowBattery {
            saidLow = .now
            Self.hideSystemWarning()
        }
    }

    /// macOS has warned of a low battery: the notch says so, unless it just has, in its place.
    private func warned() {
        guard IOPSGetBatteryWarningLevel() != kIOPSLowBatteryWarningNone, let now = Self.read(), !now.onPower,
            UserDefaults.standard.bool(forKey: Preferences.activityLowBattery)
        else { return }
        if saidLow.map({ Date.now.timeIntervalSince($0) > 120 }) ?? true {
            saidLow = .now
            Activities.shared.post(Self.lowBattery(now))
        }
        Self.hideSystemWarning()
    }

    /// Control Center's own Low Battery notification, taken away as it shows, while the notch is on.
    private static func hideSystemWarning() {
        guard UserDefaults.standard.bool(forKey: Preferences.notchEnabled) else { return }
        let center = URL(fileURLWithPath: "/System/Library/CoreServices/ControlCenter.app")
        SystemNotices.close(
            from: SystemNotices.name(of: center), saying: [SystemNotices.words("Low Battery", table: "Battery", of: center)])
    }

    /// What's worth saying about the battery going from one reading to the next: plugged in, or
    /// running down past a warning.
    static func alert(from old: Reading, to new: Reading, lowPower: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled) -> NotchAlert? {
        let level = BatteryLevel(percent: new.percent, charging: new.charging, lowPower: lowPower)
        if new.onPower, !old.onPower {
            let title = new.charging ? "Charging" : "Plugged In"
            return NotchAlert(kind: .charging, content: .battery(title: title, level: level), spoken: "\(title), \(new.percent) percent")
        }
        if !new.onPower, warnings.contains(where: { new.percent <= $0 && old.percent > $0 }) {
            return lowBattery(new, lowPower: lowPower)
        }
        return nil
    }

    static func lowBattery(_ reading: Reading, lowPower: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled) -> NotchAlert {
        let level = BatteryLevel(percent: reading.percent, charging: reading.charging, lowPower: lowPower)
        return NotchAlert(
            kind: .lowBattery, content: .battery(title: "Low Battery", level: level), spoken: "Low battery, \(reading.percent) percent",
            seconds: 4)
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
