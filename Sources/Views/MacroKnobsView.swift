import SwiftUI
import AppKit

// MARK: - Macro Knob Spec

struct MacroKnob: Identifiable {
    let id: String
    let name: String
    let bandIndices: [Int]        // which of the 10 bands this knob writes to
    let bandWeights: [Float]       // relative strength per band (0..1)

    /// Built-in set covering the full spectrum, non-overlapping band ownership.
    static let all: [MacroKnob] = [
        MacroKnob(id: "bass",     name: "BASS",     bandIndices: [0, 1], bandWeights: [1.0, 0.7]),
        MacroKnob(id: "warmth",   name: "WARMTH",   bandIndices: [2, 3], bandWeights: [0.7, 1.0]),
        MacroKnob(id: "clarity",  name: "CLARITY",  bandIndices: [4, 5], bandWeights: [0.7, 1.0]),
        MacroKnob(id: "presence", name: "PRESENCE", bandIndices: [6, 7], bandWeights: [1.0, 0.7]),
        MacroKnob(id: "air",      name: "AIR",      bandIndices: [8, 9], bandWeights: [0.7, 1.0])
    ]
}

// MARK: - Circular Knob Control

struct CircularKnob: View {
    let label: String
    @Binding var value: Float      // -12 ... +12
    var range: ClosedRange<Float> = -12...12
    var accentColor: Color = .white
    var onCommit: () -> Void = {}

    @State private var dragStart: Float?
    @State private var isHovered = false
    @State private var scrollMonitor: Any?

    private let size: CGFloat = 48

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.etherMono(EtherType.micro, weight: .semibold))
                .tracking(1.2)
                .foregroundColor(.etherTextTertiary)

            ZStack {
                // Track ring
                Circle()
                    .trim(from: 0.12, to: 0.88)
                    .stroke(Color.white.opacity(0.08), style: StrokeStyle(lineWidth: 2, lineCap: .butt))
                    .rotationEffect(.degrees(90))
                    .frame(width: size, height: size)

                // Value arc — tick marks style
                Circle()
                    .trim(from: trimStart, to: trimEnd)
                    .stroke(
                        knobColor.opacity(0.9),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .butt)
                    )
                    .rotationEffect(.degrees(90))
                    .frame(width: size, height: size)
                    .animation(.spring(response: 0.35, dampingFraction: 0.82), value: value)

                // Flat dark body — no metallic gradient
                Circle()
                    .fill(Color(white: 0.08))
                    .frame(width: size - 8, height: size - 8)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    )

                // Sharp indicator line
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 1.5, height: 10)
                    .offset(y: -(size - 18) / 2)
                    .rotationEffect(.degrees(Double(indicatorAngle)))
                    .animation(.spring(response: 0.35, dampingFraction: 0.82), value: value)

                // Center dot
                Circle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 3, height: 3)
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
            .onTapGesture(count: 2) {
                value = 0
                onCommit()
            }
            .gesture(
                DragGesture(minimumDistance: 2)  // leave room for taps to fire
                    .onChanged { g in
                        if dragStart == nil { dragStart = value }
                        let fine = NSEvent.modifierFlags.contains(.command) || NSEvent.modifierFlags.contains(.option)
                        let scale: Float = fine ? 0.08 : 0.3
                        let delta = -Float(g.translation.height) * scale
                        let newValue = (dragStart ?? value) + delta
                        value = max(range.lowerBound, min(range.upperBound, newValue))
                    }
                    .onEnded { _ in
                        dragStart = nil
                        onCommit()
                    }
            )

            Text(String(format: "%+.1f", value))
                .font(.etherMono(EtherType.tiny, weight: .medium))
                .monospacedDigit()
                .foregroundColor(.gainTint(for: value))
        }
    }

    // MARK: - Geometry

    private var normalized: Float {
        let mid = (range.lowerBound + range.upperBound) / 2
        let spread = (range.upperBound - range.lowerBound) / 2
        return (value - mid) / spread  // -1..+1
    }

    private var indicatorAngle: Float {
        normalized * 135   // +/- 135 degrees sweep
    }

    private var trimStart: CGFloat {
        value >= 0 ? 0.5 : CGFloat(0.5 + Double(normalized) * 0.375)
    }

    private var trimEnd: CGFloat {
        value >= 0 ? CGFloat(0.5 + Double(normalized) * 0.375) : 0.5
    }

    private var knobColor: Color {
        accentColor
    }

    // MARK: - Scroll monitor

    private func installScrollMonitor() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            Task { @MainActor in
                guard isHovered else { return }
                let fine = event.modifierFlags.contains(.shift)
                let scale: Float = fine ? 0.05 : 0.3
                let delta = Float(event.deltaY) * scale
                let newValue = value + delta
                value = max(range.lowerBound, min(range.upperBound, newValue))
                onCommit()
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

// MARK: - Macro Knobs Panel

struct MacroKnobsView: View {
    @ObservedObject var controller: EQController
    @AppStorage("audio.ether.macroKnobsExpanded") private var expanded: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        expanded.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        EtherSectionHeader(text: "Character")
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(.etherTextTertiary)
                    }
                }
                .buttonStyle(.plain)

                Spacer()
            }

            if expanded {
                HStack(spacing: 0) {
                    ForEach(Array(MacroKnob.all.enumerated()), id: \.element.id) { i, knob in
                        let isHighlighted = controller.highlightedKnobID == knob.id
                        CircularKnob(
                            label: knob.name,
                            value: Binding(
                                get: { controller.macroKnobValue(id: knob.id) },
                                set: { controller.setMacroKnob(id: knob.id, value: $0) }
                            ),
                            accentColor: EQController.themeColor(for: knob.bandIndices.last ?? 0)
                        )
                        .scaleEffect(isHighlighted ? 1.08 : 1.0)
                        .animation(.easeOut(duration: 0.15), value: isHighlighted)
                        .onHover { hovering in
                            if hovering {
                                controller.highlightedBandIndices = Set(knob.bandIndices)
                            } else {
                                controller.highlightedBandIndices = []
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 16)
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
}
