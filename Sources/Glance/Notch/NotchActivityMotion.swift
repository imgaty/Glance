//
//  NotchActivityMotion.swift
//  Glance
//
//  Created by Gaty on 13/11/2026.
//

import AppKit
import SwiftUI

/// One sequence for opening, closing and replacing an activity, independent of its payload.
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
    func changeActivityPresentation(animation: Animation? = IslandMotion.open, onCollapse: (() -> Void)? = nil, _ changes: () -> Void) {
        let before = activityPresentation
        let atHousing = before == .hardware && metrics.bodyWidth == closedSize.width && metrics.height == closedSize.height && bubbleReach == 0
        let hadActivity = !activities.isEmpty || alert != nil || expanded != nil
        let reduced = activityReducesMotion ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        // The first arrival has no later unfold to supply its expansion. Give that initial payload
        // the same opening motion as a destination revealed after reaching the housing.
        let updateAnimation = animation.map { atHousing ? Self.activityExpansionMotion : $0 }
        withAnimation(reduced ? nil : updateAnimation, changes)
        guard before != activityPresentation else { return }
        guard hadActivity || !activities.isEmpty || alert != nil || expanded != nil else {
            onCollapse?()
            return
        }

        let wasFolding = activityFolded
        activityTransitionTask?.cancel()
        activityTransitionTask = nil
        advanceActivityTransition()
        let request = activityTransitionID

        // Reduced motion keeps the final geometry and its controls available without an excursion.
        guard !reduced, animation != nil, !collapsed, !entering else {
            var still = Transaction(animation: nil)
            still.disablesAnimations = true
            withTransaction(still) {
                activityFolded = false
                activityOpening = false
                restoreActivityDestination()
            }
            onCollapse?()
            return
        }

        // An empty housing is already the midpoint. Its first activity only needs the opening leg.
        let folds = !atHousing || wasFolding
        let clock = ContinuousClock()
        let pace = max(NotchMotion.pace, 0.01)
        let started = clock.now
        let foldDeadline = started + .seconds(Self.activityFoldDuration / pace)
        withAnimation(folds ? Self.activityClosingMotion : Self.activityExpansionMotion) {
            activityFolded = folds
            activityOpening = !folds
            bubbleMerged = folds || state == .open
            bubbleReach = 0
            hoveredButton = nil
            pressedAlertButton = nil
        }
        if !folds { onCollapse?() }
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
                withAnimation(reduced ? nil : Self.activityExpansionMotion) {
                    self.activityOpening = !reduced && self.activityPresentation != .hardware
                    self.activityFolded = false
                    self.restoreActivityDestination()
                }
            }
            // A target change is not yet a visible button. Keep input out until the reveal has
            // reached its readable part, while Escape and destination navigation remain available.
            if self?.activityOpening == true {
                do { try await clock.sleep(until: revealStarted + .seconds(Self.activityControlDelay / pace), tolerance: .zero) } catch { return }
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

    /// Teardown invalidates the delayed opening as well as cancelling its sleep.
    func cancelActivityTransition() {
        activityTransitionTask?.cancel()
        activityTransitionTask = nil
        advanceActivityTransition()
        activityFolded = false
        activityOpening = false
        restoreActivityDestination()
    }

    private var activityMotionReduced: Bool {
        activityReducesMotion ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    static let activityControlDelay = NotchMotion.expandDuration
    static let activityFoldDuration = NotchMotion.foldDuration
    private static var activityClosingMotion: Animation { NotchMotion.fold }
    static var activityExpansionMotion: Animation { NotchMotion.expand }
}
