//
//  ClockTextTests.swift
//  Glance
//
//  Created by Gaty on 04/11/2026.
//

import Foundation
import Testing

@testable import Glance

@Suite("Clock text")
struct ClockTextTests {
    private let english = Locale(identifier: "en_US")
    /// Arabic digits, the minus to their right.
    private let saudi = Locale(identifier: "ar_SA")
    /// Latin digits, the minus to their left.
    private let israeli = Locale(identifier: "he_IL")

    @Test("Minutes and seconds, or hours too from an hour")
    func lengths() {
        #expect(ClockText.of(126, locale: english) == "2:06")
        #expect(ClockText.of(0, locale: english) == "0:00")
        #expect(ClockText.of(3726, locale: english) == "1:02:06")
        #expect(ClockText.of(7, paddingMinutes: true, locale: english) == "00:07")
    }

    @Test("Each language and region has its own digits")
    func digits() {
        #expect(ClockText.of(126, locale: saudi) == "\u{662}:\u{660}\u{666}")
        #expect(ClockText.of(126, locale: israeli) == "2:06")
    }

    @Test("The time left has its language's own minus, even at the end of a song")
    func minus() {
        #expect(ClockText.left(126, locale: english) == "-2:06")
        #expect(ClockText.left(0, locale: english) == "-0:00")
        // A letter mark before the minus says which way it reads: Arabic's, or left to right.
        #expect(ClockText.left(126, locale: saudi) == "\u{61C}-\u{662}:\u{660}\u{666}")
        #expect(ClockText.left(126, locale: israeli) == "\u{200E}-2:06")
    }
}
