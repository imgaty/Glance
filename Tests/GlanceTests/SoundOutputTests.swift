import CoreAudio
import Testing

@testable import Glance

@Suite("Sound output feedback")
@MainActor
struct SoundOutputTests {
    private let speakers = AudioOutput.Device(
        id: 0, name: "MacBook Pro Speakers", symbol: "speaker.wave.2.fill", transport: kAudioDeviceTransportTypeBuiltIn)

    @Test("The laptop control distinguishes muted, low, medium and high volume")
    func speakerLevels() {
        #expect(AudioOutput.controlSymbol(device: speakers, appLevel: 1, outputLevel: 0, muted: false) == "speaker.slash.fill")
        #expect(AudioOutput.controlSymbol(device: speakers, appLevel: 1, outputLevel: 0.15, muted: false) == "speaker.wave.1.fill")
        #expect(AudioOutput.controlSymbol(device: speakers, appLevel: 1, outputLevel: 0.5, muted: false) == "speaker.wave.2.fill")
        #expect(AudioOutput.controlSymbol(device: speakers, appLevel: 1, outputLevel: 1, muted: false) == "speaker.wave.3.fill")
        #expect(AudioOutput.controlSymbol(device: speakers, appLevel: 1, outputLevel: 1, muted: true) == "speaker.slash.fill")
    }

    @Test("App gain and hardware volume both affect the laptop control")
    func combinedVolume() {
        let hardwareVolume = 0.8
        #expect(AudioOutput.controlSymbol(device: speakers, appLevel: 1, outputLevel: hardwareVolume, muted: false) == "speaker.wave.3.fill")
        #expect(AudioOutput.controlSymbol(device: speakers, appLevel: 0.5, outputLevel: hardwareVolume, muted: false) == "speaker.wave.2.fill")
        #expect(AudioOutput.controlSymbol(device: speakers, appLevel: 0.2, outputLevel: hardwareVolume, muted: false) == "speaker.wave.1.fill")
    }

    @Test("Headphones retain their device symbol when volume changes")
    func headphones() {
        let headphones = AudioOutput.Device(id: 0, name: "External Headphones", symbol: "headphones", transport: kAudioDeviceTransportTypeBuiltIn)
        for volume in [0.0, 0.15, 0.5, 1.0] {
            #expect(AudioOutput.controlSymbol(device: headphones, appLevel: volume, outputLevel: 1, muted: false) == "headphones")
        }
    }
}
