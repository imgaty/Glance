//
//  ContrastTests.swift
//  GlanceTests
//
//  Created by Gaty on 13/10/2026.
//

import AppKit
import SwiftUI
import Testing

@testable import Glance

/// Words drawn in a cover's color on the black notch, as a new song is announced, stay as clear as
/// text needs to be: 4.5 to 1, as Apple and WCAG ask.
@MainActor
@Suite("Contrast")
struct ContrastTests {
    private func contrast(_ color: Color) -> Double {
        let rgb = NSColor(color).usingColorSpace(.sRGB)!
        return Color.contrastOnBlack([rgb.redComponent, rgb.greenComponent, rgb.blueComponent])
    }

    @Test("A deep blue cover's color is lifted until it reads on black, even dimmed")
    func deepBlue() {
        // The darkest a cover's color gets: brightness 0.9, saturation 0.85, at blue.
        let blue = Color(hue: 2 / 3, saturation: 0.85, brightness: 0.9)
        #expect(contrast(blue) < 4.5)
        #expect(contrast(blue.readableOnBlack()) >= 4.5)
        #expect(contrast(blue.readableOnBlack(opacity: 0.7)) >= 4.5)
        // Only as far as it must: still blue, not white.
        #expect(contrast(blue.readableOnBlack()) < 5)
    }

    @Test("A color that already reads on black is left as it is")
    func light() {
        let yellow = Color(.sRGB, red: 1, green: 0.85, blue: 0.2)
        let rgb = NSColor(yellow.readableOnBlack()).usingColorSpace(.sRGB)!
        #expect(abs(rgb.redComponent - 1) < 0.001 && abs(rgb.greenComponent - 0.85) < 0.001 && abs(rgb.blueComponent - 0.2) < 0.001)
    }
}
