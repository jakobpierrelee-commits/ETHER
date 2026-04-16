import Foundation

/// Rule-based tonal analyzer. Averages recent spectrum data, compares against
/// a target curve (gentle −3dB/octave slope), and suggests small EQ tweaks
/// to correct the 6 most common tonal issues.
///
/// Deterministic, no ML, no training data. ~50 lines of real logic.
final class AutoEQAnalyzer: ObservableObject {
    @Published private(set) var suggestions: [Suggestion] = []
    @Published private(set) var isAnalyzing = false

    // MARK: - Suggestion

    struct Suggestion: Identifiable {
        let id = UUID()
        let bandIndex: Int         // which of the 10 bands to adjust
        let gainDelta: Float       // how much to change gain by (±dB)
        let reasoning: String      // human-readable explanation
        let severity: Float        // 0..1, for UI emphasis
    }

    // MARK: - Rolling Average

    /// Rolling accumulator of magnitudes per display bin (in dBFS).
    /// New frames are blended in; old contributions decay.
    private var averageBins: [Float] = Array(
        repeating: -80,
        count: SpectrumAnalyzer.displayBins
    )
    private var sampleCount: Int = 0
    private let smoothing: Float = 0.02  // slow convergence — 5 sec to settle

    /// Called every spectrum frame to incorporate the latest magnitude data.
    func absorbFrame(_ magnitudes: [Float]) {
        guard magnitudes.count == averageBins.count else { return }
        sampleCount += 1
        for i in 0..<averageBins.count {
            // Only blend bins that are above silence threshold (real audio)
            if magnitudes[i] > -70 {
                averageBins[i] = averageBins[i] * (1 - smoothing) + magnitudes[i] * smoothing
            }
        }
    }

    /// True once we've seen enough real-audio frames to have a meaningful average.
    var hasEnoughData: Bool { sampleCount > 30 }

    /// Read-only snapshot of the current rolling average. Used by ReferenceMatcher.
    var currentAverageBins: [Float] { averageBins }

    // MARK: - Analysis

    /// Run the rule-based analysis against the rolling average and produce
    /// suggestions. Safe to call any time; returns [] if no audio yet.
    func analyze() {
        guard hasEnoughData else {
            suggestions = []
            return
        }

        isAnalyzing = true
        defer { isAnalyzing = false }

        // Build a frequency-axis view of the averaged spectrum
        let minFreq: Float = 20, maxFreq: Float = 20_000
        let logMin = log10(minFreq), logMax = log10(maxFreq)
        let count = averageBins.count

        func avgDB(lowHz: Float, highHz: Float) -> Float {
            let loIdx = Int((log10(lowHz) - logMin) / (logMax - logMin) * Float(count - 1))
            let hiIdx = Int((log10(highHz) - logMin) / (logMax - logMin) * Float(count - 1))
            guard loIdx >= 0, hiIdx < count, loIdx < hiIdx else { return -80 }
            var sum: Float = 0
            for i in loIdx...hiIdx { sum += averageBins[i] }
            return sum / Float(hiIdx - loIdx + 1)
        }

        // Normalize against the broadband average (so loud-vs-quiet audio still
        // compares relatively)
        let broadband = avgDB(lowHz: 200, highHz: 8000)

        // Target: music mix tends to sit roughly flat in lower-mids, with a
        // gentle rolloff in the air band. We compare REGIONS relative to each
        // other rather than absolute levels — robust to overall loudness.
        let subBass     = avgDB(lowHz: 40,   highHz: 100)  - broadband
        let bass        = avgDB(lowHz: 100,  highHz: 250)  - broadband
        let lowerMid    = avgDB(lowHz: 250,  highHz: 500)  - broadband
        let midRange    = avgDB(lowHz: 500,  highHz: 1500) - broadband
        let presence    = avgDB(lowHz: 2000, highHz: 4000) - broadband
        let harshness   = avgDB(lowHz: 5000, highHz: 8000) - broadband
        let air         = avgDB(lowHz: 10_000, highHz: 16_000) - broadband

        var result: [Suggestion] = []

        // Rule 1: Sub-bass bloat (>+6 dB hotter than broadband)
        if subBass > 6 {
            let excess = subBass - 4
            result.append(Suggestion(
                bandIndex: 1,  // 64 Hz band
                gainDelta: -min(3.0, excess * 0.5),
                reasoning: "Sub-bass hot by \(String(format: "%+.1f", subBass)) dB — tightening low end",
                severity: min(1, (subBass - 4) / 6)
            ))
        }

        // Rule 2: Muddy lower-mids (+3 dB bump around 200–400Hz)
        if bass > 3 && lowerMid > 2 {
            result.append(Suggestion(
                bandIndex: 3,  // 250 Hz
                gainDelta: -min(2.5, (lowerMid - 1) * 0.7),
                reasoning: "Lower-mid build-up — reducing 250 Hz for clarity",
                severity: min(1, lowerMid / 4)
            ))
        }

        // Rule 3: Boxy mid-range (500–800 Hz)
        if midRange > 2.5 && midRange > presence + 2 {
            result.append(Suggestion(
                bandIndex: 5,  // 1 kHz (closest band — we'll tighten Q in future)
                gainDelta: -min(2.0, (midRange - 1) * 0.5),
                reasoning: "Mid-range boxy relative to presence — gentle cut",
                severity: min(1, midRange / 4)
            ))
        }

        // Rule 4: Presence dip (under-represented 2–4 kHz)
        if presence < -3 && midRange > presence + 3 {
            result.append(Suggestion(
                bandIndex: 6,  // 2 kHz
                gainDelta: min(2.5, -presence * 0.5),
                reasoning: "Presence region recessed — lifting 2 kHz for vocal clarity",
                severity: min(1, -presence / 5)
            ))
        }

        // Rule 5: Harshness (hot 5–8 kHz)
        if harshness > 2 && harshness > air + 3 {
            result.append(Suggestion(
                bandIndex: 7,  // 4 kHz (closest)
                gainDelta: -min(2.0, (harshness - 1) * 0.5),
                reasoning: "5–8 kHz hot — taming harshness",
                severity: min(1, harshness / 4)
            ))
        }

        // Rule 6: Dull top end (air band rolled off)
        if air < -6 {
            result.append(Suggestion(
                bandIndex: 9,  // 16 kHz (high shelf by default for band 9)
                gainDelta: min(3.0, -air * 0.3),
                reasoning: "Air band rolled off by \(String(format: "%.1f", -air)) dB — restoring sparkle",
                severity: min(1, -air / 10)
            ))
        }

        suggestions = result
    }

    /// Clear any active suggestions.
    func clear() {
        suggestions = []
    }

    /// Manually load external suggestions (e.g. from ReferenceMatcher).
    func setSuggestions(_ newSuggestions: [Suggestion]) {
        suggestions = newSuggestions
    }

    /// Reset the rolling average (e.g. when engine stops).
    func reset() {
        for i in 0..<averageBins.count { averageBins[i] = -80 }
        sampleCount = 0
        suggestions = []
    }
}
