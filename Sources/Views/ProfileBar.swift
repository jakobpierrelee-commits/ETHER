import SwiftUI

struct ProfileBar: View {
    @ObservedObject var store: ProfileStore
    @ObservedObject var eqController: EQController

    @State private var showingSaveSheet = false
    @State private var newProfileName = ""
    @State private var renamingProfile: EQProfile?
    @State private var renameText = ""

    var body: some View {
        HStack(spacing: 10) {
            // Profile picker
            Menu {
                if store.profiles.isEmpty {
                    Text("No profiles saved")
                } else {
                    ForEach(store.profiles) { profile in
                        Button(action: { load(profile) }) {
                            HStack {
                                Text(profile.name)
                                if profile.id == store.currentProfileID {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                    Divider()
                    if let current = currentProfile {
                        Button("Rename '\(current.name)'") {
                            renamingProfile = current
                            renameText = current.name
                        }
                        Button("Delete '\(current.name)'", role: .destructive) {
                            store.delete(current)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                    Text(currentProfile?.name ?? "No profile")
                        .font(.etherMono(EtherType.medium))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(hex: 0x1C1C1C))
                .cornerRadius(4)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer()

            // Save as new
            Button(action: {
                newProfileName = suggestedName()
                showingSaveSheet = true
            }) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .foregroundColor(.etherTextSecondary)
            .help("Save current EQ as a new profile")

            Button(action: {
                store.overwriteCurrent(
                    bands: eqController.bands,
                    masterGain: eqController.masterGain,
                    knobValues: eqController.currentKnobValues
                )
            }) {
                Text("Save")
                    .lineLimit(1)
                    .fixedSize()
            }
            .buttonStyle(.ether(color: store.currentProfileID == nil ? .etherTextTertiary : .etherAccent))
            .disabled(store.currentProfileID == nil)
            .fixedSize()
            .help("Save current EQ to \"\(currentProfile?.name ?? "selected profile")\"")
        }
        .sheet(isPresented: $showingSaveSheet) {
            saveSheet
        }
        .sheet(item: $renamingProfile) { profile in
            renameSheet(for: profile)
        }
    }

    // MARK: - Save Sheet

    private var saveSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SAVE PROFILE")
                .font(.etherMono(EtherType.medium, weight: .bold))
                .foregroundColor(Color(hex: 0x00E5FF))

            TextField("Profile name", text: $newProfileName)
                .textFieldStyle(.roundedBorder)
                .font(.etherMono(EtherType.title))

            HStack {
                Button("Cancel") { showingSaveSheet = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    let trimmed = newProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        store.saveNew(
                            name: trimmed,
                            bands: eqController.bands,
                            masterGain: eqController.masterGain,
                            knobValues: eqController.currentKnobValues
                        )
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

    // MARK: - Rename Sheet

    private func renameSheet(for profile: EQProfile) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("RENAME PROFILE")
                .font(.etherMono(EtherType.medium, weight: .bold))
                .foregroundColor(Color(hex: 0x00E5FF))

            TextField("Profile name", text: $renameText)
                .textFieldStyle(.roundedBorder)
                .font(.etherMono(EtherType.title))

            HStack {
                Button("Cancel") { renamingProfile = nil }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Rename") {
                    let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        store.rename(profile, to: trimmed)
                    }
                    renamingProfile = nil
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 320)
    }

    // MARK: - Helpers

    private var currentProfile: EQProfile? {
        store.profiles.first(where: { $0.id == store.currentProfileID })
    }

    private func load(_ profile: EQProfile) {
        store.setCurrent(profile)
        eqController.load(bands: profile.eqBands, masterGain: profile.masterGain, knobValues: profile.knobValues ?? [:])
    }

    private func suggestedName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, HH:mm"
        return "Preset \(formatter.string(from: Date()))"
    }
}
