import SwiftUI

/// Collapsible panel: Width / Bass Mono / Crossfeed / Virtual Speakers / Reverb.
struct SpatialView: View {
    @ObservedObject var spatial: SpatialController
    @AppStorage("audio.ether.spatialExpanded") private var expanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        EtherSectionHeader(text: "Spatial")
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(.etherTextTertiary)
                    }
                }
                .buttonStyle(.plain)

                if anyActive {
                    Circle()
                        .fill(Color.etherAccent)
                        .frame(width: 5, height: 5)
                }

                Spacer()
            }

            if expanded {
                VStack(alignment: .leading, spacing: 12) {
                    widthRow
                    bassMonoRow
                    crossfeedRow
                    virtualSpeakersRow
                    Divider().opacity(0.15)
                    reverbRow
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.etherSurface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(Color.white.opacity(0.04), lineWidth: 1)
                        )
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var anyActive: Bool {
        spatial.width != 1.0
            || spatial.bassMonoEnabled
            || spatial.crossfeedEnabled
            || spatial.virtualSpeakers
            || spatial.reverbPreset != .off
    }

    // MARK: - Rows

    private var widthRow: some View {
        HStack(spacing: 10) {
            label("WIDTH")
            EtherSlider(value: $spatial.width, range: 0...2)
            valueText(String(format: "%.0f%%", spatial.width * 100))
            resetButton {
                spatial.width = 1.0
            }
        }
    }

    private var bassMonoRow: some View {
        HStack(spacing: 10) {
            label("BASS MONO")
            Toggle("", isOn: $spatial.bassMonoEnabled)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
            EtherSlider(value: $spatial.bassMonoCrossover, range: 40...300, disabled: !spatial.bassMonoEnabled)
            valueText("\(Int(spatial.bassMonoCrossover)) Hz")
        }
    }

    private var crossfeedRow: some View {
        HStack(spacing: 10) {
            label("CROSSFEED")
            Toggle("", isOn: $spatial.crossfeedEnabled)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
            EtherSlider(value: $spatial.crossfeedAmount, range: 0...0.8, disabled: !spatial.crossfeedEnabled)
            valueText(String(format: "%.0f%%", spatial.crossfeedAmount * 100))
        }
    }

    private var virtualSpeakersRow: some View {
        HStack(spacing: 10) {
            label("VIRTUAL SPEAKERS")
            Toggle("", isOn: $spatial.virtualSpeakers)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
            Text("Simulates speakers when listening on headphones")
                .font(.etherMono(9))
                .foregroundColor(.etherTextTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var reverbRow: some View {
        HStack(spacing: 10) {
            label("REVERB")
            Menu {
                ForEach(ReverbPreset.allCases) { preset in
                    Button(preset.rawValue) {
                        spatial.reverbPreset = preset
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(spatial.reverbPreset.rawValue)
                        .font(.etherMono(EtherType.small))
                        .foregroundColor(.etherTextPrimary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7))
                        .foregroundColor(.etherTextTertiary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.etherSurfaceHigh)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                        )
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            EtherSlider(value: $spatial.reverbAmount, range: 0...100, disabled: spatial.reverbPreset == .off)

            valueText("\(Int(spatial.reverbAmount))%")
        }
    }

    // MARK: - Helpers

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.etherMono(9, weight: .semibold))
            .tracking(1.0)
            .foregroundColor(.etherTextTertiary)
            .frame(width: 120, alignment: .leading)
    }

    private func valueText(_ text: String) -> some View {
        Text(text)
            .font(.etherMono(10, weight: .medium))
            .monospacedDigit()
            .foregroundColor(.etherTextPrimary)
            .frame(width: 56, alignment: .trailing)
    }

    private func resetButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 9))
                .foregroundColor(.etherTextTertiary)
        }
        .buttonStyle(.plain)
        .help("Reset")
    }
}
