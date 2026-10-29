//
//  NotchSpace.swift
//  Glance
//
//  Created by Gaty on 11/10/2026.
//

import AppKit

/// A layer of its own above every Space, which swiping between desktops and full-screen apps leaves
/// in place, as it does the menu bar. A window that only joins all Spaces still slides out with the
/// old one and back in with the new. macOS only makes such a layer through WindowServer's private
/// Space calls, as other notch apps do; without them, the notch just keeps sliding.
@MainActor
enum NotchSpace {
    static func add(_ window: NSWindow) {
        guard let calls, let space else { return }
        calls.add(calls.connection(), [window.windowNumber] as CFArray, [space] as CFArray)
    }

    static func remove(_ window: NSWindow) {
        guard let calls, let space, window.windowNumber > 0 else { return }
        calls.remove(calls.connection(), [window.windowNumber] as CFArray, [space] as CFArray)
    }

    /// The displays, by their identifiers (see `NSScreen.notchID`), whose Space in view is a
    /// full-screen app's, as WindowServer keeps them; none, should it not say.
    static func fullScreenDisplays() -> Set<String> {
        guard let calls, let copySpaces, let displays = copySpaces(calls.connection())?.takeRetainedValue() as? [[String: Any]]
        else { return [] }
        return Set(
            displays.compactMap { display in
                guard let current = display["Current Space"] as? [String: Any], current["type"] as? Int == fullScreenKind else {
                    return nil
                }
                // With one set of Spaces for every display, it goes by "Main": the main display's.
                let id = display["Display Identifier"] as? String
                return id == "Main" ? NSScreen.screens.first?.notchID : id
            })
    }

    /// A full-screen app's Space, among WindowServer's kinds of Space.
    private static let fullScreenKind = 4

    private typealias CopySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private static let copySpaces: CopySpaces? = {
        guard let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY) else { return nil }
        return dlsym(skyLight, "SLSCopyManagedDisplaySpaces").map { unsafeBitCast($0, to: CopySpaces.self) }
    }()

    /// Made once, shown above every other Space, and kept for as long as Glance runs.
    private static let space: UInt64? = {
        guard let calls else { return nil }
        let connection = calls.connection()
        // 1: a plain Space; other kinds have Finder draw the desktop icons in it.
        let space = calls.create(connection, 1, nil)
        guard space != 0 else { return nil }
        calls.setLevel(connection, space, Int32.max)
        calls.show(connection, [space] as CFArray)
        return space
    }()

    private struct Calls {
        typealias Connection = @convention(c) () -> Int32
        typealias Create = @convention(c) (Int32, Int32, CFDictionary?) -> UInt64
        typealias SetLevel = @convention(c) (Int32, UInt64, Int32) -> Void
        typealias Show = @convention(c) (Int32, CFArray) -> Void
        typealias Windows = @convention(c) (Int32, CFArray, CFArray) -> Void

        let connection: Connection
        let create: Create
        let setLevel: SetLevel
        let show: Show
        let add: Windows
        let remove: Windows
    }

    private static let calls: Calls? = {
        guard let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY) else { return nil }
        func call<T>(_ name: String, _: T.Type) -> T? {
            dlsym(skyLight, name).map { unsafeBitCast($0, to: T.self) }
        }
        guard let connection = call("SLSMainConnectionID", Calls.Connection.self),
            let create = call("SLSSpaceCreate", Calls.Create.self),
            let setLevel = call("SLSSpaceSetAbsoluteLevel", Calls.SetLevel.self),
            let show = call("SLSShowSpaces", Calls.Show.self),
            let add = call("SLSAddWindowsToSpaces", Calls.Windows.self),
            let remove = call("SLSRemoveWindowsFromSpaces", Calls.Windows.self)
        else { return nil }
        return Calls(connection: connection, create: create, setLevel: setLevel, show: show, add: add, remove: remove)
    }()
}
