import SwiftUI
import AVFoundation
import Combine

// MARK: - Reverb Presets

enum ReverbPreset: String, CaseIterable, Identifiable {
    case off           = "Off"
    case smallRoom     = "Small Room"
    case mediumRoom    = "Medium Room"
    case largeHall     = "Large Hall"
    case plate         = "Plate"
    case cathedral     = "Cathedral"

    var id: String { rawValue }

    var auPreset: AVAudioUnitReverbPreset? {
        switch self {
        case .off:         return nil
        case .smallRoom:   return .smallRoom
        case .mediumRoom:  return .mediumRoom
        case .largeHall:   return .largeHall
        case .plate:       return .plate
        case .cathedral:   return .cathedral
        }
    }
}

// MARK: - SpatialController

final class SpatialController: ObservableObject {

    // Width (M-S)
    @Published var width: Float = 1.0 { didSet { push() } }

    // Bass mono
    @Published var bassMonoEnabled: Bool = false { didSet { push() } }
    @Published var bassMonoCrossover: Float = 120 { didSet { push() } }

    // Crossfeed
    @Published var crossfeedEnabled: Bool = false { didSet { push() } }
    @Published var crossfeedAmount: Float = 0.35 { didSet { push() } }

    // Virtual speakers: strong crossfeed + ambient small-room reverb
    @Published var virtualSpeakers: Bool = false {
        didSet {
            if virtualSpeakers {
                // Preset for the HRTF approximation
                crossfeedEnabled = true
                crossfeedAmount = 0.55
            }
            push()
        }
    }

    // Reverb
    @Published var reverbPreset: ReverbPreset = .off { didSet { applyReverb() } }
    @Published var reverbAmount: Float = 25 { didSet { applyReverb() } }

    // Polarity / mono utils (Advanced)
    @Published var invertLeft: Bool = false { didSet { push() } }
    @Published var invertRight: Bool = false { didSet { push() } }
    @Published var sumToMono: Bool = false { didSet { push() } }

    weak var processor: StereoProcessor?
    weak var reverbNode: AVAudioUnitReverb?

    /// Write current values into the audio-thread processor.
    private func push() {
        guard let p = processor else { return }
        p.widthMultiplier = width
        p.bassMonoEnabled = bassMonoEnabled
        p.bassMonoCrossoverHz = bassMonoCrossover
        p.crossfeedEnabled = crossfeedEnabled || virtualSpeakers
        p.crossfeedAmount = virtualSpeakers ? 0.55 : crossfeedAmount
        p.invertLeft = invertLeft
        p.invertRight = invertRight
        p.sumToMono = sumToMono
    }

    /// Apply reverb settings to the AVAudioUnitReverb node.
    private func applyReverb() {
        guard let reverb = reverbNode else { return }
        if let preset = reverbPreset.auPreset {
            reverb.loadFactoryPreset(preset)
            reverb.wetDryMix = reverbAmount
        } else {
            reverb.wetDryMix = 0
        }
    }

    /// Called after the engine attaches the processor + reverb node.
    func syncInitial() {
        push()
        applyReverb()
    }

    func reset() {
        width = 1.0
        bassMonoEnabled = false
        bassMonoCrossover = 120
        crossfeedEnabled = false
        crossfeedAmount = 0.35
        virtualSpeakers = false
        reverbPreset = .off
        reverbAmount = 25
    }
}
