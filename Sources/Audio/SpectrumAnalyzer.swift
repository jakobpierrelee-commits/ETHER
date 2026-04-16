import Accelerate
import Foundation
import Combine

/// Real-time FFT spectrum analyzer.
/// Accepts deinterleaved float samples (we sum to mono for display),
/// runs vDSP FFT on a background queue, and publishes log-binned magnitude
/// data for the UI to draw.
final class SpectrumAnalyzer: ObservableObject {

    // Number of frequency bins displayed (log-spaced between 20Hz and 20kHz)
    // 256 bins gives smooth curves and fine detail without crushing CPU
    static let displayBins = 256

    /// Magnitudes in dBFS, one per display bin. Values typically in [-80, 0].
    @Published var magnitudes: [Float] = Array(repeating: -80, count: displayBins)

    /// Peak-hold per display bin — decays slowly for visualizer dots.
    @Published var peaks: [Float] = Array(repeating: -80, count: displayBins)
    private let peakDecayPerFrame: Float = 0.8

    // Spectrogram scrolling history: ring of columns.
    static let spectrogramColumns = 200
    /// Flattened row-major grid of dBFS values: [row * columns + col].
    /// Rows run low→high frequency (row 0 = lowest). Use `spectrogramColumnOffset`
    /// when reading to get correct temporal order.
    @Published var spectrogramGrid: [Float] = Array(
        repeating: -80,
        count: spectrogramColumns * displayBins
    )
    @Published var spectrogramWriteColumn: Int = 0

    // FFT configuration — 4096-point for higher frequency resolution (~11.7Hz bins at 48kHz)
    private let fftSize = 4096
    private let log2n: vDSP_Length
    private let fftSetup: FFTSetup
    private let sampleRate: Float = 48000

    // Scratch buffers (allocated once, reused)
    private var workingBuffer: [Float]
    private var window: [Float]
    private var realBuffer: [Float]
    private var imagBuffer: [Float]

    // Decay smoothing — each frame the displayed value decays slightly,
    // and the max of (decayed, new) is shown. Gives peak-hold with falloff.
    private let attackSmoothing: Float = 0.85  // snappy attack — responds to transients
    private let decayPerFrame: Float = 3.0     // dB lost per frame (faster release)
    private let spectralSmoothingTaps = 1      // just 1 neighbor each side — lighter smoothing

    // Background processing
    private let processingQueue = DispatchQueue(label: "audio.ether.spectrum", qos: .userInteractive)
    private var lastProcessTime: TimeInterval = 0
    private let minFrameInterval: TimeInterval = 1.0 / 30.0  // 30 fps — imperceptible vs 60

    /// Set to false to skip FFT work entirely (e.g., when window is hidden).
    var isActive: Bool = true

    init() {
        log2n = vDSP_Length(log2(Float(fftSize)))
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!

        workingBuffer = [Float](repeating: 0, count: fftSize)
        realBuffer    = [Float](repeating: 0, count: fftSize / 2)
        imagBuffer    = [Float](repeating: 0, count: fftSize / 2)

        // Hann window for spectral leakage reduction
        window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    // Accumulator buffer to collect enough samples for a 4096-point FFT
    private var accumulator: [Float] = []

    /// Called with interleaved stereo samples.
    /// Throttles to 30 fps and dispatches processing to a background queue.
    /// Completely skips work when `isActive` is false.
    func submit(interleaved: UnsafePointer<Float>, frameCount: Int) {
        guard isActive else { return }

        // Sum to mono and append to accumulator
        for i in 0..<frameCount {
            accumulator.append((interleaved[i * 2] + interleaved[i * 2 + 1]) * 0.5)
        }

        // Keep accumulator bounded; only process when we have enough and are due
        if accumulator.count < fftSize { return }

        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastProcessTime >= minFrameInterval else {
            // Trim to avoid unbounded growth
            if accumulator.count > fftSize * 2 {
                accumulator.removeFirst(accumulator.count - fftSize)
            }
            return
        }
        lastProcessTime = now

        let mono = Array(accumulator.suffix(fftSize))
        accumulator.removeFirst(accumulator.count - fftSize)

        processingQueue.async { [mono] in
            self.process(mono: mono)
        }
    }

    // MARK: - FFT + Binning

    private func process(mono: [Float]) {
        // Fill working buffer, pad with zeros if needed
        let copyCount = min(mono.count, fftSize)
        for i in 0..<copyCount { workingBuffer[i] = mono[i] }
        if copyCount < fftSize {
            for i in copyCount..<fftSize { workingBuffer[i] = 0 }
        }

        // Apply Hann window
        vDSP_vmul(workingBuffer, 1, window, 1, &workingBuffer, 1, vDSP_Length(fftSize))

        // Pack real input as complex for vDSP_fft_zrip
        let halfSize = fftSize / 2
        workingBuffer.withUnsafeBufferPointer { realPtr in
            realPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfSize) { complexPtr in
                realBuffer.withUnsafeMutableBufferPointer { realOut in
                    imagBuffer.withUnsafeMutableBufferPointer { imagOut in
                        var split = DSPSplitComplex(
                            realp: realOut.baseAddress!,
                            imagp: imagOut.baseAddress!
                        )
                        vDSP_ctoz(complexPtr, 2, &split, 1, vDSP_Length(halfSize))
                        vDSP_fft_zrip(self.fftSetup, &split, 1, self.log2n, FFTDirection(FFT_FORWARD))
                    }
                }
            }
        }

        // Compute magnitude spectrum (in linear units)
        var magnitudes = [Float](repeating: 0, count: halfSize)
        realBuffer.withUnsafeMutableBufferPointer { realOut in
            imagBuffer.withUnsafeMutableBufferPointer { imagOut in
                var split = DSPSplitComplex(
                    realp: realOut.baseAddress!,
                    imagp: imagOut.baseAddress!
                )
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(halfSize))
            }
        }

        // Convert to dBFS (10 * log10(magnitude) since zvmags already squared)
        var scale: Float = 1.0 / Float(fftSize * fftSize)
        vDSP_vsmul(magnitudes, 1, &scale, &magnitudes, 1, vDSP_Length(halfSize))

        var refValue: Float = 1.0
        var dbs = [Float](repeating: 0, count: halfSize)
        vDSP_vdbcon(magnitudes, 1, &refValue, &dbs, 1, vDSP_Length(halfSize), 0)

        // Log-bin down to displayBins (20Hz to 20kHz log-spaced)
        let minFreq: Float = 20
        let maxFreq: Float = 20000
        let binSize = sampleRate / Float(fftSize)
        let logMin = log10(minFreq)
        let logMax = log10(maxFreq)
        let displayBins = Self.displayBins

        var binned = [Float](repeating: -80, count: displayBins)
        for b in 0..<displayBins {
            let startFreq = pow(10, logMin + (logMax - logMin) * Float(b) / Float(displayBins))
            let endFreq   = pow(10, logMin + (logMax - logMin) * Float(b + 1) / Float(displayBins))
            let startIdx = max(1, Int(startFreq / binSize))
            let endIdx   = min(halfSize - 1, max(startIdx + 1, Int(endFreq / binSize)))

            var peak: Float = -120
            for i in startIdx...endIdx {
                peak = max(peak, dbs[i])
            }
            binned[b] = peak
        }

        // Spectral smoothing: 5-tap weighted moving average across the frequency axis.
        // Kills bin-to-bin jitter without blurring real peaks too much.
        var smoothed = binned
        let taps = spectralSmoothingTaps
        for i in taps..<(binned.count - taps) {
            var sum: Float = 0
            var weight: Float = 0
            for offset in -taps...taps {
                let w = 1.0 / (1.0 + abs(Float(offset)))
                sum += binned[i + offset] * w
                weight += w
            }
            smoothed[i] = sum / weight
        }

        // Hand off to main queue for smoothing + publication (triggers @Published)
        DispatchQueue.main.async { [smoothed] in
            self.applyAndPublish(newFrame: smoothed)
        }
    }

    /// Optional observer invoked on the main actor after each new frame
    /// is published. Used to feed the long-term average analyzer.
    var onFrame: (([Float]) -> Void)?

    private func applyAndPublish(newFrame: [Float]) {
        guard newFrame.count == magnitudes.count else { return }
        for i in 0..<magnitudes.count {
            let decayed = magnitudes[i] - decayPerFrame
            let blended = max(newFrame[i], decayed)
            magnitudes[i] = magnitudes[i] * (1 - attackSmoothing) + blended * attackSmoothing

            let peakDecayed = peaks[i] - peakDecayPerFrame
            peaks[i] = max(newFrame[i], peakDecayed)
        }

        let cols = Self.spectrogramColumns
        let rows = Self.displayBins
        let col = spectrogramWriteColumn
        for row in 0..<rows {
            spectrogramGrid[row * cols + col] = newFrame[row]
        }
        spectrogramWriteColumn = (col + 1) % cols

        onFrame?(newFrame)
    }
}
