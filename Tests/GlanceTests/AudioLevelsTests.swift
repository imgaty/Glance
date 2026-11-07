//
//  AudioLevelsTests.swift
//  GlanceTests
//
//  Created by Gaty on 29/10/2026.
//

import Foundation
import Testing

@testable import Glance

/// The beat the colors behind the player pulse on, and how what's heard is held back until it is.
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
            let beat = analyzer.reading(Array(samples[(end - Analyzer.size)..<end])).beat
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

    /// The bars after a second of a sound, made of tones at these pitches and loudnesses.
    static func bars(of tones: [(hertz: Double, amplitude: Double)], seconds: Double = 1.5) -> [Float] {
        let analyzer = Analyzer(sampleRate: rate)
        let count = Int(seconds * rate)
        let samples = (0..<count).map { i in
            Float(tones.reduce(0) { $0 + $1.amplitude * sin(2 * .pi * $1.hertz * Double(i) / rate) })
        }
        var last = [Float]()
        for end in stride(from: Analyzer.size, through: samples.count, by: hop) {
            last = analyzer.reading(Array(samples[(end - Analyzer.size)..<end])).levels
        }
        return last
    }

    /// Where a band's bar is, left to right.
    static func bar(ofBand band: Int) -> Int { Analyzer.order.firstIndex(of: band)! }

    @Test("The bars follow the pitch: a low note raises the bass's bar, a high one a treble bar")
    func pitch() {
        let low = Self.bars(of: [(70, 0.5)])
        #expect(low.indices.max { low[$0] < low[$1] } == Self.bar(ofBand: 0))
        let high = Self.bars(of: [(4_000, 0.5)])
        #expect(high.indices.max { high[$0] < high[$1] } == Self.bar(ofBand: 4))
        let middle = Self.bars(of: [(550, 0.5)])
        #expect(middle.indices.max { middle[$0] < middle[$1] } == Self.bar(ofBand: 2))
        // Far from the note, a bar is a dot.
        #expect(low[Self.bar(ofBand: 5)] < 0.1)
    }

    @Test("Bars differ as the sound does, rather than all standing alike")
    func uneven() {
        // A chord, loud in the low mids, softer up high.
        let chord = Self.bars(of: [(200, 0.4), (1_400, 0.08), (9_000, 0.02)])
        let tallest = chord.max() ?? 0, shortest = chord.min() ?? 0
        #expect(tallest - shortest > 0.4)
        #expect(chord[Self.bar(ofBand: 1)] > chord[Self.bar(ofBand: 3)])
        #expect(chord[Self.bar(ofBand: 3)] > chord[Self.bar(ofBand: 5)])
    }

    @Test("Music's falling spectrum reads about level across the bars")
    func tilt() {
        // A dense spread of pitches, 4.5 dB quieter an octave up, as music tends to be.
        var random = SystemRandomNumberGenerator()
        let pitches = stride(from: 40.0, through: 12_000, by: 25).map { hertz in
            (hertz, pow(hertz / 40, -Double(Analyzer.tilt) / (20 * log10(2))), Double.random(in: 0..<(2 * .pi), using: &random))
        }
        let count = Int(1.5 * Self.rate)
        let scale = 0.4 / pitches.reduce(0) { $0 + $1.1 }.squareRoot()
        let samples = (0..<count).map { i in
            let t = Double(i) / Self.rate
            return Float(scale * pitches.reduce(0) { $0 + $1.1 * sin(2 * .pi * $1.0 * t + $1.2) })
        }
        let analyzer = Analyzer(sampleRate: Self.rate)
        var level = [Float]()
        for end in stride(from: Analyzer.size, through: samples.count, by: Self.hop) {
            level = analyzer.reading(Array(samples[(end - Analyzer.size)..<end])).levels
        }
        #expect((level.max() ?? 0) - (level.min() ?? 0) < 0.3, "\(level)")
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
