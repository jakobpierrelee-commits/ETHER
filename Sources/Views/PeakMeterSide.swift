import SwiftUI

/// Tall vertical peak meter, sits beside the EQ canvas.
/// Shows the post-EQ output signal level with peak-hold.
struct PeakMeterSide: View {
    @ObservedObject var analyzer: SpectrumAnalyzer

    @State private var peakHold: Float = -80
    @State private var lastPeakTime = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !analyzer.isActive)) { context in
            let peak = analyzer.magnitudes.max() ?? -80
            let held = updatedPeakHold(current: peak, time: context.date)
            let isClipping = peak > -0.5

            VStack(spacing: 6) {
                // Top: current dB value
                Text(String(format: "%+.1f", peak))
                    .font(.etherMono(EtherType.tiny, weight: .medium))
                    .foregroundColor(isClipping ? .etherClip : .etherTextSecondary)
                    .monospacedDigit()

                // Meter body
                ZStack(alignment: .bottom) {
                    // Background track
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.black.opacity(0.55))
                        .overlay(
                            RoundedRectangle(cornerRadius: 2)
                                .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
                        )

                    // Fill — gradient mapped to level
                    GeometryReader { geo in
                        let fillNorm = CGFloat(max(0, min(1, (peak + 60) / 60)))
                        let holdNorm = CGFloat(max(0, min(1, (held + 60) / 60)))
                        let h = geo.size.height

                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.p3(1.0, 0.08, 0.08),
                                            Color.p3(1.0, 0.45, 0.12),
                                            Color.p3(1.0, 0.82, 0.0),
                                            Color.p3(0.3, 0.85, 0.3),
                                            Color.p3(0.15, 0.65, 0.9)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(height: fillNorm * h)
                                .padding(.horizontal, 2)

                            // Peak-hold marker line
                            if held > -60 {
                                Rectangle()
                                    .fill(Color.white.opacity(0.9))
                                    .frame(height: 1.5)
                                    .padding(.horizontal, 1)
                                    .offset(y: -holdNorm * h + 1)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    }

                    // dB tick marks overlaid
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach([0, -6, -12, -24, -40], id: \.self) { db in
                            HStack(spacing: 0) {
                                Rectangle()
                                    .fill(Color.white.opacity(0.25))
                                    .frame(width: 3, height: 1)
                                Spacer()
                            }
                            if db != -40 { Spacer() }
                        }
                    }
                    .padding(.vertical, 2)
                    .allowsHitTesting(false)
                }
                .frame(width: 18)

                // Clip indicator dot
                Circle()
                    .fill(isClipping ? Color.etherClip : Color.etherTextTertiary.opacity(0.2))
                    .frame(width: 5, height: 5)

                // Label
                Text("PEAK")
                    .font(.etherMono(7, weight: .semibold))
                    .tracking(1.0)
                    .foregroundColor(.etherTextTertiary)
            }
        }
    }

    private func updatedPeakHold(current: Float, time: Date) -> Float {
        if current > peakHold {
            DispatchQueue.main.async {
                peakHold = current
                lastPeakTime = time
            }
            return current
        }
        // Decay after 1.5s of hold
        let elapsed = time.timeIntervalSince(lastPeakTime)
        if elapsed > 1.5 {
            let newHold = max(current, peakHold - Float(elapsed - 1.5) * 12)
            DispatchQueue.main.async { peakHold = newHold }
            return newHold
        }
        return peakHold
    }
}
