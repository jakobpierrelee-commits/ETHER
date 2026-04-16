import SwiftUI
import AppKit

struct MenuBarContent: View {
    @EnvironmentObject var engine: EngineManager
    @ObservedObject var controller: EQController
    @ObservedObject var profileStore: ProfileStore
    @ObservedObject private var theme = ThemeManager.shared

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            EtherDivider()

            startStopRow
            bypassRow

            EtherDivider()

            profileSection
            abSection

            EtherDivider()

            knobsSection
            gainSection

            EtherDivider()

            footer
        }
        .padding(12)
        .frame(width: 280)
        .background(
            ZStack {
                Color.etherBackground
                NoiseTexture(opacity: 0.02)
            }
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Rectangle()
                .fill(Color.etherAccent.opacity(0.5))
                .frame(width: 2, height: 10)
            Text("ETHER")
                .font(.etherVariant(EtherType.body))
                .tracking(2.0)
                .foregroundColor(.etherAccent)
            Spacer()
            Circle().fill(statusColor).frame(width: 5, height: 5)
            Text(engine.status.label)
                .font(.etherMono(EtherType.micro))
                .foregroundColor(.etherTextSecondary)
        }
    }

    // MARK: - Transport

    private var startStopRow: some View {
        let running = engine.status.isRunning
        let color: Color = running ? .etherClip : .etherAccent
        return Button {
            if running { engine.stop() } else { engine.start() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: running ? "stop.fill" : "play.fill")
                    .font(.system(size: 9))
                Text(running ? "Stop" : "Start")
                    .font(.etherMono(EtherType.small, weight: .semibold))
                Spacer()
            }
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(color.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(color.opacity(0.25), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(engine.status == .starting || engine.status == .driverNotInstalled)
    }

    private var bypassRow: some View {
        HStack {
            Text("Bypass")
                .font(.etherMono(EtherType.small))
                .foregroundColor(.etherTextSecondary)
            Spacer()
            Toggle("", isOn: Binding(
                get: { controller.bypassed },
                set: { _ in controller.toggleGlobalBypass() }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
        }
    }

    // MARK: - Profile

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            EtherSectionHeader(text: "Profile")

            Menu {
                if profileStore.profiles.isEmpty {
                    Text("No presets")
                } else {
                    ForEach(profileStore.profiles) { profile in
                        Button(profile.name) {
                            profileStore.setCurrent(profile)
                            controller.load(bands: profile.eqBands, masterGain: profile.masterGain, knobValues: profile.knobValues ?? [:])
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(currentProfileName)
                        .font(.etherMono(EtherType.small))
                        .foregroundColor(.etherTextPrimary)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7))
                        .foregroundColor(.etherTextTertiary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.etherSurfaceHigh)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                        )
                )
            }
            .menuStyle(.borderlessButton)
        }
    }

    // MARK: - A/B

    private var abSection: some View {
        HStack(spacing: 6) {
            EtherSectionHeader(text: "A/B")

            slotPill(.a)

            Button { toggleAB() } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.etherAccent)
                    .frame(width: 20, height: 18)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.etherAccent.opacity(0.1))
                    )
            }
            .buttonStyle(.plain)

            slotPill(.b)
        }
    }

    @State private var activeABSlot: ABSlot?

    private func slotPill(_ slot: ABSlot) -> some View {
        let profile = profileStore.profile(for: slot)
        let label = slot == .a ? "A" : "B"
        let isActive = activeABSlot == slot

        return Menu {
            Button("Set to Current EQ") {
                let name = "Slot \(label) · \(timestamp())"
                profileStore.saveNew(name: name, bands: controller.bands, masterGain: controller.masterGain, knobValues: controller.currentKnobValues)
                if let new = profileStore.profiles.first(where: { $0.name == name }) {
                    profileStore.assignToSlot(new, slot: slot)
                }
            }
            if !profileStore.profiles.isEmpty { Divider() }
            ForEach(profileStore.profiles) { p in
                Button(p.name) { profileStore.assignToSlot(p, slot: slot) }
            }
            if profile != nil {
                Divider()
                Button("Clear") { profileStore.assignToSlot(nil, slot: slot) }
            }
        } label: {
            HStack(spacing: 3) {
                Text(label)
                    .font(.etherMono(EtherType.micro, weight: .bold))
                Text(profile?.name ?? "—")
                    .font(.etherMono(EtherType.micro))
                    .foregroundColor(profile == nil ? .etherTextTertiary : .etherTextSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(isActive ? Color.etherAccent.opacity(0.12) : Color.etherSurfaceHigh)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(isActive ? Color.etherAccent.opacity(0.3) : Color.white.opacity(0.04), lineWidth: 1)
                    )
            )
        }
        .menuStyle(.borderlessButton)
    }

    // MARK: - Knobs

    private var knobsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            EtherSectionHeader(text: "Character")
            HStack(spacing: 2) {
                ForEach(MacroKnob.all) { knob in
                    VStack(spacing: 3) {
                        Text(knob.name)
                            .font(.etherMono(7, weight: .semibold))
                            .tracking(0.5)
                            .foregroundColor(.etherTextTertiary)
                        MiniKnob(
                            value: Binding(
                                get: { controller.macroKnobValue(id: knob.id) },
                                set: { controller.setMacroKnob(id: knob.id, value: $0) }
                            ),
                            accentColor: EQController.themeColor(for: knob.bandIndices.last ?? 0)
                        )
                        Text(String(format: "%+.0f", controller.macroKnobValue(id: knob.id)))
                            .font(.etherMono(EtherType.micro, weight: .medium))
                            .monospacedDigit()
                            .foregroundColor(.gainTint(for: controller.macroKnobValue(id: knob.id)))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: - Gain

    private var gainSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                EtherSectionHeader(text: "Output")
                Spacer()
                Text(EtherFormat.gain(controller.masterGain))
                    .font(.etherMono(EtherType.tiny, weight: .medium))
                    .monospacedDigit()
                    .foregroundColor(.gainTint(for: controller.masterGain))
            }
            EtherGainSlider(
                value: Binding(
                    get: { controller.masterGain },
                    set: { controller.setMasterGain($0) }
                ),
                range: -12...12
            )
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "macwindow")
                        .font(.system(size: 9))
                    Text("Open")
                        .font(.etherMono(EtherType.tiny))
                }
                .foregroundColor(.etherTextSecondary)
            }
            .buttonStyle(.plain)

            Button {
                MiniPlayerPanel.shared.show(controller: controller, profileStore: profileStore, engine: engine)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "pip")
                        .font(.system(size: 9))
                    Text("Mini")
                        .font(.etherMono(EtherType.tiny))
                }
                .foregroundColor(.etherTextSecondary)
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                NSApp.terminate(nil)
            } label: {
                Text("Quit")
                    .font(.etherMono(EtherType.tiny))
                    .foregroundColor(.etherTextTertiary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private func toggleAB() {
        let next: ABSlot = (activeABSlot == .a) ? .b : .a
        if let profile = profileStore.profile(for: next) {
            controller.load(bands: profile.eqBands, masterGain: profile.masterGain, knobValues: profile.knobValues ?? [:])
            activeABSlot = next
        }
    }

    private func timestamp() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        return fmt.string(from: Date())
    }

    private var currentProfileName: String {
        if let id = profileStore.currentProfileID,
           let profile = profileStore.profiles.first(where: { $0.id == id }) {
            return profile.name
        }
        return "No preset"
    }

    private var statusColor: Color {
        switch engine.status {
        case .running:              return .etherPositive
        case .error, .driverNotInstalled: return .etherClip
        case .starting:             return .etherWarning
        case .stopped:              return .etherTextTertiary
        }
    }
}

// MARK: - Compact MiniKnob for menu bar

struct MiniKnob: View {
    @Binding var value: Float
    var range: ClosedRange<Float> = -12...12
    var accentColor: Color = .white

    private let size: CGFloat = 28
    @State private var dragStart: Float?
    @State private var isHovered = false
    @State private var scrollMonitor: Any?

    var body: some View {
        ZStack {
            // Track
            Circle()
                .trim(from: 0.12, to: 0.88)
                .stroke(Color.white.opacity(0.08), style: StrokeStyle(lineWidth: 1.5, lineCap: .butt))
                .rotationEffect(.degrees(90))
                .frame(width: size, height: size)

            // Value arc
            Circle()
                .trim(from: trimStart, to: trimEnd)
                .stroke(accentColor.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, lineCap: .butt))
                .rotationEffect(.degrees(90))
                .frame(width: size, height: size)
                .animation(.spring(response: 0.35, dampingFraction: 0.82), value: value)

            // Flat body
            Circle()
                .fill(Color(white: 0.08))
                .frame(width: size - 5, height: size - 5)
                .overlay(
                    Circle().strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
                )

            // Indicator
            Rectangle()
                .fill(Color.white)
                .frame(width: 1, height: 6)
                .offset(y: -(size - 12) / 2)
                .rotationEffect(.degrees(Double(indicatorAngle)))
                .animation(.spring(response: 0.35, dampingFraction: 0.82), value: value)

            Circle()
                .fill(Color.white.opacity(0.15))
                .frame(width: 2, height: 2)
        }
        .compositingGroup()
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.resizeUpDown.push()
                installScrollMonitor()
            } else {
                NSCursor.pop()
                removeScrollMonitor()
            }
        }
        .onTapGesture(count: 2) { value = 0 }
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { g in
                    if dragStart == nil { dragStart = value }
                    let fine = NSEvent.modifierFlags.contains(.command) || NSEvent.modifierFlags.contains(.option)
                    let scale: Float = fine ? 0.08 : 0.3
                    let delta = -Float(g.translation.height) * scale
                    value = max(range.lowerBound, min(range.upperBound, (dragStart ?? value) + delta))
                }
                .onEnded { _ in dragStart = nil }
        )
    }

    private var normalized: Float {
        let mid = (range.lowerBound + range.upperBound) / 2
        let spread = (range.upperBound - range.lowerBound) / 2
        return (value - mid) / spread
    }
    private var indicatorAngle: Float { normalized * 135 }
    private var trimStart: CGFloat {
        value >= 0 ? 0.5 : CGFloat(0.5 + Double(normalized) * 0.375)
    }
    private var trimEnd: CGFloat {
        value >= 0 ? CGFloat(0.5 + Double(normalized) * 0.375) : 0.5
    }

    private func installScrollMonitor() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            Task { @MainActor in
                guard isHovered else { return }
                let fine = event.modifierFlags.contains(.shift)
                let delta = Float(event.deltaY) * (fine ? 0.05 : 0.3)
                value = max(range.lowerBound, min(range.upperBound, value + delta))
            }
            return event
        }
    }
    private func removeScrollMonitor() {
        if let m = scrollMonitor {
            NSEvent.removeMonitor(m)
            scrollMonitor = nil
        }
    }
}
