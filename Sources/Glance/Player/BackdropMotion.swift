//
//  BackdropMotion.swift
//  Glance
//
//  Created by Gaty on 24/11/2026.
//

import Foundation
import simd

/// Everything that moves in the colors behind the player, frame by frame, as Apple Music's own
/// background moves it (MediaCoreUI's `Backdrop.CompositeRenderer` on macOS 27.3, read from its code).
///
/// Apple draws 30 frames a second and adds a sixtieth of a second to its clock at each, so its
/// motion runs at half speed: the cover's three copies turn once in 240, 140 and 180 seconds, and the
/// warp swings back and forth every 44. With Reduce Motion on, each frame adds a six-hundredth, so
/// everything but the music's pulse moves ten times slower still. A new cover fades in over 0.8
/// seconds; lyrics behind the colors (`exciting`) bring the warp in over 0.8 seconds, saturate less
/// and blur less, as Apple does behind its lyrics.
struct BackdropMotion: Equatable {
    /// Frames a second, and the clock's step at each, normally and with Reduce Motion on.
    static let frameRate = 30.0
    static let step: Float = 1.0 / 60
    static let reducedStep: Float = 1.0 / 600
    /// How long a new cover takes to fade in, and the warp to come in or go, in clock time.
    static let fadeDuration: Float = 0.8
    /// The warp's swing: sin(time / this), so once every 2π times this in clock time.
    static let warpSpeed: Float = 3.5
    /// White and black laid over the colors: the black darker on a dark appearance, as the notch's is.
    static let whiteScrim: Float = 0.1
    static let blackScrim: Float = 0.5
    static let lightBlackScrim: Float = 0.35
    /// The colors are drawn at a quarter of the picture's size, then blurred (`downsample` in the shader).
    static let downsample: Float = 4
    /// The blur starts here, in points, and moves a point a frame toward the look's.
    static let firstBlur: Float = 80

    /// How saturated and how blurred (in points) the colors are, by the picture's shape and whether
    /// lyrics are behind them.
    static func look(wide: Bool, exciting: Bool) -> (saturation: Float, blur: Float) {
        switch (wide, exciting) {
        case (true, false): (2.9, 200)
        case (true, true): (2.4, 120)
        case (false, false): (2.4, 160)
        case (false, true): (2.0, 85)
        }
    }

    /// The new cover's fade, Core Animation's (0, 0, 0.3, 1) curve, and the warp's coming in,
    /// ease in and out (0.42, 0, 0.58, 1).
    static let fadeCurve = TimingCurve(0, 0, 0.3, 1)
    static let modeCurve = TimingCurve(0.42, 0, 0.58, 1)

    /// The clock, in Apple's time.
    var time: Float = 0
    /// How far the newest cover has faded in, before its curve.
    var fade: Float = 1
    /// How far the warp has come in, before its curve: 1 behind lyrics, 0 otherwise.
    var mode: Float = 0
    /// The blur, in points.
    var blur: Float = firstBlur
    var spectrum = BackdropSpectrumState()

    /// A new cover starts fading in over the last.
    mutating func newCover() { fade = 0 }

    /// One of Apple's frames.
    mutating func advance(reduceMotion: Bool, exciting: Bool, wide: Bool, recent: [SIMD4<Float>]) {
        let dt = reduceMotion ? Self.reducedStep : Self.step
        time += dt
        spectrum.step(recent: recent)
        // Apple steps both by twice the clock's step over the fade's length.
        let change = 2 * dt / Self.fadeDuration
        fade = min(fade + change, 1)
        mode = exciting ? min(mode + change, 1) : max(mode - change, 0)
        let target = Self.look(wide: wide, exciting: exciting).blur
        if target < blur { blur -= 1 } else if blur < target { blur += 1 }
    }

    /// What the shaders take for a picture of `aspect` (width over height).
    func uniforms(aspect: Double, exciting: Bool, dark: Bool = true, size: (width: Int, height: Int)) -> ArtworkBackdrop.Uniforms {
        let wide = aspect > 1
        var u = ArtworkBackdrop.Uniforms()
        u.time = time
        let a = Float(aspect)
        u.view = wide ? simd_float4x4(diagonal: SIMD4(1, a, 1, 1)) : simd_float4x4(diagonal: SIMD4(1 / a, 1, 1, 1))
        u.textureMix = Self.fadeCurve.value(at: fade)
        u.warp = (sin(time / Self.warpSpeed) + 1) * 0.5
        u.pinch = Self.modeCurve.value(at: mode)
        u.downsample = Self.downsample
        u.width = Int16(clamping: size.width)
        u.height = Int16(clamping: size.height)
        u.saturation = Self.look(wide: wide, exciting: exciting).saturation
        u.whiteScrim = Self.whiteScrim
        u.blackScrim = dark ? Self.blackScrim : Self.lightBlackScrim
        u.spectrum = spectrum.shown
        return u
    }
}

/// A cubic Bézier timing curve from (0, 0) to (1, 1), solved for its output at an input, as Core
/// Animation's media timing functions are.
struct TimingCurve: Equatable {
    let c1: SIMD2<Float>
    let c2: SIMD2<Float>

    init(_ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float) {
        c1 = SIMD2(x1, y1)
        c2 = SIMD2(x2, y2)
    }

    func value(at x: Float) -> Float {
        let x = min(max(x, 0), 1)
        // Bernstein coefficients for each axis.
        func bezier(_ t: Float, _ p1: Float, _ p2: Float) -> Float {
            let c = 3 * p1, b = 3 * (p2 - p1) - c, a = 1 - c - b
            return ((a * t + b) * t + c) * t
        }
        func slope(_ t: Float, _ p1: Float, _ p2: Float) -> Float {
            let c = 3 * p1, b = 3 * (p2 - p1) - c, a = 1 - c - b
            return (3 * a * t + 2 * b) * t + c
        }
        // Newton's method, then bisection should it stall.
        var t = x
        for _ in 0..<8 {
            let error = bezier(t, c1.x, c2.x) - x
            if abs(error) < 1e-6 { return bezier(t, c1.y, c2.y) }
            let d = slope(t, c1.x, c2.x)
            if abs(d) < 1e-6 { break }
            t -= error / d
        }
        var low: Float = 0, high: Float = 1
        t = x
        for _ in 0..<32 {
            let value = bezier(t, c1.x, c2.x)
            if abs(value - x) < 1e-6 { break }
            if value < x { low = t } else { high = t }
            t = (low + high) / 2
        }
        return bezier(t, c1.y, c2.y)
    }
}
