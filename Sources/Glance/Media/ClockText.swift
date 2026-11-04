//
//  ClockText.swift
//  Glance
//
//  Created by Gaty on 04/11/2026.
//

import Foundation

/// A length of time as a clock shows it, in the digits and with the separator of the Mac's language
/// and region, as the system's own are: 4:59, or 1:04:59 for an hour or more; in Saudi Arabia, ٤:٥٩.
enum ClockText {
    static func of(_ seconds: Int, paddingMinutes: Bool = false, locale: Locale = .current) -> String {
        let pattern: Duration.TimeFormatStyle.Pattern =
            seconds >= 3600 ? .hourMinuteSecond : .minuteSecond(padMinuteToLength: paddingMinutes ? 2 : 1)
        return Duration.seconds(seconds).formatted(.time(pattern: pattern).locale(locale))
    }

    /// The time left, with the language's own minus, which also says which side of the digits it goes:
    /// their right with Arabic digits, their left with Hebrew's Latin ones.
    static func left(_ seconds: Int, locale: Locale = .current) -> String {
        let number = NumberFormatter()
        number.locale = locale
        return (number.minusSign ?? "-") + of(seconds, locale: locale)
    }
}
