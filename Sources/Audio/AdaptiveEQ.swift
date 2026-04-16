import Foundation
import os

/// Gullfoss-style continuous auto-EQ. When `isActive`, a timer periodically
/// samples the rolling spectrum average and writes gentle gain adjustments
/// to each band as an **offset** on top of the user's saved gains.
///
/// Keeps adaptive corrections small (≤ ±4 dB per band) and smooths between
/// updates so the EQ never snaps.
final class AdaptiveEQ: ObservableObject {

    private let logger = Logger(subsystem: "audio.ether.app", category: "Adaptive")

    /// On/off toggle for the whole adaptive mode.
    @Published var isActive: Bool = false {
        didSet { isActive ? start() : stop() }
    }

    /// 0…1 — scales the intensity of adaptive corrections.
    @Published var amount: Float = 0.6

    /// Per-band adaptive offset (dB), smoothed over time.
    @Published private(set) var adaptiveOffsets: [Float] = Array(repeating: 0, count: 10)

    /// Callback fired whenever offsets change — typically wired to trigger
    /// the EQController to re-apply band gains on the engine.
    var onChange: (() -> Void)?

    weak var autoEQ: AutoEQAnalyzer?

    private var timer: Timer?
    private let updateInterval: TimeInterval = 0.5   // half second
    private let smoothing: Float = 0.35              // how fast new offsets blend in

    // MARK: - Lifecycle

    private func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        logger.log("Adaptive EQ started")
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        // Decay offsets to 0 over a few ticks so it releases smoothly
        DispatchQueue.main.async {
            for _ in 0..<8 {
                for i in 0..<self.adaptiveOffsets.count {
                    self.adaptiveOffsets[i] *= 0.7
                }
                self.onChange?()
                Thread.sleep(forTimeInterval: 0.06)
            }
            for i in 0..<self.adaptiveOffsets.count { self.adaptiveOffsets[i] = 0 }
            self.onChange?()
        }
        logger.log("Adaptive EQ stopped")
    }

    // MARK: - Update cycle

    private func tick() {
        guard let analyzer = autoEQ, analyzer.hasEnoughData else { return }

        let bins = analyzer.currentAverageBins
        guard !bins.isEmpty else { return }

        // Target: gentle slope (−1 dB/octave relative to broadband average) — leaves
        // natural tonality but flags big deviations.
        let binCount = bins.count
        let minFreq: Float = 20, maxFreq: Float = 20_000
        let logMin = log10(minFreq), logMax = log10(maxFreq)

        // Broadband reference (200 Hz – 8 kHz average) — used to remove overall loudness
        func freqForBin(_ i: Int) -> Float {
            pow(10, logMin + (logMax - logMin) * Float(i) / Float(binCount - 1))
        }
        func binIndex(for hz: Float) -> Int {
            Int((log10(hz) - logMin) / (logMax - logMin) * Float(binCount - 1))
        }
        let loIdx = binIndex(for: 200), hiIdx = binIndex(for: 8000)
        var broadbandSum: Float = 0
        for i in loIdx...hiIdx { broadbandSum += bins[i] }
        let broadband = broadbandSum / Float(hiIdx - loIdx + 1)

        // For each of the 10 EQ bands, compute deviation from target
        let bandFrequencies: [Float] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
        var newOffsets = [Float](repeating: 0, count: bandFrequencies.count)

        for (bandIndex, freq) in bandFrequencies.enumerated() {
            let lowHz = freq / sqrt(2)
            let highHz = freq * sqrt(2)
            let bLo = max(0, binIndex(for: lowHz))
            let bHi = min(binCount - 1, binIndex(for: highHz))
            guard bLo < bHi else { continue }
            var sum: Float = 0
            for i in bLo...bHi { sum += bins[i] }
            let bandAvg = sum / Float(bHi - bLo + 1)

            // Target: slightly rolled-off with frequency (natural music spectrum)
            let octavesFromCenter = log2(freq / 1000)          // 0 at 1 kHz
            let target = broadband - octavesFromCenter * 0.8   // −0.8 dB/octave

            // Correction = how much we need to ADD to bring this band to target
            // If band is too HOT (higher than target), correction is negative (cut)
            let delta = target - bandAvg

            // Clamp gentle corrections
            let clamped = max(-4.0, min(4.0, delta))
            newOffsets[bandIndex] = clamped * amount
        }

        // Smooth into existing offsets (attack)
        for i in 0..<adaptiveOffsets.count {
            adaptiveOffsets[i] = adaptiveOffsets[i] * (1 - smoothing) + newOffsets[i] * smoothing
        }

        onChange?()
    }
}
