import SwiftUI

struct ContentView: View {
    @EnvironmentObject var engine: EngineManager
    @ObservedObject var eqController: EQController
    @ObservedObject var profileStore: ProfileStore
    @ObservedObject private var theme = ThemeManager.shared
    @Environment(\.openWindow) private var openWindow
    @State private var availableOutputs: [AudioDevice] = []
    @State private var showShortcuts = false
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: "audio.ether.hasSeenOnboarding")
    @State private var showThemePicker = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.25)

            HStack(spacing: 0) {
                // Left sidebar — presets
                presetSidebar
                    .frame(width: 150)

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.0), .white.opacity(0.06), .white.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 1)

                // Main content
                VStack(spacing: 0) {
                    if !engine.driverInstalled {
                        driverWarning
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                    }
                    deviceRouting
                        .padding(.horizontal, 20)
                        .padding(.top, 12)

                    Spacer().frame(height: 10)

                    // EQ hero zone — no panel, ambient glow behind
                    ZStack {
                        // Ambient accent glow behind graph
                        RadialGradient(
                            colors: [Color.etherAccent.opacity(0.035), .clear],
                            center: .center,
                            startRadius: 20,
                            endRadius: 340
                        )
                        .frame(height: 360)
                        .allowsHitTesting(false)

                        HStack(alignment: .top, spacing: 10) {
                            EQBandsView(controller: eqController)
                                .frame(maxWidth: .infinity)
                            PeakMeterSide(analyzer: engine.postSpectrum)
                                .frame(width: 36, height: 320)
                                .padding(.top, 24)
                        }
                    }
                    .padding(.horizontal, 20)

                    BandDetailStrip(controller: eqController)
                        .padding(.horizontal, 20)

                    Spacer().frame(height: 20)

                    // Controls zone — knobs + spatial
                    MacroKnobsView(controller: eqController)
                        .padding(.horizontal, 20)

                    Spacer().frame(height: 10)

                    SpatialView(spatial: engine.spatial)
                        .padding(.horizontal, 20)

                    Spacer().frame(height: 18)

                    // Output zone
                    MasterGainStrip(controller: eqController)
                        .padding(.horizontal, 20)

                    Spacer().frame(height: 10)

                    HStack(spacing: 12) {
                        ABSlotsBar(store: profileStore, eqController: eqController)
                            .frame(maxWidth: .infinity)
                        transportButton
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 14)
                }
                .padding(.vertical, 0)
            }
        }
        .background(Color.etherBackground)
        .frame(minWidth: 920)
        .fixedSize(horizontal: false, vertical: true)
        .ignoresSafeArea(.all)
        .onAppear {
            refreshDevices()
            // Force the NSWindow background to match, killing any grey bar
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                for window in NSApp.windows where window.identifier?.rawValue == "main" || window.title == "Ether" {
                    window.backgroundColor = NSColor(Color.etherBackground)
                    window.isOpaque = false
                    window.titlebarAppearsTransparent = true
                    window.styleMask.insert(.fullSizeContentView)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showShortcuts)) { _ in
            showShortcuts.toggle()
        }
        .overlay {
            if showShortcuts {
                ShortcutCheatsheet(isPresented: $showShortcuts)
            }
        }
        .overlay {
            if showOnboarding {
                OnboardingCard(isPresented: $showOnboarding)
            }
        }
        .animation(.easeOut(duration: 0.18), value: showShortcuts)
        .animation(.easeOut(duration: 0.22), value: showOnboarding)
        .background(
            // Invisible button for the `?` shortcut
            Button("") { showShortcuts.toggle() }
                .keyboardShortcut("?", modifiers: [.shift])
                .hidden()
        )
    }

    // MARK: - Preset Sidebar

    @State private var showingSaveSheet = false
    @State private var newProfileName = ""
    @State private var hoveredProfileID: UUID?
    @State private var confirmOverwriteID: UUID?

    private var presetSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Brand
            HStack(spacing: 0) {
                Spacer()
                ZStack {
                    Text("ETHER")
                        .font(.etherVariant(EtherType.medium))
                        .tracking(3.0)
                        .foregroundColor(.etherAccent.opacity(0.35))
                        .blur(radius: 6)
                    Text("ETHER")
                        .font(.etherVariant(EtherType.medium))
                        .tracking(3.0)
                        .foregroundColor(.etherAccent)
                }
                Spacer()
            }
            .padding(.vertical, 8)

            Rectangle()
                .fill(Color.white.opacity(0.04))
                .frame(height: 1)

            HStack {
                Text("PRESETS")
                    .font(.etherMono(EtherType.micro, weight: .semibold))
                    .tracking(2.0)
                    .foregroundColor(.etherTextTertiary)
                Spacer()
                Button {
                    newProfileName = "Preset \(profileStore.profiles.count + 1)"
                    showingSaveSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10))
                        .foregroundColor(.etherTextSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Rectangle()
                .fill(Color.white.opacity(0.04))
                .frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(profileStore.profiles) { profile in
                        presetRow(profile)
                    }
                }
            }

            Spacer()
        }
        .background(Color(hex: 0x060606))
        .sheet(isPresented: $showingSaveSheet) {
            VStack(alignment: .leading, spacing: 16) {
                Text("SAVE PRESET")
                    .font(.etherMono(EtherType.medium, weight: .bold))
                    .foregroundColor(.etherAccent)
                TextField("Preset name", text: $newProfileName)
                    .textFieldStyle(.roundedBorder)
                    .font(.etherMono(EtherType.title))
                HStack {
                    Button("Cancel") { showingSaveSheet = false }
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Save") {
                        let trimmed = newProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            profileStore.saveNew(name: trimmed, bands: eqController.bands, masterGain: eqController.masterGain, knobValues: eqController.currentKnobValues)
                        }
                        showingSaveSheet = false
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
            .frame(width: 320)
        }
    }

    private func presetRow(_ profile: EQProfile) -> some View {
        let isCurrent = profile.id == profileStore.currentProfileID
        let isHovered = hoveredProfileID == profile.id
        let isConfirming = confirmOverwriteID == profile.id

        return HStack(spacing: 6) {
            Rectangle()
                .fill(isCurrent ? Color.etherAccent : Color.clear)
                .frame(width: 2, height: 14)

            if isConfirming {
                Text("Overwrite?")
                    .font(.etherMono(EtherType.micro, weight: .bold))
                    .foregroundColor(.etherWarning)
                    .lineLimit(1)
                    .onTapGesture {
                        profileStore.overwriteProfile(profile, bands: eqController.bands, masterGain: eqController.masterGain, knobValues: eqController.currentKnobValues)
                        confirmOverwriteID = nil
                    }
            } else {
                Text(profile.name)
                    .font(.etherMono(EtherType.tiny))
                    .foregroundColor(isCurrent ? .etherTextPrimary : .etherTextSecondary)
                    .lineLimit(1)
                    .onTapGesture {
                        profileStore.setCurrent(profile)
                        eqController.load(bands: profile.eqBands, masterGain: profile.masterGain, knobValues: profile.knobValues ?? [:])
                    }
            }

            Spacer()

            if isCurrent && !isConfirming {
                Text("Save")
                    .font(.etherMono(7, weight: .medium))
                    .foregroundColor(.etherAccent)
                    .onTapGesture {
                        profileStore.overwriteCurrent(bands: eqController.bands, masterGain: eqController.masterGain, knobValues: eqController.currentKnobValues)
                    }
            } else if isHovered && !isCurrent && !isConfirming {
                Text("Overwrite")
                    .font(.etherMono(7, weight: .medium))
                    .foregroundColor(.etherTextTertiary)
                    .onTapGesture {
                        confirmOverwriteID = profile.id
                    }
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
        .background(isCurrent ? Color.white.opacity(0.04) : (isConfirming ? Color.etherWarning.opacity(0.06) : Color.clear))
        .contentShape(Rectangle())
        .onHover { h in
            hoveredProfileID = h ? profile.id : nil
            if !h && confirmOverwriteID == profile.id {
                confirmOverwriteID = nil
            }
        }
        .contextMenu {
            Button("Delete", role: .destructive) {
                profileStore.delete(profile)
            }
        }
    }

    private var themePopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text("THEME")
                    .font(.etherMono(EtherType.micro, weight: .semibold))
                    .tracking(2.0)
                    .foregroundColor(.etherTextTertiary)
                HStack(spacing: 6) {
                    ForEach(ColorThemeID.allCases) { tid in
                        themeChip(tid)
                    }
                }
            }

            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 6) {
                Text("EQ CURVE")
                    .font(.etherMono(EtherType.micro, weight: .semibold))
                    .tracking(2.0)
                    .foregroundColor(.etherTextTertiary)
                HStack(spacing: 6) {
                    ForEach(CurveColorMode.allCases) { mode in
                        curveChip(mode)
                    }
                }
            }
        }
        .padding(14)
        .background(Color.etherBackground)
    }

    private func curveChip(_ mode: CurveColorMode) -> some View {
        let colors = mode.colors ?? theme.current.bandColors
        let isSelected = theme.curveColorMode == mode
        return Button {
            theme.curveColorMode = mode
        } label: {
            HStack(spacing: 0) {
                ForEach(0..<5, id: \.self) { i in
                    Rectangle()
                        .fill(colors[i * 2])
                        .frame(width: 3, height: 6)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 1))
            .overlay(
                RoundedRectangle(cornerRadius: 1)
                    .strokeBorder(isSelected ? Color.white : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(mode.rawValue)
    }

    private func themeChip(_ id: ColorThemeID) -> some View {
        let t = ColorTheme.theme(for: id)
        let isSelected = theme.currentID == id
        return Button {
            theme.currentID = id
        } label: {
            HStack(spacing: 0) {
                ForEach(0..<5, id: \.self) { i in
                    Rectangle()
                        .fill(t.bandColors[i * 2])
                        .frame(width: 3, height: 8)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 1))
            .overlay(
                RoundedRectangle(cornerRadius: 1)
                    .strokeBorder(isSelected ? Color.white : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(id.rawValue)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Spacer().frame(width: 58)

            Spacer()

            HStack(spacing: 6) {
                Circle().fill(statusColor).frame(width: 6, height: 6)
                Text(engine.status.label)
                    .font(.etherMono(10))
                    .foregroundColor(.etherTextSecondary)
            }

            Text("·").foregroundColor(.etherTextTertiary)

            Text("48 kHz · 512 · 10.7 ms")
                .font(.etherValue(9))
                .foregroundColor(.etherTextTertiary)
                .monospacedDigit()

            // Utility icons grouped in a pill
            HStack(spacing: 10) {
                Button {
                    MiniPlayerPanel.shared.show(controller: eqController, profileStore: profileStore, engine: engine)
                } label: {
                    Image(systemName: "pip")
                        .font(.system(size: 11))
                        .foregroundColor(.etherTextSecondary)
                }
                .buttonStyle(.plain)
                .help("Mini Player")

                Button {
                    WideMiniPlayerPanel.shared.show(controller: eqController, engine: engine)
                } label: {
                    Image(systemName: "rectangle.split.3x1")
                        .font(.system(size: 11))
                        .foregroundColor(.etherTextSecondary)
                }
                .buttonStyle(.plain)
                .help("Wide Player")

                Button {
                    openWindow(id: "visualizer")
                } label: {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 11))
                        .foregroundColor(.etherTextSecondary)
                }
                .buttonStyle(.plain)
                .help("Visualizer")

                Button {
                    openWindow(id: "advanced")
                } label: {
                    Image(systemName: "waveform.badge.magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundColor(.etherTextSecondary)
                }
                .buttonStyle(.plain)
                .help("Advanced Audio")

                SettingsLink {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11))
                        .foregroundColor(.etherTextSecondary)
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.04))
            )

            Spacer().frame(width: 14)
        }
        .frame(height: 40)
        .padding(.top, 4)
        .contentShape(Rectangle())
        .background(WindowDragHandle())
    }

    // MARK: - Driver Warning

    private var driverWarning: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.etherWarning)
            VStack(alignment: .leading, spacing: 2) {
                Text("Ether driver not installed")
                    .font(.etherMono(11, weight: .semibold))
                    .foregroundColor(.etherWarning)
                Text("Run install-driver.sh from the project root")
                    .font(.etherMono(10))
                    .foregroundColor(.etherTextSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.etherWarning.opacity(0.08))
                .shadow(color: Color.etherWarning.opacity(0.15), radius: 8, y: 0)
        )
    }

    // MARK: - Device Routing

    private var deviceRouting: some View {
        VStack(alignment: .leading, spacing: 6) {
            EtherSectionHeader(text: "Routing")

            HStack(spacing: 12) {
                routingLine(
                    icon: "waveform.circle.fill",
                    label: "Source",
                    value: engine.inputDeviceName
                )

                Image(systemName: "arrow.right")
                    .font(.system(size: 10))
                    .foregroundColor(.etherTextTertiary)

                HStack(spacing: 6) {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundColor(.etherAccent)
                    Text("Output")
                        .font(.etherMono(10, weight: .semibold))
                        .foregroundColor(.etherTextTertiary)
                    EtherDropdown(
                        options: availableOutputs.map(\.name),
                        selection: engine.selectedOutputDevice?.name,
                        onSelect: { name in
                            if let device = availableOutputs.first(where: { $0.name == name }) {
                                engine.selectedOutputDevice = device
                                engine.hotSwapOutputDevice(device)
                                UserDefaults.standard.set(device.uid, forKey: "audio.ether.lastOutputUID")
                            }
                        }
                    ) {
                        Text(engine.selectedOutputDevice?.name ?? "Select output…")
                            .font(.etherMono(EtherType.body))
                            .foregroundColor(engine.selectedOutputDevice != nil ? .etherTextPrimary : .etherTextTertiary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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

    private func routingLine(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundColor(.etherAccent)
            Text(label)
                .font(.etherMono(10, weight: .semibold))
                .foregroundColor(.etherTextTertiary)
            Text(value)
                .font(.etherMono(11))
                .foregroundColor(.etherTextSecondary)
                .lineLimit(1)
        }
    }

    // MARK: - Transport

    private var transportButton: some View {
        let running = engine.status.isRunning
        let color: Color = running ? .etherClip : .etherAccent
        return Button(action: {
            if running { engine.stop() } else { engine.start() }
        }) {
            HStack(spacing: 6) {
                Image(systemName: running ? "stop.fill" : "play.fill")
                    .font(.system(size: 10))
                Text(running ? "Stop" : "Start")
                    .font(.etherMono(11, weight: .semibold))
            }
            .foregroundColor(color)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(color.opacity(0.12))
                    .shadow(color: color.opacity(0.2), radius: 6, y: 0)
            )
        }
        .buttonStyle(.plain)
        .disabled(engine.status == .starting || engine.status == .driverNotInstalled)
        .keyboardShortcut(.space, modifiers: [])
        .fixedSize()
    }

    // MARK: - Helpers

    private var statusColor: Color {
        switch engine.status {
        case .running:              return .etherPositive
        case .error, .driverNotInstalled: return .etherClip
        case .starting:             return .etherWarning
        case .stopped:              return .etherTextTertiary
        }
    }

    private func refreshDevices() {
        availableOutputs = AudioDeviceManager.outputDevices().filter { !$0.name.contains("Ether") }
        // Restore previously selected output device by UID
        if engine.selectedOutputDevice == nil {
            let savedUID = UserDefaults.standard.string(forKey: "audio.ether.lastOutputUID")
            if let uid = savedUID,
               let match = availableOutputs.first(where: { $0.uid == uid }) {
                engine.selectedOutputDevice = match
            } else if let first = availableOutputs.first {
                engine.selectedOutputDevice = first
            }
        }
        engine.driverInstalled = DriverCommunicator.isDriverInstalled
    }
}
