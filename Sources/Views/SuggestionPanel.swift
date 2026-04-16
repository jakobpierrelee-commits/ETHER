import SwiftUI

/// Floating panel showing Auto-EQ suggestions with Apply / Dismiss actions.
/// Replaces the current suggestions with a single click; undoable via Cmd-Z.
struct SuggestionPanel: View {
    @ObservedObject var analyzer: AutoEQAnalyzer
    @ObservedObject var controller: EQController
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11))
                    .foregroundColor(.etherAccent)
                Text("AI SUGGESTIONS")
                    .font(.etherMono(10, weight: .semibold))
                    .tracking(1.0)
                    .foregroundColor(.etherTextPrimary)
                Spacer()
                Button {
                    isPresented = false
                    analyzer.clear()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9))
                        .foregroundColor(.etherTextTertiary)
                }
                .buttonStyle(.plain)
            }

            if analyzer.suggestions.isEmpty {
                Text("Nothing to suggest — this already sounds balanced.")
                    .font(.etherMono(10))
                    .foregroundColor(.etherTextSecondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(analyzer.suggestions) { s in
                    HStack(alignment: .top, spacing: 8) {
                        // Severity pip
                        Circle()
                            .fill(severityColor(s.severity))
                            .frame(width: 6, height: 6)
                            .padding(.top, 4)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(bandLabel(s.bandIndex))
                                    .font(.etherMono(10, weight: .medium))
                                    .foregroundColor(.etherTextPrimary)
                                Text(String(format: "%+.1f dB", s.gainDelta))
                                    .font(.etherMono(10, weight: .medium))
                                    .monospacedDigit()
                                    .foregroundColor(s.gainDelta > 0 ? .etherPositive : .etherNegative)
                            }
                            Text(s.reasoning)
                                .font(.etherMono(EtherType.small))
                                .foregroundColor(.etherTextSecondary)
                        }
                    }
                }

                HStack(spacing: 8) {
                    Spacer()
                    Button("Dismiss") {
                        isPresented = false
                        analyzer.clear()
                    }
                    .buttonStyle(.plain)
                    .font(.etherMono(10))
                    .foregroundColor(.etherTextSecondary)

                    Button("Apply") {
                        applySuggestions()
                        isPresented = false
                        analyzer.clear()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(.etherAccent)
                }
                .padding(.top, 4)
            }
        }
        .padding(12)
        .frame(width: 320)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(white: 0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.etherAccent.opacity(0.25), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.5), radius: 12, x: 0, y: 4)
    }

    private func bandLabel(_ index: Int) -> String {
        let freq = EQController.defaultFrequencies[index]
        return EtherFormat.frequency(freq)
    }

    private func severityColor(_ severity: Float) -> Color {
        if severity < 0.33 { return .etherPositive.opacity(0.8) }
        if severity < 0.66 { return .etherWarning }
        return .etherNegative
    }

    private func applySuggestions() {
        for s in analyzer.suggestions {
            guard s.bandIndex < controller.bands.count else { continue }
            let band = controller.bands[s.bandIndex]
            let newGain = max(-24, min(24, band.gain + s.gainDelta))
            controller.setGain(bandID: band.id, gain: newGain)
        }
    }
}
