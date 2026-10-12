//
//  Shortcuts.swift
//  Glance
//
//  Created by Gaty on 12/10/2026.
//

import AppKit
import Carbon.HIToolbox

/// Glance's keyboard shortcuts, which work from any app, ahead of the app's own shortcuts. They're
/// the system's hotkeys, which need no permission and catch only their own keys. Each can be
/// changed in Settings, as System Settings lets any shortcut be.
@MainActor
final class Shortcuts: ObservableObject {
    static let shared = Shortcuts()

    enum Action: UInt32, CaseIterable {
        /// Opens the notch with the player.
        case music = 1
        /// Opens the notch with the tray.
        case tray = 2

        var title: String {
            switch self {
            case .music: "Open the player"
            case .tray: "Open the tray"
            }
        }

        /// The shortcut out of the box.
        var standard: KeyCombo {
            switch self {
            case .music: KeyCombo(keyCode: UInt32(kVK_ANSI_1), modifiers: UInt32(shiftKey | cmdKey), key: "1")
            case .tray: KeyCombo(keyCode: UInt32(kVK_ANSI_2), modifiers: UInt32(shiftKey | cmdKey), key: "2")
            }
        }

        var defaultsKey: String {
            switch self {
            case .music: Preferences.shortcutMusic
            case .tray: Preferences.shortcutTray
            }
        }

        /// The tray's shortcut is only there while the tray is.
        var isAvailable: Bool { self != .tray || Tray.isOn }
    }

    /// Glance's mark on its hotkeys, so the ones it gets back are known as its own: "GLNC".
    static let signature: OSType = "GLNC".utf8.reduce(0) { $0 << 8 | OSType($1) }

    /// Each action's shortcut, as chosen, or out of the box.
    @Published private(set) var combos: [Action: KeyCombo] = [:]
    /// Those another app already holds, which Glance couldn't take.
    @Published private(set) var taken: Set<Action> = []

    var onAction: ((Action) -> Void)?
    private var hotKeys: [Action: EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?

    private init() {
        for action in Action.allCases {
            combos[action] =
                UserDefaults.standard.data(forKey: action.defaultsKey)
                .flatMap { try? JSONDecoder().decode(KeyCombo.self, from: $0) } ?? action.standard
        }
    }

    /// Starts listening for every shortcut.
    func register() {
        if handler == nil {
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
        }
        Action.allCases.forEach(take)
    }

    /// A new shortcut, kept and in use at once.
    func set(_ combo: KeyCombo, for action: Action) {
        combos[action] = combo
        if combo == action.standard {
            UserDefaults.standard.removeObject(forKey: action.defaultsKey)
        } else if let data = try? JSONEncoder().encode(combo) {
            UserDefaults.standard.set(data, forKey: action.defaultsKey)
        }
        take(action)
    }

    /// While a new shortcut is typed, the old ones let every key through to be recorded.
    func pause() {
        for (action, hotKey) in hotKeys {
            UnregisterEventHotKey(hotKey)
            hotKeys[action] = nil
        }
    }

    private func take(_ action: Action) {
        if let held = hotKeys.removeValue(forKey: action) { UnregisterEventHotKey(held) }
        guard action.isAvailable, let combo = combos[action] else {
            taken.remove(action)
            return
        }
        var hotKey: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: action.rawValue)
        if RegisterEventHotKey(combo.keyCode, combo.modifiers, id, GetApplicationEventTarget(), 0, &hotKey) == noErr, let hotKey {
            hotKeys[action] = hotKey
            taken.remove(action)
        } else {
            taken.insert(action)
        }
    }
}

/// A key and the modifiers held with it: where the key is on the keyboard, the modifiers as the
/// system's hotkeys take them, and the key's name as the keyboard shows it.
struct KeyCombo: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var key: String

    /// As Apple writes a shortcut: the modifiers in the order ⌃⌥⇧⌘, then the key.
    var symbols: String {
        let marks: [(Int, String)] = [(controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘")]
        return marks.filter { modifiers & UInt32($0.0) != 0 }.map(\.1).joined() + key
    }

    /// A shortcut for any app holds Command, Option or Control; Shift alone would take a key away
    /// from typing.
    var isValid: Bool { modifiers & UInt32(cmdKey | optionKey | controlKey) != 0 }

    init(keyCode: UInt32, modifiers: UInt32, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    /// A key pressed while a shortcut is being recorded.
    init(event: NSEvent) {
        self.init(
            keyCode: UInt32(event.keyCode), modifiers: Self.modifiers(of: event.modifierFlags),
            key: Self.name(ofKey: event.keyCode))
    }

    static func modifiers(of flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers = 0
        if flags.contains(.control) { modifiers |= controlKey }
        if flags.contains(.option) { modifiers |= optionKey }
        if flags.contains(.shift) { modifiers |= shiftKey }
        if flags.contains(.command) { modifiers |= cmdKey }
        return UInt32(modifiers)
    }

    /// The key as it's printed on the keyboard in use, whatever the modifiers would make it type.
    static func name(ofKey keyCode: UInt16) -> String {
        if let special = specialKeys[Int(keyCode)] { return special }
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
            let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return "?" }
        let layout = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue()
        var deadKeys: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = CFDataGetBytePtr(layout).withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) {
            UCKeyTranslate(
                $0, keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeys, characters.count, &length, &characters)
        }
        guard status == noErr, length > 0 else { return "?" }
        return String(utf16CodeUnits: characters, count: length).uppercased()
    }

    /// Keys that print no character, by the names macOS's menus give them.
    private static let specialKeys: [Int: String] = [
        kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦", kVK_Escape: "⎋",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_Home: "↖", kVK_End: "↘",
        kVK_PageUp: "⇞", kVK_PageDown: "⇟", kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
        kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]
}
