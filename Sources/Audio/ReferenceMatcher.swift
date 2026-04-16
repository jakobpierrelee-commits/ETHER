import Foundation
import AVFoundation
import Accelerate
import os

/// Decodes an audio file, averages its magnitude spectrum, compares to the
/// currently-playing audio's rolling spectrum, and produces band-level gain
/// deltas so current playback matches the reference's tonal balance.
///
/// Deterministic, runs on a background queue, returns suggestions that slot
/// into the existing `AutoEQAnalyzer.Suggestion` flow.
final class ReferenceMatcher {

    private let logger = Logger(subsystem: "audio.ether.app", category: "RefMatch")
    private let fftSize = 4096
    private let log2n: vDSP_Length
    private let fftSetup: FFTSetup

    init() {
        log2n = vDSP_Length(log2(Float(fftSize)))
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
    }

    deinit { vDSP_destroy_fftsetup(fftSetup) }

    // MARK: - Public API

    /// Analyze a reference audio file and return per-band gain deltas that
    /// would bring the current playback's tonal balance toward the reference.
    /// `currentAverageBins` is the rolling average from SpectrumAnalyzer.
    func analyze(
        referenceURL: URL,
        currentAverageBins: [Float],
        bandFrequencies: [Float]
    ) throws -> [AutoEQAnalyzer.Suggestion] {

        let refBins = try decodeAndAveragedSpectrum(url: referenceURL)
        guard refBins.count == currentAverageBins.count else {
            throw MatchError.binMismatch
        }

        // Delta[i] = ref - current (both dBFS), in display-bin resolution
        var deltaBins = [Float](repeating: 0, count: refBins.count)
        for i in 0..<refBins.count {
            deltaBins[i] = refBins[i] - currentAverageBins[i]
        }

        // Remove overall loudness offset (we only care about tonal shape)
        let meanDelta = deltaBins.reduce(0, +) / Float(deltaBins.count)
        for i in 0..<deltaBins.count {
            deltaBins[i] -= meanDelta
        }

        // Average deltas within each of the 10 band regions
        let minFreq: Float = 20, maxFreq: Float = 20_000
        let logMin = log10(minFreq), logMax = log10(maxFreq)
        let binCount = refBins.count

        func binIndex(for hz: Float) -> Int {
            Int((log10(hz) - logMin) / (logMax - logMin) * Float(binCount - 1))
        }

        var suggestions: [AutoEQAnalyzer.Suggestion] = []

        for (bandIndex, freq) in bandFrequencies.enumerated() {
            let lowHz = freq / sqrt(2)   // ~third-octave span
            let highHz = freq * sqrt(2)
            let loIdx = max(0, binIndex(for: lowHz))
            let hiIdx = min(binCount - 1, binIndex(for: highHz))
            guard loIdx < hiIdx else { continue }

            var sum: Float = 0
            for i in loIdx...hiIdx { sum += deltaBins[i] }
            let avgDelta = sum / Float(hiIdx - loIdx + 1)

            // Clamp to gentle corrections only
            let clamped = max(-6.0, min(6.0, avgDelta))
            guard abs(clamped) > 0.5 else { continue }

            let sign = clamped > 0 ? "+" : ""
            let reasoning = "Reference is \(sign)\(String(format: "%.1f", clamped)) dB at \(EtherFormat.frequency(freq))"

            suggestions.append(
                AutoEQAnalyzer.Suggestion(
                    bandIndex: bandIndex,
                    gainDelta: clamped,
                    reasoning: reasoning,
                    severity: Float(min(1.0, abs(clamped) / 6.0))
                )
            )
        }

        logger.log("Reference match produced \(suggestions.count, privacy: .public) suggestions")
        return suggestions
    }

    // MARK: - File decoding + FFT

    /// Returns an averaged magnitude spectrum (in dBFS) log-binned to the
    /// same `displayBins` resolution as SpectrumAnalyzer.
    private func decodeAndAveragedSpectrum(url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let fileFormat = file.processingFormat
        let totalFrames = AVAudioFrameCount(file.length)
        guard totalFrames > 0,
              let fullBuffer = AVAudioPCMBuffer(pcmFormat: fileFormat, frameCapacity: totalFrames) else {
            throw MatchError.decodingFailed
        }

        try file.read(into: fullBuffer)

        // Sum to mono Float array
        guard let channelData = fullBuffer.floatChannelData else {
            throw MatchError.decodingFailed
        }
        let frames = Int(fullBuffer.frameLength)
        let numChannels = Int(fullBuffer.format.channelCount)
        var mono = [Float](repeating: 0, count: frames)
        for ch in 0..<numChannels {
            let src = channelData[ch]
            for f in 0..<frames { mono[f] += src[f] }
        }
        var invCh = 1.0 / Float(max(1, numChannels))
        vDSP_vsmul(mono, 1, &invCh, &mono, 1, vDSP_Length(frames))

        // Chunk through, accumulate magnitudes
        let displayBins = SpectrumAnalyzer.displayBins
        var accumulated = [Float](repeating: 0, count: displayBins)
        var chunkCount = 0

        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))

        var offset = 0
        while offset + fftSize <= frames {
            let chunk = Array(mono[offset..<(offset + fftSize)])
            let magDB = fftAndLogBin(chunk: chunk, window: window,
                                      sampleRate: Float(fileFormat.sampleRate))
            for i in 0..<displayBins { accumulated[i] += magDB[i] }
            chunkCount += 1
            offset += fftSize / 2       // 50% overlap
        }

        guard chunkCount > 0 else { throw MatchError.decodingFailed }

        for i in 0..<displayBins { accumulated[i] /= Float(chunkCount) }
        return accumulated
    }

    private func fftAndLogBin(chunk: [Float], window: [Float], sampleRate: Float) -> [Float] {
        let halfSize = fftSize / 2

        var windowed = [Float](repeating: 0, count: fftSize)
        vDSP_vmul(chunk, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))

        var realBuf = [Float](repeating: 0, count: halfSize)
        var imagBuf = [Float](repeating: 0, count: halfSize)

        windowed.withUnsafeBufferPointer { ptr in
            ptr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfSize) { complexPtr in
                realBuf.withUnsafeMutableBufferPointer { realOut in
                    imagBuf.withUnsafeMutableBufferPointer { imagOut in
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

        var mags = [Float](repeating: 0, count: halfSize)
        realBuf.withUnsafeMutableBufferPointer { realOut in
            imagBuf.withUnsafeMutableBufferPointer { imagOut in
                var split = DSPSplitComplex(
                    realp: realOut.baseAddress!,
                    imagp: imagOut.baseAddress!
                )
                vDSP_zvmags(&split, 1, &mags, 1, vDSP_Length(halfSize))
            }
        }

        var scale: Float = 1.0 / Float(fftSize * fftSize)
        vDSP_vsmul(mags, 1, &scale, &mags, 1, vDSP_Length(halfSize))

        var refValue: Float = 1.0
        var dbs = [Float](repeating: 0, count: halfSize)
        vDSP_vdbcon(mags, 1, &refValue, &dbs, 1, vDSP_Length(halfSize), 0)

        // Log-bin to displayBins
        let minFreq: Float = 20, maxFreq: Float = 20_000
        let binSize = sampleRate / Float(fftSize)
        let logMin = log10(minFreq), logMax = log10(maxFreq)
        let displayBins = SpectrumAnalyzer.displayBins

        var binned = [Float](repeating: -80, count: displayBins)
        for b in 0..<displayBins {
            let startFreq = pow(10, logMin + (logMax - logMin) * Float(b) / Float(displayBins))
            let endFreq   = pow(10, logMin + (logMax - logMin) * Float(b + 1) / Float(displayBins))
            let startIdx = max(1, Int(startFreq / binSize))
            let endIdx   = min(halfSize - 1, max(startIdx + 1, Int(endFreq / binSize)))
            var peak: Float = -120
            for i in startIdx...endIdx { peak = max(peak, dbs[i]) }
            binned[b] = peak
        }
        return binned
    }
}

enum MatchError: LocalizedError {
    case decodingFailed
    case binMismatch

    var errorDescription: String? {
        switch self {
        case .decodingFailed:  return "Could not decode the reference file."
        case .binMismatch:     return "Reference / current spectrum mismatch."
        }
    }
}
