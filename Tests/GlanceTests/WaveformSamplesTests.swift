//
//  WaveformSamplesTests.swift
//  GlanceTests
//
//  Created by Gaty on 14/11/2026.
//

import CoreAudio
import Testing

@testable import Glance

@Suite("Waveform samples")
struct WaveformSamplesTests {
    private func write(_ values: [Float], to ring: SampleRing, startingAt sample: Double, time: Double = 10, scalar: Double = 1) -> Bool {
        values.withUnsafeBufferPointer { data in
            var list = AudioBufferList(
                mNumberBuffers: 1,
                mBuffers: AudioBuffer(
                    mNumberChannels: 1, mDataByteSize: UInt32(data.count * MemoryLayout<Float>.size),
                    mData: UnsafeMutableRawPointer(mutating: data.baseAddress)))
            var stamp = AudioTimeStamp()
            stamp.mSampleTime = sample
            stamp.mHostTime = AudioConvertNanosToHostTime(UInt64(time * 1_000_000_000))
            stamp.mRateScalar = scalar
            stamp.mFlags = [.sampleTimeValid, .hostTimeValid, .rateScalarValid]
            return withUnsafeMutablePointer(to: &list) { ring.write(UnsafeMutableAudioBufferListPointer($0), timestamp: stamp) }
        }
    }

    @Test("Uneven callback sizes produce consecutive windows once, independent of polling")
    func unevenBuffers() throws {
        let ring = SampleRing(capacity: 32, sampleRate: 8, windowSize: 8)
        #expect(!write([0, 1, 2], to: ring, startingAt: 0))
        #expect(ring.nextWindow() == nil)
        #expect(write([3, 4, 5, 6, 7, 8, 9], to: ring, startingAt: 3, time: 10.375))
        let first = try #require(ring.nextWindow())
        #expect(first.samples == (0..<8).map(Float.init))
        #expect(abs(first.completedAt - 11) < 0.000001)
        #expect(ring.nextWindow() == nil)
        #expect(write([10, 11, 12, 13, 14, 15], to: ring, startingAt: 10, time: 11.25))
        let second = try #require(ring.nextWindow())
        #expect(second.samples == (8..<16).map(Float.init))
        #expect(abs(second.completedAt - 12) < 0.000001)
        #expect(ring.nextWindow() == nil)
        // The beat reader does not consume or rearrange waveform windows.
        #expect(ring.latest(4) == [12, 13, 14, 15])
        #expect(ring.nextWindow() == nil)
    }

    @Test("Overflow skips whole overwritten blocks, including a partially overwritten oldest block")
    func overflow() throws {
        let ring = SampleRing(capacity: 16, sampleRate: 8, windowSize: 8)
        #expect(write((0..<25).map(Float.init), to: ring, startingAt: 0))
        #expect(try #require(ring.nextWindow()).samples == (16..<24).map(Float.init))
        #expect(ring.nextWindow() == nil)
        #expect(write((25..<32).map(Float.init), to: ring, startingAt: 25))
        #expect(try #require(ring.nextWindow()).samples == (24..<32).map(Float.init))
    }

    @Test("An input gap discards the partial window instead of joining unrelated samples")
    func discontinuity() throws {
        let ring = SampleRing(capacity: 16, sampleRate: 8, windowSize: 8)
        _ = write((0..<8).map(Float.init), to: ring, startingAt: 0)
        let before = try #require(ring.nextWindow())
        _ = write([8, 9, 10], to: ring, startingAt: 8)
        _ = write((20..<28).map(Float.init), to: ring, startingAt: 20)
        let after = try #require(ring.nextWindow())
        #expect(after.samples == (20..<28).map(Float.init))
        #expect(after.generation != before.generation)
        #expect(ring.nextWindow() == nil)
    }

    @Test("An unusable callback also breaks a partial window")
    func missingData() throws {
        let ring = SampleRing(capacity: 16, sampleRate: 8, windowSize: 8)
        _ = write([0, 1, 2], to: ring, startingAt: 0)
        var empty = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 2, mDataByteSize: 32, mData: nil))
        #expect(!withUnsafeMutablePointer(to: &empty) { ring.write(UnsafeMutableAudioBufferListPointer($0), timestamp: AudioTimeStamp()) })
        // Even a driver reporting contiguous sample time must not join across an unusable buffer.
        _ = write((3..<11).map(Float.init), to: ring, startingAt: 3)
        #expect(try #require(ring.nextWindow()).samples == (3..<11).map(Float.init))
    }

    @Test("Completion timestamps include frame offset and the audio clock's rate scalar")
    func timestamp() throws {
        let ring = SampleRing(capacity: 16, sampleRate: 8, windowSize: 8)
        _ = write(Array(repeating: 1, count: 16), to: ring, startingAt: 0, time: 20, scalar: 1.001)
        #expect(abs(try #require(ring.nextWindow()).completedAt - 21.001) < 0.000001)
        #expect(abs(try #require(ring.nextWindow()).completedAt - 22.002) < 0.000001)
    }

    @Test("A block's output deadline compensates for its age only once")
    func presentationDeadline() throws {
        let ring = SampleRing(capacity: 16, sampleRate: 8, windowSize: 8)
        _ = write(Array(repeating: 1, count: 8), to: ring, startingAt: 0, time: 20)
        let window = try #require(ring.nextWindow())
        // Center at20.5 plus output latency0.75: show at21.25, without subtracting a callback buffer.
        let delay = AudioSampleWindow.outputDelay(latency: 0.75, sampleRate: 8, windowSize: 8)
        #expect(window.completedAt + delay == 21.25)
        #expect(AudioSampleWindow.outputDelay(latency: 0.1, sampleRate: 8, windowSize: 8) == 0)
    }

    @Test("A drain snapshot stays bounded when further audio arrives")
    func boundedDrain() throws {
        let ring = SampleRing(capacity: 16, sampleRate: 8, windowSize: 8)
        _ = write((0..<16).map(Float.init), to: ring, startingAt: 0)
        let batch = ring.readyWindowCount
        #expect(batch == 2)
        for index in 0..<batch {
            _ = try #require(ring.nextWindow())
            let start = 16 + index * 8
            _ = write((start..<start + 8).map(Float.init), to: ring, startingAt: Double(start))
        }
        #expect(ring.readyWindowCount == 2)
        #expect(try #require(ring.nextWindow()).samples == (16..<24).map(Float.init))
    }

    @Test("Stereo mixes all channels while disabled null-data streams do not dim the signal")
    func mix() throws {
        let ring = SampleRing(capacity: 8, sampleRate: 8, windowSize: 4)
        let buffers = AudioBufferList.allocate(maximumBuffers: 2)
        defer { buffers.unsafeMutablePointer.deallocate() }
        let stereo: [Float] = [1, 3, 2, 4, 3, 5, 4, 6]
        stereo.withUnsafeBufferPointer { data in
            buffers[0] = AudioBuffer(mNumberChannels: 2, mDataByteSize: 32, mData: UnsafeMutableRawPointer(mutating: data.baseAddress))
            buffers[1] = AudioBuffer(mNumberChannels: 2, mDataByteSize: 32, mData: nil)
            #expect(ring.write(buffers, timestamp: AudioTimeStamp()))
        }
        #expect(try #require(ring.nextWindow()).samples == [2, 3, 4, 5])
    }

    @Test("A final delayed reading becomes due without a subsequent audio callback")
    func finalDeadline() {
        var delivery = WaveformDelivery(delay: 0.15)
        let reading = AudioReading(levels: [0.8], beat: 0)
        delivery.append(reading, at: 10, generation: 0)
        #expect(delivery.nextDeadline == 10.15)
        #expect(delivery.takeDue(at: 10.14) == nil)
        #expect(delivery.takeDue(at: 10.15) == reading)
        #expect(delivery.nextDeadline == nil)
    }

    @Test("A stalled consumer and output-latency changes cannot replay older readings")
    func deliveryOrder() {
        var delivery = WaveformDelivery(delay: 0.2)
        for index in 0..<4 { delivery.append(AudioReading(levels: [Float(index)], beat: 0), at: 10 + Double(index) * 0.1, generation: 0) }
        #expect(delivery.takeDue(at: 10.45)?.levels == [2])
        delivery.delay = 0
        #expect(delivery.takeDue(at: 10.45)?.levels == [3])
        delivery.delay = 0.4
        #expect(delivery.takeDue(at: 11) == nil)
        delivery.append(AudioReading(levels: [9], beat: 0), at: 12, generation: 0)
        delivery.append(AudioReading(levels: [1], beat: 0), at: 12.1, generation: 1)
        #expect(delivery.takeDue(at: 13)?.levels == [1])
        #expect(delivery.nextDeadline == nil)
    }

    @Test("Future timestamps cannot accumulate unbounded waveform history")
    func boundedDelivery() {
        var delivery = WaveformDelivery()
        for index in 0..<1000 { delivery.append(AudioReading(levels: [Float(index)], beat: 0), at: Double(index), generation: 0) }
        #expect(delivery.nextDeadline == Double(1000 - WaveformDelivery.capacity))
        #expect(delivery.takeDue(at: 1000)?.levels == [999])
    }

    @Test("Invalid driver clock metadata cannot create an infinite deadline")
    func invalidClock() throws {
        let ring = SampleRing(capacity: 8, sampleRate: 8, windowSize: 8)
        _ = write(Array(repeating: 1, count: 8), to: ring, startingAt: .nan, time: 20, scalar: .infinity)
        #expect(try #require(ring.nextWindow()).completedAt == 21)
        #expect(AudioSampleWindow.outputDelay(latency: .infinity, sampleRate: 8) == 0)
        var delivery = WaveformDelivery()
        delivery.append(AudioReading(levels: [1], beat: 0), at: .infinity, generation: 0)
        #expect(delivery.nextDeadline == nil)
    }

    @Test("Delayed bars leave the newer beat and its easing untouched")
    @MainActor func separateBeat() {
        let audio = AudioLevels()
        audio.receive(AudioReading(levels: Array(repeating: 1, count: 6), beat: 0))
        audio.receive(AudioReading(levels: nil, beat: 0.8))
        let pulse = audio.pulse
        audio.receive(AudioReading(levels: Array(repeating: 0.5, count: 6), beat: 0.1))
        #expect(audio.beat == 0.8)
        #expect(audio.pulse == pulse)
        #expect(audio.levels == Array(repeating: 0.5, count: 6))
    }
}
