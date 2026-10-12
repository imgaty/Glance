//
//  Shortcuts.swift
//  Glance
//
//  Created by Gaty on 12/10/2026.
//

import AppKit
import Carbon.HIToolbox

/// Glance's keyboard shortcuts, which work from any app: Control-Option-Command and a number, a
/// combination apps leave alone, so none loses its own. They're the system's hotkeys, which need no
/// permission and catch only these keys.
@MainActor
final class Shortcuts {
    static let shared = Shortcuts()

    enum Action: UInt32, CaseIterable {
        /// The player.
        case music = 1

        /// The key it's on, with Control, Option and Command.
        var key: Int {
            switch self {
            case .music: kVK_ANSI_1
            }
        }

        /// As menus write it.
        var symbols: String { "⌃⌥⌘\(rawValue)" }
    }

    static let modifiers = UInt32(controlKey | optionKey | cmdKey)
    /// Glance's mark on its hotkeys, so the ones it gets back are known as its own: "GLNC".
    static let signature: OSType = "GLNC".utf8.reduce(0) { $0 << 8 | OSType($1) }

    var onAction: ((Action) -> Void)?
    private var hotKeys: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?

    private init() {}

    /// Starts listening for every shortcut; any that another app already holds is skipped.
    func register() {
        guard handler == nil else { return }
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ in
                var id = EventHotKeyID()
                let status = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &id)
                guard status == noErr, id.signature == Shortcuts.signature, let action = Action(rawValue: id.id) else {
                    return OSStatus(eventNotHandledErr)
                }
                // The application's own target, so on the main thread.
                MainActor.assumeIsolated { Shortcuts.shared.onAction?(action) }
                return noErr
            }, 1, &pressed, nil, &handler)
        for action in Action.allCases {
            var hotKey: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: action.rawValue)
            if RegisterEventHotKey(UInt32(action.key), Self.modifiers, id, GetApplicationEventTarget(), 0, &hotKey) == noErr,
                let hotKey
            {
                hotKeys.append(hotKey)
            }
        }
    }
}
