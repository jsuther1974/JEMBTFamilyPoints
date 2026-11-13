import AVFoundation
import Observation
#if canImport(UIKit)
import UIKit
#endif

@MainActor
@Observable
final class SoundscapeDirector {
    enum Scene: Equatable, CaseIterable {
        case none
        case storefront
        case rules
        case ledger
        case statistics
        case family
        case rewardEntry
        case penaltyEntry
    }

    enum Cue {
        case storeDoor
        case storeCounterClick
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
    @ObservationIgnored private var sceneOwners: [(id: UUID, scene: Scene)] = []

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
        case .rules:
            startMusic(.rules)
        case .ledger:
            startMusic(.ledger)
        case .family:
            startMusic(.family)
        case .rewardEntry:
            startMusic(.rewardEntry)
        case .penaltyEntry:
            startMusic(.penaltyEntry)
        }
    }

    /// Gives a visible view temporary ownership of the soundtrack. When that view
    /// leaves, the most recently visible room resumes automatically.
    func enter(_ newScene: Scene, owner: UUID) {
        sceneOwners.removeAll { $0.id == owner }
        sceneOwners.append((owner, newScene))
        activate(newScene)
    }

    func leave(owner: UUID) {
        sceneOwners.removeAll { $0.id == owner }
        activate(sceneOwners.last?.scene ?? .none)
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
        sceneOwners.removeAll()
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
        player.volume = scene == .penaltyEntry ? 0.09 : 0.12
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
                self.play([Cue.storeDoor, .storeCounterClick, .storeRegister].randomElement() ?? .storeDoor)
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
        case .storeDoor, .storeCounterClick, .storeRegister:
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.35)
        }
#endif
    }

    private func audioData(for cue: Cue) -> Data {
        switch cue {
        case .storeDoor:
            return render([
                Tone(0, 1.3, 1_318.5, 0.22, .sine, decay: 2.8),
                Tone(0, 1.1, 2_637, 0.12, .sine, decay: 3.2),
                Tone(0.11, 1.45, 1_568, 0.24, .sine, decay: 2.6),
                Tone(0.11, 1.2, 3_136, 0.1, .sine, decay: 3.4),
                Tone(0.25, 1.5, 1_978, 0.16, .sine, decay: 2.9)
            ], duration: 1.8)
        case .storeCounterClick:
            return render([
                Tone(0, 0.035, 180, 0.2, .noise, decay: 24),
                Tone(0.045, 0.025, 1_100, 0.15, .square, decay: 28),
                Tone(0.11, 0.035, 150, 0.18, .noise, decay: 24)
            ], duration: 0.22)
        case .storeRegister:
            return render([
                Tone(0, 0.04, 130, 0.24, .noise, decay: 22),
                Tone(0.07, 0.035, 170, 0.22, .noise, decay: 24),
                Tone(0.14, 0.05, 105, 0.26, .square, decay: 20),
                Tone(0.23, 0.16, 75, 0.2, .noise, decay: 9),
                Tone(0.38, 1.05, 1_760, 0.18, .sine, decay: 3.6),
                Tone(0.38, 0.9, 3_520, 0.08, .sine, decay: 4.2)
            ], duration: 1.45)
        case .purchaseComplete:
            return render([
                Tone(0, 0.04, 150, 0.23, .noise, decay: 24),
                Tone(0.08, 0.04, 190, 0.2, .noise, decay: 24),
                Tone(0.18, 0.16, 72, 0.2, .noise, decay: 9),
                Tone(0.38, 1.2, 1_760, 0.2, .sine, decay: 3.3),
                Tone(0.38, 1.0, 3_520, 0.08, .sine, decay: 4),
                Tone(0.58, 0.22, 523.25, 0.16, .triangle),
                Tone(0.78, 0.22, 659.25, 0.17, .triangle),
                Tone(0.98, 0.7, 783.99, 0.18, .triangle, decay: 1.5)
            ], duration: 1.85)
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
            return roomTheme(
                melody: [523.25, 659.25, 783.99, 659.25, 587.33, 698.46, 880, 698.46,
                         523.25, 659.25, 783.99, 1_046.5, 880, 783.99, 659.25, 587.33],
                bass: [130.81, 146.83, 174.61, 196], beat: 0.42, style: .ragtime
            )
        case .rules:
            return roomTheme(
                melody: [523.25, 659.25, 783.99, 1_046.5, 987.77, 880, 783.99, 659.25,
                         587.33, 739.99, 880, 1_174.66, 1_046.5, 880, 739.99, 587.33],
                bass: [130.81, 196, 146.83, 220], beat: 0.3, style: .calliope
            )
        case .ledger:
            return roomTheme(
                melody: [261.63, 329.63, 392, 329.63, 293.66, 369.99, 440, 369.99,
                         261.63, 311.13, 392, 466.16, 392, 349.23, 311.13, 293.66],
                bass: [130.81, 146.83, 155.56, 146.83], beat: 0.36, style: .mechanical
            )
        case .statistics:
            return roomTheme(
                melody: [392, 523.25, 659.25, 783.99, 659.25, 698.46, 783.99, 1_046.5,
                         440, 587.33, 698.46, 880, 783.99, 880, 987.77, 1_174.66],
                bass: [98, 110, 130.81, 146.83], beat: 0.28, style: .march
            )
        case .family:
            return roomTheme(
                melody: [523.25, 659.25, 783.99, 659.25, 698.46, 880, 783.99, 659.25,
                         587.33, 698.46, 880, 698.46, 659.25, 783.99, 1_046.5, 783.99],
                bass: [130.81, 174.61, 146.83, 196], beat: 0.32, style: .dance
            )
        case .rewardEntry:
            return roomTheme(
                melody: [523.25, 659.25, 783.99, 1_046.5, 880, 783.99, 659.25, 783.99],
                bass: [130.81, 174.61], beat: 0.28, style: .calliope
            )
        case .penaltyEntry:
            return roomTheme(
                melody: [392, 369.99, 349.23, 329.63, 349.23, 329.63, 293.66, 261.63],
                bass: [98, 87.31], beat: 0.42, style: .mechanical
            )
        case .none:
            return render([], duration: 0.2)
        }
    }

    private enum RoomStyle {
        case ragtime
        case calliope
        case mechanical
        case march
        case dance
    }

    private func roomTheme(
        melody: [Double],
        bass: [Double],
        beat: Double,
        style: RoomStyle
    ) -> Data {
        var tones: [Tone] = []
        let melodyWave: Waveform = style == .calliope ? .triangle : .sine
        for (index, frequency) in melody.enumerated() {
            let start = Double(index) * beat
            let syncopation = style == .ragtime && index.isMultiple(of: 4) ? beat * 0.16 : 0
            tones.append(Tone(start + syncopation, beat * 0.72, frequency, 0.075, melodyWave))
            tones.append(Tone(start + syncopation, beat * 0.64, frequency * 2, 0.014, .sine))

            if style == .mechanical {
                tones.append(Tone(start, 0.025, 180, 0.035, .noise, decay: 28))
                if index.isMultiple(of: 4) {
                    tones.append(Tone(start + beat * 0.52, 0.035, 120, 0.045, .noise, decay: 24))
                }
            } else if style == .march {
                tones.append(Tone(start, beat * 0.12, index.isMultiple(of: 2) ? 92 : 138, 0.045, .square, decay: 12))
            } else if style == .dance {
                tones.append(Tone(start, beat * 0.11, index.isMultiple(of: 2) ? 82 : 164, 0.035, .square, decay: 13))
                tones.append(Tone(start + beat * 0.5, 0.025, 900, 0.025, .noise, decay: 30))
            }
        }

        for index in melody.indices where index.isMultiple(of: 2) {
            let bassNote = bass[(index / 2) % bass.count]
            let start = Double(index) * beat
            tones.append(Tone(start, beat * 1.65, bassNote, 0.055, .triangle))
            if style == .ragtime || style == .calliope {
                tones.append(Tone(start + beat, beat * 0.62, bassNote * 2, 0.035, .triangle))
                tones.append(Tone(start + beat, beat * 0.62, bassNote * 2.5, 0.025, .triangle))
            }
        }
        return render(tones, duration: Double(melody.count) * beat)
    }

    private enum Waveform {
        case sine
        case square
        case triangle
        case noise
    }

    private struct Tone {
        let start: Double
        let duration: Double
        let frequency: Double
        let amplitude: Double
        let waveform: Waveform
        let decay: Double?

        init(
            _ start: Double,
            _ duration: Double,
            _ frequency: Double,
            _ amplitude: Double,
            _ waveform: Waveform = .sine,
            decay: Double? = nil
        ) {
            self.start = start
            self.duration = duration
            self.frequency = frequency
            self.amplitude = amplitude
            self.waveform = waveform
            self.decay = decay
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
                let wave: Double
                switch tone.waveform {
                case .sine:
                    wave = sin(phase)
                case .square:
                    wave = sin(phase) >= 0 ? 1 : -1
                case .triangle:
                    wave = 2 * abs(2 * (tone.frequency * localTime - floor(tone.frequency * localTime + 0.5))) - 1
                case .noise:
                    let seed = UInt64(index &* 1_103_515_245 &+ Int(tone.frequency * 97))
                    wave = Double(seed % 2_001) / 1_000 - 1
                }
                let decay = tone.decay.map { exp(-$0 * localTime) } ?? 1
                value += wave * tone.amplitude * envelope * decay
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
