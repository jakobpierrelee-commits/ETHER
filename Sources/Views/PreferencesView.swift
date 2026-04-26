import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject var engine: EngineManager
    @ObservedObject var launchAtLogin: LaunchAtLogin
    @ObservedObject var hotkeys: GlobalHotkeys
    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 2) {
                    Text("SETTINGS")
                        .font(.etherVariant(EtherType.large))
                        .tracking(2.2)
                        .foregroundColor(.etherAccent)
                    Text("Appearance, sync, shortcuts, and startup.")
                        .font(.etherMono(11))
                        .foregroundColor(.etherTextSecondary)
                }

                // ── Appearance ──────────────────────────────────
                appearanceSection

                // ── Visual Sync ─────────────────────────────────
                visualSyncSection

                // ── Hotkeys ─────────────────────────────────────
                hotkeysSection

                // ── Startup ─────────────────────────────────────
                startupSection

                // ── About ───────────────────────────────────────
                aboutSection
            }
            .padding(24)
        }
        .frame(width: 480, height: 560)
        .background(Color.etherBackground)
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            EtherSectionHeader(text: "Appearance")

            // Theme picker
            VStack(alignment: .leading, spacing: 6) {
                Text("Color Theme")
                    .font(.etherMono(10, weight: .semibold))
                    .foregroundColor(.etherTextTertiary)
                HStack(spacing: 8) {
                    ForEach(ColorThemeID.allCases) { id in
                        themeChip(id)
                    }
                }
            }

            // Curve color mode
            VStack(alignment: .leading, spacing: 6) {
                Text("EQ Curve Color")
                    .font(.etherMono(10, weight: .semibold))
                    .foregroundColor(.etherTextTertiary)
                HStack(spacing: 8) {
                    ForEach(CurveColorMode.allCases) { mode in
                        curveChip(mode)
                    }
                }
            }
        }
        .etherPanel()
    }

    private func themeChip(_ id: ColorThemeID) -> some View {
        let theme = ColorTheme.theme(for: id)
        let isSelected = themeManager.currentID == id
        return Button {
            themeManager.currentID = id
        } label: {
            VStack(spacing: 4) {
                HStack(spacing: 1) {
                    ForEach(0..<5, id: \.self) { i in
                        Rectangle()
                            .fill(theme.bandColors[i * 2])
                            .frame(width: 6, height: 12)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 2))
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(isSelected ? theme.accent : Color.clear, lineWidth: 1.5)
                )
                Text(id.rawValue)
                    .font(.etherMono(7, weight: isSelected ? .bold : .regular))
                    .foregroundColor(isSelected ? .etherTextPrimary : .etherTextTertiary)
            }
        }
        .buttonStyle(.plain)
    }

    private func curveChip(_ mode: CurveColorMode) -> some View {
        let colors = mode.colors ?? themeManager.current.bandColors
        let isSelected = themeManager.curveColorMode == mode
        return Button {
            themeManager.curveColorMode = mode
        } label: {
            VStack(spacing: 4) {
                HStack(spacing: 0) {
                    ForEach(0..<5, id: \.self) { i in
                        Rectangle()
                            .fill(colors[i * 2])
                            .frame(width: 4, height: 8)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 1))
                .overlay(
                    RoundedRectangle(cornerRadius: 1)
                        .strokeBorder(isSelected ? Color.white : Color.clear, lineWidth: 1)
                )
                Text(mode.rawValue)
                    .font(.etherMono(7, weight: isSelected ? .bold : .regular))
                    .foregroundColor(isSelected ? .etherTextPrimary : .etherTextTertiary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Visual Sync

    private var visualSyncSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            EtherSectionHeader(text: "Visual Sync")

            Text("Adds a tiny delay to audio output so the spectrum and visualizer appear in sync with what you hear.")
                .font(.etherMono(9))
                .foregroundColor(.etherTextTertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Text("Audio Delay")
                    .font(.etherMono(10, weight: .semibold))
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
                    .font(.etherValue(10))
                    .foregroundColor(.etherTextPrimary)
                    .monospacedDigit()
                    .frame(width: 52, alignment: .trailing)
            }
        }
        .etherPanel()
    }

    // MARK: - Hotkeys

    private var hotkeysSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            EtherSectionHeader(text: "Global Hotkeys")

            Text("Shortcuts that work even when Ether isn't focused.")
                .font(.etherMono(9))
                .foregroundColor(.etherTextTertiary)

            hotkeyRow(enabled: $hotkeys.bypassEnabled, label: "Bypass EQ", keys: "⌘ ⌥ B")
            hotkeyRow(enabled: $hotkeys.abToggleEnabled, label: "Toggle A/B", keys: "⌘ ⌥ X")
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
                .font(.etherValue(10))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.etherSurfaceHigh)
                )
                .foregroundColor(.etherAccent)
        }
    }

    // MARK: - Startup

    private var startupSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            EtherSectionHeader(text: "Startup")

            HStack {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                Spacer()
                Text(launchAtLogin.statusDescription)
                    .font(.etherMono(9))
                    .foregroundColor(.etherTextTertiary)
            }

            if launchAtLogin.statusDescription.contains("approval") {
                Button("Open System Settings → Login Items") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .font(.etherMono(9))
                .buttonStyle(.plain)
                .foregroundColor(.etherAccent)
            }
        }
        .etherPanel()
    }

    // MARK: - About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            EtherSectionHeader(text: "About")
            Text("Ether · System Audio Equalizer")
                .font(.etherMono(10))
                .foregroundColor(.etherTextSecondary)
            Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") · Ether driver · 32-bit float · 48 kHz")
                .font(.etherValue(9))
                .foregroundColor(.etherTextTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .etherPanel()
    }
}
