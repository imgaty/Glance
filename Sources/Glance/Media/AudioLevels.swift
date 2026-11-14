//
//  AudioLevels.swift
//  Glance
//
//  Created by Gaty on 07/10/2026.
//

import Accelerate
import AppKit
import CoreAudio

/// How loud the playing app is in six frequency bands, for the waveforms, and its beat, for the
/// colors behind the player. It listens to the player's own sound through a Core Audio process
/// tap; nothing is recorded or kept. What it hears is shown as it's heard, held back by as long as
/// the speakers or headphones take to play it. It only runs while music plays, and only once the
/// user has allowed audio capture.
@MainActor
final class AudioLevels: ObservableObject {
    static let shared = AudioLevels()
    static let bands = 6

    /// 0...1 per bar, left to right. All zero while nothing is being measured.
    @Published private(set) var levels = [Float](repeating: 0, count: bands)
    /// 0...1: 1 on a kick or a bass note's attack, easing off over a fraction of a second. Not
    /// published: the colors read it as they're drawn, frame by frame.
    private(set) var beat: Float = 0
    /// The same beat as the colors behind the player show it: only a huge bang shows at all, a beat
    /// with the waveform near its full height, swelling in quickly and easing away. Read as they're
    /// drawn, as the beat is.
    private(set) var pulse: Float = 0

    /// How tall the waveform's tallest bar must reach, of its full height, for a beat to show in the
    /// colors: below it none does, so they hold still for all but the biggest hits.
    nonisolated static let bang: Float = 0.9

    /// How much of a beat the colors show: none while the tallest bar is under `bang`, rising to all
    /// of it at the waveform's full height.
    nonisolated static func shown(_ beat: Float, tallest: Float) -> Float {
        beat * min(max((tallest - bang) / (1 - bang), 0), 1)
    }

    /// A reading's step of the pulse toward what's shown: quick to rise, so a bang lands, and slow to
    /// fall.
    nonisolated static func eased(_ pulse: Float, toward shown: Float) -> Float {
        pulse + (shown - pulse) * (shown > pulse ? 0.5 : 0.06)
    }

    private var pipeline: TapPipeline?
    private var permissionProbe: TapPipeline?
    private var tappedPID: pid_t = 0
    private var generation: UInt = 0
    private var stopTask: Task<Void, Never>?
    private var last: (pid: pid_t, playing: Bool) = (0, false)

    /// macOS shows its audio-capture prompt the first time an app starts a tap. This starts one on
    /// everything the Mac plays, keeps it while the prompt is up (a minute at most), then lets go.
    /// `Permissions.recheck()` starts the waveform once it's allowed.
    func requestPermission(answered: @escaping () -> Void) {
        guard permissionProbe == nil else { return answered() }
        permissionProbe = TapPipeline(target: .everything) { _ in }
        Task { [weak self] in
            var checks = 0
            while await Permissions.recheck().audio == .notDetermined, checks < 60 {
                try? await Task.sleep(for: .seconds(1))
                checks += 1
            }
            self?.permissionProbe?.stop()
            self?.permissionProbe = nil
            answered()
        }
    }

    /// Measures `pid` while it plays; stops a moment after playback pauses.
    func follow(pid: pid_t, playing: Bool) {
        last = (pid, playing)
        guard playing, pid > 0 else {
            if pipeline != nil, stopTask == nil {
                stopTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled else { return }
                    self?.stop()
                }
            }
            return
        }
        stopTask?.cancel()
        stopTask = nil
        guard pid != tappedPID || pipeline == nil else { return }
        stop()
        guard Permissions.audioCapture == .granted else { return }
        tappedPID = pid
        let generation = generation
        pipeline = TapPipeline(target: .player(pid)) { [weak self] reading in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.generation == generation else { return }
                    self.receive(reading)
                }
            }
        }
    }

    /// Starts listening as soon as audio capture is allowed, rather than at the next track.
    func permissionChanged() {
        tappedPID = 0
        follow(pid: last.pid, playing: last.playing)
    }

    private func stop() {
        generation &+= 1
        stopTask = nil
        pipeline?.stop()
        pipeline = nil
        tappedPID = 0
        levels = [Float](repeating: 0, count: Self.bands)
        beat = 0
        pulse = 0
    }

    /// Bars and beats have separate clocks. A delayed bar must not replay an older beat.
    func receive(_ reading: AudioReading) {
        if let levels = reading.levels {
            if levels != self.levels { self.levels = levels }
        } else {
            beat = reading.beat
            pulse = Self.eased(pulse, toward: Self.shown(reading.beat, tallest: levels.max() ?? 0))
        }
    }
}

/// What the analysis hears at a moment: the bars' levels, when there's a new reading of them, the
/// beat, and how loud the sound is, 0 to 1.
struct AudioReading: Equatable {
    var levels: [Float]?
    var beat: Float
    var loudness: Float = 0
}

/// Readings held back until the sound they were made from is heard: the tap hears the player as it
/// plays, ahead of the speakers or the headphones by as long as they take to play it.
struct HeardLater {
    /// In seconds.
    var delay: TimeInterval = 0
    private var waiting: [(time: TimeInterval, reading: AudioReading)] = []

    /// Takes a reading made at `time`; gives back the latest one that's due by then, if any.
    mutating func take(_ reading: AudioReading, at time: TimeInterval) -> AudioReading? {
        waiting.append((time, reading))
        var due: AudioReading?
        while let first = waiting.first, first.time + delay <= time { due = waiting.removeFirst().reading }
        return due
    }
}

/// The tap, the private aggregate device that carries it, and the analysis, on one serial queue.
/// The audio thread only writes into the ring.
final class TapPipeline: @unchecked Sendable {
    enum Target {
        /// The process Now Playing names, and every process sharing its responsible app.
        case player(pid_t)
        /// Everything the Mac plays, used once to bring up the permission prompt.
        case everything
    }

    private let queue = DispatchQueue(label: "Glance.AudioLevels")
    private let publish: (AudioReading) -> Void
    /// The beat and the bars, each held back until it's heard.
    private var heard = HeardLater()
    private var heardBars = WaveformDelivery()
    private var active = false
    private var ticks = 0
    private var tapID = AudioObjectID(0)
    private var aggregateID = AudioObjectID(0)
    private var ioProc: AudioDeviceIOProcID?
    private var timer: DispatchSourceTimer?
    private var barsTimer: DispatchSourceTimer?
    private var barsReady: DispatchSourceUserDataAdd?
    private var analyzer: Analyzer?
    private var binned: BinnedFFT?

    init(target: Target, publish: @escaping (AudioReading) -> Void) {
        self.publish = publish
        queue.async { [self] in
            if !start(target) { tearDown() }
        }
    }

    func stop() {
        queue.async { [self] in tearDown() }
    }

    private func start(_ target: Target) -> Bool {
        let description: CATapDescription
        switch target {
        case .player(let pid):
            let processes = AudioProperty.processes(of: pid)
            guard !processes.isEmpty else { return false }
            description = CATapDescription(stereoMixdownOfProcesses: processes)
        case .everything:
            description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        }
        description.name = "Glance waveform"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        guard AudioHardwareCreateProcessTap(description, &tapID) == noErr, tapID != 0,
            let clock = Self.clockDeviceUID()
        else { return false }

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Glance waveform",
            kAudioAggregateDeviceUIDKey: AudioProperty.ownDevicePrefix + "waveform." + UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceMainSubDeviceKey: clock,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: clock]],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: description.uuid.uuidString,
                    kAudioSubTapDriftCompensationKey: true,
                ]
            ],
            kAudioAggregateDeviceTapAutoStartKey: true,
        ]
        guard AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID) == noErr, aggregateID != 0
        else { return false }
        let rate = Self.sampleRate(of: aggregateID)
        analyzer = Analyzer(sampleRate: rate)
        binned = BinnedFFT(sampleRate: rate)

        let ring = SampleRing(capacity: BinnedFFT.size * 8, sampleRate: rate)
        active = true
        heard.delay = Self.heardAfter(aggregate: aggregateID, window: Analyzer.size)
        heardBars.delay = Self.waveformDelay(sampleRate: rate)
        let barsTimer = DispatchSource.makeTimerSource(queue: queue)
        barsTimer.schedule(deadline: .distantFuture)
        barsTimer.setEventHandler { [weak self] in self?.deliverBars() }
        barsTimer.resume()
        self.barsTimer = barsTimer
        let barsReady = DispatchSource.makeUserDataAddSource(queue: queue)
        barsReady.setEventHandler { [weak self] in
            guard let self, active, let binned else { return }
            // Snapshot a bounded batch so a busy producer cannot starve delivery or teardown.
            for _ in 0..<ring.readyWindowCount {
                guard let window = ring.nextWindow() else { break }
                let reading = AudioReading(levels: binned.levels(window.samples), beat: 0, loudness: analyzer?.loudness ?? 0)
                heardBars.append(reading, at: window.completedAt, generation: window.generation)
            }
            deliverBars()
            if ring.readyWindowCount > 0 { self.barsReady?.add(data: 1) }
        }
        barsReady.resume()
        self.barsReady = barsReady
        let created = AudioDeviceCreateIOProcIDWithBlock(&ioProc, aggregateID, nil) { _, input, inputTime, output, _ in
            // The clock device plays whatever is in the output buffers, so keep them silent.
            for buffer in UnsafeMutableAudioBufferListPointer(output) {
                if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
            }
            if ring.write(UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input)), timestamp: inputTime.pointee) {
                barsReady.add(data: 1)
            }
        }
        guard created == noErr, let ioProc, AudioDeviceStart(aggregateID, ioProc) == noErr else { return false }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 1.0 / 45)
        timer.setEventHandler { [weak self] in
            guard let self, let analyzer, let samples = ring.latest(Analyzer.size) else { return }
            // The sound can move to other speakers or headphones as it plays: how late it's heard is
            // read again every second.
            if ticks % 45 == 0 {
                heard.delay = Self.heardAfter(aggregate: aggregateID, window: Analyzer.size)
                heardBars.delay = Self.waveformDelay(sampleRate: rate)
                deliverBars()
            }
            ticks += 1
            let beat = analyzer.beat(samples)
            let reading = AudioReading(levels: nil, beat: beat, loudness: analyzer.loudness)
            if let due = heard.take(reading, at: ProcessInfo.processInfo.systemUptime) { publish(due) }
        }
        timer.resume()
        self.timer = timer
        return true
    }

    /// Wake for the reading's own deadline, even if no further audio arrives. A stalled consumer
    /// shows only the newest due reading instead of replaying a burst of old movement.
    private func deliverBars() {
        guard active else { return }
        let now = Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
        if let reading = heardBars.takeDue(at: now) { publish(reading) }
        if let next = heardBars.nextDeadline {
            // Recheck unusually distant driver times without overflowing Dispatch's nanoseconds.
            barsTimer?.schedule(deadline: .now() + min(max(next - now, 0), 1), leeway: .nanoseconds(0))
        } else {
            barsTimer?.schedule(deadline: .distantFuture)
        }
    }

    private func tearDown() {
        active = false
        heardBars = WaveformDelivery()
        timer?.cancel()
        timer = nil
        barsTimer?.cancel()
        barsTimer = nil
        barsReady?.cancel()
        barsReady = nil
        if aggregateID != 0 {
            if let ioProc {
                AudioDeviceStop(aggregateID, ioProc)
                AudioDeviceDestroyIOProcID(aggregateID, ioProc)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != 0 { AudioHardwareDestroyProcessTap(tapID) }
        ioProc = nil
        aggregateID = 0
        tapID = 0
    }

    // MARK: Core Audio

    private static let system = AudioProperty.system

    /// The built-in speakers keep the aggregate's time. Unlike AirPods, they have no microphone,
    /// so running the aggregate never switches headphones into headset mode.
    private static func clockDeviceUID() -> String? {
        let builtIn = AudioProperty.readArray(system, kAudioHardwarePropertyDevices).first { device in
            var transport: UInt32 = 0
            return AudioProperty.read(device, kAudioDevicePropertyTransportType, &transport)
                && transport == kAudioDeviceTransportTypeBuiltIn
                && AudioProperty.size(of: device, kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput) > 0
                && AudioProperty.size(of: device, kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput) == 0
        }
        var device = builtIn ?? 0
        if device == 0, !AudioProperty.read(system, kAudioHardwarePropertyDefaultOutputDevice, &device) { return nil }
        return AudioProperty.uid(of: device)
    }

    /// How much later the sound is heard than the tap hears it: as long as the Mac's sound output
    /// takes to play it, less what the aggregate's buffer and the analysis's window of `window`
    /// samples already hold it back.
    private static func heardAfter(aggregate: AudioObjectID, window: Int) -> TimeInterval {
        var output = AudioObjectID(0)
        guard AudioProperty.read(system, kAudioHardwarePropertyDefaultOutputDevice, &output), output != 0 else { return 0 }
        var buffer: UInt32 = 0
        _ = AudioProperty.read(aggregate, kAudioDevicePropertyBufferFrameSize, &buffer)
        let own = (Double(buffer) + Double(window) / 2) / sampleRate(of: aggregate)
        return max(AudioProperty.outputLatency(of: output) - own, 0)
    }

    /// Waveform timestamps already describe the samples, not the callback's arrival. Only the
    /// window's age is deducted here; subtracting the aggregate buffer again would lead the sound.
    private static func waveformDelay(sampleRate: Double) -> TimeInterval {
        var output = AudioObjectID(0)
        guard AudioProperty.read(system, kAudioHardwarePropertyDefaultOutputDevice, &output), output != 0 else { return 0 }
        return AudioSampleWindow.outputDelay(latency: AudioProperty.outputLatency(of: output), sampleRate: sampleRate)
    }

    private static func sampleRate(of device: AudioObjectID) -> Double {
        var rate: Float64 = 0
        return AudioProperty.read(device, kAudioDevicePropertyNominalSampleRate, &rate) && rate > 0 ? rate : 48_000
    }

}

/// The beat, which the colors behind the player pulse on, from 1024 samples at a time, 45 times a
/// second: the bass rising more sharply than it has been lately, to well above its usual level, as a
/// kick or a bass note starts; no sooner than a fifth of a second after the last. The bars come from
/// `BinnedFFT`.
final class Analyzer {
    static let size = 1024
    /// The bass, in hertz, which the beat is heard in.
    static let bass: (Double, Double) = (45, 90)
    /// The loudness, in dB below full scale, at which the music is too quiet to have a beat, and at
    /// which it's loud enough for any.
    private static let quiet: Float = -50
    private static let loud: Float = -14
    /// The least rise in the bass, in dB from one reading to the next, that's a beat; the fewest
    /// readings (45 a second) between two beats; how much of the beat is left at the next; and how
    /// far the beat shown moves toward it at each reading, so it swells in rather than snapping.
    private static let beatRise: Float = 4
    /// How far above its usual level, in dB, the bass must reach.
    private static let beatAbove: Float = 3
    private static let beatGap = 9
    private static let beatFade: Float = 0.86
    private static let beatAttack: Float = 0.5

    private let fft = vDSP.FFT(log2n: 10, radix: .radix2, ofType: DSPSplitComplex.self)!
    private let window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: size, isHalfWindow: false)
    private let bins: Range<Int>
    /// The bass's level over the last second or so, which a rise is measured against.
    private var average: Float?
    private var previous: Float = -120
    private var volume: Float = 0
    /// The last beat, fading; and the beat as shown, following it in.
    private var kick: Float = 0
    private var beat: Float = 0
    private var sinceBeat = 0
    /// How sharply the bass has been rising lately, which a beat must clearly beat.
    private var rises: Float = 0
    /// The beat as of the last reading.
    var lastBeat: Float { beat }
    /// How loud the sound is, 0 when too quiet for a beat to 1 when loud enough for any, eased.
    var loudness: Float { volume }

    init(sampleRate: Double) {
        let hertzPerBin = sampleRate / Double(Self.size)
        let first = max(1, Int(Self.bass.0 / hertzPerBin))
        bins = first..<max(first + 1, min(Self.size / 2, Int(Self.bass.1 / hertzPerBin)))
    }

    func beat(_ samples: [Float]) -> Float {
        let windowed = vDSP.multiply(samples, window)
        var real = [Float](repeating: 0, count: Self.size / 2)
        var imaginary = [Float](repeating: 0, count: Self.size / 2)
        var power = [Float](repeating: 0, count: Self.size / 2)
        real.withUnsafeMutableBufferPointer { realPointer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryPointer in
                var split = DSPSplitComplex(realp: realPointer.baseAddress!, imagp: imaginaryPointer.baseAddress!)
                windowed.withUnsafeBufferPointer { input in
                    input.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: Self.size / 2) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(Self.size / 2))
                    }
                }
                fft.forward(input: split, output: &split)
                vDSP_zvmags(&split, 1, &power, 1, vDSP_Length(Self.size / 2))
            }
        }
        // Digital silence has no beat.
        guard vDSP.sum(power) > 1e-9 else {
            volume = 0
            kick = 0
            beat = 0
            return 0
        }

        // How loud the music is, in dB below full scale: a quiet song has no beat.
        let loudness = 20 * log10(vDSP.rootMeanSquare(samples) + 1e-9)
        let reach = min(max((loudness - Self.quiet) / (Self.loud - Self.quiet), 0), 1)
        volume += (reach - volume) * (reach > volume ? 0.4 : 0.08)

        let bass = 10 * log10(power[bins].reduce(0, +) / Float(bins.count) + 1e-12)
        // How sharply the bass rose since the last reading, and how far above its usual level, so the
        // bass only wavering isn't a beat. The first reading has nothing to go by.
        let rise = bass - previous
        let above = bass - (average ?? bass)
        kick *= Self.beatFade
        sinceBeat += 1
        if average != nil, rise > max(Self.beatRise, rises * 2.5), above > Self.beatAbove, sinceBeat >= Self.beatGap, volume > 0.05 {
            kick = max(kick, 0.55 + 0.45 * min((rise - Self.beatRise) / 9, 1))
            sinceBeat = 0
        }
        beat = kick > beat ? beat + (kick - beat) * Self.beatAttack : kick
        rises += (max(rise, 0) - rises) * 0.05
        average = (average ?? bass) + (bass - (average ?? bass)) * 0.03
        previous = bass
        return beat
    }
}

/// The six bars, made exactly as Apple's own waveform makes them: `MediaCoreUI`'s
/// `WaveformBinnedFFT`, read from macOS 27.3's code and its log. A window of 4096 samples, once
/// each as it fills (about 12 times a second), Hann windowed, through an FFT; each bar the sum of
/// the bins in its band, bass at the left, the bins counted from 20 Hz up; the sum raised to the
/// power 0.4 after a 0.6 gain, each bar a twentieth lower than the one to its left, then shaped by
/// Apple's own curve and kept between 0 and 1. Nothing is eased here: the bars animate each reading
/// in (see `LiveBarsView`).
final class BinnedFFT {
    static let size = 4096
    /// The bands' edges, in hertz, left to right.
    static let edges: [Float] = [20, 81, 170, 527, 1_500, 4_500, 10_000]
    /// Each bar this much lower than the one to its left, as a share.
    static let tilt: Float = 0.05
    static let gain: Float = 0.6
    static let exponent: Float = 0.4
    /// The curve each bar is shaped by: a bar of `v` stands `v` times this tall.
    static let curve: [Float] = [3.84082293510437, -8.182433128356934, 7.772333145141602, -2.4307219982147217]

    private let fft = vDSP.FFT(log2n: 12, radix: .radix2, ofType: DSPSplitComplex.self)!
    private let window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: size, isHalfWindow: false)
    private let hertzPerBin: Float

    init(sampleRate: Double) {
        hertzPerBin = Float(sampleRate) / Float(Self.size)
    }

    /// The bars from the latest `size` samples.
    func levels(_ samples: [Float]) -> [Float] {
        let half = Self.size / 2
        let windowed = vDSP.multiply(samples, window)
        var real = [Float](repeating: 0, count: half)
        var imaginary = [Float](repeating: 0, count: half)
        var power = [Float](repeating: 0, count: half)
        real.withUnsafeMutableBufferPointer { realPointer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryPointer in
                var split = DSPSplitComplex(realp: realPointer.baseAddress!, imagp: imaginaryPointer.baseAddress!)
                windowed.withUnsafeBufferPointer { input in
                    input.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
                    }
                }
                fft.forward(input: split, output: &split)
                vDSP_zvmags(&split, 1, &power, 1, vDSP_Length(half))
            }
        }
        // Each bin's size, scaled as Apple scales it: by 2 over the bins counted.
        let magnitudes = vDSP.multiply(2 / Float(half), vForce.sqrt(power))
        return Self.bars(magnitudes, hertzPerBin: hertzPerBin)
    }

    /// The bars from each bin's size. The bins are counted off from the first edge up, one bin's width
    /// each, so the first bar takes the lowest bins whatever they hold.
    static func bars(_ magnitudes: [Float], hertzPerBin: Float) -> [Float] {
        var hertz = edges[0]
        var bin = 0
        return (0..<edges.count - 1).map { band in
            var sum: Float = 0
            while bin < magnitudes.count, hertz < edges[band + 1] {
                sum += magnitudes[bin]
                hertz += hertzPerBin
                bin += 1
            }
            return height(of: (1 - tilt * Float(band)) * powf(gain * sum, exponent))
        }
    }

    /// A bar of `v`, shaped by the curve and kept between 0 and 1.
    static func height(of v: Float) -> Float {
        let shaped = v * (curve[0] + v * (curve[1] + v * (curve[2] + v * curve[3])))
        return min(max(v * shaped, 0), 1)
    }
}
