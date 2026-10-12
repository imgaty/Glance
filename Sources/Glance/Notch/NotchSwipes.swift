//
//  NotchSwipes.swift
//  Glance
//
//  Created by Gaty on 12/10/2026.
//

import AppKit

/// Three fingers sideways on the open notch turn its page, instead of moving to another desktop.
/// macOS keeps that swipe for itself and gives apps no word of it, so it's caught on its way to the
/// Dock: a tap on the session's events sees the Dock's swipe events go by, and keeps back the ones
/// of a swipe that starts on the open notch. Anywhere else, every swipe goes through untouched.
/// It needs Accessibility, as any tap that holds events back does; without it, Shift and a scroll
/// still turn the page.
///
/// The tap sees every trackpad gesture on the Mac, so it runs on a thread of its own: whatever
/// Glance is doing, no swipe or scroll anywhere waits for it.
///
/// The Dock's swipe events and their fields aren't documented; their numbers are those macOS 26
/// and 27 use, as the open source iss (github.com/joshuarli/iss) found them.
final class NotchSwipes: @unchecked Sendable {
    static let shared = NotchSwipes()

    /// A swipe on the notch: toward the page on the right, or the left.
    @MainActor var onSwipe: ((_ right: Bool) -> Void)?

    private let lock = NSLock()
    /// Where each open notch takes swipes, in the session's points (from the top left of the main
    /// display), set by the notches as they open and close.
    private var regions: [ObjectIdentifier: CGRect] = [:]
    private var thread: Thread?
    private var tap: CFMachPort?
    /// On the tap's thread only: a swipe on the notch is under way, and whether it has turned the
    /// page yet.
    private var tracking = false
    private var fired = false

    private static let typeField = CGEventField(rawValue: 55)!
    private static let hidTypeField = CGEventField(rawValue: 110)!
    private static let motionField = CGEventField(rawValue: 123)!
    private static let progressField = CGEventField(rawValue: 124)!
    private static let velocityXField = CGEventField(rawValue: 129)!
    private static let velocityYField = CGEventField(rawValue: 130)!
    private static let phaseField = CGEventField(rawValue: 132)!
    private static let gestureType: Int64 = 29
    private static let dockType: Int64 = 30
    private static let dockSwipe: Int64 = 23
    private static let horizontal: Int64 = 1
    private static let began: Int64 = 1, changed: Int64 = 2, ended: Int64 = 4, cancelled: Int64 = 8
    /// macOS 27 reports a swipe's direction the other way round from 26, and wants the Dock to see
    /// the end of every swipe.
    private static let isTwentySeven = ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27

    /// Taps once Accessibility is allowed; asked again each time the notch opens, so allowing it
    /// takes effect without a restart.
    @MainActor func start() {
        lock.lock()
        defer { lock.unlock() }
        guard thread == nil, AXIsProcessTrusted() else { return }
        let thread = Thread { [self] in run() }
        thread.name = "Glance notch swipes"
        thread.qualityOfService = .userInteractive
        self.thread = thread
        thread.start()
    }

    /// Where a notch takes swipes while it's open, in AppKit's screen points; nil once it closes.
    @MainActor func set(_ zone: CGRect?, for owner: AnyObject) {
        let height = NSScreen.screens.first?.frame.height ?? 0
        let region = zone.map { CGRect(x: $0.minX, y: height - $0.maxY, width: $0.width, height: $0.height) }
        lock.lock()
        regions[ObjectIdentifier(owner)] = region
        lock.unlock()
    }

    private func run() {
        let mask = CGEventMask(1 << Self.gestureType) | CGEventMask(1 << Self.dockType)
        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask,
                callback: notchSwipesCallback, userInfo: nil)
        else {
            // Not allowed after all: asked again next time.
            lock.lock()
            thread = nil
            lock.unlock()
            return
        }
        lock.lock()
        self.tap = tap
        lock.unlock()
        CFRunLoopAddSource(CFRunLoopGetCurrent(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        CFRunLoopRun()
    }

    private func claims(_ point: CGPoint) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return regions.values.contains { $0.contains(point) }
    }

    /// Whether a swipe goes toward the desktop, or page, on the right.
    private static func isRight(_ value: Double) -> Bool {
        isTwentySeven ? value < 0 : value > 0
    }

    private func turn(right: Bool) {
        DispatchQueue.main.async { MainActor.assumeIsolated { NotchSwipes.shared.onSwipe?(right) } }
    }

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> CGEvent? {
        // Turned off for being slow, or by the system: back on, unless Accessibility was taken away.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            tracking = false
            lock.lock()
            let tap = tap
            lock.unlock()
            if let tap, AXIsProcessTrusted() { CGEvent.tapEnable(tap: tap, enable: true) }
            return event
        }
        let kind = event.getIntegerValueField(Self.typeField)
        if kind == Self.dockType, event.getIntegerValueField(Self.hidTypeField) == Self.dockSwipe,
            event.getIntegerValueField(Self.motionField) == Self.horizontal
        {
            switch event.getIntegerValueField(Self.phaseField) {
            case Self.began:
                // Decided once, where the swipe starts: on the open notch, it's the notch's.
                tracking = CGEvent(source: nil).map { claims($0.location) } ?? false
                fired = false
                return tracking ? nil : event
            case Self.changed where tracking:
                let progress = event.getDoubleValueField(Self.progressField)
                if !fired, progress != 0 {
                    fired = true
                    turn(right: Self.isRight(progress))
                }
                return nil
            case Self.ended where tracking:
                if !fired {
                    let velocity = event.getDoubleValueField(Self.velocityXField)
                    if velocity != 0 { turn(right: Self.isRight(velocity)) }
                }
                tracking = false
                fired = false
                guard Self.isTwentySeven else { return nil }
                // Its end, made still, so the Dock closes the swipe without moving anywhere.
                event.setDoubleValueField(Self.velocityXField, value: 0)
                event.setDoubleValueField(Self.velocityYField, value: 0)
                event.setDoubleValueField(Self.progressField, value: 0)
                return event
            case Self.cancelled where tracking:
                tracking = false
                return nil
            default:
                return tracking ? nil : event
            }
        }
        // The gesture events that go along with a swipe on the notch.
        if kind == Self.gestureType, tracking { return nil }
        return event
    }
}

/// Called on the tap's own thread.
private func notchSwipesCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    NotchSwipes.shared.handle(type, event).map { Unmanaged.passUnretained($0) }
}
