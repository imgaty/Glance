//
//  TimerChime.swift
//  Glance
//
//  Created by Gaty on 24/10/2026.
//

import AVFoundation
import Foundation

/// The chime a Clock timer rings with, played by Glance in place of macOS's own alert, which the
/// notch takes the place of (see `ClockActivity`): the tone chosen for it in Clock, over and over,
/// at the Mac's volume, until it's stopped or repeated in the notch, the notch is opened, or five
/// minutes have gone by.
@MainActor
final class TimerChime {
    private var player: AVAudioPlayer?
    private var timeout: Task<Void, Never>?

    /// The longest it rings with no one there to stop it.
    static let longest: Duration = .seconds(300)

    var isPlaying: Bool { player != nil }

    /// Rings with the tone macOS names, as Clock keeps it for the timer ("system:Radial"); none if
    /// the timer was set to ring with none.
    func play(tone: String?) {
        stop()
        guard let file = Self.file(for: tone), let player = try? AVAudioPlayer(contentsOf: file) else { return }
        player.numberOfLoops = -1
        player.play()
        self.player = player
        timeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.longest)
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    func stop() {
        timeout?.cancel()
        timeout = nil
        player?.stop()
        player = nil
    }

    /// Where macOS keeps the tones its timers ring with.
    nonisolated private static let tones = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/ToneLibrary.framework/Versions/A/Resources")

    /// The file for one of macOS's tones, by the name Clock keeps it by: "system:Radial" is the
    /// ringtone Radial, in whichever version this macOS has. Radial, Clock's own, when it isn't
    /// found; none when there's no tone.
    nonisolated static func file(for tone: String?, in folder: URL = tones) -> URL? {
        guard let tone, tone.hasPrefix("system:") else { return nil }
        let wanted = String(tone.dropFirst("system:".count))
        let places = [folder.appendingPathComponent("Ringtones")]
            + ((try? FileManager.default.contentsOfDirectory(at: folder.appendingPathComponent("AlertTones"), includingPropertiesForKeys: nil)) ?? [])
        func find(_ name: String) -> URL? {
            for place in places {
                let files = (try? FileManager.default.contentsOfDirectory(at: place, includingPropertiesForKeys: nil)) ?? []
                // Named as it is, or as its newer version is, "Radial-EncoreInfinitum".
                if let file = files.first(where: { Self.name(of: $0).caseInsensitiveCompare(name) == .orderedSame }) { return file }
            }
            return nil
        }
        return find(wanted) ?? find("Radial")
    }

    /// A tone file's name, without its version: "Radial-EncoreInfinitum.m4r" is Radial.
    nonisolated private static func name(of file: URL) -> String {
        let name = file.deletingPathExtension().lastPathComponent
        return name.components(separatedBy: "-").first ?? name
    }
}
