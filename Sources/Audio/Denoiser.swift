import Foundation
import Combine

/// Simple single-band dehisser: downward expander on the high band above `pivotHz`,
/// plus a small static high-shelf trim. Good enough to rescue a hissy stream;
/// not studio-grade spectral restoration.
final class DenoiseController: ObservableObject {

    @Published var enabled: Bool = false            { didSet { push() } }
    @Published var pivotHz: Float = 6000            { didSet { push() } }  // 3k…10k
    @Published var thresholdDB: Float = -55         { didSet { push() } }  // -80…-30
    @Published var reductionDB: Float = 9           { didSet { push() } }  // 0…18
    @Published var shelfCutDB: Float = 2            { didSet { push() } }  // 0…6

    weak var processor: StereoProcessor?

    private func push() {
        guard let p = processor else { return }
        p.dehissEnabled = enabled
        p.dehissPivotHz = max(1000, min(16000, pivotHz))
        p.dehissThreshold = pow(10.0, thresholdDB / 20.0)
        p.dehissMaxReduction = max(0, min(1, 1 - pow(10.0, -reductionDB / 20.0)))
        p.dehissShelfGain = pow(10.0, -shelfCutDB / 20.0)
    }

    func syncInitial() { push() }

    func reset() {
        enabled = false
        pivotHz = 6000
        thresholdDB = -55
        reductionDB = 9
        shelfCutDB = 2
    }
}
