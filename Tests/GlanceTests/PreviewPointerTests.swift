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

@Suite("Live activity spacing")
struct LiveActivitySpacingTests {
    @Test("A notch's are 6 points all round")
    func notch() {
        #expect(LiveActivityView.inset == 6)
    }

    @Test("The demos' pointer moves as a hand does: off quickly, short of the place, then onto it")
    func handMove() {
        let from = CGPoint(x: 360, y: 214), to = CGPoint(x: 168, y: 62)
        let length = hypot(to.x - from.x, to.y - from.y)
        func gone(_ p: CGPoint) -> CGFloat { 1 - hypot(to.x - p.x, to.y - p.y) / length }
        for move in [HandMove(from: from, to: to), HandMove(from: from, to: to, corrects: false), HandMove(from: from, to: to, flicks: true)] {
            #expect(move.point(at: 0) == from)
            #expect(isClose(move.point(at: 1).x, to.x, tolerance: 0.001) && isClose(move.point(at: 1).y, to.y, tolerance: 0.001))
        }
        let reach = HandMove(from: from, to: to)
        // Most of the way in the first half of the time; the main movement lands short, then corrects.
        #expect(gone(reach.point(at: 0.5)) > 0.6)
        let landing = reach.point(at: HandMove.main)
        let short = hypot(to.x - landing.x, to.y - landing.y)
        #expect(short > 2 && short < 12)
        // A flick, leaving, speeds up: it's covered less than half the way halfway through.
        #expect(gone(HandMove(from: from, to: to, flicks: true).point(at: 0.5)) < 0.5)
    }
}
