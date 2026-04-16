import Foundation
import SwiftUI
import Combine

// MARK: - EQ Controller

@MainActor
final class EQController: ObservableObject {
    @Published private(set) var bands: [EQBand]
    @Published var masterGain: Float = 0       // ±12 dB master output trim
    @Published var bypassed: Bool = false      // global EQ bypass
    @Published var selectedBandID: UUID?
    @Published var highlightedBandIndices: Set<Int> = []
    @Published var highlightedKnobID: String?
    @Published private var macroKnobs: [String: Float] = [:]   // id → value (dB)

    weak var engine: EngineManager?
    let undoManager = UndoManager()

    static let defaultFrequencies: [Float] = [
        32, 64, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000
    ]

    // Band colors and accent are driven by ThemeManager

    init() {
        var defaults = EQController.defaultFrequencies.enumerated().map { (i, f) -> EQBand in
            let type: EQFilterType = (i == 0) ? .lowCut : (i == 9) ? .highCut : .bell
            return EQBand(frequency: f, gain: 0, type: type)
        }
        defaults[0].gain = 0
        defaults[9].gain = 0
        self.bands = defaults
    }

    /// The per-band color for the band at this index. Rendered in Display P3
    /// space so saturated cyans, magentas, and greens use the full wide gamut
    /// on modern displays; sRGB monitors receive the clamped conversion.
    static func color(for index: Int) -> Color {
        let colors = ThemeManager.shared.curveGradient
        return colors[index % colors.count]
    }

    static var rainbowGradient: [Color] {
        ThemeManager.shared.curveGradient
    }

    static func themeColor(for index: Int) -> Color {
        let colors = ThemeManager.shared.current.bandColors
        return colors[index % colors.count]
    }

    // MARK: - Mutations (undoable)

    func setGain(bandID: UUID, gain: Float) {
        guard let index = bands.firstIndex(where: { $0.id == bandID }) else { return }
        let previous = bands[index].gain
        bands[index].gain = gain
        registerUndo { ctrl in ctrl.setGain(bandID: bandID, gain: previous) }
        apply()
    }

    func setFrequency(bandID: UUID, frequency: Float) {
        guard let index = bands.firstIndex(where: { $0.id == bandID }) else { return }
        let previous = bands[index].frequency
        bands[index].frequency = frequency
        registerUndo { ctrl in ctrl.setFrequency(bandID: bandID, frequency: previous) }
        apply()
    }

    func setQ(bandID: UUID, q: Float) {
        guard let index = bands.firstIndex(where: { $0.id == bandID }) else { return }
        let previous = bands[index].q
        bands[index].q = q
        registerUndo { ctrl in ctrl.setQ(bandID: bandID, q: previous) }
        apply()
    }

    func setType(bandID: UUID, type: EQFilterType) {
        guard let index = bands.firstIndex(where: { $0.id == bandID }) else { return }
        let previousType = bands[index].type
        let previousQ = bands[index].q
        bands[index].type = type
        bands[index].q = type.defaultQ
        registerUndo { ctrl in
            ctrl.setType(bandID: bandID, type: previousType)
            ctrl.setQ(bandID: bandID, q: previousQ)
        }
        apply()
    }

    func toggleBypass(bandID: UUID) {
        guard let index = bands.firstIndex(where: { $0.id == bandID }) else { return }
        bands[index].bypassed.toggle()
        registerUndo { ctrl in ctrl.toggleBypass(bandID: bandID) }
        apply()
    }

    func resetBand(bandID: UUID) {
        guard let index = bands.firstIndex(where: { $0.id == bandID }) else { return }
        let before = bands[index]
        bands[index].gain = 0
        bands[index].q = bands[index].type.defaultQ
        registerUndo { ctrl in
            ctrl.bands[index] = before
            ctrl.apply()
        }
        apply()
    }

    func setMasterGain(_ value: Float) {
        let previous = masterGain
        masterGain = value
        registerUndo { ctrl in ctrl.setMasterGain(previous) }
        apply()
    }

    func toggleGlobalBypass() {
        bypassed.toggle()
        let prev = !bypassed
        registerUndo { ctrl in ctrl.bypassed = prev; ctrl.apply() }
        apply()
    }

    func reset() {
        let before = bands
        let beforeGain = masterGain
        let beforeKnobs = macroKnobs
        for i in bands.indices {
            bands[i].gain = 0
            bands[i].q = bands[i].type.defaultQ
            bands[i].bypassed = false
        }
        masterGain = 0
        macroKnobs.removeAll()   // snap every knob back to 0
        registerUndo { ctrl in
            ctrl.bands = before
            ctrl.masterGain = beforeGain
            ctrl.macroKnobs = beforeKnobs
            ctrl.apply()
        }
        apply()
    }

    func load(bands: [EQBand], masterGain: Float = 0, knobValues: [String: Float] = [:]) {
        // Animate bands, knobs, and master gain to their saved positions so
        // profile switching feels cinematic instead of a hard snap.
        withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
            self.bands = bands
            self.masterGain = masterGain
            self.macroKnobs = knobValues
        }
        undoManager.removeAllActions()
        apply()
    }

    /// Expose current knob values (read-only) so the profile store can save them.
    var currentKnobValues: [String: Float] { macroKnobs }

    // MARK: - Macro knobs

    /// Current value of a macro knob (dB). Returns 0 if not set.
    func macroKnobValue(id: String) -> Float {
        macroKnobs[id] ?? 0
    }

    /// Set a macro knob value and write its scaled gain to the mapped bands.
    /// Overwrites any manual gain on those bands. Undoable as one atomic step.
    func setMacroKnob(id: String, value: Float) {
        guard let knob = MacroKnob.all.first(where: { $0.id == id }) else { return }
        let previousKnob = macroKnobs[id] ?? 0
        let previousGains: [Float] = knob.bandIndices.map { bands[$0].gain }

        macroKnobs[id] = value
        for (i, bandIndex) in knob.bandIndices.enumerated() {
            guard bandIndex < bands.count else { continue }
            let weight = i < knob.bandWeights.count ? knob.bandWeights[i] : 1.0
            bands[bandIndex].gain = max(-24, min(24, value * weight))
        }

        registerUndo { ctrl in
            ctrl.macroKnobs[id] = previousKnob
            for (i, bandIndex) in knob.bandIndices.enumerated() where bandIndex < ctrl.bands.count {
                ctrl.bands[bandIndex].gain = previousGains[i]
            }
            ctrl.apply()
        }
        apply()
    }

    // MARK: - Application

    private func apply() {
        engine?.applyEQ(bands: bands, masterGain: masterGain, bypassed: bypassed)
    }

    // MARK: - Undo helpers

    private func registerUndo(_ action: @escaping @MainActor (EQController) -> Void) {
        undoManager.registerUndo(withTarget: self) { target in
            Task { @MainActor in action(target) }
        }
    }
}
