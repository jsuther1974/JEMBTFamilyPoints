#!/usr/bin/env swift

import AVFoundation
import AudioToolbox
import Foundation

struct RenderSpec {
    let source: String
    let output: String
    let program: UInt8
    let seconds: Double
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let sourceDirectory = root.appendingPathComponent("Tools/SoundtrackSources", isDirectory: true)
let outputDirectory = root.appendingPathComponent("JEMBT Family Points Tracker/Audio", isDirectory: true)
let soundBank = URL(fileURLWithPath: "/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls")
let specs = [
    RenderSpec(source: "store-entertainer.mid", output: "storefront-theme.wav", program: 3, seconds: 38),
    RenderSpec(source: "rules-easy-winners.mid", output: "rules-theme.wav", program: 16, seconds: 36),
    RenderSpec(source: "ledger-magnetic-rag.mid", output: "ledger-theme.wav", program: 0, seconds: 38),
    RenderSpec(source: "stats-liberty-bell.mid", output: "statistics-theme.wav", program: 61, seconds: 38),
    RenderSpec(source: "family-maple-leaf.mid", output: "family-theme.wav", program: 1, seconds: 38),
]

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

func render(_ spec: RenderSpec) throws {
    let engine = AVAudioEngine()
    let sampler = AVAudioUnitSampler()
    engine.attach(sampler)
    engine.connect(sampler, to: engine.mainMixerNode, format: nil)

    let sequencer = AVAudioSequencer(audioEngine: engine)
    try sequencer.load(from: sourceDirectory.appendingPathComponent(spec.source), options: [])
    for track in sequencer.tracks {
        track.destinationAudioUnit = sampler
    }
    try sampler.loadSoundBankInstrument(
        at: soundBank,
        program: spec.program,
        bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
        bankLSB: UInt8(kAUSampler_DefaultBankLSB)
    )

    let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
    try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4_096)
    try engine.start()
    sequencer.prepareToPlay()
    sequencer.currentPositionInBeats = 0
    try sequencer.start()

    let outputURL = outputDirectory.appendingPathComponent(spec.output)
    try? FileManager.default.removeItem(at: outputURL)
    let file = try AVAudioFile(forWriting: outputURL, settings: format.settings)
    let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: engine.manualRenderingMaximumFrameCount)!
    let targetFrames = AVAudioFramePosition(spec.seconds * format.sampleRate)

    while engine.manualRenderingSampleTime < targetFrames {
        let remaining = targetFrames - engine.manualRenderingSampleTime
        let frames = AVAudioFrameCount(min(AVAudioFramePosition(engine.manualRenderingMaximumFrameCount), remaining))
        let status = try engine.renderOffline(frames, to: buffer)
        switch status {
        case .success:
            try file.write(from: buffer)
        case .insufficientDataFromInputNode:
            continue
        case .cannotDoInCurrentContext:
            Thread.sleep(forTimeInterval: 0.001)
        case .error:
            throw NSError(domain: "SoundtrackRenderer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Offline rendering failed for \(spec.source)"])
        @unknown default:
            throw NSError(domain: "SoundtrackRenderer", code: 2)
        }
    }

    sequencer.stop()
    engine.stop()
    print("Rendered \(spec.output)")
}

for spec in specs {
    try render(spec)
}
