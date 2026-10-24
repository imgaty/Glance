//
//  AudioLevels.swift
//  Glance
//
//  Created by Gaty on 07/10/2026.
//

import Accelerate
import AppKit
import CoreAudio

/// How loud the playing app is in six frequency bands, for the waveforms. It listens to the
/// player's own sound through a Core Audio process tap; nothing is recorded or kept. It only runs
/// while music plays, and only once the user has allowed audio capture.
@MainActor
final class AudioLevels: ObservableObject {
    static let shared = AudioLevels()
    static let bands = 6

    /// 0...1 per bar, left to right. All zero while nothing is being measured.
    @Published private(set) var levels = [Float](repeating: 0, count: bands)
    /// The music's beat, once it's clear, set with the levels. Not published: what pulses with it
    /// reads it as it draws, so nothing else redraws 45 times a second for it.
    private(set) var beat: Beat?

    private var pipeline: TapPipeline?
    private var permissionProbe: TapPipeline?
    private var tappedPID: pid_t = 0
    private var stopTask: Task<Void, Never>?
    private var last: (pid: pid_t, playing: Bool) = (0, false)

    /// macOS shows its audio-capture prompt the first time an app starts a tap. This starts one on
    /// everything the Mac plays, keeps it while the prompt is up (a minute at most), then lets go.
    /// `Permissions.recheck()` starts the waveform once it's allowed.
    func requestPermission(answered: @escaping () -> Void) {
        guard permissionProbe == nil else { return answered() }
        permissionProbe = TapPipeline(target: .everything) { _, _ in }
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
        pipeline = TapPipeline(target: .player(pid)) { [weak self] levels, beat in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.beat = beat
                    self?.levels = levels
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
        stopTask = nil
        pipeline?.stop()
        pipeline = nil
        tappedPID = 0
        beat = nil
        levels = [Float](repeating: 0, count: Self.bands)
    }
}

/// The music's beat: every `period` seconds from `anchor`, as heard, for as long as it's sure of it.
struct Beat: Sendable {
    var period: TimeInterval
    var anchor: Date
    var until: Date

    var bpm: Double { 60 / period }

    /// 1 the moment a beat lands, dying away well before the next; 0 once it's no longer sure.
    func pulse(at date: Date) -> Double {
        guard date < until else { return 0 }
        let beats = date.timeIntervalSince(anchor) / period
        let since = (beats - beats.rounded(.down)) * period
        let attack = 0.03
        return since < attack ? since / attack : exp(-(since - attack) / (period * 0.22))
    }
}

/// The tap, the private aggregate device that carries it, and the analysis, on one serial queue.
/// The audio thread only writes into the ring.
private final class TapPipeline: @unchecked Sendable {
    enum Target {
        /// The process Now Playing names, and every process sharing its responsible app.
        case player(pid_t)
        /// Everything the Mac plays, used once to bring up the permission prompt.
        case everything
    }

    private let queue = DispatchQueue(label: "Glance.AudioLevels")
    private let ring = SampleRing(capacity: 4096)
    private let publish: ([Float], Beat?) -> Void
    private var tapID = AudioObjectID(0)
    private var aggregateID = AudioObjectID(0)
    private var ioProc: AudioDeviceIOProcID?
    private var timer: DispatchSourceTimer?
    private var analyzer: Analyzer?
    /// The tap hears the music as it leaves for the speakers; it's heard this much later (with
    /// AirPods, a fifth of a second), so the beat is put back by as much. Read again every second,
    /// in case the sound moves to other speakers.
    private var heard: TimeInterval = 0
    private var ticksUntilHeard = 0

    init(target: Target, publish: @escaping ([Float], Beat?) -> Void) {
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
        analyzer = Analyzer(sampleRate: Self.sampleRate(of: aggregateID))

        let ring = ring
        let created = AudioDeviceCreateIOProcIDWithBlock(&ioProc, aggregateID, nil) { _, input, _, output, _ in
            // The clock device plays whatever is in the output buffers, so keep them silent.
            for buffer in UnsafeMutableAudioBufferListPointer(output) {
                if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
            }
            ring.write(UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input)))
        }
        guard created == noErr, let ioProc, AudioDeviceStart(aggregateID, ioProc) == noErr else { return false }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 1.0 / 45)
        timer.setEventHandler { [weak self] in
            guard let self, let analyzer, let samples = ring.latest(Analyzer.size) else { return }
            let levels = analyzer.levels(samples)
            if ticksUntilHeard == 0 { heard = Self.outputLatency() }
            ticksUntilHeard = (ticksUntilHeard + 1) % 45
            let now = Date() + heard
            let beat = analyzer.beat.map { Beat(period: $0.period, anchor: now - $0.since, until: now + 1) }
            publish(levels, beat)
        }
        timer.resume()
        self.timer = timer
        return true
    }

    private func tearDown() {
        timer?.cancel()
        timer = nil
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

    private static func sampleRate(of device: AudioObjectID) -> Double {
        var rate: Float64 = 0
        return AudioProperty.read(device, kAudioDevicePropertyNominalSampleRate, &rate) && rate > 0 ? rate : 48_000
    }

    /// How long the sound takes from leaving the Mac's mixer to being heard, in seconds, as the
    /// output device reports it: its own latency, its safety margin, one buffer, and its stream's.
    private static func outputLatency() -> TimeInterval {
        var device = AudioObjectID(0)
        guard AudioProperty.read(system, kAudioHardwarePropertyDefaultOutputDevice, &device), device != 0 else { return 0 }
        func output(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32 {
            var address = AudioProperty.address(selector, scope: kAudioObjectPropertyScopeOutput)
            var value: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr ? value : 0
        }
        var frames =
            output(device, kAudioDevicePropertyLatency) + output(device, kAudioDevicePropertySafetyOffset)
            + output(device, kAudioDevicePropertyBufferFrameSize)
        var address = AudioProperty.address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)
        var stream = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var streamLatency: UInt32 = 0
        if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &stream) == noErr, stream != 0,
            AudioProperty.read(stream, kAudioStreamPropertyLatency, &streamLatency)
        {
            frames += streamLatency
        }
        // A latency past half a second is a device reporting nonsense.
        return min(Double(frames) / sampleRate(of: device), 0.5)
    }

}

/// Mono samples from the audio thread, newest last. The audio thread never waits: if the analysis
/// holds the lock it skips that buffer.
private final class SampleRing: @unchecked Sendable {
    private let lock = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
    private var samples: [Float]
    private var mono: [Float]
    private var head = 0
    private var filled = 0

    init(capacity: Int) {
        samples = [Float](repeating: 0, count: capacity)
        mono = [Float](repeating: 0, count: capacity)
        lock.initialize(to: os_unfair_lock())
    }

    deinit { lock.deallocate() }

    /// Runs on the audio thread, so it allocates nothing.
    func write(_ buffers: UnsafeMutableAudioBufferListPointer) {
        // Average every channel of every buffer into one mono frame.
        var frames = Int.max
        var channelTotal = 0
        for buffer in buffers {
            let channels = max(Int(buffer.mNumberChannels), 1)
            channelTotal += channels
            frames = min(frames, Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * channels))
        }
        let count = min(frames, mono.count)
        guard channelTotal > 0, count > 0, os_unfair_lock_trylock(lock) else { return }
        defer { os_unfair_lock_unlock(lock) }
        let channels = Float(channelTotal)
        for frame in 0..<count { mono[frame] = 0 }
        for buffer in buffers {
            guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let stride = max(Int(buffer.mNumberChannels), 1)
            for frame in 0..<count {
                for channel in 0..<stride { mono[frame] += data[frame * stride + channel] }
            }
        }
        for frame in 0..<count {
            samples[head] = mono[frame] / channels
            head = (head + 1) % samples.count
        }
        filled = min(filled + count, samples.count)
    }

    /// The newest `count` samples in order, or nil until that many have arrived.
    func latest(_ count: Int) -> [Float]? {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        guard filled >= count else { return nil }
        return (0..<count).map { samples[(head - count + $0 + samples.count) % samples.count] }
    }
}

/// Turns 1024 samples into six bar heights, each bar its own part of the sound, as on iOS. How
/// loud the music really is sets how tall the bars can grow, so a quiet song stays low. Within
/// that, six separate slices of the spectrum each move against their own slow-moving average, with
/// what they all share taken out, so a kick, a voice and a hi-hat each move their own bar; bass
/// swells slowly, treble flickers.
private final class Analyzer {
    static let size = 1024
    /// Bass, low mids, mids, upper mids, presence and air, in hertz.
    private static let bands: [(Double, Double)] = [(45, 90), (150, 260), (400, 700), (1_100, 1_800), (3_000, 5_000), (7_000, 12_000)]
    /// Bands to bars: bass sits right of center, as in the iPhone's waveform.
    private static let order = [4, 5, 3, 1, 0, 2]
    private static let attack: [Float] = [0.55, 0.65, 0.75, 0.85, 0.9, 0.95]
    private static let release: [Float] = [0.12, 0.18, 0.25, 0.32, 0.4, 0.5]
    /// The loudness, in dB below full scale, at which the bars stay flat, and at which they can reach the top.
    private static let quiet: Float = -50
    private static let loud: Float = -14

    private let fft = vDSP.FFT(log2n: 10, radix: .radix2, ofType: DSPSplitComplex.self)!
    private let window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: size, isHalfWindow: false)
    private let bins: [Range<Int>]
    /// Each band's level over the last second or so, which it's measured against.
    private var averages: [Float]?
    private var previous = [Float](repeating: -120, count: 6)
    private var volume: Float = 0
    private var smoothed = [Float](repeating: 0, count: 6)
    private let tracker: BeatTracker

    /// The music's pace, and how long ago its last beat landed, once it's clear.
    var beat: (period: TimeInterval, since: TimeInterval)? { tracker.beat }

    init(sampleRate: Double) {
        tracker = BeatTracker(sampleRate: sampleRate)
        let hertzPerBin = sampleRate / Double(Self.size)
        bins = Self.bands.map { low, high in
            let first = max(1, Int(low / hertzPerBin))
            return first..<max(first + 1, min(Self.size / 2, Int(high / hertzPerBin)))
        }
    }

    func levels(_ samples: [Float]) -> [Float] {
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
        // Digital silence reads as nothing at all.
        guard vDSP.sum(power) > 1e-9 else {
            smoothed = [Float](repeating: 0, count: 6)
            volume = 0
            tracker.addSilence()
            return smoothed
        }
        tracker.add(power)

        // How loud the music is, in dB below full scale, sets how tall the bars may grow.
        let loudness = 20 * log10(vDSP.rootMeanSquare(samples) + 1e-9)
        let reach = min(max((loudness - Self.quiet) / (Self.loud - Self.quiet), 0), 1)
        volume += (reach - volume) * (reach > volume ? 0.4 : 0.08)

        var decibels = [Float](repeating: 0, count: 6)
        for band in 0..<6 {
            let energy: Float = power[bins[band]].reduce(0, +) / Float(bins[band].count)
            decibels[band] = 10 * log10(energy + 1e-12)
        }
        var averages = self.averages ?? decibels
        var relative = [Float](repeating: 0, count: 6)
        var kicks = [Float](repeating: 0, count: 6)
        for band in 0..<6 {
            // Above or below its own recent level, 10 dB either way spanning the whole range.
            relative[band] = min(max((decibels[band] - averages[band] + 10) / 20, 0), 1)
            averages[band] += (decibels[band] - averages[band]) * 0.03
            // A sudden rise of more than 3 dB is a hit.
            kicks[band] = min(max((decibels[band] - previous[band] - 3) / 9, 0), 1)
            previous[band] = decibels[band]
        }
        self.averages = averages
        // What every band shares (a hit across the whole spectrum) is taken out, so each bar shows
        // how much its own part of the sound stands out right now.
        let shared = relative.reduce(0, +) / 6, sharedKick = kicks.reduce(0, +) / 6
        // The bars let go at the song's pace: slowly in a slow song, quickly in a fast one.
        let pace = tracker.bpm.map { Float(min(max($0 / 120, 0.7), 1.4)) } ?? 1
        var bars = [Float](repeating: 0, count: 6)
        for band in 0..<6 {
            let own = relative[band] - shared, kick = max(kicks[band] - sharedKick, 0)
            let shape = min(max(0.35 + 0.6 * (relative[band] - 0.5) + 0.8 * own + 0.6 * kick, 0), 1)
            let level = volume * shape
            // Each bar keeps its own temperament: bass swells and lets go slowly, treble flickers.
            let rate = level > smoothed[band] ? Self.attack[band] : Self.release[band] * pace
            smoothed[band] += (level - smoothed[band]) * rate
            bars[Self.order.firstIndex(of: band)!] = smoothed[band]
        }
        return bars
    }
}

/// Finds the music's beat, as a listener taps along: 45 times a second, how strongly the sound
/// starts something new (a rise in loudness across the spectrum, the bass counting double); then,
/// over the last eight seconds of that, the pace at which it repeats most, and where along that
/// pace the strongest starts land. A pace once found is held, so a fill or a quiet bar doesn't throw
/// it, and let go when nothing repeats any more.
final class BeatTracker {
    private static let rate = 45.0
    private static let length = 360
    /// The paces it looks for, as frames between beats: 190 down to 70 beats a minute.
    private static let lags = 14...39

    private let bands: [Range<Int>]
    private var previous: [Float]?
    /// How much the sound usually rises from one frame to the next; only more than that starts
    /// something.
    private var floor: Float = 0
    private var onsets = [Float](repeating: 0, count: length)
    /// Frames so far, the newest being `count - 1`.
    private var count = 0
    /// Frames between beats, once found.
    private var period: Double?
    /// A frame a beat landed on, counted as `count` is.
    private var beatFrame: Double = 0
    /// A different pace, and how many times running it's been found.
    private var rival: (period: Double, seen: Int)?
    private var misses = 0

    init(sampleRate: Double) {
        let hertzPerBin = sampleRate / Double(Analyzer.size)
        // 24 bands evenly spread in pitch, from 40 Hz to 10 kHz. The lowest share bins, which
        // makes the bass count for more.
        bands = (0..<24).map { band in
            let low = 40 * pow(250, Double(band) / 24), high = 40 * pow(250, Double(band + 1) / 24)
            let first = max(1, Int(low / hertzPerBin))
            return first..<max(first + 1, min(Analyzer.size / 2, Int(high / hertzPerBin)))
        }
    }

    var bpm: Double? { period.map { Self.rate * 60 / $0 } }

    /// The pace, and how long ago the last beat landed, in seconds.
    var beat: (period: TimeInterval, since: TimeInterval)? {
        guard let period else { return nil }
        let beats = (Double(count - 1) - beatFrame) / period
        return (period / Self.rate, (beats - beats.rounded(.down)) * period / Self.rate)
    }

    func add(_ power: [Float]) {
        let levels = bands.map { 10 * log10(power[$0].reduce(0, +) / Float($0.count) + 1e-12) }
        var rise: Float = 0
        if let previous {
            for band in levels.indices { rise += max(levels[band] - previous[band], 0) * (band < 6 ? 2 : 1) }
        }
        previous = levels
        record(rise)
    }

    func addSilence() {
        previous = nil
        record(0)
    }

    private func record(_ rise: Float) {
        floor += (rise - floor) * 0.02
        onsets[count % Self.length] = max(rise - floor, 0)
        count += 1
        // Every half second, once there are four seconds to go on.
        if count % 23 == 0, count >= Self.length / 2 { estimate() }
    }

    private func estimate() {
        let n = min(count, Self.length)
        // Softened over a few frames, so beats a fraction of a frame off the pace still line up.
        let raw = (0..<n).map { onsets[(count - n + $0) % Self.length] }
        let kernel: [Float] = [1, 2, 3, 2, 1]
        var x = (0..<n).map { i in
            kernel.indices.reduce(Float(0)) { sum, k in
                let j = i + k - 2
                return j >= 0 && j < n ? sum + raw[j] * kernel[k] : sum
            } / 9
        }
        let mean = x.reduce(0, +) / Float(n)
        x = x.map { $0 - mean }
        func repeats(_ lag: Int) -> Float {
            guard lag < n else { return 0 }
            var sum: Float = 0
            for i in lag..<n { sum += x[i] * x[i - lag] }
            return sum / Float(n - lag)
        }
        let energy = repeats(0)
        guard energy > 1e-6 else { return lose() }
        var scores: [Int: Float] = [:]
        for lag in (Self.lags.lowerBound - 1)...(Self.lags.upperBound + 1) {
            // Most music sits near 120 beats a minute; far from it, a pace has to repeat more
            // clearly to win. Twice as long apart counts too, as a pace's bars do.
            let prior = Float(exp(-0.5 * pow(log2(Self.rate * 60 / Double(lag) / 120) / 0.9, 2)))
            scores[lag] = (repeats(lag) + 0.5 * repeats(lag * 2)) * prior
        }
        guard let best = Self.lags.max(by: { scores[$0]! < scores[$1]! }), repeats(best) / energy > 0.15 else { return lose() }
        // Between whole frames: the top of the curve through the best and its neighbors.
        let (before, at, after) = (scores[best - 1]!, scores[best]!, scores[best + 1]!)
        let bend = before - 2 * at + after
        let found = Double(best) + (bend < 0 ? Double(0.5 * (before - after) / bend) : 0)
        misses = 0
        settle(on: found)
        if let period { place(period) }
    }

    /// Held, and eased toward when found again. Another pace takes over once found three times
    /// running, as when the song changes; one twice or half as fast, or in thirds of it, which
    /// the same song often seems to be in for a bar or two, only once found for four seconds.
    private func settle(on found: Double) {
        guard let current = period else { return period = found }
        func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) / b < 0.06 }
        if near(found, current) {
            period = current + (found - current) * 0.3
            rival = nil
            return
        }
        let related = [2, 0.5, 1.5, 2.0 / 3].contains { near(found, current * $0) }
        let seen = rival.map { near(found, $0.period) ? $0.seen + 1 : 1 } ?? 1
        if seen >= (related ? 8 : 3) {
            period = found
            rival = nil
        } else {
            rival = (found, seen)
        }
    }

    /// Where the beats land: of every way of laying them back from now, a frame apart, the one
    /// landing on the strongest starts. Eased toward, so the pulses don't stutter.
    private func place(_ period: Double) {
        let n = min(count, Self.length)
        var best = (offset: 0.0, score: -Float.infinity)
        for offset in stride(from: 0.0, to: period, by: 1) {
            var score: Float = 0
            var back = offset
            while back < Double(n - 1) {
                score += onsets[(count - 1 - Int(back.rounded())) % Self.length]
                back += period
            }
            if score > best.score { best = (offset, score) }
        }
        let now = Double(count - 1)
        let measured = now - best.offset
        let latest = beatFrame + ((now - beatFrame) / period).rounded(.down) * period
        var error = (measured - latest).truncatingRemainder(dividingBy: period)
        if error > period / 2 { error -= period } else if error < -period / 2 { error += period }
        beatFrame = abs(error) > period * 0.35 ? measured : latest + error * 0.3
    }

    private func lose() {
        misses += 1
        // Two seconds with nothing repeating: there's no beat to follow.
        if misses >= 4 {
            period = nil
            rival = nil
        }
    }
}
