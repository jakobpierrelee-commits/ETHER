import SwiftUI

/// The Advanced window — LUFS meter, polarity/mono tools, global hotkeys,
/// and device transport info. Opened via a gear icon in the main header.
struct AdvancedView: View {
    @EnvironmentObject var engine: EngineManager
    @ObservedObject var spatial: SpatialController
    @ObservedObject var loudness: LoudnessMeter
    @ObservedObject var hotkeys: GlobalHotkeys
    @ObservedObject var denoise: DenoiseController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                loudnessSection
                dehissSection
                visualOffsetSection
                transportSection
                stereoUtilsSection
                hotkeysSection
                aboutFooter
            }
            .padding(24)
        }
        .frame(minWidth: 560, idealWidth: 620, minHeight: 560, idealHeight: 720)
        .background(Color.etherBackground)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ADVANCED")
                .font(.etherVariant(EtherType.large))
                .tracking(2.2)
                .foregroundColor(.etherAccent)
            Text("Monitoring, stereo tools, and global shortcuts.")
                .font(.etherMono(11))
                .foregroundColor(.etherTextSecondary)
        }
    }

    // MARK: - LUFS meter

    private var loudnessSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                EtherSectionHeader(text: "Loudness (LUFS)")
                Spacer()
                Button("Reset") { loudness.reset() }
                    .buttonStyle(.plain)
                    .font(.etherMono(10))
                    .foregroundColor(.etherTextSecondary)
            }

            HStack(spacing: 14) {
                lufsCell(label: "MOMENTARY", value: loudness.momentaryLUFS)
                lufsCell(label: "SHORT-TERM", value: loudness.shortTermLUFS)
                lufsCell(label: "INTEGRATED", value: loudness.integratedLUFS, highlight: true)
                lufsCell(label: "TRUE PEAK", value: loudness.truePeakDBFS, unit: "dBFS")
            }
        }
        .etherPanel()
    }

    private func lufsCell(label: String, value: Float, highlight: Bool = false, unit: String = "LUFS") -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.etherMono(8, weight: .semibold))
                .tracking(1.0)
                .foregroundColor(.etherTextTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(String(format: "%.1f", value.isFinite ? value : -70))
                    .font(.etherValue(highlight ? EtherType.xxl : EtherType.xl))
                    .monospacedDigit()
                    .foregroundColor(highlight ? .etherAccent : .etherTextPrimary)
                Text(unit)
                    .font(.etherMono(9))
                    .foregroundColor(.etherTextTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Dehiss

    private var dehissSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                EtherSectionHeader(text: "Dehiss")
                tierBadge("SIMPLE")
                Spacer()
                Toggle("", isOn: $denoise.enabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }

            Text("Shelf + downward expander above the pivot. Ducks hiss when the high band goes quiet; leaves cymbals, sibilance, and air intact above the threshold.")
                .font(.etherMono(9))
                .foregroundColor(.etherTextTertiary)
                .fixedSize(horizontal: false, vertical: true)

            dehissSlider(label: "Pivot",     value: $denoise.pivotHz,     range: 3000...10000, unit: "Hz", format: "%.0f")
            dehissSlider(label: "Threshold", value: $denoise.thresholdDB, range: -80...(-30),  unit: "dB", format: "%.1f")
            dehissSlider(label: "Reduction", value: $denoise.reductionDB, range: 0...18,       unit: "dB", format: "%.1f")
            dehissSlider(label: "Shelf Cut", value: $denoise.shelfCutDB,  range: 0...6,        unit: "dB", format: "%.1f")

            HStack {
                Spacer()
                Button("Reset") { denoise.reset() }
                    .buttonStyle(.plain)
                    .font(.etherMono(10))
                    .foregroundColor(.etherTextSecondary)
            }
        }
        .etherPanel()
        .opacity(denoise.enabled ? 1.0 : 0.72)
    }

    private func dehissSlider(label: String, value: Binding<Float>, range: ClosedRange<Float>, unit: String, format: String) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.etherMono(10, weight: .semibold))
                .tracking(0.8)
                .foregroundColor(.etherTextTertiary)
                .frame(width: 80, alignment: .leading)

            EtherSlider(value: value, range: range, disabled: !denoise.enabled)

            Text("\(String(format: format, value.wrappedValue)) \(unit)")
                .font(.etherMono(10))
                .foregroundColor(.etherTextPrimary)
                .monospacedDigit()
                .frame(width: 72, alignment: .trailing)
        }
    }

    private func tierBadge(_ text: String) -> some View {
        Text(text)
            .font(.etherMono(8, weight: .bold))
            .tracking(1.2)
            .foregroundColor(.etherAccent)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.etherAccent.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(Color.etherAccent.opacity(0.35), lineWidth: 1)
                    )
            )
    }

    // MARK: - Visual latency compensation

    private var visualOffsetSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                EtherSectionHeader(text: "Visual Sync")
                Spacer()
                Button("Reset") {
                    engine.visualSyncSec = 0
                }
                .buttonStyle(.plain)
                .font(.etherMono(10))
                .foregroundColor(.etherTextSecondary)
            }

            Text("Adds a tiny delay to audio output so visuals appear in sync. Increase if the spectrum lags behind what you hear.")
                .font(.etherMono(9))
                .foregroundColor(.etherTextTertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Text("Audio Delay")
                    .font(.etherMono(10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundColor(.etherTextTertiary)
                    .frame(width: 80, alignment: .leading)

                EtherSlider(
                    value: Binding(
                        get: { engine.visualSyncSec * 1000 },
                        set: { engine.visualSyncSec = $0 / 1000 }
                    ),
                    range: 0...500
                )

                Text("\(Int(engine.visualSyncSec * 1000)) ms")
                    .font(.etherMono(10))
                    .foregroundColor(.etherTextPrimary)
                    .monospacedDigit()
                    .frame(width: 52, alignment: .trailing)
            }
        }
        .etherPanel()
    }

    // MARK: - Transport / device info

    private var transportSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            EtherSectionHeader(text: "Output Device")

            if let device = engine.selectedOutputDevice {
                infoRow("Device",    value: device.name)
                infoRow("Transport", value: AudioDeviceManager.transportTypeLabel(for: device.id))
                infoRow("Format",    value: AudioDeviceManager.formatDescription(for: device.id))
                infoRow("UID",       value: device.uid, mono: true)
            } else {
                Text("No output device selected")
                    .font(.etherMono(11))
                    .foregroundColor(.etherTextTertiary)
            }
        }
        .etherPanel()
    }

    private func infoRow(_ label: String, value: String, mono: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.etherMono(10, weight: .semibold))
                .tracking(0.8)
                .foregroundColor(.etherTextTertiary)
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(mono ? .etherMono(10) : .system(size: 11))
                .foregroundColor(.etherTextPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
    }

    // MARK: - Stereo utilities

    private var stereoUtilsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            EtherSectionHeader(text: "Stereo Utilities")

            HStack(spacing: 20) {
                Toggle(isOn: $spatial.invertLeft) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Invert Left")
                            .font(.etherMono(11))
                        Text("Polarity flip on L channel")
                            .font(.etherMono(9))
                            .foregroundColor(.etherTextTertiary)
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)

                Toggle(isOn: $spatial.invertRight) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Invert Right")
                            .font(.etherMono(11))
                        Text("Polarity flip on R channel")
                            .font(.etherMono(9))
                            .foregroundColor(.etherTextTertiary)
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            Toggle(isOn: $spatial.sumToMono) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mono Check")
                        .font(.etherMono(11))
                    Text("Sum L+R to mono — verify mix compatibility")
                        .font(.etherMono(9))
                        .foregroundColor(.etherTextTertiary)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .etherPanel()
    }

    // MARK: - Global hotkeys

    private var hotkeysSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            EtherSectionHeader(text: "Global Hotkeys")
            Text("Shortcuts that work even when Ether isn't focused.")
                .font(.etherMono(9))
                .foregroundColor(.etherTextTertiary)

            hotkeyRow(
                enabled: $hotkeys.bypassEnabled,
                label: "Bypass EQ",
                keys: "⌘ ⌥ B"
            )

            hotkeyRow(
                enabled: $hotkeys.abToggleEnabled,
                label: "Toggle A/B Profile",
                keys: "⌘ ⌥ X"
            )
        }
        .etherPanel()
    }

    private func hotkeyRow(enabled: Binding<Bool>, label: String, keys: String) -> some View {
        HStack {
            Toggle("", isOn: enabled)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .onChange(of: enabled.wrappedValue) { _, _ in hotkeys.refresh() }

            Text(label)
                .font(.etherMono(11))
                .foregroundColor(.etherTextPrimary)

            Spacer()

            Text(keys)
                .font(.etherMono(10, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.etherSurfaceHigh)
                )
                .foregroundColor(.etherAccent)
        }
    }

    // MARK: - Footer

    private var aboutFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("COMING SOON")
                .font(.etherMono(8, weight: .semibold))
                .tracking(1.2)
                .foregroundColor(.etherTextTertiary)
            Text("Per-app audio profiles · Auto profile switching · Linear-phase EQ")
                .font(.etherMono(10))
                .foregroundColor(.etherTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.etherSurfaceHigh.opacity(0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Color.white.opacity(0.03), lineWidth: 1)
                )
        )
    }
}
