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
    /// change of presentation folds the shell; elapsed time, progress and button feedback do not.
    func changeActivityPresentation(
        animation: Animation? = IslandMotion.open,
        onCollapse: (() -> Void)? = nil, _ changes: () -> Void
    ) {
        let before = activityPresentation
        let atHousing = before == .hardware && metrics.bodyWidth == closedSize.width && metrics.height == closedSize.height && bubbleReach == 0
        let hadActivity = !activities.isEmpty || alert != nil || expanded != nil
        let reduced = activityReducesMotion ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let folds = !atHousing || activityFolded
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
            bubbleMerged = folds || state == .open
            bubbleReach = 0
            hoveredButton = nil
            pressedAlertButton = nil
        }
        // Feedback runs only after state and phase have committed, and may itself cancel the request.
        if feedbackAtCommit { onCollapse?() }
        guard let request, activityTransitionID == request else { return }
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
                    self.restoreActivityDestination()
                }
            }
            // A target change is not yet a visible button. Keep input out until the reveal has
            // reached its readable part, while Escape and destination navigation remain available.
            if self?.activityOpening == true {
                let delay = Self.activityControlDelay
                do { try await clock.sleep(until: revealStarted + .seconds(delay / pace), tolerance: .zero) } catch { return }
            }
            guard let self, !Task.isCancelled, self.activityTransitionID == request else { return }
            self.activityOpening = false
            self.activityTransitionTask = nil
        }
    }

    private func restoreActivityDestination() {
        bubbleReach = 0
        bubbleMerged = state == .open
        if state != .open { openedFromBubble = false }
    }

    /// Tool opening keeps the old direct spring, with a short merge before opening beside a
    /// detached activity. The task controls bubble choreography, never the tool input gate.
    func openTools(onOpen: (() -> Void)? = nil) {
        guard state != .open || activityControlsHidden else { return }
        let reduced = activityMotionReduced
        let origin = openedFromBubble
        let merges = second != nil && !origin && state != .open && !reduced
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) {
            cancelActivityTransition()
            toolPresentation = true
            openedFromBubble = origin
            bubbleReach = origin && !reduced ? bubbleSpan : 0
        }
        let request = activityTransitionID
        if merges {
            withAnimation(ToolMotion.close) { bubbleMerged = true }
        }
        onOpen?()
        guard activityTransitionID == request else { return }
        guard merges else {
            revealTools(reduced: reduced)
            return
        }
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(0.08 / max(NotchMotion.pace, 0.01))
        activityTransitionTask = Task { @MainActor [weak self] in
            do { try await clock.sleep(until: deadline, tolerance: .zero) } catch { return }
            guard let self, !Task.isCancelled, self.activityTransitionID == request else { return }
            self.revealTools(reduced: self.activityMotionReduced)
            self.activityTransitionTask = nil
        }
    }

    private func revealTools(reduced: Bool) {
        withAnimation(reduced ? nil : ToolMotion.open) {
            state = .open
            pressed = false
            bubblePressed = false
            proximity = 0
            pop = false
            bubbleMerged = true
            bubbleReach = 0
        }
    }

    /// A tool closes directly to compact. A merged bubble buds off after 250 ms; a detached
    /// origin reaches back to its bubble and retracts its connecting end after 380 ms.
    func closeTools() {
        let reduced = activityMotionReduced
        let intoBubble = openedFromBubble && second != nil && alert == nil && !folded
        let merged = bubbleMerged && second != nil && !intoBubble && !reduced
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds((intoBubble ? 0.38 : 0.25) / max(NotchMotion.pace, 0.01))
        withAnimation(reduced ? nil : ToolMotion.close) {
            cancelActivityTransition()
            toolPresentation = true
            state = .closed
            stretch = 0
            lean = 0
            pageStretch = 0
            bubbleMerged = merged
            bubbleReach = intoBubble && !reduced ? bubbleSpan : 0
            openedFromBubble = intoBubble && !reduced
        }
        guard !reduced, intoBubble || merged else { return }
        let request = activityTransitionID
        activityTransitionTask = Task { @MainActor [weak self] in
            do { try await clock.sleep(until: deadline, tolerance: .zero) } catch { return }
            guard let self, !Task.isCancelled, self.activityTransitionID == request else { return }
            withAnimation(self.activityMotionReduced ? nil : intoBubble ? ToolMotion.close : ToolMotion.bubble) {
                self.restoreActivityDestination()
            }
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

    static let activityControlDelay = NotchMotion.expandDuration
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
