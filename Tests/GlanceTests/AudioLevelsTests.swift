//
//  AudioLevelsTests.swift
//  GlanceTests
//
//  Created by Gaty on 29/10/2026.
//

import Foundation
import Testing

@testable import Glance

/// The beat, the spectrum the colors behind the player pulse on, the bars as Apple's own waveform
/// makes them, and how what's heard is held back until it is.
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

    /// `seconds` of tones, at `rate`.
    static func tones(_ tones: [(hertz: Double, amplitude: Double)], count: Int = BackdropSpectrum.window) -> [Float] {
        (0..<count).map { i in Float(tones.reduce(0) { $0 + $1.amplitude * sin(2 * .pi * $1.hertz * Double(i) / rate) }) }
    }

    @Test("A spectrum report is each band's share of the sound times its loudness over 120 dB, as Apple's")
    func spectrumReport() {
        // A full-scale tone in each band: its share is all but the whole, and 2048 samples of it are
        // loud enough (about 132 dB of vDSP's power) to count in full.
        let bass = BackdropSpectrum.report(Self.tones([(100, 1)]), sampleRate: Self.rate)
        #expect(bass.x > 0.95 && bass.y < 0.05 && bass.z < 0.01 && bass.w == 1)
        let middle = BackdropSpectrum.report(Self.tones([(1_000, 1)]), sampleRate: Self.rate)
        #expect(middle.y > 0.95 && middle.x < 0.05)
        let treble = BackdropSpectrum.report(Self.tones([(8_000, 1)]), sampleRate: Self.rate)
        #expect(treble.z > 0.95 && treble.x < 0.05)
        // Quieter, each share counts less: by its decibels over 120.
        let quiet = BackdropSpectrum.report(Self.tones([(100, 0.01)]), sampleRate: Self.rate)
        let loudness = 20 * log10(Float(0.01 * 1024 * 2) * Float(0.01 * 1024 * 2))
        #expect(abs(quiet.x - loudness / 120) < 0.03)
        // The same analyzer, used again and again, gives the same report each time.
        let analyzer = BackdropSpectrumAnalyzer()!
        let samples = Self.tones([(1_000, 0.3), (8_000, 0.05)])
        let once = analyzer.report(samples, sampleRate: Self.rate)
        for _ in 0..<5 { #expect(analyzer.report(samples, sampleRate: Self.rate) == once) }
        #expect(once.y > 0.8 && once.y < 1 && once.z > 0.01 && once.x < 0.05)
        // Silence is nothing at all.
        #expect(BackdropSpectrum.report([Float](repeating: 0, count: 2048), sampleRate: Self.rate) == .zero)
        // Lyrics behind the colors take it in full; otherwise a fifth of it.
        #expect(BackdropSpectrum.report(shares: SIMD3(0.5, 0.25, 0.1), total: 1e6) == SIMD4(0.5, 0.25, 0.1, 1))
        #expect(BackdropSpectrum.report(shares: SIMD3(0.5, 0, 0), total: 1e6, intensity: BackdropSpectrum.subdued) == SIMD4(0.1, 0, 0, 0.2))
    }

    @Test("The colors' level weighs the last four reports, holds its peak and follows it halfway each frame")
    func spectrumLevel() {
        var state = BackdropSpectrumState()
        var recent = [SIMD4<Float>](repeating: .zero, count: 4)
        // One report of a hit: the newest counts four tenths.
        recent = Array(recent.dropFirst()) + [SIMD4(1, 1, 1, 1)]
        state.step(recent: recent)
        #expect(abs(state.peak.x - 0.4) < 0.0001 && abs(state.level.x - 0.2) < 0.0001)
        // Then silence: the hit moves down the four, weighing less each report, while the peak lets go
        // fastest in the bass, barely in the treble, and not at all held for whether there's sound.
        for _ in 0..<4 { recent = Array(recent.dropFirst()) + [.zero] }
        state.step(recent: recent)
        #expect(abs(state.peak.x - 0.4 * 0.98) < 0.0001)
        #expect(abs(state.peak.y - 0.4 * 0.99) < 0.0001)
        #expect(abs(state.peak.z - 0.4 * 0.999) < 0.0001)
        #expect(state.peak.w == 0)
        // Shown eased in and out: half is half, a little is less.
        let half = BackdropSpectrumState(peak: .zero, level: SIMD4(repeating: 0.5)).shown
        #expect(abs(half.x - 0.5) < 0.0001)
        let little = BackdropSpectrumState(peak: .zero, level: SIMD4(repeating: 0.2)).shown
        #expect(abs(little.x - 0.05792) < 0.0001)
    }

    @Test("Spectrum reports count only while music plays, and a pause brings one silent report")
    @MainActor func spectrumWhilePlaying() {
        let audio = AudioLevels()
        audio.receive(AudioReading(levels: nil, beat: 0, spectrum: SIMD4(1, 0, 0, 1)))
        #expect(audio.recent.allSatisfy { $0 == .zero })
        audio.follow(pid: 0, playing: true)
        audio.receive(AudioReading(levels: nil, beat: 0, spectrum: SIMD4(1, 0, 0, 1)))
        audio.receive(AudioReading(levels: nil, beat: 0, spectrum: SIMD4(0.5, 0, 0, 1)))
        #expect(audio.recent.suffix(2) == [SIMD4(1, 0, 0, 1), SIMD4(0.5, 0, 0, 1)])
        audio.follow(pid: 0, playing: false)
        #expect(audio.recent.suffix(3) == [SIMD4(1, 0, 0, 1), SIMD4(0.5, 0, 0, 1), .zero])
        audio.receive(AudioReading(levels: nil, beat: 0, spectrum: SIMD4(1, 1, 1, 1)))
        #expect(audio.recent.last == .zero)
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
        // Spectrum reports each count: every one that's due comes, oldest first.
        var reports = HeardLater(delay: 0.1)
        #expect(reports.takeAll(reading(1), at: 20).isEmpty)
        #expect(reports.takeAll(reading(2), at: 20.05).isEmpty)
        #expect(reports.takeAll(reading(3), at: 20.2) == [reading(1), reading(2)])
    }
}
