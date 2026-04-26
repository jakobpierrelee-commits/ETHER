import SwiftUI

// MARK: - Ethereal Skin (dev spike)
//
// A self-contained alternate skin for Ether. Not wired to EQController yet —
// uses local state so the visual language can be evaluated in isolation.
// Open via the "Skins" menu or `openWindow(id: "ethereal")`.

// MARK: Mock model

private struct EtherealBand: Identifiable {
    let id = UUID()
    var hz: Float
    var gainDB: Float = 0  // -12 ... +12
    let label: String
}

private final class EtherealMockState: ObservableObject {
    @Published var bands: [EtherealBand] = [
        EtherealBand(hz: 60,     label: "60"),
        EtherealBand(hz: 250,    label: "250"),
        EtherealBand(hz: 1_000,  label: "1k"),
        EtherealBand(hz: 4_000,  label: "4k"),
        EtherealBand(hz: 16_000, label: "16k"),
    ]
}

// MARK: Palette

private enum EtherealPalette {
    // Dawn-mist palette: deep indigo → violet → pale rose → off-white
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
    @StateObject private var state = EtherealMockState()
    @State private var time: TimeInterval = 0
    @State private var activeBandID: UUID?

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
                    .frame(maxWidth: 760)
                    .padding(.horizontal, 48)
                Spacer()
                footer
                    .padding(.bottom, 40)
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

            Text("a quieter eq")
                .font(.system(size: 11, weight: .light, design: .default))
                .tracking(6)
                .textCase(.uppercase)
                .foregroundColor(EtherealPalette.textTertiary)
        }
    }

    // MARK: EQ stage

    private var eqStage: some View {
        GeometryReader { geo in
            let bandCount = state.bands.count
            let stride = geo.size.width / CGFloat(bandCount)
            let centers: [CGPoint] = state.bands.enumerated().map { i, band in
                let x = stride * (CGFloat(i) + 0.5)
                let y = yForGain(band.gainDB, height: geo.size.height)
                return CGPoint(x: x, y: y)
            }

            ZStack {
                EQCurve(points: centers, height: geo.size.height)
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
                    .allowsHitTesting(false)

                ForEach(Array(state.bands.enumerated()), id: \.element.id) { i, band in
                    let center = centers[i]
                    BandHalo(
                        band: band,
                        isActive: activeBandID == band.id,
                        onDrag: { delta in
                            let range: Float = 12
                            let height = geo.size.height
                            let perPoint = (range * 2) / Float(height)
                            var next = state.bands[i].gainDB - Float(delta) * perPoint
                            next = max(-12, min(12, next))
                            state.bands[i].gainDB = next
                            activeBandID = band.id
                        },
                        onRelease: { activeBandID = nil }
                    )
                    .position(center)
                }
            }
        }
        .frame(height: 280)
    }

    private func yForGain(_ gain: Float, height: CGFloat) -> CGFloat {
        let normalized = CGFloat((gain + 12) / 24) // 0..1
        return height * (1 - normalized)
    }

    // MARK: footer

    private var footer: some View {
        HStack(spacing: 44) {
            ForEach(state.bands) { band in
                VStack(spacing: 4) {
                    Text(band.label)
                        .font(.system(size: 10, weight: .light))
                        .tracking(2)
                        .foregroundColor(EtherealPalette.textSecondary)
                    Text(String(format: "%+.1f", band.gainDB))
                        .font(.system(size: 9, weight: .light, design: .monospaced))
                        .foregroundColor(EtherealPalette.textTertiary)
                }
                .frame(width: 60)
            }
        }
    }
}

// MARK: - Band halo

private struct BandHalo: View {
    let band: EtherealBand
    let isActive: Bool
    let onDrag: (CGFloat) -> Void
    let onRelease: () -> Void

    @State private var dragStart: CGFloat?
    @State private var startGain: Float = 0
    @State private var hovered = false

    var body: some View {
        let intensity = min(1.0, abs(Double(band.gainDB)) / 12.0)
        let baseSize: CGFloat = 22
        let glowSize: CGFloat = baseSize + CGFloat(intensity) * 28 + (isActive ? 14 : 0)

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

            // Floating dB readout (only when active or hovered)
            if isActive || hovered {
                Text(String(format: "%+.1f dB", band.gainDB))
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
        .contentShape(Circle().size(width: 60, height: 60))
        .onHover { hovered = $0 }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { g in
                    if dragStart == nil {
                        dragStart = g.startLocation.y
                        startGain = band.gainDB
                    }
                    let delta = g.translation.height
                    onDrag(delta)
                }
                .onEnded { _ in
                    dragStart = nil
                    onRelease()
                }
        )
        .animation(.easeOut(duration: 0.6), value: band.gainDB)
        .animation(.easeOut(duration: 0.25), value: isActive)
        .animation(.easeOut(duration: 0.25), value: hovered)
    }
}

// MARK: - EQ curve shape

private struct EQCurve: Shape {
    let points: [CGPoint]
    let height: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard points.count >= 2 else { return path }

        // Anchor curve to the vertical midline at the edges so it fades in/out
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

                // Big diffuse violet glow
                RadialGradient(
                    colors: [EtherealPalette.violet.opacity(0.55), .clear],
                    center: UnitPoint(x: 0.30 + drift, y: 0.35),
                    startRadius: 40,
                    endRadius: 700
                )
                .blendMode(.screen)

                // Warm rose glow
                RadialGradient(
                    colors: [EtherealPalette.rose.opacity(0.32), .clear],
                    center: UnitPoint(x: 0.78 - drift2, y: 0.62),
                    startRadius: 40,
                    endRadius: 600
                )
                .blendMode(.screen)

                // Cool glow at top to suggest atmosphere
                LinearGradient(
                    colors: [
                        EtherealPalette.mist.opacity(0.10),
                        .clear,
                    ],
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
                    let baseX = (sin(seed) * 0.5 + 0.5)  // 0..1
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
    EtherealSkinView()
        .frame(width: 960, height: 680)
}
