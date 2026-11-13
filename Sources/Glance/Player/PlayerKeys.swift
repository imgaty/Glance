//
//  PlayerKeys.swift
//  Glance
//
//  Created by Gaty on 04/11/2026.
//

import AppKit
import Carbon.HIToolbox
import SwiftUI

/// The open player's controls, in the order Tab goes through them: as they read, the cover and the
/// waveform, then the lyrics' lines, then the progress bar, then the row of buttons. An activity's
/// own view has its buttons instead.
enum PlayerControl: Hashable {
    case cover, lyrics, line, position, left, previous, playPause, next, right
    case activityFirst, activitySecond, activityThird, activityFourth

    var onActivity: Bool { [.activityFirst, .activitySecond, .activityThird, .activityFourth].contains(self) }
}

/// Where the keyboard is in the open player. The notch takes every key typed while it has the
/// keyboard, so it's the notch that moves the ring from control to control, whatever the Mac's
/// Keyboard navigation setting is, and presses the control the ring is on.
@MainActor
@Observable
final class PlayerKeys {
    /// What a key does on the player.
    enum Outcome: Equatable {
        case moved, pressed, playPause, previous, next, seekBack, seekAhead
        /// Up or down, with the ring on Sound Output.
        case louder, quieter
        /// Up or down otherwise: from the player to a live activity's own view, and back.
        case activityBefore, activityAfter
        /// The key has no use here: the alert sound.
        case none
    }

    /// How far the arrows move through the song, with the ring on the progress bar.
    static let seekStep = 10.0

    /// What can be used now, in the order Tab goes through them, as the player says. The ring leaves
    /// a control that can't be used any more.
    var usable: [PlayerControl] = [] {
        didSet {
            if let focus, !focus.onActivity, !usable.contains(focus) { self.focus = nil }
        }
    }
    /// The player's control that's Sound Output, if one is: up and down turn the sound up and down.
    var soundControl: PlayerControl?
    /// The lyrics' lines are showing, with lines to go to.
    var hasLines = false
    /// The control with the ring around it. With none, the keys work the song.
    private(set) var focus: PlayerControl?
    /// Counts the presses: each new value presses the control with the ring.
    private(set) var presses = 0
    /// Counts the lines moved through, down or back up, with the ring on the lyrics' lines.
    private(set) var lineSteps = 0
    /// Where the control with the ring is, in the notch's own points, for what opens from it.
    var focusFrame: CGRect?
    /// Where something opening from a control goes on the screen, as the notch's window knows.
    var screenPoint: ((CGRect) -> CGPoint?)?

    /// Where Tab or Shift-Tab goes from a control: the next or the one before, and round from one
    /// end to the other. With none, Tab goes to the first and Shift-Tab to the last.
    static func step(_ controls: [PlayerControl], from focus: PlayerControl?, backward: Bool) -> PlayerControl? {
        guard !controls.isEmpty else { return nil }
        guard let focus, let index = controls.firstIndex(of: focus) else {
            return backward ? controls.last : controls.first
        }
        return controls[(index + (backward ? controls.count - 1 : 1)) % controls.count]
    }

    /// A key typed on the player, or on an activity's own view with the buttons given. Moves the ring
    /// if it's Tab; what else it does is for the notch to carry out.
    func typed(key: Int, shift: Bool, hasMedia: Bool, activity: [PlayerControl]? = nil) -> Outcome {
        let controls = activity ?? usable
        if let focus, !controls.contains(focus) { self.focus = nil }
        switch key {
        case kVK_Tab:
            guard let next = Self.step(activity ?? usable, from: focus, backward: shift) else { return .none }
            focus = next
            return .moved
        case kVK_Space, kVK_Return, kVK_ANSI_KeypadEnter:
            // The progress bar has nothing to press: Space there still plays or pauses.
            if let focus, focus != .position {
                presses += 1
                return .pressed
            }
            return key == kVK_Space && hasMedia && activity == nil ? .playPause : .none
        case kVK_LeftArrow:
            guard hasMedia, activity == nil else { return .none }
            return focus == .position ? .seekBack : .previous
        case kVK_RightArrow:
            guard hasMedia, activity == nil else { return .none }
            return focus == .position ? .seekAhead : .next
        case kVK_UpArrow, kVK_DownArrow:
            let down = key == kVK_DownArrow
            if focus == .line {
                lineSteps += down ? 1 : -1
                return .moved
            }
            if let focus, focus == soundControl { return down ? .quieter : .louder }
            return down ? .activityAfter : .activityBefore
        default:
            return .none
        }
    }

    /// The ring goes to a control: an activity's first button, as its view opens from the keyboard.
    func focus(on control: PlayerControl) {
        focus = control
    }

    /// The ring goes: a click, or the notch letting go of the keyboard.
    func clear() {
        focus = nil
    }
}

extension EnvironmentValues {
    @Entry var playerKeys: PlayerKeys? = nil
}

extension View {
    /// The ring around one of the player's controls while the keyboard is on it, as far outside the
    /// control as given. White, the one color that reads on all the notch's backgrounds.
    func keyRing(_ control: PlayerControl, in shape: some InsettableShape = Circle(), outset: CGSize = .zero) -> some View {
        modifier(KeyRing(control: control, shape: shape, outset: outset))
    }

    /// One of an activity's own buttons on the keyboard: the ring around it, what Space or Return
    /// does, and its name, said to VoiceOver as the ring reaches it.
    func keyControl(
        _ control: PlayerControl, in shape: some InsettableShape = Circle(), outset: CGSize = .zero, spoken: String, action: @escaping () -> Void
    ) -> some View {
        modifier(KeyControl(control: control, spoken: spoken, action: action)).keyRing(control, in: shape, outset: outset)
    }
}

private struct KeyControl: ViewModifier {
    let control: PlayerControl
    let spoken: String
    let action: () -> Void
    @Environment(\.playerKeys) private var keys
    @Environment(\.notchControls) private var shown
    @Environment(\.activityPreview) private var preview
    @Environment(\.isEnabled) private var enabled
    @Environment(\.notchOnScreen) private var onScreen

    func body(content: Content) -> some View {
        content
            .onChange(of: keys?.presses) {
                guard shown, enabled, !preview, keys?.focus == control else { return }
                action()
            }
            .onChange(of: keys?.focus, initial: true) {
                guard shown, enabled, !preview, onScreen, keys?.focus == control else { return }
                NSAccessibility.post(
                    element: NSApp as Any, notification: .announcementRequested,
                    userInfo: [.announcement: spoken, .priority: NSAccessibilityPriorityLevel.high.rawValue])
            }
    }
}

private struct KeyRing<RingShape: InsettableShape>: ViewModifier {
    let control: PlayerControl
    let shape: RingShape
    let outset: CGSize
    @Environment(\.playerKeys) private var keys
    @Environment(\.notchControls) private var shown
    @Environment(\.activityPreview) private var preview
    @Environment(\.isEnabled) private var enabled

    func body(content: Content) -> some View {
        content.overlay {
            if shown, enabled, !preview, keys?.focus == control {
                shape
                    .strokeBorder(.white, lineWidth: 2)
                    .padding(.horizontal, -outset.width)
                    .padding(.vertical, -outset.height)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .onGeometryChange(for: CGRect.self) {
                        $0.frame(in: .named(ControlFrames.space))
                    } action: {
                        keys?.focusFrame = $0
                    }
            }
        }
    }
}
