import Foundation

/// Inline stereo DSP applied inside the AVAudioSourceNode render callback.
/// Runs on the audio thread — no allocations, no locks.
final class StereoProcessor {

    // MARK: - Parameters (read by audio thread, written by UI thread — atomic-safe on ARM64)
    var widthMultiplier: Float = 1.0          // 0 = mono, 1 = natural, 2 = hyper-wide
    var bassMonoEnabled: Bool = false
    var bassMonoCrossoverHz: Float = 120      // below this goes mono
    var crossfeedEnabled: Bool = false
    var crossfeedAmount: Float = 0.35         // 0...1
    var crossfeedHighCutHz: Float = 700       // LP on the crossfed signal

    // Polarity
    var invertLeft: Bool = false
    var invertRight: Bool = false
    var sumToMono: Bool = false               // forces stereo → mono (mix check)

    // Dehiss (simple: high-band downward expander + static shelf cut)
    var dehissEnabled: Bool = false
    var dehissPivotHz: Float = 6000           // crossover: hiss lives above this
    var dehissThreshold: Float = 0.00178      // linear amplitude (~-55 dBFS)
    var dehissMaxReduction: Float = 0.355     // linear (~9 dB of ducking)
    var dehissShelfGain: Float = 0.794        // static HF trim (~-2 dB)

    // MARK: - State (one-pole filter memory per channel)

    private let sampleRate: Float
    private var bassLPL: Float = 0   // L channel bass-mono LP state
    private var bassLPR: Float = 0
    private var xfLPL: Float = 0     // L channel crossfeed LP state
    private var xfLPR: Float = 0

    // Dehiss state: splitter LP, envelope follower, smoothed gain (per channel)
    private var dhSplitL: Float = 0
    private var dhSplitR: Float = 0
    private var dhEnvL: Float = 0
    private var dhEnvR: Float = 0
    private var dhGainL: Float = 1
    private var dhGainR: Float = 1

    init(sampleRate: Float = 48000) {
        self.sampleRate = sampleRate
    }

    // MARK: - Process

    /// Process `frameCount` deinterleaved stereo samples in-place.
    /// `l` and `r` are pointers to the left and right channel float buffers.
    func process(l: UnsafeMutablePointer<Float>, r: UnsafeMutablePointer<Float>, frameCount: Int) {
        // Pre-compute filter alphas (cheap, safe to do here)
        let twoPi = 2 * Float.pi

        let bassAlpha = max(0.001, min(0.999, twoPi * bassMonoCrossoverHz / sampleRate))
        let xfAlpha = max(0.001, min(0.999, twoPi * crossfeedHighCutHz / sampleRate))

        let width = widthMultiplier
        let doBassMono = bassMonoEnabled
        let doCrossfeed = crossfeedEnabled
        let xfAmt = crossfeedAmount

        // Dehiss pre-compute (safe — no allocs, cheap math)
        let doDehiss = dehissEnabled
        let splitAlpha = max(0.001, min(0.999, twoPi * dehissPivotHz / sampleRate))
        let thresh = max(1e-6, dehissThreshold)
        let threshInv: Float = 1.0 / thresh
        let floorGain = max(0.0, 1.0 - dehissMaxReduction)  // lowest gain when fully ducked
        let shelfGain = dehissShelfGain
        // ~3ms attack, ~80ms release at 48k
        let envAttack: Float  = 1 - exp(-1.0 / (0.003 * sampleRate))
        let envRelease: Float = 1 - exp(-1.0 / (0.080 * sampleRate))
        // Gain smoothing — ~15 ms, avoids zipper noise on gate transitions
        let gainSmooth: Float = 1 - exp(-1.0 / (0.015 * sampleRate))

        for n in 0..<frameCount {
            var left = l[n]
            var right = r[n]

            // ── 1. Bass-mono: sum L+R below crossover, keep stereo above ──────
            if doBassMono {
                bassLPL += bassAlpha * (left - bassLPL)
                bassLPR += bassAlpha * (right - bassLPR)
                let mono = (bassLPL + bassLPR) * 0.5
                // Subtract each channel's LP, then add the mono LP back to both
                left = (left - bassLPL) + mono
                right = (right - bassLPR) + mono
            }

            // ── 2. M-S width: scale side signal ───────────────────────────────
            // Skip math when width == 1
            if abs(width - 1.0) > 0.001 {
                let mid = (left + right) * 0.5
                let side = (left - right) * 0.5 * width
                left = mid + side
                right = mid - side
            }

            // ── 3. Crossfeed: low-passed cross-channel bleed ─────────────────
            if doCrossfeed {
                xfLPL += xfAlpha * (left - xfLPL)
                xfLPR += xfAlpha * (right - xfLPR)
                let leftCrossed = left + xfLPR * xfAmt
                let rightCrossed = right + xfLPL * xfAmt
                // Gain-compensate: add crossfeed energy lightly, then scale back
                let comp = 1.0 / (1.0 + xfAmt * 0.6)
                left = leftCrossed * comp
                right = rightCrossed * comp
            }

            // ── 3b. Dehiss: HP/LP split + downward expander on highs ─────
            if doDehiss {
                // Splitter: LP gives lows; highs = x - lp
                dhSplitL += splitAlpha * (left - dhSplitL)
                dhSplitR += splitAlpha * (right - dhSplitR)
                var hL = left - dhSplitL
                var hR = right - dhSplitR
                let lL = dhSplitL
                let lR = dhSplitR

                // Envelope: fast attack, slow release on |hf|
                let aL = abs(hL), aR = abs(hR)
                let coL: Float = aL > dhEnvL ? envAttack : envRelease
                let coR: Float = aR > dhEnvR ? envAttack : envRelease
                dhEnvL += coL * (aL - dhEnvL)
                dhEnvR += coR * (aR - dhEnvR)

                // Target gain: below threshold → ducked to (1 - maxRed); above → 1
                let tgtL: Float = dhEnvL >= thresh ? 1 : (floorGain + (1 - floorGain) * (dhEnvL * threshInv))
                let tgtR: Float = dhEnvR >= thresh ? 1 : (floorGain + (1 - floorGain) * (dhEnvR * threshInv))
                dhGainL += gainSmooth * (tgtL - dhGainL)
                dhGainR += gainSmooth * (tgtR - dhGainR)

                // Apply gate gain + static shelf cut to the high band, then recombine
                hL *= dhGainL * shelfGain
                hR *= dhGainR * shelfGain
                left = lL + hL
                right = lR + hR
            }

            // ── 4. Polarity / mono check ─────────────────────────────────
            if invertLeft  { left  = -left  }
            if invertRight { right = -right }
            if sumToMono {
                let m = (left + right) * 0.5
                left = m
                right = m
            }

            // Hard safety clip (shouldn't ever hit, but just in case)
            l[n] = max(-1.5, min(1.5, left))
            r[n] = max(-1.5, min(1.5, right))
        }
    }

    /// Reset filter state — call when the engine stops or sample rate changes.
    func reset() {
        bassLPL = 0; bassLPR = 0; xfLPL = 0; xfLPR = 0
        dhSplitL = 0; dhSplitR = 0; dhEnvL = 0; dhEnvR = 0
        dhGainL = 1; dhGainR = 1
    }
}
