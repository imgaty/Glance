//
//  PreviewPointerTests.swift
//  GlanceTests
//
//  Created by Gaty on 10/10/2026.
//

import Foundation
import Testing

@testable import Glance

/// Settings' and the welcome tour's pictures of the notch answer the pointer as the real one does,
/// and go back to how they rest once it leaves.
@MainActor
@Suite("Preview follows the pointer", .serialized)
struct PreviewPointerTests {
    /// The notch in the picture: closed at the top middle, open below and around it.
    private let geometry = SettingsPreview.Geometry(
        rect: { state in
            switch state {
            case .closed: CGRect(x: 150, y: 0, width: 100, height: 30)
            case .peek: CGRect(x: 136, y: 0, width: 128, height: 37)
            case .open: CGRect(x: 50, y: 0, width: 300, height: 150)
            }
        }, scale: 1)

    private let away = CGPoint(x: 200, y: 300)

    /// Waits for `condition` as long as a busy Mac might take to animate there: up to two seconds.
    private func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<40 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }

    @Test("Resting open, it closes when the pointer moves off it, and opens again once the pointer leaves")
    func restsOpen() async {
        let preview = SettingsPreview()
        preview.model.state = .open
        preview.pointer(at: away, geometry)
        #expect(await eventually { preview.model.state == .closed })
        preview.pointer(at: nil, geometry)
        #expect(await eventually { preview.model.state == .open })
    }

    @Test("Resting open, it stays open when the pointer leaves from on it")
    func staysOpen() async {
        let preview = SettingsPreview()
        preview.model.state = .open
        preview.pointer(at: CGPoint(x: 200, y: 60), geometry)
        preview.pointer(at: nil, geometry)
        try? await Task.sleep(for: .milliseconds(450))
        #expect(preview.model.state == .open)
    }

    @Test("Closed, it swells as the pointer nears, and peeks under it")
    func nearing() {
        let preview = SettingsPreview()
        preview.setInteractive(true, animated: false)
        preview.pointer(at: CGPoint(x: 200, y: 60), geometry)
        #expect(preview.model.proximity > 0)
        preview.pointer(at: CGPoint(x: 200, y: 15), geometry)
        #expect(preview.model.state == .peek)
    }

    @Test("Resting closed, it stays closed once the pointer leaves")
    func restsClosed() async {
        let preview = SettingsPreview()
        preview.setInteractive(true, animated: false)
        preview.pointer(at: CGPoint(x: 200, y: 60), geometry)
        preview.pointer(at: nil, geometry)
        try? await Task.sleep(for: .milliseconds(700))
        #expect(preview.model.state == .closed)
        #expect(preview.model.proximity == 0)
    }
}

/// On a Dynamic Island, the artwork keeps as far from the island's round ends as from its top and
/// bottom; on a notch, it sits as it always has.
@Suite("Live activity spacing")
struct LiveActivitySpacingTests {
    @Test("A notch's are 6 points all round")
    func notch() {
        #expect(LiveActivityView.inset(island: false) == 6)
        #expect(LiveActivityView.edgeInset(island: false, restingHeight: 32) == 6)
    }

    @Test("An island's artwork sits in from the round ends, its corners clear of the curve")
    func island() {
        let height: CGFloat = 28
        let inset = LiveActivityView.inset(island: true)
        let edge = LiveActivityView.edgeInset(island: true, restingHeight: height)
        let side = height - inset * 2
        #expect(edge > inset)
        // The artwork's corner, as far inside the island's end as the artwork is from the top.
        let radius = side * ArtworkShape.restingRadius
        let end = CGPoint(x: height / 2, y: height / 2)
        let corner = CGPoint(x: edge + radius, y: inset + radius)
        #expect(isClose(hypot(end.x - corner.x, end.y - corner.y) + radius, height / 2 - inset, tolerance: 0.01))
    }
}
