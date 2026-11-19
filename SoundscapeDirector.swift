import AVFoundation
import Observation
#if canImport(UIKit)
import UIKit
#endif

nonisolated final class AudioSessionController: @unchecked Sendable {
    typealias Activation = @Sendable (@escaping @Sendable (Bool) -> Void) -> Void

    private let queue = DispatchQueue(label: "com.jembt.family-points.audio-session", qos: .userInitiated)
    private let activation: Activation
    private var isActive = false
    private var isActivating = false
    private var waiters: [CheckedContinuation<Bool, Never>] = []

    init(activation: @escaping Activation) {
        self.activation = activation
    }

    static func live() -> AudioSessionController {
        AudioSessionController { completion in
#if os(iOS) || os(tvOS) || os(watchOS)
            let session = AVAudioSession.sharedInstance()
            do {
                try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
                if #available(iOS 27.0, tvOS 27.0, watchOS 27.0, *) {
                    session.activate(options: []) { activated, error in
                        completion(activated && error == nil)
                    }
                } else {
                    try session.setActive(true)
                    completion(true)
                }
            } catch {
                completion(false)
            }
#else
            completion(true)
#endif
        }
    }

    func perform(_ operation: @escaping @Sendable () -> Void) {
        queue.async(execute: operation)
    }

    func activateIfNeeded() async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                guard !isActive else {
                    continuation.resume(returning: true)
                    return
                }

                waiters.append(continuation)
                guard !isActivating else { return }
                isActivating = true
                activation { [weak self] succeeded in
                    guard let self else { return }
                    queue.async {
                        self.isActive = succeeded
                        self.isActivating = false
                        let currentWaiters = self.waiters
                        self.waiters.removeAll()
                        currentWaiters.forEach { $0.resume(returning: succeeded) }
                    }
                }
            }
        }
    }
}

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

        var soundtrackResourceName: String? {
            switch self {
            case .none:
                nil
            case .storefront:
                "storefront-theme"
            case .rules, .rewardEntry, .penaltyEntry:
                "rules-theme"
            case .ledger:
                "ledger-theme"
            case .statistics:
                "statistics-theme"
            case .family:
                "family-theme"
            }
        }
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
            guard !runtimeAudioDisabled else {
                stopAllAudio()
                return
            }
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
    @ObservationIgnored private var playbackTask: Task<Void, Never>?
    @ObservationIgnored private var sceneOwners: [(id: UUID, scene: Scene)] = []
    @ObservationIgnored private let audioSession: AudioSessionController
    @ObservationIgnored private let runtimeAudioDisabled: Bool

    private static let soundPreferenceKey = "soundscapeEnabled"

    init(audioSession: AudioSessionController = .live(), disableAudio: Bool = false) {
        self.audioSession = audioSession
        runtimeAudioDisabled = disableAudio
        if disableAudio {
            isEnabled = false
        } else if UserDefaults.standard.object(forKey: Self.soundPreferenceKey) == nil {
            isEnabled = true
        } else {
            isEnabled = UserDefaults.standard.bool(forKey: Self.soundPreferenceKey)
        }
    }

    func activate(_ newScene: Scene) {
        scene = newScene
        guard isEnabled, !runtimeAudioDisabled else {
            stopAllAudio()
            return
        }

        stopAllAudio()
        guard newScene != .none else { return }
        playbackTask = Task { [weak self] in
            guard let self, await audioSession.activateIfNeeded(), !Task.isCancelled,
                  isEnabled, scene == newScene else { return }
            startPlayback(for: newScene)
        }
    }

    private func startPlayback(for scene: Scene) {
        switch scene {
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
        guard isEnabled, !runtimeAudioDisabled else { return }
        Task { [weak self] in
            guard let self, await audioSession.activateIfNeeded(), !Task.isCancelled, isEnabled else { return }
            playAfterSessionActivation(cue)
        }
    }

    private func playAfterSessionActivation(_ cue: Cue) {
        effectPlayers.removeAll { !$0.isPlaying }
        guard let player = try? AVAudioPlayer(data: audioData(for: cue)) else { return }
        player.volume = cue == .pointsLost ? 0.3 : 0.38
        audioSession.perform {
            player.prepareToPlay()
            player.play()
        }
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
        guard let resourceName = scene.soundtrackResourceName,
              let url = Bundle(for: SoundscapeDirector.self).url(
                forResource: resourceName,
                withExtension: "m4a",
                subdirectory: "Audio"
              ) ?? Bundle(for: SoundscapeDirector.self).url(forResource: resourceName, withExtension: "m4a"),
              let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.numberOfLoops = -1
        player.volume = scene == .penaltyEntry ? 0.07 : 0.09
        audioSession.perform {
            player.prepareToPlay()
            player.play()
        }
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
        playbackTask?.cancel()
        playbackTask = nil
        incidentalTask?.cancel()
        incidentalTask = nil
        if let musicPlayer {
            audioSession.perform { musicPlayer.stop() }
        }
        musicPlayer = nil
        for player in effectPlayers {
            audioSession.perform { player.stop() }
        }
        effectPlayers.removeAll()
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
