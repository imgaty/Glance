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
    func changeActivityPresentation(animation: Animation? = IslandMotion.open, _ changes: () -> Void) {
        let before = activityPresentation
        let atHousing = before == .hardware && metrics.bodyWidth == closedSize.width && metrics.height == closedSize.height && bubbleReach == 0
        let hadActivity = !activities.isEmpty || alert != nil || expanded != nil
        let reduced = activityReducesMotion ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        // The first arrival has no later unfold to supply its spring. Give that initial payload
        // the same opening motion as a destination revealed after the closing rebound.
        let updateAnimation = animation.map { atHousing ? Self.activityOpeningSpring : $0 }
        withAnimation(reduced ? nil : updateAnimation, changes)
        guard before != activityPresentation,
            hadActivity || !activities.isEmpty || alert != nil || expanded != nil
        else { return }

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
                activityHousingRebound = 0
                restoreActivityDestination()
            }
            return
        }

        // An empty housing is already the midpoint. Its first activity only needs the opening leg.
        let folds = !atHousing || wasFolding
        withAnimation(folds ? Self.activityClosingMotion : Self.activityOpeningSpring) {
            activityFolded = folds
            activityOpening = !folds
            activityHousingRebound = 0
            bubbleMerged = folds || state == .open
            bubbleReach = 0
            hoveredButton = nil
            pressedAlertButton = nil
        }
        activityTransitionTask = Task { @MainActor [weak self] in
            if folds {
                do { try await Task.sleep(for: .seconds(Self.activityLandingDuration / max(NotchMotion.pace, 0.01))) } catch { return }
                guard let self, !Task.isCancelled, self.activityTransitionID == request else { return }
                // A spring aimed inside the camera is clamped away. Rebound outward only after
                // reaching the hardware, with the same small displacement from every origin.
                if !self.activityMotionReduced {
                    withAnimation(Animation.easeOut(duration: Self.activityReboundDuration).paced) {
                        self.activityHousingRebound = 1
                    }
                    do { try await Task.sleep(for: .seconds(Self.activityReboundDuration / max(NotchMotion.pace, 0.01))) } catch { return }
                    guard !Task.isCancelled, self.activityTransitionID == request else { return }
                    withAnimation(self.activityMotionReduced ? nil : Animation.easeInOut(duration: Self.activitySettleDuration - 0.02).paced) {
                        self.activityHousingRebound = 0
                    }
                    if !self.activityMotionReduced {
                        do { try await Task.sleep(for: .seconds(Self.activitySettleDuration / max(NotchMotion.pace, 0.01))) } catch { return }
                        guard !Task.isCancelled, self.activityTransitionID == request else { return }
                    }
                }
                // Read the destination afresh; a source may have ended while the shell was closing.
                let reduced = self.activityMotionReduced
                withAnimation(reduced ? nil : Self.activityOpeningSpring) {
                    self.activityHousingRebound = 0
                    self.activityOpening = !reduced && self.activityPresentation != .hardware
                    self.activityFolded = false
                    self.restoreActivityDestination()
                }
            }
            // A target change is not yet a visible button. Keep input out until the reveal has
            // reached its readable part, while Escape and destination navigation remain available.
            if self?.activityOpening == true {
                do { try await Task.sleep(for: .seconds(Self.activityControlDelay / max(NotchMotion.pace, 0.01))) } catch { return }
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
        activityHousingRebound = 0
        restoreActivityDestination()
    }

    private var activityMotionReduced: Bool {
        activityReducesMotion ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    static let activityControlDelay = 0.44
    static let activityLandingDuration = 0.34
    static let activityReboundDuration = 0.12
    static let activitySettleDuration = 0.18
    static let activityFoldDuration = activityLandingDuration + activityReboundDuration + activitySettleDuration
    static let activityHousingSpread: CGFloat = 12
    static let activityHousingLift: CGFloat = 3
    private static var activityClosingMotion: Animation {
        .timingCurve(0.3, 0, 0.2, 1, duration: activityLandingDuration - 0.02).paced
    }
    private static var activityOpeningSpring: Animation {
        .spring(response: 0.78, dampingFraction: 0.54).paced
    }
}
