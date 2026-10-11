//
//  AppVolume.swift
//  Glance
//
//  Created by Gaty on 10/10/2026.
//

import AppKit
import CoreAudio

/// How loud the playing app plays, apart from the Mac's own volume, for the slider in the sound
/// output menu. Music and Spotify have a volume of their own, which their scripting sets. Any other
/// app, Safari say, is turned down through a Core Audio process tap: the app is quieted and its
/// sound played on, softer. Only while it's turned down: at full volume nothing stands between an
/// app and the speakers, and if Glance quits, macOS gives the app its sound back.
@MainActor
final class AppVolume: ObservableObject {
    static let shared = AppVolume()

    /// 0...1, the playing app's.
    @Published private(set) var level: Double = 1
    /// The playing app, by bundle ID.
    @Published private(set) var app: String?
    private var pid: pid_t = 0
    /// The apps turned down through a tap, and how far, by bundle ID.
    private var levels: [String: Double] = [:]
    private var taps: [String: VolumeTap] = [:]
    /// The latest volume for Music or Spotify, sent once the one before it has been.
    private var wanted: Int?
    private var sending = false

    private init() {
        // An app that quits takes its tap with it.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated {
                guard let self, let app else { return }
                self.taps.removeValue(forKey: app)?.stop()
                self.levels[app] = nil
            }
        }
        // Played through the device the Mac plays on: a new one, and the taps are made again for it.
        var address = AudioProperty.address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectAddPropertyListenerBlock(AudioProperty.system, &address, .main) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.retap() }
        }
    }

    /// Whether the slider can change the playing app: Music and Spotify always; another app once
    /// audio capture is allowed.
    var canChange: Bool {
        guard let app else { return false }
        return Self.scriptable(app) || Permissions.audioCapture == .granted
    }

    /// The app Now Playing names, and the process making its sound.
    func follow(app: String?, pid: pid_t) {
        guard app != self.app || pid != self.pid else { return }
        let samePlayer = app == self.app
        self.app = app
        self.pid = pid
        guard let app else { return level = 1 }
        if Self.scriptable(app) {
            if !samePlayer { Task { await refresh() } }
        } else {
            level = levels[app] ?? 1
            // A new process (a browser's new tab plays through another), tapped afresh.
            if level < 1, pid > 0 { tap(app) }
        }
    }

    /// Music's and Spotify's volume can change in the app itself, so it's read as the menu opens.
    func refresh() async {
        guard let app, Self.scriptable(app),
            let reply = await PlayerScripting.run(PlayerScripting.tell(app, "return sound volume")),
            let volume = Double(reply.trimmingCharacters(in: .whitespacesAndNewlines)), app == self.app
        else { return }
        level = min(max(volume / 100, 0), 1)
    }

    func set(_ value: Double) {
        let value = min(max(value, 0), 1)
        level = value
        guard let app else { return }
        if Self.scriptable(app) { return send(Int((value * 100).rounded()), to: app) }
        if value > 0.995 {
            // Back to full: the tap goes, and the app plays straight to the speakers again.
            levels[app] = nil
            taps.removeValue(forKey: app)?.stop()
        } else if let tap = taps[app] {
            levels[app] = value
            tap.gain = Float(value)
        } else {
            levels[app] = value
            tap(app)
        }
    }

    private func tap(_ app: String) {
        taps.removeValue(forKey: app)?.stop()
        guard pid > 0, Permissions.audioCapture == .granted else { return }
        taps[app] = VolumeTap(pid: pid, gain: Float(levels[app] ?? 1))
    }

    /// Every app turned down, made again for the device now playing.
    private func retap() {
        for (app, tap) in taps {
            tap.stop()
            taps[app] = nil
            if app == self.app { self.tap(app) }
        }
    }

    /// Sliding sends a lot of volumes; each goes once the one before has, and only the latest.
    private func send(_ volume: Int, to app: String) {
        wanted = volume
        guard !sending else { return }
        sending = true
        Task {
            while let volume = wanted {
                wanted = nil
                _ = await PlayerScripting.run(PlayerScripting.tell(app, "set sound volume to \(volume)"))
            }
            sending = false
        }
    }

    private static func scriptable(_ app: String) -> Bool {
        app == PlayerScripting.music || app == PlayerScripting.spotify
    }
}

/// An app's sound, quieted where it plays and played on through the Mac's output at a gain: a
/// process tap that mutes the app while it's read, in a private aggregate device with the output
/// device, whose IO copies the tap's sound to the output, scaled. Set up and torn down on its own
/// queue; the audio thread only reads the gain.
private final class VolumeTap: @unchecked Sendable {
    private let queue = DispatchQueue(label: "Glance.AppVolume")
    private let gainBox = UnsafeMutablePointer<Float>.allocate(capacity: 1)
    /// Whether the tap's sound has reached the IO.
    private let heard = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
    private var tapID = AudioObjectID(0)
    private var aggregateID = AudioObjectID(0)
    private var ioProc: AudioDeviceIOProcID?

    var gain: Float {
        get { gainBox.pointee }
        set { gainBox.pointee = newValue }
    }

    init(pid: pid_t, gain: Float) {
        gainBox.initialize(to: gain)
        heard.initialize(to: false)
        queue.async { [self] in
            guard start(pid) else { return tearDown() }
            // Quieted but never heard, the app would go silent: without the tap's sound, it's let go.
            queue.asyncAfter(deadline: .now() + 0.5) { [self] in
                if !heard.pointee { tearDown() }
            }
        }
    }

    deinit {
        gainBox.deallocate()
        heard.deallocate()
    }

    func stop() {
        queue.async { [self] in tearDown() }
    }

    private func start(_ pid: pid_t) -> Bool {
        let processes = AudioProperty.processes(of: pid)
        guard !processes.isEmpty, let output = Self.output() else { return false }
        let description = CATapDescription(stereoMixdownOfProcesses: processes)
        description.name = "Glance volume"
        description.isPrivate = true
        description.muteBehavior = .mutedWhenTapped
        guard AudioHardwareCreateProcessTap(description, &tapID) == noErr, tapID != 0 else { return false }

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Glance volume",
            kAudioAggregateDeviceUIDKey: AudioProperty.ownDevicePrefix + "volume." + UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceMainSubDeviceKey: output.uid,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: output.uid]],
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

        let gain = gainBox, heard = heard
        let created = AudioDeviceCreateIOProcIDWithBlock(&ioProc, aggregateID, nil) { _, input, _, output, _ in
            let input = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            if Self.play(input, into: UnsafeMutableAudioBufferListPointer(output), gain: gain.pointee) { heard.pointee = true }
        }
        guard created == noErr, let ioProc else { return false }
        // Only the tap's sound is wanted in. The output device's own microphone (AirPods have one)
        // stays off, so playing through them never switches them to headset mode.
        Self.leaveOff(inputStreams: output.inputStreams, of: aggregateID, for: ioProc)
        return AudioDeviceStart(aggregateID, ioProc) == noErr
    }

    private func tearDown() {
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

    /// The tap's sound into the output's channels, left and right in turn, scaled; false if there
    /// was none to play. Runs on the audio thread, so it allocates nothing. Input buffers left off
    /// carry no data.
    @discardableResult private static func play(
        _ input: UnsafeMutableAudioBufferListPointer, into output: UnsafeMutableAudioBufferListPointer, gain: Float
    ) -> Bool {
        var sourceChannels = 0
        for buffer in input where buffer.mData != nil { sourceChannels += Int(buffer.mNumberChannels) }
        var firstChannel = 0
        for buffer in output {
            guard let samples = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            memset(samples, 0, Int(buffer.mDataByteSize))
            let channels = Int(buffer.mNumberChannels)
            guard channels > 0, sourceChannels > 0 else { continue }
            let frames = Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * channels)
            for channel in 0..<channels {
                // Which of the tap's channels, and in which of its buffers.
                var wanted = (firstChannel + channel) % sourceChannels
                for source in input {
                    guard let data = source.mData?.assumingMemoryBound(to: Float.self) else { continue }
                    let count = Int(source.mNumberChannels)
                    guard wanted < count else {
                        wanted -= count
                        continue
                    }
                    let sourceFrames = Int(source.mDataByteSize) / (MemoryLayout<Float>.size * max(count, 1))
                    for frame in 0..<min(frames, sourceFrames) {
                        samples[frame * channels + channel] = data[frame * count + wanted] * gain
                    }
                    break
                }
            }
            firstChannel += channels
        }
        return sourceChannels > 0
    }

    /// The device the Mac plays on: its ID, and how many input streams it has of its own.
    private static func output() -> (uid: String, inputStreams: Int)? {
        var device = AudioObjectID(0)
        guard AudioProperty.read(AudioProperty.system, kAudioHardwarePropertyDefaultOutputDevice, &device), device != 0
        else { return nil }
        guard let uid = AudioProperty.uid(of: device) else { return nil }
        let streams = AudioProperty.size(of: device, kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput)
        return (uid, Int(streams) / MemoryLayout<AudioStreamID>.size)
    }

    /// Turns off the aggregate's first input streams for this IO, the output device's own, which
    /// come before the tap's.
    private static func leaveOff(inputStreams count: Int, of aggregate: AudioObjectID, for ioProc: AudioDeviceIOProcID) {
        guard count > 0 else { return }
        var address = AudioProperty.address(kAudioDevicePropertyIOProcStreamUsage, scope: kAudioObjectPropertyScopeInput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(aggregate, &address, 0, nil, &size) == noErr, size > 0 else { return }
        // An AudioHardwareIOProcStreamUsage: the IO, how many streams, and an on or off for each.
        let usage = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 8)
        defer { usage.deallocate() }
        usage.storeBytes(of: unsafeBitCast(ioProc, to: UnsafeMutableRawPointer.self), as: UnsafeMutableRawPointer.self)
        guard AudioObjectGetPropertyData(aggregate, &address, 0, nil, &size, usage) == noErr else { return }
        let streams = Int(usage.load(fromByteOffset: 8, as: UInt32.self))
        for stream in 0..<min(count, streams) {
            usage.storeBytes(of: UInt32(0), toByteOffset: 12 + stream * 4, as: UInt32.self)
        }
        AudioObjectSetPropertyData(aggregate, &address, 0, nil, size, usage)
    }
}
