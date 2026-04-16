import Foundation
import AVFoundation
import SwiftUI

// MARK: - Filter Type

enum EQFilterType: Int, Codable, CaseIterable, Identifiable {
    case lowCut       = 0
    case lowShelf     = 1
    case bell         = 2
    case highShelf    = 3
    case highCut      = 4
    case notch        = 5

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .lowCut:    return "Low Cut"
        case .lowShelf:  return "Low Shelf"
        case .bell:      return "Bell"
        case .highShelf: return "High Shelf"
        case .highCut:   return "High Cut"
        case .notch:     return "Notch"
        }
    }

    var symbol: String {
        switch self {
        case .lowCut:    return "square.slash"
        case .lowShelf:  return "chart.bar"
        case .bell:      return "waveform.path.ecg"
        case .highShelf: return "chart.bar.fill"
        case .highCut:   return "square.slash.fill"
        case .notch:     return "arrow.down.to.line"
        }
    }

    /// Default Q for this filter type when newly created / reset.
    var defaultQ: Float {
        switch self {
        case .lowCut, .highCut, .lowShelf, .highShelf: return 0.71   // Butterworth
        case .bell:  return 1.0
        case .notch: return 10.0
        }
    }

    /// Whether gain is meaningful for this filter type. Cuts and notches don't use gain.
    var usesGain: Bool {
        switch self {
        case .lowCut, .highCut, .notch: return false
        default: return true
        }
    }

    /// Map our enum to AVAudioUnitEQ filter type.
    var avFilterType: AVAudioUnitEQFilterType {
        switch self {
        case .lowCut:    return .highPass       // name inverted vs. AVAudioUnit — low cut = high pass
        case .lowShelf:  return .lowShelf
        case .bell:      return .parametric
        case .highShelf: return .highShelf
        case .highCut:   return .lowPass
        case .notch:     return .parametric     // high-Q bell approximates a notch
        }
    }
}

// MARK: - EQ Band

struct EQBand: Identifiable, Hashable {
    let id: UUID
    var frequency: Float
    var gain: Float           // dB
    var q: Float
    var type: EQFilterType
    var bypassed: Bool

    init(id: UUID = UUID(),
         frequency: Float,
         gain: Float = 0,
         q: Float? = nil,
         type: EQFilterType = .bell,
         bypassed: Bool = false) {
        self.id = id
        self.frequency = frequency
        self.gain = gain
        self.q = q ?? type.defaultQ
        self.type = type
        self.bypassed = bypassed
    }

    /// Color for this band based on gain and type.
    var tint: Color {
        if bypassed { return .etherTextTertiary }
        if !type.usesGain { return .etherAccent }
        return .gainTint(for: gain)
    }
}
