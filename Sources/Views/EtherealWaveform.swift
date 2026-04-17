import SwiftUI

// MARK: - Ethereal Waveform
//
// Audio-reactive trace. Two principles do 95% of the visible work:
//   1. Asymmetric envelope: instant attack, slow blanket-fall decay
//   2. Adaptive smoothing: quiet regions merge, peaks keep detail

struct EtherealWaveform: View {
    @ObservedObject var analyzer: SpectrumAnalyzer
    var tint: Color
    var xCurve: CGFloat = 1.0
    var highAttenuation: Float = 0.0

    private static let steps = 24
    @State private var env: [Float] = Array(repeating: 0, count: 24)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !analyzer.isActive)) { _ in
            Canvas { ctx, size in
                let bins = analyzer.magnitudes
                guard bins.count > 1 else { return }
                let w = size.width, h = size.height
                let steps = Self.steps

                // Sample 25Hz–15kHz range from the spectrum
                let logMin = log10(Float(20)), logMax = log10(Float(20000))
                let startBin = Int(Float(bins.count) * (log10(Float(25)) - logMin) / (logMax - logMin))
                let endBin = Int(Float(bins.count) * (log10(Float(15000)) - logMin) / (logMax - logMin))
                let binRange = max(1, endBin - startBin)

                var mags = [Float](repeating: 0, count: steps)
                for i in 0..<steps {
                    let binIdx = startBin + Int(Float(i) / Float(steps) * Float(binRange))
                    let t = Float(i) / Float(steps - 1)
                    let raw = max(0, min(1, (bins[min(binIdx, bins.count - 1)] + 60) / 60))
                    let freqT = Float(i) / Float(steps - 1)
                    mags[i] = raw * (1.0 - highAttenuation * freqT)
                }

                // Asymmetric envelope
                var next = env
                for i in 0..<steps {
                    if mags[i] > next[i] {
                        next[i] = mags[i]
                    } else {
                        let dist = next[i] - mags[i]
                        let decay: Float = 0.50 + dist * 0.06
                        next[i] = next[i] * decay + mags[i] * (1 - decay)
                    }
                }

                // Adaptive smoothing — less aggressive at high frequencies so treble stays active
                var shaped = next
                for i in 1..<(steps - 1) {
                    let freqPos = Float(i) / Float(steps - 1)
                    let smooth = max(0, min(0.7, 0.7 - next[i] * 1.2)) * (1.0 - freqPos * 0.65)
                    shaped[i] = next[i] * (1 - smooth) + (next[i - 1] + next[i + 1]) * 0.5 * smooth
                }

                DispatchQueue.main.async { env = shaped }

                // Build points — xCurve > 1 compresses high end toward right
                var points: [CGPoint] = []
                for i in 0..<steps {
                    let t = CGFloat(i) / CGFloat(steps - 1)
                    let x = pow(t, xCurve) * w
                    let y = h - CGFloat(shaped[i]) * h * 0.8
                    points.append(CGPoint(x: x, y: y))
                }

                // Path
                var path = Path()
                path.move(to: CGPoint(x: 0, y: h))
                path.addLine(to: points[0])
                for i in 1..<points.count {
                    let prev = points[i - 1], curr = points[i]
                    let midX = (prev.x + curr.x) / 2
                    path.addCurve(to: curr,
                                  control1: CGPoint(x: midX, y: prev.y),
                                  control2: CGPoint(x: midX, y: curr.y))
                }
                path.addLine(to: CGPoint(x: w, y: h))
                path.closeSubpath()

                let peakY = points.map(\.y).min() ?? h

                // Blurred glow
                var glow = ctx
                glow.addFilter(.blur(radius: 8))
                glow.fill(path, with: .linearGradient(
                    Gradient(stops: [
                        .init(color: tint.opacity(0.5), location: 0),
                        .init(color: tint.opacity(0.15), location: 0.5),
                        .init(color: .clear, location: 1.0),
                    ]),
                    startPoint: CGPoint(x: 0, y: peakY),
                    endPoint: CGPoint(x: 0, y: h)
                ))

                // Fill
                ctx.fill(path, with: .linearGradient(
                    Gradient(stops: [
                        .init(color: tint.opacity(0.55), location: 0),
                        .init(color: tint.opacity(0.2), location: 0.35),
                        .init(color: tint.opacity(0.03), location: 0.8),
                        .init(color: .clear, location: 1.0),
                    ]),
                    startPoint: CGPoint(x: 0, y: peakY),
                    endPoint: CGPoint(x: 0, y: h)
                ))

                // Edge stroke
                var edge = Path()
                edge.move(to: points[0])
                for i in 1..<points.count {
                    let prev = points[i - 1], curr = points[i]
                    let midX = (prev.x + curr.x) / 2
                    edge.addCurve(to: curr,
                                  control1: CGPoint(x: midX, y: prev.y),
                                  control2: CGPoint(x: midX, y: curr.y))
                }
                ctx.stroke(edge, with: .color(tint.opacity(0.8)), lineWidth: 1)
            }
        }
        .blendMode(.screen)
    }
}
