import AVFoundation
import Observation
#if canImport(UIKit)
import UIKit
#endif

@MainActor
@Observable
final class SoundscapeDirector {
    enum Scene: Equatable {
        case none
        case storefront
        case statistics
        case rewardEntry
        case penaltyEntry
    }

    enum Cue {
        case storeDoor
        case storeScanner
        case storeRegister
        case purchaseComplete
        case pointsGained
        case pointsLost
    }

    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.soundPreferenceKey)
            if isEnabled {
                activate(scene)
            } else {
                stopAllAudio()
            }
        }
    }

    private(set) var scene: Scene = .none
    @ObservationIgnored private var musicPlayer: AVAudioPlayer?
    @ObservationIgnored private var effectPlayers: [AVAudioPlayer] = []
    @ObservationIgnored private var incidentalTask: Task<Void, Never>?

    private static let soundPreferenceKey = "soundscapeEnabled"

    init() {
        if UserDefaults.standard.object(forKey: Self.soundPreferenceKey) == nil {
            isEnabled = true
        } else {
            isEnabled = UserDefaults.standard.bool(forKey: Self.soundPreferenceKey)
        }
    }

    func activate(_ newScene: Scene) {
        scene = newScene
        guard isEnabled else {
            stopAllAudio()
            return
        }

        stopAllAudio()
        configureAudioSession()
        switch newScene {
        case .none:
            break
        case .storefront:
            play(.storeDoor)
            startMusic(.storefront)
            scheduleStoreIncidentalSounds()
        case .statistics:
            startMusic(.statistics)
        case .rewardEntry:
            startMusic(.rewardEntry)
        case .penaltyEntry:
            startMusic(.penaltyEntry)
        }
    }

    func play(_ cue: Cue) {
        guard isEnabled else { return }
        configureAudioSession()
        effectPlayers.removeAll { !$0.isPlaying }
        guard let player = try? AVAudioPlayer(data: audioData(for: cue)) else { return }
        player.volume = cue == .pointsLost ? 0.3 : 0.38
        player.prepareToPlay()
        player.play()
        effectPlayers.append(player)
        provideHaptic(for: cue)
    }

    func stop() {
        scene = .none
        stopAllAudio()
    }

    func deactivate(_ endingScene: Scene) {
        guard scene == endingScene else { return }
        stop()
    }

    private func startMusic(_ scene: Scene) {
        guard let player = try? AVAudioPlayer(data: musicData(for: scene)) else { return }
        player.numberOfLoops = -1
        player.volume = scene == .penaltyEntry ? 0.11 : 0.13
        player.prepareToPlay()
        player.play()
        musicPlayer = player
    }

    private func scheduleStoreIncidentalSounds() {
        incidentalTask = Task { [weak self] in
            while !Task.isCancelled {
                let delay = UInt64.random(in: 14...28)
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, let self, self.scene == .storefront else { return }
                self.play([Cue.storeDoor, .storeScanner, .storeRegister].randomElement() ?? .storeDoor)
            }
        }
    }

    private func stopAllAudio() {
        incidentalTask?.cancel()
        incidentalTask = nil
        musicPlayer?.stop()
        musicPlayer = nil
        effectPlayers.forEach { $0.stop() }
        effectPlayers.removeAll()
    }

    private func configureAudioSession() {
#if os(iOS) || os(tvOS) || os(watchOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
#endif
    }

    private func provideHaptic(for cue: Cue) {
#if canImport(UIKit)
        switch cue {
        case .pointsGained, .purchaseComplete:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .pointsLost:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .storeDoor, .storeScanner, .storeRegister:
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.35)
        }
#endif
    }

    private func audioData(for cue: Cue) -> Data {
        switch cue {
        case .storeDoor:
            return render([
                Tone(0, 0.65, 1_568, 0.28), Tone(0.08, 0.7, 2_093, 0.18), Tone(0.2, 0.8, 2_637, 0.11)
            ], duration: 1.15)
        case .storeScanner:
            return render([
                Tone(0, 0.07, 1_150, 0.22, .square), Tone(0.08, 0.1, 1_760, 0.2, .square)
            ], duration: 0.25)
        case .storeRegister:
            return render([
                Tone(0, 0.08, 660, 0.2, .square), Tone(0.1, 0.1, 880, 0.18, .square),
                Tone(0.24, 0.42, 2_350, 0.13), Tone(0.31, 0.38, 2_900, 0.1)
            ], duration: 0.8)
        case .purchaseComplete:
            return render([
                Tone(0, 0.07, 1_150, 0.23, .square), Tone(0.08, 0.1, 1_760, 0.2, .square),
                Tone(0.25, 0.08, 660, 0.18, .square), Tone(0.36, 0.12, 880, 0.17, .square),
                Tone(0.58, 0.18, 523.25, 0.2), Tone(0.76, 0.18, 659.25, 0.2),
                Tone(0.94, 0.65, 783.99, 0.24), Tone(0.94, 0.65, 1_046.5, 0.12)
            ], duration: 1.7)
        case .pointsGained:
            return render([
                Tone(0, 0.16, 523.25, 0.17), Tone(0.15, 0.16, 659.25, 0.18),
                Tone(0.3, 0.24, 783.99, 0.2), Tone(0.14, 0.36, 2_400, 0.1),
                Tone(0.23, 0.34, 2_950, 0.09), Tone(0.36, 0.35, 3_300, 0.08)
            ], duration: 0.85)
        case .pointsLost:
            return render([
                Tone(0, 0.25, 880, 0.16), Tone(0.18, 0.3, 659.25, 0.15),
                Tone(0.42, 0.5, 440, 0.14), Tone(0.62, 0.42, 329.63, 0.1)
            ], duration: 1.1)
        }
    }

    private func musicData(for scene: Scene) -> Data {
        switch scene {
        case .storefront:
            return noteSequence(
                [261.63, 329.63, 392, 329.63, 293.66, 349.23, 440, 349.23,
                 261.63, 329.63, 392, 523.25, 440, 392, 329.63, 293.66],
                beat: 0.48,
                amplitude: 0.09
            )
        case .statistics:
            return noteSequence(
                [261.63, 329.63, 392, 523.25, 392, 440, 523.25, 659.25,
                 293.66, 369.99, 440, 587.33, 440, 493.88, 587.33, 698.46],
                beat: 0.28,
                amplitude: 0.12,
                pulse: true
            )
        case .rewardEntry:
            return noteSequence(
                [392, 493.88, 587.33, 783.99, 659.25, 587.33, 493.88, 523.25],
                beat: 0.32,
                amplitude: 0.11
            )
        case .penaltyEntry:
            return noteSequence(
                [220, 207.65, 185, 164.81, 196, 174.61, 164.81, 146.83],
                beat: 0.5,
                amplitude: 0.09
            )
        case .none:
            return render([], duration: 0.2)
        }
    }

    private func noteSequence(
        _ frequencies: [Double],
        beat: Double,
        amplitude: Double,
        pulse: Bool = false
    ) -> Data {
        var tones: [Tone] = []
        for (index, frequency) in frequencies.enumerated() {
            let start = Double(index) * beat
            tones.append(Tone(start, beat * 0.88, frequency, amplitude))
            tones.append(Tone(start, beat * 0.88, frequency / 2, amplitude * 0.32))
            if pulse && index.isMultiple(of: 2) {
                tones.append(Tone(start, beat * 0.24, 98, amplitude * 0.7, .square))
            }
        }
        return render(tones, duration: Double(frequencies.count) * beat)
    }

    private enum Waveform {
        case sine
        case square
    }

    private struct Tone {
        let start: Double
        let duration: Double
        let frequency: Double
        let amplitude: Double
        let waveform: Waveform

        init(_ start: Double, _ duration: Double, _ frequency: Double, _ amplitude: Double, _ waveform: Waveform = .sine) {
            self.start = start
            self.duration = duration
            self.frequency = frequency
            self.amplitude = amplitude
            self.waveform = waveform
        }
    }

    private func render(_ tones: [Tone], duration: Double, sampleRate: Int = 22_050) -> Data {
        let frameCount = max(1, Int(duration * Double(sampleRate)))
        var samples = [Int16](repeating: 0, count: frameCount)

        for index in 0..<frameCount {
            let time = Double(index) / Double(sampleRate)
            var value = 0.0
            for tone in tones where time >= tone.start && time < tone.start + tone.duration {
                let localTime = time - tone.start
                let attack = min(1, localTime / 0.018)
                let release = min(1, (tone.duration - localTime) / min(0.16, tone.duration * 0.42))
                let envelope = max(0, min(attack, release))
                let phase = 2 * Double.pi * tone.frequency * localTime
                let wave = tone.waveform == .sine ? sin(phase) : (sin(phase) >= 0 ? 1.0 : -1.0)
                value += wave * tone.amplitude * envelope
            }
            samples[index] = Int16(max(-1, min(1, value)) * Double(Int16.max))
        }

        var data = Data()
        data.appendASCII("RIFF")
        data.appendLittleEndian(UInt32(36 + samples.count * MemoryLayout<Int16>.size))
        data.appendASCII("WAVEfmt ")
        data.appendLittleEndian(UInt32(16))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(UInt32(sampleRate))
        data.appendLittleEndian(UInt32(sampleRate * MemoryLayout<Int16>.size))
        data.appendLittleEndian(UInt16(MemoryLayout<Int16>.size))
        data.appendLittleEndian(UInt16(16))
        data.appendASCII("data")
        data.appendLittleEndian(UInt32(samples.count * MemoryLayout<Int16>.size))
        samples.forEach { data.appendLittleEndian($0) }
        return data
    }
}

private extension Data {
    mutating func appendASCII(_ string: String) {
        append(string.data(using: .ascii) ?? Data())
    }

    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
