//
//  TrayDropTargetTests.swift
//  GlanceTests
//
//  Created by Gaty on 23/11/2026.
//

import CoreGraphics
import Testing

@testable import Glance

/// The tray's two places to drop something dragged in from another app: Keep in Tray and AirDrop.
@Suite("Places to drop")
struct TrayDropTargetTests {
    // Side by side, Shelf.dropGap apart.
    private let keep = CGRect(x: 14, y: 40, width: 200, height: 100)
    private let airDrop = CGRect(x: 214 + Shelf.dropGap, y: 40, width: 200, height: 100)

    private func target(_ x: CGFloat, _ y: CGFloat) -> DropTarget? {
        NotchController.dropTarget(at: CGPoint(x: x, y: y), keep: keep, airDrop: airDrop)
    }

    @Test("Opened for a drag, neither is lit before the drag is over one")
    @MainActor func noneAtFirst() {
        let model = NotchModel(closedSize: CGSize(width: 185, height: 32), layout: .top, hasCamera: true)
        model.dropping = true
        #expect(model.dropTarget == nil)
        // Under the camera, and below the two: over neither.
        #expect(target(200, 10) == nil)
        #expect(target(300, 200) == nil)
    }

    @Test("Each is lit only while the drag is over it, and none once it has left")
    func followsThePointer() {
        let path: [(CGPoint, DropTarget?)] = [
            (CGPoint(x: 300, y: 5), nil),
            (CGPoint(x: 100, y: 90), .keep),
            (CGPoint(x: 300, y: 90), .airDrop),
            (CGPoint(x: 100, y: 90), .keep),
            (CGPoint(x: 100, y: 200), nil),
        ]
        for (point, expected) in path {
            #expect(target(point.x, point.y) == expected, "\(point)")
        }
    }

    @Test("A drag just short of a place's edge is over it")
    func nearMiss() {
        #expect(target(10, 90) == .keep)
        #expect(target(426, 90) == .airDrop)
        #expect(target(100, 150) == nil)
    }

    @Test("Before the places are laid out, nothing is lit")
    func unplaced() {
        #expect(NotchController.dropTarget(at: CGPoint(x: 100, y: 90), keep: nil, airDrop: nil) == nil)
    }
}
