//
//  IslandSwell.swift
//  Glance
//
//  Created by Gaty on 25/11/2026.
//

import CoreGraphics

/// How far the notch's outline reaches past its resting shape on each side, with what's in it
/// staying where it is: the pointer resting on it swells it, leaning toward where the pointer is, as
/// the Mac's own island does. Its top is the screen's edge, so it swells at its ends and bottom only.
struct IslandSwell: Equatable {
    var leading: CGFloat = 0
    var trailing: CGFloat = 0
    var bottom: CGFloat = 0

    static let zero = IslandSwell()

    /// The island's swell a side and at its bottom, by its height, measured with the pointer resting
    /// in its middle: 2.4 points at each end and 1.5 at the bottom of a 34.5 point island.
    static let side: CGFloat = 2.4 / 34.5
    static let foot: CGFloat = 1.5 / 34.5
    /// The bubble's, about a point each way for the same height.
    static let bubble: CGFloat = 1 / 34.5

    /// Where a point is on a shape, by its middle: -1 at its leading end or top, 1 at its trailing end
    /// or bottom, and no further either way. The shape and the point are in the screen's points, which
    /// count up from the bottom; right to left, its leading end is on the right.
    static func place(of point: CGPoint, in shape: CGRect, rightToLeft: Bool = false) -> CGPoint {
        func clamped(_ x: CGFloat) -> CGFloat { min(max(x.isFinite ? x : 0, -1), 1) }
        let across = (point.x - shape.midX) / max(shape.width / 2, 1)
        let down = (shape.midY - point.y) / max(shape.height / 2, 1)
        return CGPoint(x: clamped(rightToLeft ? -across : across), y: clamped(down))
    }

    /// Swollen by `side` at each end and `foot` at the bottom with the pointer in the middle, leaning
    /// toward it: the end it's nearer reaches out up to twice as far as the end it's away from draws
    /// in, which stays still with the pointer at the other end. The bottom reaches further with the
    /// pointer below the middle; the top, the screen's edge, never moves.
    static func leaning(toward place: CGPoint, side: CGFloat, foot: CGFloat) -> IslandSwell {
        let across = min(max(place.x, -1), 1), down = min(max(place.y, -1), 1)
        return IslandSwell(leading: side * (1 - across), trailing: side * (1 + across), bottom: foot * (1 + max(down, 0)))
    }

    /// The island's, for its resting height.
    static func island(toward place: CGPoint, height: CGFloat) -> IslandSwell {
        leaning(toward: place, side: side * height, foot: foot * height)
    }

    /// The bubble's, for the island's resting height.
    static func bubble(toward place: CGPoint, height: CGFloat) -> IslandSwell {
        leaning(toward: place, side: bubble * height, foot: bubble * height)
    }

    /// Pressed, it lets go of its width and keeps its height, as a button gives under a finger.
    var pressed: IslandSwell { IslandSwell(leading: 0, trailing: 0, bottom: bottom) }

    /// How much wider it is, all told.
    var across: CGFloat { leading + trailing }
}
