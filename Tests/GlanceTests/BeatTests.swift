//
//  BeatTests.swift
//  GlanceTests
//
//  Created by Gaty on 22/10/2026.
//

import Foundation
import Testing

@testable import Glance

/// Finding the music's beat from how its sound changes, 45 times a second, and the pulse that's
/// drawn with it.
@Suite("Beat")
struct BeatTests {
    /// Made-up sound at 48 kHz, as the analyzer sees it each time: a hum with a little noise in it,
    /// and on a beat, a kick on the bass and a hi-hat in the treble.
    private struct Song {
        private var seed: UInt32 = 7

        mutating func spectrum(beat: Bool) -> [Float] {
            (0..<512).map { bin in
                let noise = 1 + 0.5 * random()
                guard beat else { return 1e-6 * noise }
                return (bin < 5 ? 1e-2 : bin > 100 && bin < 160 ? 1e-4 : 1e-6) * noise
            }
        }

        /// 0 to 1, the same every run.
        private mutating func random() -> Float {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return Float(seed >> 8) / Float(1 << 24)
        }
    }

    @Test("A steady beat is found at its pace, and where it lands", arguments: [80.0, 100.0, 120.0, 150.0])
    func steady(bpm: Double) throws {
        let tracker = BeatTracker(sampleRate: 48_000)
        var song = Song()
        let period = 45 * 60 / bpm
        var next = 0.0, last = 0
        // Ten seconds.
        for frame in 0..<450 {
            let beat = Double(frame) >= next
            if beat {
                next += period
                last = frame
            }
            tracker.add(song.spectrum(beat: beat))
        }
        let found = try #require(tracker.bpm)
        #expect(abs(found - bpm) / bpm < 0.03)
        let beat = try #require(tracker.beat)
        // The last beat, within a frame and a half either way.
        var off = beat.since - Double(449 - last) / 45
        off -= (off / beat.period).rounded() * beat.period
        #expect(abs(off) < 1.5 / 45)
    }

    @Test("Sound that never repeats has no beat")
    func noBeat() {
        let tracker = BeatTracker(sampleRate: 48_000)
        var song = Song()
        for frame in 0..<450 {
            // A hit now and then, at no pace at all.
            tracker.add(song.spectrum(beat: [3, 40, 41, 97, 160, 171, 260, 300, 333, 401].contains(frame)))
        }
        #expect(tracker.bpm == nil)
    }

    @Test("Silence lets the beat go")
    func silence() {
        let tracker = BeatTracker(sampleRate: 48_000)
        var song = Song()
        for frame in 0..<450 { tracker.add(song.spectrum(beat: frame % 22 == 0)) }
        #expect(tracker.bpm != nil)
        for _ in 0..<450 { tracker.addSilence() }
        #expect(tracker.bpm == nil)
    }

    @Test("The pulse is full as a beat lands and has died away before the next; none once it's unsure")
    func pulse() {
        let start = Date(timeIntervalSinceReferenceDate: 1000)
        let beat = Beat(period: 0.5, anchor: start, until: start + 10)
        #expect(beat.bpm == 120)
        #expect(beat.pulse(at: start + 0.03) > 0.99)
        #expect(beat.pulse(at: start + 0.01) < 0.5)
        #expect(beat.pulse(at: start + 0.3) < 0.15)
        #expect(beat.pulse(at: start + 2.53) > 0.99)
        #expect(beat.pulse(at: start - 0.47) > 0.99)
        #expect(beat.pulse(at: start + 10.03) == 0)
    }
}
