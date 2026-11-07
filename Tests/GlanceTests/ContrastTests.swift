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

    @Test("The side buttons keep 3 to 1 on the lightest backgrounds measured behind them")
    func sideButtons() {
        func contrast(_ color: Color, onGray gray: Double) -> Double {
            func luminance(_ value: Double) -> Double { value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
            let rgb = NSColor(color).usingColorSpace(.sRGB)!
            let front =
                0.2126 * luminance(rgb.redComponent) + 0.7152 * luminance(rgb.greenComponent) + 0.0722 * luminance(rgb.blueComponent)
            return (max(front, luminance(gray)) + 0.05) / (min(front, luminance(gray)) + 0.05)
        }
        // Behind the buttons: a white cover's colors, and Clear glass over a white window.
        for gray in [136.0, 139.0, 145.0] {
            #expect(contrast(PlayerLayout.sideButton(onLight: true), onGray: gray / 255) >= 3)
            #expect(contrast(PlayerLayout.sideButtonOff(onLight: true), onGray: gray / 255) >= 3)
        }
    }

    @Test("With Increase Contrast on, the player's words read 4.5 to 1 on the lightest cover's colors, dimmed further")
    func increasedContrast() {
        func luminance(_ value: Double) -> Double { value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
        func contrast(_ color: Color, onGray gray: Double) -> Double {
            let rgb = NSColor(color).usingColorSpace(.sRGB)!
            let front = 0.2126 * luminance(rgb.redComponent) + 0.7152 * luminance(rgb.greenComponent) + 0.0722 * luminance(rgb.blueComponent)
            return (max(front, luminance(gray)) + 0.05) / (min(front, luminance(gray)) + 0.05)
        }
        let usual = NotchView.colorsBrightest * (1 - NotchView.colorsDim)
        let dimmed = NotchView.colorsBrightest * (1 - NotchView.contrastDim)
        // The usual dimming leaves a white cover's colors about Apple Music's 139 gray.
        #expect(abs(usual * 255 - 139) < 2)
        #expect(contrast(NotchType.detailColor, onGray: usual) < 4.5)
        #expect(contrast(NotchType.detailColor, onGray: dimmed) >= 4.5)
        #expect(contrast(.white, onGray: dimmed) >= 7)
        // Still some color left to show.
        #expect(dimmed * 255 > 40)
    }

    @Test("A color that already reads on black is left as it is")
    func light() {
        let yellow = Color(.sRGB, red: 1, green: 0.85, blue: 0.2)
        let rgb = NSColor(yellow.readableOnBlack()).usingColorSpace(.sRGB)!
        #expect(abs(rgb.redComponent - 1) < 0.001 && abs(rgb.greenComponent - 0.85) < 0.001 && abs(rgb.blueComponent - 0.2) < 0.001)
    }
}
