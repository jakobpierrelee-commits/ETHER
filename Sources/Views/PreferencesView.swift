import SwiftUI

struct PreferencesView: View {
    @ObservedObject var launchAtLogin: LaunchAtLogin

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ETHER")
                    .font(.etherVariant(EtherType.title))
                    .tracking(1.8)
                    .foregroundColor(.etherAccent)
                Text("Preferences")
                    .font(.etherMono(EtherType.body))
                    .foregroundColor(.etherTextSecondary)
            }

            Divider().opacity(0.3)

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
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
                    }
                    .font(.etherMono(9))
                    .buttonStyle(.plain)
                    .foregroundColor(.etherAccent)
                }
            }

            Divider().opacity(0.3)

            VStack(alignment: .leading, spacing: 10) {
                EtherSectionHeader(text: "Color Theme")

                HStack(spacing: 8) {
                    ForEach(ColorThemeID.allCases) { theme in
                        themeChip(theme)
                    }
                }
            }

            Divider().opacity(0.3)

            VStack(alignment: .leading, spacing: 6) {
                EtherSectionHeader(text: "About")
                Text("Ether · System Audio Equalizer")
                    .font(.etherMono(10))
                    .foregroundColor(.etherTextSecondary)
                Text("Routes through BlackHole 2ch · 32-bit float · 48 kHz")
                    .font(.etherMono(9))
                    .foregroundColor(.etherTextTertiary)
            }

            Spacer()
        }
        .padding(24)
        .frame(width: 420, height: 380)
        .background(Color.etherBackground)
    }

    @ObservedObject private var themeManager = ThemeManager.shared

    private func themeChip(_ id: ColorThemeID) -> some View {
        let theme = ColorTheme.theme(for: id)
        let isSelected = themeManager.currentID == id
        return Button {
            themeManager.currentID = id
        } label: {
            VStack(spacing: 4) {
                HStack(spacing: 1) {
                    ForEach(0..<5, id: \.self) { i in
                        let idx = i * 2
                        Rectangle()
                            .fill(theme.bandColors[min(idx, theme.bandColors.count - 1)])
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
}
