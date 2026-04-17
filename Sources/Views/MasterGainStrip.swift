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
                .font(.etherValue(11))
                .monospacedDigit()
                .foregroundColor(.gainTint(for: controller.masterGain))
                .frame(width: 60, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.etherSurface)
                .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
        )
    }
}
