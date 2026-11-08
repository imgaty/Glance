//
//  AudioLevelsTests.swift
//  GlanceTests
//
//  Created by Gaty on 29/10/2026.
//

import Foundation
import Testing

@testable import Glance

/// The beat the colors behind the player pulse on, the bars as Apple's own waveform makes them, and
/// how what's heard is held back until it is.
@Suite("Audio levels")
struct AudioLevelsTests {
    static let rate = 48_000.0
    /// The analysis runs 45 times a second, on the latest window of samples.
    static let hop = Int(rate / 45)

    /// A bass line, with a kick on every beat at `bpm` when there are kicks, and a hi-hat between.
    static func song(seconds: Double, bpm: Double, kicks: Bool) -> (samples: [Float], beats: [Double]) {
        let count = Int(seconds * rate)
        let beat = 60 / bpm
        var generator = SystemRandomNumberGenerator()
        var samples = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let t = Double(i) / rate
            let since = t.truncatingRemainder(dividingBy: beat)
            let half = t.truncatingRemainder(dividingBy: beat / 2)
            var value = 0.15 * sin(2 * .pi * 62 * t) * (0.8 + 0.2 * sin(2 * .pi * 0.3 * t))
            if kicks { value += 0.7 * exp(-since / 0.07) * sin(2 * .pi * (50 + 60 * exp(-since / 0.02)) * since) }
            value += 0.05 * exp(-half / 0.02) * Double.random(in: -1...1, using: &generator)
            samples[i] = Float(value)
        }
        let beats = kicks ? stride(from: 0.0, to: seconds, by: beat).map { $0 } : []
        return (samples, beats)
    }

    /// When the analysis found a beat, in seconds from the start: each reading where the beat shown
    /// swelled past 0.4.
    static func found(in samples: [Float]) -> [Double] {
        let analyzer = Analyzer(sampleRate: rate)
        var last: Float = 0
        var found: [Double] = []
        for end in stride(from: Analyzer.size, through: samples.count, by: hop) {
            let beat = analyzer.beat(Array(samples[(end - Analyzer.size)..<end]))
            if beat >= 0.4, last < 0.4 { found.append(Double(end) / rate) }
            last = beat
        }
        return found
    }

    @Test("A kick on every beat is found once, as it's played")
    func kicks() {
        let song = Self.song(seconds: 8, bpm: 120, kicks: true)
        let found = Self.found(in: song.samples)
        // From when the bass's usual level has settled, a second in.
        let expected = song.beats.filter { $0 >= 1 }
        #expect(found.count == expected.count)
        for (beat, at) in zip(expected, found) {
            // Within the window it was heard in, and the two readings it takes to swell in.
            #expect(at >= beat && at - beat < Double(Analyzer.size) / Self.rate + 2.0 / 45, "beat at \(beat), found at \(at)")
        }
    }

    /// The bars from one window of a sound made of tones at these pitches and loudnesses.
    static func bars(of tones: [(hertz: Double, amplitude: Double)]) -> [Float] {
        let samples = (0..<BinnedFFT.size).map { i in
            Float(tones.reduce(0) { $0 + $1.amplitude * sin(2 * .pi * $1.hertz * Double(i) / rate) })
        }
        return BinnedFFT(sampleRate: rate).levels(samples)
    }

    @Test("Each bar sums the bins of its band, counted off from 20 Hz a bin's width at a time, as Apple's do")
    func bins() {
        let hertzPerBin = Float(Self.rate) / Float(BinnedFFT.size)
        // The last bin each bar takes, at 48 kHz: 20 Hz plus a bin's width each, below its band's top.
        let last = [5, 12, 43, 126, 382, 851]
        for (bar, bin) in last.enumerated() {
            for (spike, expected) in [(bin, bar), (bin + 1, bar + 1)] {
                var magnitudes = [Float](repeating: 0, count: BinnedFFT.size / 2)
                magnitudes[spike] = 0.01
                let bars = BinnedFFT.bars(magnitudes, hertzPerBin: hertzPerBin)
                let raised = bars.indices.filter { bars[$0] > 0 }
                #expect(raised == (expected < bars.count ? [expected] : []), "bin \(spike)")
            }
        }
    }

    @Test("A bar's height is Apple's curve: none at none, all at one, a third at a half")
    func curve() {
        #expect(BinnedFFT.height(of: 0) == 0)
        #expect(abs(BinnedFFT.height(of: 1) - 1) < 0.001)
        #expect(abs(BinnedFFT.height(of: 0.5) - 0.3472) < 0.001)
        #expect(abs(BinnedFFT.height(of: 0.3) - 0.1818) < 0.001)
        // Kept between 0 and 1, however loud.
        for v in stride(from: Float(0), through: 3, by: 0.05) { #expect((0...1).contains(BinnedFFT.height(of: v))) }
    }

    @Test("A tone raises its own band's bar, bass at the left and treble at the right")
    func pitch() {
        for (bar, hertz) in [50.0, 120, 300, 1_000, 3_000, 7_000].enumerated() {
            let bars = Self.bars(of: [(hertz, 0.05)])
            #expect(bars.indices.max { bars[$0] < bars[$1] } == bar, "\(hertz) Hz: \(bars)")
        }
    }

    @Test("Silence is six dots")
    func silence() {
        #expect(Self.bars(of: []) == [Float](repeating: 0, count: 6))
    }

    @Test("The colors' pulse rises and falls more gently than the beat, and follows it")
    func pulse() {
        var pulse: Float = 0
        let rise = AudioLevels.eased(pulse, toward: 1)
        #expect(rise > 0 && rise < 0.2)
        for _ in 0..<20 { pulse = AudioLevels.eased(pulse, toward: 1) }
        #expect(pulse > 0.9)
        let top = pulse
        pulse = AudioLevels.eased(pulse, toward: 0)
        #expect(pulse < top && top - pulse < 0.1)
    }

    @Test("A bass line with no kicks has no beat")
    func noKicks() {
        let song = Self.song(seconds: 6, bpm: 120, kicks: false)
        #expect(Self.found(in: song.samples).count <= 1)
    }

    @Test("What's heard later is held back as long, the latest due first")
    func heardLater() {
        func reading(_ beat: Float) -> AudioReading { AudioReading(levels: [beat], beat: beat) }
        var heard = HeardLater(delay: 0.15)
        #expect(heard.take(reading(1), at: 10) == nil)
        #expect(heard.take(reading(2), at: 10.1) == nil)
        #expect(heard.take(reading(3), at: 10.15) == reading(1))
        // Two due at once: only the later shows.
        #expect(heard.take(reading(4), at: 10.3) == reading(3))
        // Moved to speakers that play at once, what's waiting shows straight away.
        heard.delay = 0
        #expect(heard.take(reading(5), at: 10.31) == reading(5))
    }
}
