//
//  NotchActivityMotion.swift
//  Glance
//
//  Created by Gaty on 13/11/2026.
//

import AppKit
import SwiftUI

/// Activity presentation changes pass through the housing; tools retain direct navigation.
extension NotchModel {
    private enum Presentation: Equatable {
        case hardware
        case compact([Activity], transfer: String?, title: Bool)
        case announcement(String, extended: Bool)
        case expanded(NotchPage, Activity?, transfer: String?, stage: Int, available: Bool)
    }

    private var activityPresentation: Presentation {
        if collapsed || entering { return .hardware }
        if state == .open {
            return .expanded(page, expanded, transfer: expanded == .airdrop ? airdrop?.id : nil, stage: activityStage, available: !expandedGone)
        }
        if let alert { return .announcement(String(describing: alert.id), extended: alertExtended) }
        let shown = Array(activities.prefix(2))
        return shown.isEmpty ? .hardware : .compact(shown, transfer: shown.contains(.airdrop) ? airdrop?.id : nil, title: pop)
    }

    /// Layout-changing phases, without their running timestamps, progress or error messages.
    private var activityStage: Int {
        if expanded == .call { return call?.rings == true ? 0 : call?.isConnected == true ? 2 : 1 }
        if expanded == .screenRecording {
            switch screenRecording {
            case .countdown: return 0
            case .recording: return 1
            case .saving: return 2
            case .saved: return 3
            case nil: return 4
            }
        }
        return 0
    }

    /// Payload updates remain immediate, so a later input always acts on the latest state. Only a
    /// change of presentation moves the shell; elapsed time, progress and button feedback do not.
    /// It goes straight when told to (the notch's own activity opening or closing), and otherwise
    /// folds to the housing first, as the Mac's island does when what it shows changes hands.
    func changeActivityPresentation(
        animation: Animation? = IslandMotion.open, opensDirectly: Bool = false,
        onCollapse: (() -> Void)? = nil, _ changes: () -> Void
    ) {
        let before = activityPresentation
        let wasOpen = state == .open
        let openHeight = metrics.height
        let atHousing = before == .hardware && metrics.bodyWidth == closedSize.width && metrics.height == closedSize.height && bubbleReach == 0
        let hadActivity = !activities.isEmpty || alert != nil || expanded != nil
        let reduced = activityReducesMotion ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let folds = !opensDirectly && (!atHousing || activityFolded)
        let clock = ContinuousClock()
        let pace = max(NotchMotion.pace, 0.01)
        let started = clock.now
        let foldDeadline = started + .seconds(Self.activityFoldDuration / pace)
        var request: UInt?
        var feedbackAtCommit = false

        // State and its first geometry phase must share one transaction. Publishing the open
        // destination before its fold starts a competing expansion, even within one run-loop turn.
        let firstMotion = folds ? Self.activityClosingMotion : Self.activityExpansionMotion
        var transaction = Transaction(animation: reduced ? nil : animation.map { _ in firstMotion })
        transaction.disablesAnimations = reduced || animation == nil
        withTransaction(transaction) {
            changes()
            guard before != activityPresentation else { return }
            feedbackAtCommit = true
            toolPresentation = false
            guard hadActivity || !activities.isEmpty || alert != nil || expanded != nil else { return }

            activityTransitionTask?.cancel()
            activityTransitionTask = nil
            advanceActivityTransition()
            if case .expanded = before, case .compact = activityPresentation {
                activityReturnsInline = true
            } else {
                activityReturnsInline = false
            }

            // Reduced motion keeps final geometry and controls available without an excursion.
            guard !reduced, animation != nil, !collapsed, !entering else {
                activityFolded = false
                activityOpening = false
                activityReturnsInline = false
                restoreActivityDestination()
                return
            }

            request = activityTransitionID
            feedbackAtCommit = !folds
            activityFolded = folds
            activityOpening = !folds
            // Into the notch with the fold, or taken in by the notch opening around it; one that
            // belongs beside the new shape stays in until the growth carrying it is under way.
            bubbleMerged = folds || (state == .open && !openedFromBubble) || bubbleRests
            bubbleReach = 0
            hoveredButton = nil
            pressedAlertButton = nil
        }
        // Feedback runs only after state and phase have committed, and may itself cancel the request.
        if feedbackAtCommit { onCollapse?() }
        guard let request, activityTransitionID == request else { return }
        let closes = wasOpen && state != .open
        if closes, !folds { settleArrival(from: openHeight, at: started) }
        activityTransitionTask = Task { @MainActor [weak self] in
            var revealStarted = started
            if folds {
                // Anchor the deadline to the animation, not to whenever this task first runs.
                // Animation joins cannot use the default wake-up coalescing tolerance.
                do { try await clock.sleep(until: foldDeadline, tolerance: .zero) } catch { return }
                guard let self, !Task.isCancelled, self.activityTransitionID == request else { return }
                // User-initiated opening gives its single tap at the housing, before expanding.
                // Automatic updates provide no callback and remain silent.
                onCollapse?()
                guard !Task.isCancelled, self.activityTransitionID == request else { return }
                // Read the destination afresh; a source may have ended while the shell was closing.
                let reduced = self.activityMotionReduced
                revealStarted = clock.now
                withAnimation(reduced ? nil : self.activityRevealMotion) {
                    self.activityOpening = !reduced && self.activityPresentation != .hardware
                    self.activityFolded = false
                    self.restoreActivityDestination(buds: !reduced)
                }
                if closes, !reduced { self.settleArrival(from: openHeight, at: revealStarted) }
            }
            guard let self else { return }
            // A bubble pinches off once the growth that carries it is under way.
            if self.bubbleMerged, self.bubbleRests {
                do { try await clock.sleep(until: revealStarted + .seconds(NotchMotion.budDelay / pace), tolerance: .zero) } catch { return }
                guard !Task.isCancelled, self.activityTransitionID == request else { return }
                withAnimation(self.activityMotionReduced ? nil : NotchMotion.island) { self.bubbleMerged = false }
            }
            // A target change is not yet a visible button. Keep input out until the reveal has
            // reached its readable part, while Escape and destination navigation remain available.
            if self.activityOpening {
                let delay = Self.activityControlDelay
                do { try await clock.sleep(until: revealStarted + .seconds(delay / pace), tolerance: .zero) } catch { return }
            }
            guard !Task.isCancelled, self.activityTransitionID == request else { return }
            self.activityOpening = false
            self.activityTransitionTask = nil
        }
    }

    /// A bubble belongs beside the notch once it settles: the second activity beside the compact,
    /// or the notch's own beside a view opened from the bubble, on the compact's row.
    var bubbleRests: Bool {
        guard second != nil else { return false }
        if state == .open { return openedFromBubble }
        return alert == nil && !collapsed && !entering && !switching && !(musicShown && pop)
    }

    /// Where it all rests: the bubble out where it belongs, or kept in a moment more to bud off.
    private func restoreActivityDestination(buds: Bool = false) {
        bubbleReach = 0
        bubbleMerged = (state == .open && !openedFromBubble) || (buds && bubbleRests)
        if state != .open { openedFromBubble = false }
    }

    /// The player and the tray open on the island's spring. Opened from the notch with music beside
    /// the camera, or nothing, they grow straight out of it, its end taking the bubble in at once;
    /// opened from the bubble, or over what isn't music, the notch first folds to the housing and
    /// the notch's own activity buds off beside the open player.
    func openTools(onOpen: (() -> Void)? = nil) {
        guard state != .open || activityControlsHidden else { return }
        let reduced = activityMotionReduced
        let origin = openedFromBubble
        let folds = !reduced && state != .open && !opensStraight && !collapsed
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) {
            cancelActivityTransition()
            toolPresentation = true
            openedFromBubble = origin
        }
        if !folds, !reduced { coverBubble() }
        let request = activityTransitionID
        onOpen?()
        guard activityTransitionID == request else { return }
        guard folds else {
            revealTools(reduced: reduced)
            return
        }
        withAnimation(NotchMotion.fold) {
            activityFolded = true
            bubbleMerged = true
            bubbleReach = 0
            pressed = false
            bubblePressed = false
            hoverPlace = nil
            bubbleHoverPlace = nil
        }
        let clock = ContinuousClock()
        let pace = max(NotchMotion.pace, 0.01)
        let deadline = clock.now + .seconds(Self.activityFoldDuration / pace)
        activityTransitionTask = Task { @MainActor [weak self] in
            do { try await clock.sleep(until: deadline, tolerance: .zero) } catch { return }
            guard let self, !Task.isCancelled, self.activityTransitionID == request else { return }
            let grows = clock.now
            self.revealTools(reduced: self.activityMotionReduced, buds: true)
            guard self.bubbleMerged, self.bubbleRests else {
                self.activityTransitionTask = nil
                return
            }
            do { try await clock.sleep(until: grows + .seconds(NotchMotion.budDelay / pace), tolerance: .zero) } catch { return }
            guard !Task.isCancelled, self.activityTransitionID == request else { return }
            withAnimation(self.activityMotionReduced ? nil : NotchMotion.island) { self.bubbleMerged = false }
            self.activityTransitionTask = nil
        }
    }

    private func revealTools(reduced: Bool, buds: Bool = false) {
        withAnimation(reduced ? nil : ToolMotion.open) {
            state = .open
            activityFolded = false
            pressed = false
            bubblePressed = false
            hoverPlace = nil
            bubbleHoverPlace = nil
            pop = false
            bubbleMerged = !openedFromBubble || (buds && bubbleRests)
            bubbleReach = 0
        }
    }

    /// A tool closes straight back to its compact, the bubble budding off the shrinking end; one
    /// opened from the bubble folds to the housing first, the notch's own activity growing back
    /// and the bubble budding off it after.
    func closeTools() {
        let reduced = activityMotionReduced
        let intoBubble = openedFromBubble && second != nil && alert == nil && !folded
        let folds = intoBubble && !reduced
        let openHeight = metrics.height
        let clock = ContinuousClock()
        let pace = max(NotchMotion.pace, 0.01)
        let started = clock.now
        withAnimation(reduced ? nil : folds ? NotchMotion.fold : ToolMotion.close) {
            cancelActivityTransition()
            toolPresentation = true
            state = .closed
            stretch = 0
            lean = 0
            pageStretch = 0
            bubbleReach = 0
            activityFolded = folds
            openedFromBubble = false
            bubbleMerged = !reduced && second != nil
        }
        guard !reduced else { return }
        if !folds { settleArrival(from: openHeight, at: started) }
        guard folds || (bubbleMerged && bubbleRests) else { return }
        let request = activityTransitionID
        activityTransitionTask = Task { @MainActor [weak self] in
            var grows = started
            if folds {
                do { try await clock.sleep(until: started + .seconds(Self.activityFoldDuration / pace), tolerance: .zero) } catch { return }
                guard let self, !Task.isCancelled, self.activityTransitionID == request else { return }
                grows = clock.now
                withAnimation(self.activityMotionReduced ? nil : NotchMotion.island) { self.activityFolded = false }
                self.settleArrival(from: openHeight, at: grows)
            }
            guard let self, self.bubbleMerged, self.bubbleRests else {
                self?.activityTransitionTask = nil
                return
            }
            do { try await clock.sleep(until: grows + .seconds(NotchMotion.budDelay / pace), tolerance: .zero) } catch { return }
            guard !Task.isCancelled, self.activityTransitionID == request else { return }
            withAnimation(self.activityMotionReduced ? nil : NotchMotion.island) { self.restoreActivityDestination() }
            self.activityTransitionTask = nil
        }
    }

    /// Teardown invalidates the delayed opening as well as cancelling its sleep.
    func cancelActivityTransition() {
        activityTransitionTask?.cancel()
        activityTransitionTask = nil
        advanceActivityTransition()
        toolPresentation = false
        activityFolded = false
        activityOpening = false
        activityReturnsInline = false
        restoreActivityDestination()
    }

    private var activityMotionReduced: Bool {
        activityReducesMotion ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Kept after the reveal so content that explicitly animates its return shares the shell's
    /// curve. The next presentation change chooses anew; ordinary progress leaves it alone.
    var activityRevealMotion: Animation {
        if toolPresentation || (state == .open && expanded == nil) { return ToolMotion.open }
        if activityReturnsInline, case .compact = activityPresentation { return NotchMotion.inlineReturn }
        return Self.activityExpansionMotion
    }

    static let activityControlDelay = NotchMotion.revealDuration
    static let activityFoldDuration = NotchMotion.foldDuration
    private static var activityClosingMotion: Animation { NotchMotion.fold }
    static var activityExpansionMotion: Animation { NotchMotion.expand }
}

private struct IslandExpansionMotionKey: EnvironmentKey {
    static var defaultValue: Animation { NotchMotion.expand }
}

extension EnvironmentValues {
    var islandExpansionMotion: Animation {
        get { self[IslandExpansionMotionKey.self] }
        set { self[IslandExpansionMotionKey.self] = newValue }
    }
}
