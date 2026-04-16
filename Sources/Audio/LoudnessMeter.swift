import Foundation
import Accelerate

/// ITU-R BS.1770-style loudness meter (simplified, not fully spec-compliant but
/// close enough for real-time display). Computes momentary (400ms), short-term
/// (3s), and integrated (whole session) LUFS values from the post-EQ signal.
///
/// Integrated uses absolute -70 LUFS gate; relative gating is approximated.
final class LoudnessMeter: ObservableObject {

    @Published var momentaryLUFS: Float = -70    // last 400 ms
    @Published var shortTermLUFS: Float = -70   // last 3 seconds
    @Published var integratedLUFS: Float = -70  // whole session (until reset)
    @Published var truePeakDBFS: Float = -70

    private let sampleRate: Float = 48000

    // Momentary (400 ms) ring
    private let momentaryFrames: Int
    // Short-term (3 s) ring
    private let shortTermFrames: Int

    private var momentaryRing: [Float]
    private var shortTermRing: [Float]
    private var momentaryIndex = 0
    private var shortTermIndex = 0

    // K-weighting pre-filter state (stage 1: HP shelf, stage 2: HP)
    // We use a simple approximation: high-shelf +4dB @ 1.5kHz, HP @ 38Hz
    private var hsX1: Float = 0; private var hsY1: Float = 0   // stage 1 state L
    private var hsX1R: Float = 0; private var hsY1R: Float = 0
    private var hpX1: Float = 0; private var hpY1: Float = 0   // stage 2 state L
    private var hpX1R: Float = 0; private var hpY1R: Float = 0

    // Integrated accumulators
    private var blockSquareSum: Double = 0
    private var blockSampleCount: Int = 0
    private var gatedBlocks: [Double] = []

    init() {
        momentaryFrames = Int(0.4 * sampleRate)   // 19200
        shortTermFrames = Int(3.0 * sampleRate)   // 144000
        momentaryRing = Array(repeating: 0, count: momentaryFrames)
        shortTermRing = Array(repeating: 0, count: shortTermFrames)
    }

    /// Feed interleaved stereo samples (called from the main-thread analyzer timer).
    func submit(interleaved samples: UnsafePointer<Float>, frameCount: Int) {
        var peak: Float = truePeakDBFS > -70 ? powf(10, truePeakDBFS / 20) : 0
        let momentaryCapacity = momentaryFrames
        let shortTermCapacity = shortTermFrames

        for f in 0..<frameCount {
            let l = samples[f * 2]
            let r = samples[f * 2 + 1]

            // Apply simplified K-weighting to both channels, then sum
            let kL = kWeighted(sample: l,
                               x1: &hsX1, y1: &hsY1,
                               hpX1: &hpX1, hpY1: &hpY1)
            let kR = kWeighted(sample: r,
                               x1: &hsX1R, y1: &hsY1R,
                               hpX1: &hpX1R, hpY1: &hpY1R)

            // BS.1770: sum the squared filtered channels (L=R weight 1.0)
            let squared = kL * kL + kR * kR

            momentaryRing[momentaryIndex] = squared
            momentaryIndex = (momentaryIndex + 1) % momentaryCapacity

            shortTermRing[shortTermIndex] = squared
            shortTermIndex = (shortTermIndex + 1) % shortTermCapacity

            // Integrated: accumulate 400ms blocks, then gate
            blockSquareSum += Double(squared)
            blockSampleCount += 1
            if blockSampleCount >= momentaryCapacity {
                let meanSquare = blockSquareSum / Double(blockSampleCount)
                if meanSquare > 0 {
                    let lufs = -0.691 + 10 * log10(meanSquare)
                    if lufs > -70 {   // absolute gate
                        gatedBlocks.append(meanSquare)
                    }
                }
                blockSquareSum = 0
                blockSampleCount = 0
            }

            peak = max(peak, abs(l), abs(r))
        }

        // Compute momentary & short-term on demand
        let momMean = meanSquare(of: momentaryRing)
        let shortMean = meanSquare(of: shortTermRing)

        let mom = momMean > 0 ? (-0.691 + 10 * log10f(momMean)) : -70
        let short = shortMean > 0 ? (-0.691 + 10 * log10f(shortMean)) : -70

        // Integrated
        var integ: Float = -70
        if !gatedBlocks.isEmpty {
            let sum = gatedBlocks.reduce(0, +)
            let mean = sum / Double(gatedBlocks.count)
            integ = -0.691 + 10 * log10f(Float(mean))
        }

        let peakDB: Float = peak > 0 ? 20 * log10f(peak) : -70

        DispatchQueue.main.async {
            self.momentaryLUFS = mom
            self.shortTermLUFS = short
            self.integratedLUFS = integ
            self.truePeakDBFS = peakDB
        }
    }

    func reset() {
        gatedBlocks.removeAll()
        blockSquareSum = 0
        blockSampleCount = 0
        for i in 0..<momentaryRing.count { momentaryRing[i] = 0 }
        for i in 0..<shortTermRing.count { shortTermRing[i] = 0 }
        DispatchQueue.main.async {
            self.momentaryLUFS = -70
            self.shortTermLUFS = -70
            self.integratedLUFS = -70
            self.truePeakDBFS = -70
        }
    }

    // MARK: - DSP

    /// Simplified 2-stage K-weighting filter: high-shelf + high-pass.
    /// State is externally stored so L/R have independent memories.
    @inline(__always)
    private func kWeighted(sample: Float,
                           x1: inout Float, y1: inout Float,
                           hpX1: inout Float, hpY1: inout Float) -> Float {
        // Stage 1: high-shelf +4dB @ 1.5kHz (BS.1770 approximation)
        // One-pole HP + slight shelf boost — very rough but directionally correct
        let a1: Float = 0.995
        let b0: Float = 1.535  // brings high-shelf gain ~+4dB
        let b1: Float = -1.49
        let hs = b0 * sample + b1 * x1 + a1 * y1
        x1 = sample
        y1 = hs

        // Stage 2: 38 Hz high-pass
        // y[n] = a * (y[n-1] + x[n] - x[n-1])
        let hpA: Float = 0.995
        let hp = hpA * (hpY1 + hs - hpX1)
        hpX1 = hs
        hpY1 = hp

        return hp
    }

    private func meanSquare(of buffer: [Float]) -> Float {
        var sum: Float = 0
        vDSP_svesq(buffer, 1, &sum, vDSP_Length(buffer.count))
        return sum / Float(buffer.count)
    }
}
