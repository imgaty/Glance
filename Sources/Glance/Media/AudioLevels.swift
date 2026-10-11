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
        pipeline = TapPipeline(target: .player(pid)) { [weak self] levels in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.levels = levels } }
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
        levels = [Float](repeating: 0, count: Self.bands)
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
    private let publish: ([Float]) -> Void
    private var tapID = AudioObjectID(0)
    private var aggregateID = AudioObjectID(0)
    private var ioProc: AudioDeviceIOProcID?
    private var timer: DispatchSourceTimer?
    private var analyzer: Analyzer?

    init(target: Target, publish: @escaping ([Float]) -> Void) {
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
            publish(analyzer.levels(samples))
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

    init(sampleRate: Double) {
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
            return smoothed
        }

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
        var bars = [Float](repeating: 0, count: 6)
        for band in 0..<6 {
            let own = relative[band] - shared, kick = max(kicks[band] - sharedKick, 0)
            let shape = min(max(0.35 + 0.6 * (relative[band] - 0.5) + 0.8 * own + 0.6 * kick, 0), 1)
            let level = volume * shape
            // Each bar keeps its own temperament: bass swells and lets go slowly, treble flickers.
            let rate = level > smoothed[band] ? Self.attack[band] : Self.release[band]
            smoothed[band] += (level - smoothed[band]) * rate
            bars[Self.order.firstIndex(of: band)!] = smoothed[band]
        }
        return bars
    }
}
