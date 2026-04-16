import SwiftUI

/// Shows the selected band's Freq / Gain / Q / Type with editable fields.
/// Tab cycles, scroll adjusts, clicks to edit.
struct BandDetailStrip: View {
    @ObservedObject var controller: EQController

    var body: some View {
        HStack(spacing: 0) {
            if let band = selectedBand {
                field(label: "BAND", value: bandIndex(for: band).map { "\($0 + 1)" } ?? "–", editable: false)
                divider
                typeField(band: band)
                divider
                freqField(band: band)
                divider
                if band.type.usesGain {
                    gainField(band: band)
                    divider
                }
                qField(band: band)
                divider
                Toggle("", isOn: Binding(
                    get: { !band.bypassed },
                    set: { _ in controller.toggleBypass(bandID: band.id) }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .padding(.horizontal, 12)
                Text(band.bypassed ? "BYPASSED" : "ACTIVE")
                    .font(.etherMono(9, weight: .semibold))
                    .foregroundColor(band.bypassed ? .etherTextTertiary : .etherPositive)
                    .frame(minWidth: 70, alignment: .leading)
            }
        }
        .etherPanel(padding: 0)
        .frame(height: controller.selectedBandID != nil ? 36 : 0)
        .opacity(controller.selectedBandID != nil ? 1 : 0)
        .animation(.easeOut(duration: 0.15), value: controller.selectedBandID != nil)
    }

    // MARK: - Selected

    private var selectedBand: EQBand? {
        guard let id = controller.selectedBandID else { return nil }
        return controller.bands.first(where: { $0.id == id })
    }

    private func bandIndex(for band: EQBand) -> Int? {
        controller.bands.firstIndex(where: { $0.id == band.id })
    }

    // MARK: - Fields

    private func field(label: String, value: String, editable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.etherMono(8, weight: .semibold))
                .tracking(0.8)
                .foregroundColor(.etherTextTertiary)
            Text(value)
                .font(.etherMono(11, weight: .medium))
                .foregroundColor(.etherTextPrimary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private func typeField(band: EQBand) -> some View {
        Menu {
            ForEach(EQFilterType.allCases) { type in
                Button {
                    controller.setType(bandID: band.id, type: type)
                } label: {
                    HStack {
                        if type == band.type { Image(systemName: "checkmark") }
                        Text(type.displayName)
                    }
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("TYPE")
                    .font(.etherMono(8, weight: .semibold))
                    .tracking(0.8)
                    .foregroundColor(.etherTextTertiary)
                HStack(spacing: 4) {
                    Text(band.type.displayName)
                        .font(.etherMono(11, weight: .medium))
                        .foregroundColor(.etherTextPrimary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7))
                        .foregroundColor(.etherTextSecondary)
                }
            }
        }
        .menuStyle(.borderlessButton)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
    }

    private func freqField(band: EQBand) -> some View {
        field(label: "FREQ", value: EtherFormat.frequency(band.frequency), editable: true)
    }

    private func gainField(band: EQBand) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("GAIN")
                .font(.etherMono(8, weight: .semibold))
                .tracking(0.8)
                .foregroundColor(.etherTextTertiary)
            Text(EtherFormat.gain(band.gain))
                .font(.etherMono(11, weight: .medium))
                .foregroundColor(band.tint)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
    }

    private func qField(band: EQBand) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text("Q")
                    .font(.etherMono(8, weight: .semibold))
                    .tracking(0.8)
                    .foregroundColor(.etherTextTertiary)
                Text("◂ ▸")
                    .font(.etherMono(7))
                    .foregroundColor(.etherTextTertiary.opacity(0.6))
            }
            Text(EtherFormat.q(band.q))
                .font(.etherMono(11, weight: .medium))
                .foregroundColor(.etherTextPrimary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    // Drag left/right OR up/down to change Q
                    let delta = Float(-value.translation.height / 80 + value.translation.width / 120)
                    let newQ = max(0.1, min(20, band.q + delta * band.q * 0.5))
                    controller.setQ(bandID: band.id, q: newQ)
                }
        )
        .help("Drag or scroll to adjust Q · \(EtherFormat.q(band.q))")
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(width: 1, height: 26)
    }
}
