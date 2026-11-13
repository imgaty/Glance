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
        case compact([Activity], title: Bool)
        case announcement(String, extended: Bool)
        case expanded(NotchPage, Activity?, stage: Int, available: Bool)
    }

    private var activityPresentation: Presentation {
        if collapsed || entering { return .hardware }
        if state == .open {
            return .expanded(page, expanded, stage: activityStage, available: !expandedGone)
        }
        if let alert { return .announcement(String(describing: alert.id), extended: alertExtended) }
        let shown = Array(activities.prefix(2))
        return shown.isEmpty ? .hardware : .compact(shown, title: pop)
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
    func changeActivityPresentation(animation: Animation? = IslandMotion.open, _ changes: () -> Void) {
        let before = activityPresentation
        let atHousing = before == .hardware && metrics.bodyWidth == closedSize.width && metrics.height == closedSize.height && bubbleReach == 0
        let hadActivity = !activities.isEmpty || alert != nil || expanded != nil
        let reduced = activityReducesMotion ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        withAnimation(reduced ? nil : animation, changes)
        guard before != activityPresentation,
            hadActivity || !activities.isEmpty || alert != nil || expanded != nil
        else { return }

        let wasFolding = activityFolded
        activityTransitionTask?.cancel()
        activityTransitionTask = nil
        advanceActivityTransition()
        let request = activityTransitionID

        // Reduced motion keeps the final geometry and uses the content's existing opacity change.
        // An empty housing has already reached the midpoint, so its first activity opens directly.
        guard !reduced, animation != nil, !collapsed, !entering,
            !atHousing || wasFolding
        else {
            var still = Transaction(animation: nil)
            still.disablesAnimations = reduced || animation == nil
            withTransaction(still) {
                activityFolded = false
                bubbleReach = 0
                bubbleMerged = state == .open
                if state != .open { openedFromBubble = false }
            }
            return
        }

        withAnimation(Self.activityClosingSpring) {
            activityFolded = true
            bubbleMerged = true
            bubbleReach = 0
            hoveredButton = nil
            pressedAlertButton = nil
        }
        activityTransitionTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(Self.activityFoldDuration / max(NotchMotion.pace, 0.01))) } catch { return }
            guard let self, !Task.isCancelled, self.activityTransitionID == request else { return }
            // Read the current destination, never a captured payload that may have ended meanwhile.
            let reduced = self.activityReducesMotion ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            withAnimation(reduced ? nil : NotchMotion.spring(response: 0.5, dampingFraction: 0.68, reduced: false)) {
                self.activityFolded = false
                self.bubbleMerged = self.state == .open
                if self.state != .open { self.openedFromBubble = false }
            }
            self.activityTransitionTask = nil
        }
    }

    /// Teardown invalidates the delayed opening as well as cancelling its sleep.
    func cancelActivityTransition() {
        activityTransitionTask?.cancel()
        activityTransitionTask = nil
        advanceActivityTransition()
        activityFolded = false
    }

    static let activityFoldDuration = 0.38
    private static var activityClosingSpring: Animation {
        .spring(response: 0.3, dampingFraction: 0.7).paced
    }
}
