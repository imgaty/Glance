//
//  WaveformSamples.swift
//  Glance
//
//  Created by Gaty on 14/11/2026.
//

import CoreAudio
import Foundation

/// One complete, previously unread window. Its time comes from the audio clock, not the analysis
/// timer, so callback size and scheduling jitter do not change which samples belong together.
struct AudioSampleWindow {
    let samples: [Float]
    let completedAt: TimeInterval
    let generation: UInt

    static func outputDelay(latency: TimeInterval, sampleRate: Double, windowSize: Int = BinnedFFT.size) -> TimeInterval {
        latency.isFinite ? max(latency - Double(windowSize) / (2 * sampleRate), 0) : 0
    }
}

/// A bounded, single-producer ring. The audio callback never waits or allocates; analysis copies
/// a completed window under the lock and transforms it afterward. Beat detection reads the latest
/// samples independently, without consuming waveform windows.
final class SampleRing: @unchecked Sendable {
    private let lock = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
    private let samples: UnsafeMutablePointer<Float>
    private let capacity: Int
    private let windowSize: Int
    private let sampleRate: Double
    private var completedTimes: [TimeInterval]
    private var written = 0
    private var consumed = 0
    private var generation: UInt = 0
    private var expectedSampleTime: Double?
    // Only the audio producer accesses this flag, including when it cannot acquire the lock.
    private var interrupted = false

    init(capacity: Int, sampleRate: Double, windowSize: Int = BinnedFFT.size) {
        precondition(windowSize > 0 && capacity >= windowSize && capacity.isMultiple(of: windowSize))
        precondition(sampleRate.isFinite && sampleRate > 0)
        self.capacity = capacity
        self.windowSize = windowSize
        self.sampleRate = sampleRate
        samples = .allocate(capacity: capacity)
        samples.initialize(repeating: 0, count: capacity)
        completedTimes = Array(repeating: 0, count: capacity / windowSize)
        lock.initialize(to: os_unfair_lock())
    }

    deinit {
        samples.deinitialize(count: capacity)
        samples.deallocate()
        lock.deinitialize(count: 1)
        lock.deallocate()
    }

    var readyWindowCount: Int {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        let oldest = max(written - capacity, 0)
        let first = max(consumed, (oldest + windowSize - 1) / windowSize)
        return max(written / windowSize - first, 0)
    }

    /// True when at least one complete window is ready. Null-data streams are disabled by Core
    /// Audio and do not count toward the mono average. A dropped buffer breaks the partial window.
    func write(_ buffers: UnsafeMutableAudioBufferListPointer, timestamp: AudioTimeStamp) -> Bool {
        var frames = Int.max
        var channels = 0
        for buffer in buffers where buffer.mData != nil && buffer.mNumberChannels > 0 {
            let count = Int(buffer.mNumberChannels)
            channels += count
            frames = min(frames, Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * count))
        }
        guard channels > 0, frames > 0, os_unfair_lock_trylock(lock) else {
            interrupted = true
            return false
        }
        defer { os_unfair_lock_unlock(lock) }
        let sampleTime = timestamp.mFlags.contains(.sampleTimeValid) && timestamp.mSampleTime.isFinite ? timestamp.mSampleTime : nil
        let gap = sampleTime.flatMap { current in expectedSampleTime.map { abs(current - $0) > 0.5 } } ?? false
        if interrupted || gap {
            // Discard pending history as well as the partial block; never splice across a gap.
            written = 0
            consumed = 0
            generation &+= 1
            interrupted = false
        }
        expectedSampleTime = sampleTime.map { $0 + Double(frames) }
        let scalar = timestamp.mFlags.contains(.rateScalarValid) && timestamp.mRateScalar.isFinite && timestamp.mRateScalar > 0 ? timestamp.mRateScalar : 1
        let step = scalar / sampleRate
        let firstTime: Double
        if timestamp.mFlags.contains(.hostTimeValid) {
            firstTime = Double(AudioConvertHostTimeToNanos(timestamp.mHostTime)) / 1_000_000_000
        } else {
            firstTime = Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000 - Double(frames) * step
        }
        let previous = written / windowSize
        for frame in 0..<frames {
            var mono: Float = 0
            for buffer in buffers where buffer.mData != nil && buffer.mNumberChannels > 0 {
                let stride = Int(buffer.mNumberChannels)
                let data = buffer.mData!.assumingMemoryBound(to: Float.self)
                for channel in 0..<stride { mono += data[frame * stride + channel] }
            }
            samples[written % capacity] = mono / Float(channels)
            written += 1
            if written.isMultiple(of: windowSize) {
                completedTimes[(written / windowSize - 1) % completedTimes.count] = firstTime + Double(frame + 1) * step
            }
        }
        return written / windowSize > previous
    }

    /// Takes the next complete block exactly once. If the consumer fell behind the bounded ring,
    /// only whole overwritten blocks are skipped; a partially overwritten window is never read.
    func nextWindow() -> AudioSampleWindow? {
        // Allocate outside the lock so the audio thread is held off only for a contiguous copy.
        var copied = [Float](repeating: 0, count: windowSize)
        os_unfair_lock_lock(lock)
        let oldest = max(written - capacity, 0)
        consumed = max(consumed, (oldest + windowSize - 1) / windowSize)
        guard (consumed + 1) * windowSize <= written else {
            os_unfair_lock_unlock(lock)
            return nil
        }
        let offset = consumed * windowSize % capacity
        copied.withUnsafeMutableBufferPointer { $0.baseAddress!.update(from: samples + offset, count: windowSize) }
        let time = completedTimes[consumed % completedTimes.count]
        let generation = generation
        consumed += 1
        os_unfair_lock_unlock(lock)
        return AudioSampleWindow(samples: copied, completedAt: time, generation: generation)
    }

    func latest(_ count: Int) -> [Float]? {
        precondition(count > 0 && count <= capacity)
        var copied = [Float](repeating: 0, count: count)
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        guard written >= count else { return nil }
        let start = (written - count) % capacity
        let first = min(count, capacity - start)
        copied.withUnsafeMutableBufferPointer {
            $0.baseAddress!.update(from: samples + start, count: first)
            if first < count { ($0.baseAddress! + first).update(from: samples, count: count - first) }
        }
        return copied
    }
}

/// Delayed waveform delivery has its own wake-up. Updating the output delay moves every remaining
/// deadline together; consumed readings never return, including after a route becomes faster.
struct WaveformDelivery {
    /// More than ten seconds at the usual rate, while bounding a broken driver's future timestamps.
    static let capacity = 128
    var delay: TimeInterval = 0
    private var generation: UInt?
    private var waiting: [(time: TimeInterval, reading: AudioReading)] = []

    var nextDeadline: TimeInterval? { waiting.first.map { $0.time + delay } }

    mutating func append(_ reading: AudioReading, at time: TimeInterval, generation: UInt) {
        if self.generation != generation {
            waiting.removeAll(keepingCapacity: true)
            self.generation = generation
        }
        guard time.isFinite else { return }
        waiting.append((time, reading))
        if waiting.count > Self.capacity { waiting.removeFirst(waiting.count - Self.capacity) }
    }

    mutating func takeDue(at time: TimeInterval) -> AudioReading? {
        var due: AudioReading?
        while let first = waiting.first, first.time + delay <= time { due = waiting.removeFirst().reading }
        return due
    }
}
