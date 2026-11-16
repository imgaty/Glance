//
//  GlanceLogo.swift
//  Glance
//
//  Created by Gaty on 14/11/2026.
//

import AppKit

/// Glance's mark: a rounded frame with a notch hanging from its top, and a panel inside it, a gap
/// from the frame all round, the notch included. Every corner is concentric with the frame's.
/// Measures are in the app icon's units, where the mark is 600 tall in a 1,024 icon; the icon's
/// layers in `Resources/AppIcon.icon` are this mark at `icon`, which a test checks.
struct GlanceMark {
    /// 9% wider than tall, so it reads as square: a vertical length looks longer than the same
    /// horizontal one, and a notch at the top makes it read as an upright screen.
    static let width: CGFloat = 654
    static let height: CGFloat = 600
    static let radius: CGFloat = 128
    static let notchHalfWidth: CGFloat = 118
    static let notchDepth: CGFloat = 78
    static let notchRadius: CGFloat = 30
    /// Where the notch meets the frame.
    static let notchFillet: CGFloat = 16
    /// The panel's corners beside the notch, which would come to a point if they stayed concentric.
    static let panelFillet: CGFloat = 14
    /// The panel's fade in the icon, top to bottom.
    static let fade: (top: CGFloat, bottom: CGFloat) = (0.6, 0.2)

    /// How thick the frame is, and how wide the gap between it and the panel.
    var frame: CGFloat
    var gap: CGFloat

    /// The app icon's.
    static let icon = GlanceMark(frame: 46, gap: 30)

    /// A mark `height` points tall whose frame and gap are these many points, as small sizes need
    /// heavier lines than the icon's to read.
    static func lines(height points: CGFloat, frame: CGFloat, gap: CGFloat) -> GlanceMark {
        GlanceMark(frame: frame * height / points, gap: gap * height / points)
    }

    /// The frame, as two outlines to fill even-odd: the square and its opening.
    var framePath: CGPath {
        let path = CGMutablePath()
        path.addPath(Self.outline(inset: 0))
        path.addPath(opening(gap: 0))
        return path
    }

    var panelPath: CGPath { opening(gap: gap) }

    /// The panel's top and bottom, where its fade starts and ends.
    var panelSpan: ClosedRange<CGFloat> { (frame + gap)...(Self.height - frame - gap) }

    /// The outline `inset` in from the mark's edge, its corners keeping their centers. Top down, as
    /// SVG draws, from the top left.
    private static func outline(inset d: CGFloat) -> CGPath {
        let (x0, y0, x1, y1, r) = (d, d, width - d, height - d, radius - d)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: x0 + r, y: y0))
        path.addArc(tangent1End: CGPoint(x: x1, y: y0), tangent2End: CGPoint(x: x1, y: y1), radius: r)
        path.addArc(tangent1End: CGPoint(x: x1, y: y1), tangent2End: CGPoint(x: x0, y: y1), radius: r)
        path.addArc(tangent1End: CGPoint(x: x0, y: y1), tangent2End: CGPoint(x: x0, y: y0), radius: r)
        path.addArc(tangent1End: CGPoint(x: x0, y: y0), tangent2End: CGPoint(x: x1, y: y0), radius: r)
        path.closeSubpath()
        return path
    }

    /// The frame's opening with the notch hanging into it, all of it `gap` further in.
    private func opening(gap g: CGFloat) -> CGPath {
        let d = frame + g
        let (x0, y0, x1, y1, r) = (d, d, Self.width - d, Self.height - d, Self.radius - d)
        let around = Self.notchRadius + g
        // As round as it can be with a straight wall left between it and the notch's corner.
        let fillet = g == 0 ? Self.notchFillet : min(max(Self.notchFillet - g, Self.panelFillet), Self.notchDepth - around)
        let left = Self.width / 2 - Self.notchHalfWidth - g, right = Self.width / 2 + Self.notchHalfWidth + g
        let bottom = frame + Self.notchDepth + g
        let path = CGMutablePath()
        path.move(to: CGPoint(x: x0 + r, y: y0))
        path.addArc(tangent1End: CGPoint(x: left, y: y0), tangent2End: CGPoint(x: left, y: bottom), radius: fillet)
        path.addArc(tangent1End: CGPoint(x: left, y: bottom), tangent2End: CGPoint(x: right, y: bottom), radius: around)
        path.addArc(tangent1End: CGPoint(x: right, y: bottom), tangent2End: CGPoint(x: right, y: y0), radius: around)
        path.addArc(tangent1End: CGPoint(x: right, y: y0), tangent2End: CGPoint(x: x1, y: y0), radius: fillet)
        path.addArc(tangent1End: CGPoint(x: x1, y: y0), tangent2End: CGPoint(x: x1, y: y1), radius: r)
        path.addArc(tangent1End: CGPoint(x: x1, y: y1), tangent2End: CGPoint(x: x0, y: y1), radius: r)
        path.addArc(tangent1End: CGPoint(x: x0, y: y1), tangent2End: CGPoint(x: x0, y: y0), radius: r)
        path.addArc(tangent1End: CGPoint(x: x0, y: y0), tangent2End: CGPoint(x: x0 + r, y: y0), radius: r)
        path.closeSubpath()
        return path
    }
}

/// The mark without the icon's tile, drawn to any size.
@MainActor
enum GlanceLogo {
    /// The welcome tour's: the icon's frame and gap, and its panel's fade.
    static let image = make(width: 64)
    /// 16 points tall, its frame 1.5 and its gap 1, as heavy as the symbols beside it.
    static let menuBar = make(width: 16 * GlanceMark.width / GlanceMark.height, mark: .lines(height: 16, frame: 1.5, gap: 1))

    /// Templates follow the menu bar and SwiftUI's foreground. About draws in the window's ink.
    static func make(width: CGFloat, mark: GlanceMark = .icon, faded: Bool = true, template: Bool = true) -> NSImage {
        let size = NSSize(width: width, height: width * GlanceMark.height / GlanceMark.width)
        let image = NSImage(size: size, flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.saveGState()
            let scale = rect.width / GlanceMark.width
            context.translateBy(x: rect.minX, y: rect.minY)
            context.scaleBy(x: scale, y: scale)
            let ink = CGColor(gray: 0, alpha: 1)
            context.setFillColor(ink)
            context.addPath(mark.framePath)
            context.fillPath(using: .evenOdd)
            context.addPath(mark.panelPath)
            if faded {
                context.clip()
                let colors = [ink.copy(alpha: GlanceMark.fade.top)!, ink.copy(alpha: GlanceMark.fade.bottom)!] as CFArray
                if let gradient = CGGradient(colorsSpace: nil, colors: colors, locations: [0, 1]) {
                    let span = mark.panelSpan
                    context.drawLinearGradient(
                        gradient, start: CGPoint(x: 0, y: span.lowerBound), end: CGPoint(x: 0, y: span.upperBound), options: [])
                }
            } else {
                context.fillPath()
            }
            context.restoreGState()
            if !template {
                NSColor.labelColor.setFill()
                rect.fill(using: .sourceIn)
            }
            return true
        }
        image.isTemplate = template
        image.accessibilityDescription = "Glance"
        return image
    }
}
