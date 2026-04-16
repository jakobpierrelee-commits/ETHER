import SwiftUI

/// Compact master output gain slider. Peak meter now lives beside the EQ.
struct MasterGainStrip: View {
    @ObservedObject var controller: EQController

    private let minGain: Float = -12
    private let maxGain: Float = +12

    var body: some View {
        HStack(spacing: 10) {
            Text("OUTPUT")
                .font(.etherMono(9, weight: .semibold))
                .tracking(1.0)
                .foregroundColor(.etherTextTertiary)
                .frame(width: 58, alignment: .leading)

            EtherGainSlider(
                value: Binding(
                    get: { controller.masterGain },
                    set: { controller.setMasterGain($0) }
                ),
                range: minGain...maxGain
            )

            Text(EtherFormat.gain(controller.masterGain))
                .font(.etherMono(11, weight: .medium))
                .monospacedDigit()
                .foregroundColor(.gainTint(for: controller.masterGain))
                .frame(width: 60, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.etherSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Color.white.opacity(0.04), lineWidth: 1)
                )
        )
    }
}
