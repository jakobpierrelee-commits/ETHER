import SwiftUI

// MARK: - Ethereal Skin (dev spike)
//
// Alternate skin for Ether. Wired to a real EQController so dragging halos
// shapes audio. Open via Skins menu (⌘⇧E) or `openWindow(id: "ethereal")`.
// Lives alongside the existing ContentView — does not replace it.

// MARK: Palette

private enum EtherealPalette {
    static let deep   = Color(.displayP3, red: 0.06, green: 0.05, blue: 0.14)
    static let violet = Color(.displayP3, red: 0.32, green: 0.22, blue: 0.55)
    static let rose   = Color(.displayP3, red: 0.78, green: 0.55, blue: 0.72)
    static let mist   = Color(.displayP3, red: 0.92, green: 0.90, blue: 0.96)
    static let glow   = Color(.displayP3, red: 0.85, green: 0.78, blue: 1.00)

    static let textPrimary   = Color.white.opacity(0.92)
    static let textSecondary = Color.white.opacity(0.55)
    static let textTertiary  = Color.white.opacity(0.30)
}

// MARK: Root

struct EtherealSkinView: View {
    @ObservedObject var controller: EQController
    @State private var activeBandID: UUID?

    /// Bell bands only — lowCut/highCut surface in the disclosure layer (phase 2).
    private var visibleBands: [EQBand] {
        controller.bands.filter { $0.type == .bell }
    }

    var body: some View {
        ZStack {
            EtherealBackground()
            EtherealParticles()
                .blendMode(.screen)
                .opacity(0.55)

            VStack(spacing: 0) {
                header
                    .padding(.top, 56)
                Spacer()
                eqStage
                    .frame(maxWidth: 820)
                    .padding(.horizontal, 32)
                Spacer()
                bypassRow
                    .padding(.bottom, 32)
            }
        }
        .frame(minWidth: 880, minHeight: 620)
        .background(EtherealPalette.deep)
        .preferredColorScheme(.dark)
    }

    // MARK: header

    private var header: some View {
        VStack(spacing: 10) {
            Text("ether")
                .font(.system(size: 56, weight: .ultraLight, design: .default))
                .tracking(18)
                .foregroundColor(EtherealPalette.textPrimary)
                .shadow(color: EtherealPalette.glow.opacity(0.45), radius: 18, y: 0)

            Text(controller.bypassed ? "bypassed" : "a quieter eq")
                .font(.system(size: 11, weight: .light, design: .default))
                .tracking(6)
                .textCase(.uppercase)
                .foregroundColor(EtherealPalette.textTertiary)
                .animation(.easeOut(duration: 0.4), value: controller.bypassed)
        }
    }

    // MARK: EQ stage

    private var eqStage: some View {
        let bands = visibleBands
        return GeometryReader { geo in
            let stageHeight = geo.size.height - 56  // leave room for freq labels at bottom
            let stride = geo.size.width / CGFloat(max(bands.count, 1))
            let centers: [CGPoint] = bands.enumerated().map { i, band in
                let x = stride * (CGFloat(i) + 0.5)
                let y = yForGain(band.gain, height: stageHeight)
                return CGPoint(x: x, y: y)
            }

            ZStack(alignment: .top) {
                // Curve
                EQCurve(points: centers, height: stageHeight)
                    .stroke(
                        LinearGradient(
                            colors: [
                                EtherealPalette.glow.opacity(0.0),
                                EtherealPalette.glow.opacity(0.85),
                                EtherealPalette.rose.opacity(0.85),
                                EtherealPalette.glow.opacity(0.0),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 1.4, lineCap: .round)
                    )
                    .shadow(color: EtherealPalette.glow.opacity(0.6), radius: 14)
                    .shadow(color: EtherealPalette.violet.opacity(0.5), radius: 28)
                    .frame(height: stageHeight)
                    .opacity(controller.bypassed ? 0.18 : 1.0)
                    .animation(.easeOut(duration: 0.4), value: controller.bypassed)
                    .allowsHitTesting(false)

                // Halos
                ForEach(Array(bands.enumerated()), id: \.element.id) { i, band in
                    let center = centers[i]
                    BandHalo(
                        band: band,
                        stageHeight: stageHeight,
                        bypassed: controller.bypassed,
                        isActive: activeBandID == band.id,
                        onGainChange: { newGain in
                            controller.setGain(bandID: band.id, gain: newGain)
                        },
                        onActiveChange: { active in
                            activeBandID = active ? band.id : (activeBandID == band.id ? nil : activeBandID)
                        }
                    )
                    .position(center)
                }

                // Frequency labels — anchored under each halo
                ForEach(Array(bands.enumerated()), id: \.element.id) { i, band in
                    let x = stride * (CGFloat(i) + 0.5)
                    Text(prettyFreq(band.frequency))
                        .font(.system(size: 10, weight: .light))
                        .tracking(2)
                        .foregroundColor(EtherealPalette.textSecondary)
                        .position(x: x, y: stageHeight + 24)
                }
            }
        }
        .frame(height: 320)
    }

    // MARK: bypass row (single quiet control at the bottom)

    private var bypassRow: some View {
        HStack(spacing: 28) {
            Button(action: { controller.toggleGlobalBypass() }) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(controller.bypassed ? EtherealPalette.textTertiary : EtherealPalette.glow)
                        .frame(width: 6, height: 6)
                        .shadow(color: controller.bypassed ? .clear : EtherealPalette.glow.opacity(0.7), radius: 4)
                    Text(controller.bypassed ? "engage" : "bypass")
                        .font(.system(size: 10, weight: .light))
                        .tracking(4)
                        .textCase(.uppercase)
                        .foregroundColor(EtherealPalette.textSecondary)
                }
            }
            .buttonStyle(.plain)

            Button(action: { controller.reset() }) {
                Text("reset")
                    .font(.system(size: 10, weight: .light))
                    .tracking(4)
                    .textCase(.uppercase)
                    .foregroundColor(EtherealPalette.textTertiary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: helpers

    private func yForGain(_ gain: Float, height: CGFloat) -> CGFloat {
        let normalized = CGFloat((gain + 12) / 24) // 0..1
        return height * (1 - normalized)
    }

    private func prettyFreq(_ hz: Float) -> String {
        if hz < 1000 { return "\(Int(hz.rounded()))" }
        let k = hz / 1000
        if k < 10 { return String(format: "%.0fk", k) }
        return String(format: "%.0fk", k)
    }
}

// MARK: - Band halo

private struct BandHalo: View {
    let band: EQBand
    let stageHeight: CGFloat
    let bypassed: Bool
    let isActive: Bool
    let onGainChange: (Float) -> Void
    let onActiveChange: (Bool) -> Void

    @State private var startGain: Float?
    @State private var hovered = false

    var body: some View {
        let intensity = min(1.0, abs(Double(band.gain)) / 12.0)
        let baseSize: CGFloat = 22
        let glowSize: CGFloat = baseSize + CGFloat(intensity) * 28 + (isActive ? 14 : 0)
        let dimmed = bypassed ? 0.25 : 1.0

        ZStack {
            // Outer halo
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            EtherealPalette.glow.opacity(0.55 * (0.4 + intensity * 0.6)),
                            EtherealPalette.violet.opacity(0.0),
                        ],
                        center: .center,
                        startRadius: 2,
                        endRadius: glowSize
                    )
                )
                .frame(width: glowSize * 2, height: glowSize * 2)
                .blendMode(.screen)

            // Inner core
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white.opacity(0.95), EtherealPalette.glow.opacity(0.6)],
                        center: .center,
                        startRadius: 0,
                        endRadius: baseSize / 2
                    )
                )
                .frame(width: baseSize, height: baseSize)
                .overlay(
                    Circle()
                        .strokeBorder(.white.opacity(0.6), lineWidth: 0.5)
                )
                .shadow(color: EtherealPalette.glow.opacity(0.8), radius: 6)

            // Floating dB readout (active or hovered)
            if isActive || hovered {
                Text(String(format: "%+.1f dB", band.gain))
                    .font(.system(size: 10, weight: .light, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(EtherealPalette.textPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(.black.opacity(0.35))
                            .overlay(Capsule().strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
                    )
                    .offset(y: -36)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .opacity(dimmed)
        .contentShape(Circle().size(width: 60, height: 60))
        .onHover { hovered = $0 }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { g in
                    if startGain == nil {
                        startGain = band.gain
                        onActiveChange(true)
                    }
                    guard let anchor = startGain else { return }
                    let perPoint = Float(24) / Float(stageHeight)
                    let next = max(-12, min(12, anchor - Float(g.translation.height) * perPoint))
                    onGainChange(next)
                }
                .onEnded { _ in
                    startGain = nil
                    onActiveChange(false)
                }
        )
        .animation(.easeOut(duration: 0.6), value: band.gain)
        .animation(.easeOut(duration: 0.25), value: isActive)
        .animation(.easeOut(duration: 0.25), value: hovered)
        .animation(.easeOut(duration: 0.4), value: bypassed)
    }
}

// MARK: - EQ curve shape

private struct EQCurve: Shape {
    let points: [CGPoint]
    let height: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard points.count >= 2 else { return path }

        let mid = height / 2
        let entry = CGPoint(x: 0, y: mid)
        let exit  = CGPoint(x: rect.width, y: mid)
        let all = [entry] + points + [exit]

        path.move(to: all[0])
        for i in 0..<(all.count - 1) {
            let p0 = all[i]
            let p1 = all[i + 1]
            let mx = (p0.x + p1.x) / 2
            let c1 = CGPoint(x: mx, y: p0.y)
            let c2 = CGPoint(x: mx, y: p1.y)
            path.addCurve(to: p1, control1: c1, control2: c2)
        }
        return path
    }
}

// MARK: - Background

private struct EtherealBackground: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let drift = CGFloat(sin(t * 0.08) * 0.08)
            let drift2 = CGFloat(cos(t * 0.06) * 0.10)

            ZStack {
                EtherealPalette.deep

                RadialGradient(
                    colors: [EtherealPalette.violet.opacity(0.55), .clear],
                    center: UnitPoint(x: 0.30 + drift, y: 0.35),
                    startRadius: 40,
                    endRadius: 700
                )
                .blendMode(.screen)

                RadialGradient(
                    colors: [EtherealPalette.rose.opacity(0.32), .clear],
                    center: UnitPoint(x: 0.78 - drift2, y: 0.62),
                    startRadius: 40,
                    endRadius: 600
                )
                .blendMode(.screen)

                LinearGradient(
                    colors: [EtherealPalette.mist.opacity(0.10), .clear],
                    startPoint: .top,
                    endPoint: .center
                )
                .blendMode(.screen)
            }
            .ignoresSafeArea()
        }
    }
}

// MARK: - Drifting particles

private struct EtherealParticles: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let count = 80
                for i in 0..<count {
                    let seed = Double(i) * 12.9898
                    let baseX = (sin(seed) * 0.5 + 0.5)
                    let baseY = (cos(seed * 1.7) * 0.5 + 0.5)
                    let speed = 0.02 + (sin(seed * 3.1) * 0.5 + 0.5) * 0.05
                    let driftX = sin(t * speed + seed) * 0.08
                    let driftY = cos(t * speed * 0.8 + seed * 1.3) * 0.05

                    let x = (baseX + driftX) * size.width
                    let y = (baseY + driftY) * size.height
                    let r = 0.6 + (sin(seed * 2.3) * 0.5 + 0.5) * 1.4
                    let alpha = 0.12 + (sin(t * 0.3 + seed) * 0.5 + 0.5) * 0.18

                    let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                    ctx.fill(Path(ellipseIn: rect), with: .color(.white.opacity(alpha)))
                }
            }
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Preview

#Preview {
    EtherealSkinView(controller: EQController())
        .frame(width: 960, height: 680)
}
