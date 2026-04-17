import SwiftUI
import AppKit

/// A/B profile slots — assign profiles to slots, toggle between them with X or the button.
struct ABSlotsBar: View {
    @ObservedObject var store: ProfileStore
    @ObservedObject var eqController: EQController

    @State private var activeSlot: ABSlot?

    var body: some View {
        HStack(spacing: 10) {
            EtherSectionHeader(text: "A/B")

            slotButton(.a)
            Button {
                toggle()
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.etherAccent)
                    .frame(width: 24, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.etherAccent.opacity(0.1))
                    )
            }
            .buttonStyle(.plain)
            .help("Toggle between A and B (X)")
            .keyboardShortcut("x", modifiers: [])

            slotButton(.b)

            Spacer()

            Button("Copy A → B") {
                if let profile = store.profile(for: .a) {
                    store.assignToSlot(profile, slot: .b)
                }
            }
            .buttonStyle(.ether(color: .etherTextSecondary))
            .disabled(store.profile(for: .a) == nil)
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.etherSurface)
                .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
        )
        .onReceive(NotificationCenter.default.publisher(for: .toggleABSlots)) { _ in
            toggle()
        }
    }

    private func slotButton(_ slot: ABSlot) -> some View {
        let profile = store.profile(for: slot)
        let isActive = activeSlot == slot
        let label = slot == .a ? "A" : "B"

        return Menu {
            Button("Set to Current EQ") {
                let snapshotName = "Slot \(label) · \(timestamp())"
                store.saveNew(name: snapshotName, bands: eqController.bands, masterGain: eqController.masterGain, knobValues: eqController.currentKnobValues)
                if let new = store.profiles.first(where: { $0.name == snapshotName }) {
                    store.assignToSlot(new, slot: slot)
                }
            }
            Divider()
            ForEach(store.profiles) { p in
                Button(p.name) {
                    store.assignToSlot(p, slot: slot)
                }
            }
            if profile != nil {
                Divider()
                Button("Clear Slot \(label)") {
                    store.assignToSlot(nil, slot: slot)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(label)
                    .font(.etherMono(11, weight: .bold))
                Text("·")
                    .foregroundColor(.etherTextTertiary)
                Text(profile?.name ?? "—")
                    .font(.etherMono(10))
                    .foregroundColor(profile == nil ? .etherTextTertiary : .etherTextSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: 180, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isActive ? Color.etherAccent.opacity(0.15) : Color.etherSurfaceHigh)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(isActive ? Color.etherAccent : .clear, lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func toggle() {
        let target: ABSlot = (activeSlot == .a) ? .b : .a
        if let profile = store.profile(for: target) {
            eqController.load(bands: profile.eqBands, masterGain: profile.masterGain, knobValues: profile.knobValues ?? [:])
            activeSlot = target
        }
    }

    private func timestamp() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        return fmt.string(from: Date())
    }
}
