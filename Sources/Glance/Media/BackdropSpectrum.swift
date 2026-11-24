//
//  BackdropSpectrum.swift
//  Glance
//
//  Created by Gaty on 24/11/2026.
//

import Accelerate
import simd

/// How the music moves the colors behind the player, exactly as Apple Music's own background takes
/// it on macOS 27.3: MediaPlaybackCore's `MPCAudioSpectrumAnalyzer` and `MPCAudioSpectrumObserver`
/// hear the player 2048 samples at a time, and MediaCoreUI's `SpectrumAnalysis` turns each hearing
/// into a report and the reports into the level the colors show, frame by frame.
///
/// A report has four parts: the bass's, the middle's and the treble's share of all the sound, each
/// scaled by how loud the sound is, and whether there's any sound at all. The colors use the bass to
/// swell the cover's copies and add contrast, and the treble to saturate them (see `ArtworkBackdrop`).
enum BackdropSpectrum {
    /// Samples heard at a time: 48 kHz over Apple's 30 readings a second, rounded up to a power of
    /// two, so about 23 reports a second.
    static let window = 2048
    /// The three bands, in hertz: a frequency counts toward a band above its low edge and up to its high one.
    static let bands: [(low: Float, high: Float)] = [(20, 300), (300, 3_500), (3_500, 24_000)]
    /// How loud a sound is, in decibels of its whole spectrum's power, at which each band's share
    /// counts in full.
    static let fullScale: Float = 120
    /// Each of the last four reports' weight, oldest first.
    static let ramp: [Float] = [0.1, 0.2, 0.3, 0.4]
    /// How much of its peak each part keeps from one frame to the next: the bass lets go fastest, the
    /// treble barely at all, and whether there's sound none.
    static let hold = SIMD4<Float>(1 - 1.0 / 50, 1 - 1.0 / 100, 1 - 1.0 / 1000, 0)
    /// How far the level shown moves toward the peak at each frame.
    static let follow: Float = 0.5
    /// How strongly the music moves the colors: with lyrics behind them, and otherwise.
    static let exciting: Float = 1
    static let subdued: Float = 0.2

    /// A report from `window` samples of the player's sound, a mix of both channels, Apple's way: no
    /// window function, the power of each bin of the FFT as vDSP scales it, each band's share of the
    /// power of all the bins, times the sound's loudness in decibels over 120.
    static func report(_ samples: [Float], sampleRate: Double, intensity: Float = exciting) -> SIMD4<Float> {
        BackdropSpectrumAnalyzer(count: samples.count)?.report(samples, sampleRate: sampleRate, intensity: intensity) ?? .zero
    }

    /// A report from each band's share of the sound and the power of all of it.
    static func report(shares: SIMD3<Float>, total: Float, intensity: Float = exciting) -> SIMD4<Float> {
        guard total > 0 else { return .zero }
        let loudness = 20 * log10(total)
        let parts = SIMD4(shares.x * loudness / fullScale, shares.y * loudness / fullScale, shares.z * loudness / fullScale, loudness)
        return simd_clamp(parts, .zero, .one) * intensity
    }

    /// Apple's last four reports weighed together, the newest counting most.
    static func weighed(_ recent: [SIMD4<Float>]) -> SIMD4<Float> {
        zip(recent.suffix(ramp.count), ramp.suffix(min(recent.count, ramp.count))).reduce(.zero) { $0 + $1.0 * $1.1 }
    }
}

/// The level the colors show, made from the reports frame by frame as Apple's `SpectrumAnalysis`
/// makes it: a peak that holds and lets go a little each frame, unless the weighed reports reach
/// higher; a level that moves halfway toward the peak each frame; and that level eased in and out.
struct BackdropSpectrumState: Equatable {
    var peak = SIMD4<Float>.zero
    var level = SIMD4<Float>.zero

    /// One of Apple's frames, with the latest reports.
    mutating func step(recent: [SIMD4<Float>]) {
        peak = simd_max(peak * BackdropSpectrum.hold, BackdropSpectrum.weighed(recent))
        level += (peak - level) * BackdropSpectrum.follow
    }

    /// The level as the colors take it: kept within 0...1 and eased in and out (6x⁵ - 15x⁴ + 10x³).
    var shown: SIMD4<Float> {
        let x = simd_clamp(level, .zero, .one)
        return x * x * x * (x * (x * 6 - 15) + 10)
    }
}

/// The FFT behind each report, set up once for the pipeline's queue.
final class BackdropSpectrumAnalyzer {
    let count: Int
    private let log2n: vDSP_Length
    private let setup: FFTSetup
    private var real: [Float]
    private var imaginary: [Float]
    private var power: [Float]
    /// Each bin's band, for the sample rate last used; -1 for none.
    private var bands: [Int] = []
    private var bandsRate = 0.0

    init?(count: Int = BackdropSpectrum.window) {
        guard count >= 2, count & (count - 1) == 0 else { return nil }
        let log2n = vDSP_Length(log2(Double(count)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return nil }
        self.count = count
        self.log2n = log2n
        self.setup = setup
        real = [Float](repeating: 0, count: count / 2)
        imaginary = real
        power = real
    }

    deinit { vDSP_destroy_fftsetup(setup) }

    func report(_ samples: [Float], sampleRate: Double, intensity: Float = BackdropSpectrum.exciting) -> SIMD4<Float> {
        guard samples.count == count else { return .zero }
        let half = count / 2
        if bandsRate != sampleRate {
            bandsRate = sampleRate
            bands = (0..<half).map { bin in
                let hertz = Float(sampleRate) * Float(bin) / Float(count)
                return BackdropSpectrum.bands.firstIndex { hertz > $0.low && hertz <= $0.high } ?? -1
            }
        }
        real.withUnsafeMutableBufferPointer { realPointer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryPointer in
                var split = DSPSplitComplex(realp: realPointer.baseAddress!, imagp: imaginaryPointer.baseAddress!)
                samples.withUnsafeBufferPointer { input in
                    input.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))
                // Each bin's power, the DC and Nyquist bins packed into the first as vDSP packs them.
                // vDSP adds to what's there, so it's cleared first, as Apple's is.
                power.withUnsafeMutableBufferPointer { powerPointer in
                    vDSP_vclr(powerPointer.baseAddress!, 1, vDSP_Length(half))
                    vDSP_zaspec(&split, powerPointer.baseAddress!, vDSP_Length(half))
                }
            }
        }
        var total: Float = 0
        vDSP_sve(power, 1, &total, vDSP_Length(half))
        guard total > 0 else { return .zero }
        var shares = SIMD3<Float>.zero
        for bin in 0..<half where bands[bin] >= 0 {
            shares[bands[bin]] += power[bin] / total
        }
        return BackdropSpectrum.report(shares: shares, total: total, intensity: intensity)
    }
}
