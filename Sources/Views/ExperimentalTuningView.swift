import SwiftUI

// MARK: - Skin

enum TuningSkin: String, CaseIterable, Identifiable {
    case trench   = "Trench"
    case orrery   = "Orrery"
    case riso     = "Riso"
    case crt      = "CRT"
    var id: String { rawValue }
}

// MARK: - Layout

enum TuningLayout: String, CaseIterable, Identifiable {
    case ring     = "Ring"
    case helix    = "Helix"
    case tidePool = "Pool"
    case stacked  = "Octaves"
    case field    = "Field"
    var id: String { rawValue }
}

private struct SkinPalette {
    let background: Color
    let ringBase: Color
    let ringGlow: Color
    let traceLow: Color
    let traceMid: Color
    let traceHigh: Color
    let particleCore: Color
    let particleHalo: Color
    let accent: Color
    let hudText: Color
    let hudDim: Color
    let handleStalk: Color
    let handleBulb: Color
    let bandBoost: Color
    let bandCut: Color
    let hudFontDesign: Font.Design
    let scanlines: Bool
    let phosphorTrail: Bool

    static func palette(for skin: TuningSkin) -> SkinPalette {
        switch skin {
        case .trench:
            return SkinPalette(
                background: Color(hex: 0x030608),
                ringBase: Color.p3(0.08, 0.22, 0.28),
                ringGlow: Color.p3(0.20, 0.95, 0.80),
                traceLow: Color.p3(0.95, 0.70, 0.10),
                traceMid: Color.p3(0.10, 0.95, 0.85),
                traceHigh: Color.p3(0.55, 0.45, 1.00),
                particleCore: Color.p3(0.60, 1.00, 0.85),
                particleHalo: Color.p3(0.15, 0.60, 0.90),
                accent: Color.p3(0.20, 0.95, 0.80),
                hudText: Color(hex: 0xC8F8E8),
                hudDim: Color(hex: 0x3A6860),
                handleStalk: Color.p3(0.08, 0.45, 0.45),
                handleBulb: Color.p3(0.40, 1.00, 0.85),
                bandBoost: Color.p3(1.00, 0.85, 0.25),
                bandCut: Color.p3(0.60, 0.20, 0.90),
                hudFontDesign: .monospaced,
                scanlines: false,
                phosphorTrail: false
            )
        case .orrery:
            return SkinPalette(
                background: Color(hex: 0x060504),
                ringBase: Color.p3(0.28, 0.20, 0.10),
                ringGlow: Color.p3(0.85, 0.65, 0.30),
                traceLow: Color.p3(0.70, 0.35, 0.15),
                traceMid: Color.p3(0.85, 0.70, 0.35),
                traceHigh: Color.p3(0.95, 0.90, 0.75),
                particleCore: Color(hex: 0xF4E6C8),
                particleHalo: Color.p3(0.60, 0.45, 0.20),
                accent: Color.p3(0.85, 0.70, 0.35),
                hudText: Color(hex: 0xF0E2C4),
                hudDim: Color(hex: 0x6A5838),
                handleStalk: Color.p3(0.40, 0.30, 0.15),
                handleBulb: Color.p3(0.95, 0.82, 0.50),
                bandBoost: Color.p3(0.95, 0.82, 0.50),
                bandCut: Color.p3(0.35, 0.25, 0.55),
                hudFontDesign: .serif,
                scanlines: false,
                phosphorTrail: false
            )
        case .riso:
            return SkinPalette(
                background: Color(hex: 0x0A0806),
                ringBase: Color.p3(0.20, 0.10, 0.25),
                ringGlow: Color.p3(1.00, 0.30, 0.70),
                traceLow: Color.p3(1.00, 0.30, 0.70),
                traceMid: Color.p3(0.95, 0.90, 0.40),
                traceHigh: Color.p3(0.25, 0.35, 0.95),
                particleCore: Color.p3(1.00, 0.30, 0.70),
                particleHalo: Color.p3(0.25, 0.35, 0.95),
                accent: Color.p3(1.00, 0.30, 0.70),
                hudText: Color(hex: 0xFFE8F4),
                hudDim: Color(hex: 0x704860),
                handleStalk: Color.p3(0.25, 0.35, 0.95),
                handleBulb: Color.p3(1.00, 0.30, 0.70),
                bandBoost: Color.p3(0.95, 0.90, 0.40),
                bandCut: Color.p3(0.25, 0.35, 0.95),
                hudFontDesign: .monospaced,
                scanlines: false,
                phosphorTrail: false
            )
        case .crt:
            return SkinPalette(
                background: Color(hex: 0x000000),
                ringBase: Color.p3(0.05, 0.25, 0.10),
                ringGlow: Color.p3(0.30, 1.00, 0.40),
                traceLow: Color.p3(0.30, 1.00, 0.40),
                traceMid: Color.p3(0.30, 1.00, 0.40),
                traceHigh: Color.p3(0.50, 1.00, 0.60),
                particleCore: Color.p3(0.60, 1.00, 0.70),
                particleHalo: Color.p3(0.10, 0.60, 0.25),
                accent: Color.p3(0.30, 1.00, 0.40),
                hudText: Color.p3(0.50, 1.00, 0.60),
                hudDim: Color.p3(0.12, 0.40, 0.18),
                handleStalk: Color.p3(0.10, 0.55, 0.22),
                handleBulb: Color.p3(0.60, 1.00, 0.70),
                bandBoost: Color.p3(0.60, 1.00, 0.70),
                bandCut: Color.p3(0.85, 1.00, 0.35),
                hudFontDesign: .monospaced,
                scanlines: true,
                phosphorTrail: true
            )
        }
    }
}

// MARK: - Model

private struct DemoBand: Identifiable {
    let id = UUID()
    var frequency: Float
    var gain: Float
    var q: Float
    var stereo: Float = 0          // -1 = hard L, 0 = mono, +1 = hard R. Used by .field.
}

// MARK: - Geometry helpers

private enum RadialMath {
    static let voidHalfArc: Double = 10        // degrees on each side of 6 o'clock
    static let freqStart: Float = 20
    static let freqEnd: Float = 20000

    /// 6 o'clock is 180° in a clock where 0° = 12 and positive = clockwise.
    /// Audible arc sweeps clockwise from (180+voidHalf)° → 540-voidHalf° (= 180-voidHalf° wrapped).
    static var sweepStart: Double { 180 + voidHalfArc }      // ≈ 190°
    static var sweepEnd:   Double { 540 - voidHalfArc }      // ≈ 530°
    static var sweepSpan:  Double { sweepEnd - sweepStart }  // ≈ 340°

    /// Map frequency in Hz → clockwise degrees from 12 o'clock.
    static func angleForFreq(_ hz: Float) -> Double {
        let t = log10(max(hz, freqStart) / freqStart) / log10(freqEnd / freqStart)
        return sweepStart + Double(t) * sweepSpan
    }

    /// Inverse: degrees-from-top → Hz.
    static func freqForAngle(_ deg: Double) -> Float {
        let clamped = max(sweepStart, min(sweepEnd, deg))
        let t = (clamped - sweepStart) / sweepSpan
        return freqStart * pow(freqEnd / freqStart, Float(t))
    }

    /// 0° = top (12 o'clock), positive = clockwise.
    static func point(center: CGPoint, radius: CGFloat, angleDeg: Double) -> CGPoint {
        let r = angleDeg * .pi / 180
        return CGPoint(x: center.x + radius * CGFloat(sin(r)),
                       y: center.y - radius * CGFloat(cos(r)))
    }

    /// Angle of a point relative to center, normalized to the sweep range.
    static func angleForPoint(_ p: CGPoint, center: CGPoint) -> Double {
        let dx = Double(p.x - center.x)
        let dy = Double(p.y - center.y)
        var deg = atan2(dx, -dy) * 180 / .pi           // -180..180, 0 = top, clockwise
        if deg < 0 { deg += 360 }                      // 0..360
        // Bump wrap-around so the seam at the void doesn't jump from 190° to 530°
        if deg < sweepStart - 1 { deg += 360 }
        return deg
    }
}

// MARK: - Main view

struct ExperimentalTuningView: View {
    @EnvironmentObject var engine: EngineManager
    @State private var skin: TuningSkin = .trench
    @State private var layout: TuningLayout = .ring
    @State private var bands: [DemoBand] = [
        DemoBand(frequency: 120,  gain:  4.5, q: 1.2),
        DemoBand(frequency: 1000, gain: -3.0, q: 2.0),
        DemoBand(frequency: 8000, gain:  2.0, q: 0.9)
    ]
    @State private var draggingBandID: UUID?
    @State private var fieldDragAnchor: CGPoint?
    @State private var idleSince: Date = .now
    @State private var hoveredHUD: DemoBand?

    var body: some View {
        let palette = SkinPalette.palette(for: skin)

        VStack(spacing: 0) {
            header(palette: palette)
            GeometryReader { geo in
                TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    canvas(geo: geo, palette: palette, time: t)
                        .contentShape(Rectangle())
                        .gesture(dragGesture(geo: geo))
                }
            }
            .background(palette.background)
        }
        .frame(minWidth: 640, minHeight: 640)
        .background(palette.background.ignoresSafeArea())
    }

    // MARK: Header

    @ViewBuilder
    private func header(palette: SkinPalette) -> some View {
        HStack(spacing: 12) {
            Text("EXPERIMENTAL TUNING")
                .font(.system(size: 11, weight: .semibold, design: palette.hudFontDesign))
                .tracking(2.4)
                .foregroundColor(palette.hudText)
            Spacer()
            Picker("Layout", selection: $layout) {
                ForEach(TuningLayout.allCases) { l in Text(l.rawValue).tag(l) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .frame(maxWidth: 260)
            Picker("Skin", selection: $skin) {
                ForEach(TuningSkin.allCases) { s in Text(s.rawValue).tag(s) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .frame(maxWidth: 260)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(palette.background)
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.hudDim.opacity(0.35)).frame(height: 0.5)
        }
    }

    // MARK: Canvas

    private func canvas(geo: GeometryProxy, palette: SkinPalette, time: TimeInterval) -> some View {
        let size = geo.size
        let side = min(size.width, size.height) - 40
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let outerR = side / 2
        let unityR = outerR * 0.70
        let spectrum = engine.postSpectrum.magnitudes

        return Canvas(opaque: false) { ctx, _ in
            drawBackdropGlow(ctx: ctx, center: center, outerR: outerR, palette: palette, time: time)

            switch layout {
            case .ring:
                drawVoidWedge(ctx: ctx, center: center, outerR: outerR, palette: palette)
                drawSpectrumRing(ctx: ctx, center: center, radius: outerR, spectrum: spectrum, palette: palette, time: time)
                drawUnityRing(ctx: ctx, center: center, radius: unityR, bands: bands, palette: palette, time: time)
                drawParticles(ctx: ctx, center: center, unityR: unityR, outerR: outerR, spectrum: spectrum, palette: palette, time: time)
                drawHandles(ctx: ctx, center: center, unityR: unityR, bands: bands, palette: palette)
                drawHUD(ctx: ctx, center: center, outerR: outerR, bands: bands, palette: palette)

            case .helix:
                drawHelix(ctx: ctx, center: center, outerR: outerR, spectrum: spectrum, palette: palette, time: time)
                drawParticles(ctx: ctx, center: center, unityR: unityR, outerR: outerR, spectrum: spectrum, palette: palette, time: time)
                drawHelixHandles(ctx: ctx, center: center, outerR: outerR, bands: bands, palette: palette, time: time)
                drawHUD(ctx: ctx, center: center, outerR: outerR, bands: bands, palette: palette)

            case .tidePool:
                drawTidePool(ctx: ctx, center: center, outerR: outerR, spectrum: spectrum, bands: bands, palette: palette, time: time)
                drawTidePoolParticles(ctx: ctx, center: center, outerR: outerR, spectrum: spectrum, palette: palette, time: time)
                drawTidePoolHandles(ctx: ctx, center: center, outerR: outerR, bands: bands, palette: palette)
                drawHUD(ctx: ctx, center: center, outerR: outerR, bands: bands, palette: palette)

            case .stacked:
                drawStackedOctaves(ctx: ctx, center: center, outerR: outerR, spectrum: spectrum, bands: bands, palette: palette, time: time)
                drawStackedHandles(ctx: ctx, center: center, outerR: outerR, bands: bands, palette: palette)
                drawHUD(ctx: ctx, center: center, outerR: outerR, bands: bands, palette: palette)

            case .field:
                drawField(ctx: ctx, size: size, spectrum: spectrum, bands: bands, palette: palette, time: time)
            }

            if palette.scanlines { drawScanlines(ctx: ctx, size: size, palette: palette) }
        }
    }

    // MARK: Drawing

    private func drawBackdropGlow(ctx: GraphicsContext, center: CGPoint, outerR: CGFloat, palette: SkinPalette, time: TimeInterval) {
        let breath = 1.0 + 0.04 * sin(time * 0.4)
        let r = outerR * 1.35 * CGFloat(breath)
        let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
        let grad = Gradient(colors: [
            palette.ringGlow.opacity(0.10),
            palette.ringGlow.opacity(0.02),
            .clear
        ])
        ctx.fill(Path(ellipseIn: rect),
                 with: .radialGradient(grad, center: center, startRadius: 0, endRadius: r))
    }

    private func drawVoidWedge(ctx: GraphicsContext, center: CGPoint, outerR: CGFloat, palette: SkinPalette) {
        var path = Path()
        let r = outerR * 1.15
        path.move(to: center)
        path.addArc(center: center, radius: r,
                    startAngle: .degrees(90 - RadialMath.voidHalfArc - 90),
                    endAngle:   .degrees(90 + RadialMath.voidHalfArc - 90),
                    clockwise: false)
        path.closeSubpath()
        ctx.fill(path, with: .color(palette.background))
    }

    /// Outer ring: live spectrum pushed outward from a baseline radius.
    private func drawSpectrumRing(ctx: GraphicsContext, center: CGPoint, radius: CGFloat,
                                  spectrum: [Float], palette: SkinPalette, time: TimeInterval) {
        guard !spectrum.isEmpty else { return }
        let baseR = radius * 0.95
        let maxExtra = radius * 0.10
        var path = Path()
        let steps = 240
        var first = true
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let deg = RadialMath.sweepStart + t * RadialMath.sweepSpan
            let binIdx = Int(t * Double(spectrum.count - 1))
            let db = spectrum[binIdx]                        // ~ -80..0
            let energy = max(0, min(1, (db + 60) / 60))
            let r = baseR + CGFloat(energy) * maxExtra
            let p = RadialMath.point(center: center, radius: r, angleDeg: deg)
            if first { path.move(to: p); first = false } else { path.addLine(to: p) }
        }
        // three-tone gradient by angle: low=orange-ish, mid=cyan, high=violet
        let grad = Gradient(colors: [palette.traceLow, palette.traceMid, palette.traceHigh, palette.traceLow])
        ctx.stroke(path, with: .conicGradient(grad, center: center, angle: .degrees(0)),
                   style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))

        // Soft glow pass
        var glow = ctx
        glow.addFilter(.blur(radius: 6))
        glow.stroke(path, with: .color(palette.ringGlow.opacity(0.4)),
                    style: StrokeStyle(lineWidth: 3.0, lineCap: .round))
    }

    /// Inner sculpt ring: unity circle, deformed by bands.
    private func drawUnityRing(ctx: GraphicsContext, center: CGPoint, radius: CGFloat,
                               bands: [DemoBand], palette: SkinPalette, time: TimeInterval) {
        var path = Path()
        let steps = 360
        var first = true
        for i in 0...steps {
            let deg = RadialMath.sweepStart + Double(i) / Double(steps) * RadialMath.sweepSpan
            let freq = RadialMath.freqForAngle(deg)
            let deform = deformation(at: freq, bands: bands)     // -1..+1
            let r = radius + CGFloat(deform) * radius * 0.18
            let p = RadialMath.point(center: center, radius: r, angleDeg: deg)
            if first { path.move(to: p); first = false } else { path.addLine(to: p) }
        }
        ctx.stroke(path, with: .color(palette.ringBase.opacity(0.6)),
                   style: StrokeStyle(lineWidth: 0.8))

        // Glowing scars along deformed segments
        var scarPath = Path()
        var scarFirst = true
        for i in 0...steps {
            let deg = RadialMath.sweepStart + Double(i) / Double(steps) * RadialMath.sweepSpan
            let freq = RadialMath.freqForAngle(deg)
            let deform = deformation(at: freq, bands: bands)
            if abs(deform) < 0.05 { scarFirst = true; continue }
            let r = radius + CGFloat(deform) * radius * 0.18
            let p = RadialMath.point(center: center, radius: r, angleDeg: deg)
            if scarFirst { scarPath.move(to: p); scarFirst = false } else { scarPath.addLine(to: p) }
        }
        var glow = ctx
        glow.addFilter(.blur(radius: 4))
        glow.stroke(scarPath, with: .color(palette.ringGlow.opacity(0.7)),
                    style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
        ctx.stroke(scarPath, with: .color(palette.accent.opacity(0.9)),
                   style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
    }

    /// Combined unity-ring deformation at a frequency from all bands, in [-1, 1].
    private func deformation(at freq: Float, bands: [DemoBand]) -> Double {
        var sum: Double = 0
        for b in bands {
            let ratio = Double(log(freq / b.frequency))
            let bw = 1.0 / Double(b.q)
            let falloff = exp(-(ratio * ratio) / (2 * bw * bw))
            sum += Double(b.gain / 18) * falloff          // 18 dB ≈ full push
        }
        return max(-1, min(1, sum))
    }

    /// Bioluminescent motes — pulled toward energetic bands.
    private func drawParticles(ctx: GraphicsContext, center: CGPoint, unityR: CGFloat, outerR: CGFloat,
                               spectrum: [Float], palette: SkinPalette, time: TimeInterval) {
        let count = 140
        for i in 0..<count {
            // deterministic jitter per particle
            let seed = Double(i)
            let baseAngle = RadialMath.sweepStart + (RadialMath.sweepSpan) * (fract(seed * 0.6180339887))
            let drift = sin(time * 0.25 + seed) * 6.0
            let deg = baseAngle + drift
            let binIdx = Int(((deg - RadialMath.sweepStart) / RadialMath.sweepSpan) * Double(spectrum.count - 1))
            let db = spectrum[max(0, min(spectrum.count - 1, binIdx))]
            let energy = max(0, min(1, (db + 55) / 55))
            let radial = unityR + CGFloat(fract(seed * 0.7548776662)) * (outerR - unityR)
            let breathe = 1.0 + 0.08 * sin(time * (0.6 + fract(seed * 0.31)) + seed)
            let r = radial * CGFloat(breathe) + CGFloat(energy) * 6
            let p = RadialMath.point(center: center, radius: r, angleDeg: deg)
            let coreSize: CGFloat = 1.2 + CGFloat(energy) * 3.0
            let rect = CGRect(x: p.x - coreSize, y: p.y - coreSize, width: coreSize * 2, height: coreSize * 2)

            var halo = ctx
            halo.addFilter(.blur(radius: 3))
            halo.fill(Path(ellipseIn: rect.insetBy(dx: -coreSize, dy: -coreSize)),
                      with: .color(palette.particleHalo.opacity(0.35 + Double(energy) * 0.35)))
            ctx.fill(Path(ellipseIn: rect),
                     with: .color(palette.particleCore.opacity(0.75 + Double(energy) * 0.25)))
        }
    }

    /// Anglerfish-lure band handles on the unity ring.
    private func drawHandles(ctx: GraphicsContext, center: CGPoint, unityR: CGFloat,
                             bands: [DemoBand], palette: SkinPalette) {
        for band in bands {
            let deg = RadialMath.angleForFreq(band.frequency)
            let deform = deformation(at: band.frequency, bands: bands)
            let ringPoint = RadialMath.point(center: center, radius: unityR + CGFloat(deform) * unityR * 0.18, angleDeg: deg)
            // Bulb sits further out past the ring deformation, scaled by gain
            let bulbR = unityR + CGFloat(band.gain / 18) * unityR * 0.28 + unityR * 0.06
            let bulb = RadialMath.point(center: center, radius: bulbR, angleDeg: deg)

            // Stalk from ring to bulb
            var stalk = Path()
            stalk.move(to: ringPoint)
            stalk.addLine(to: bulb)
            ctx.stroke(stalk, with: .color(palette.handleStalk.opacity(0.9)),
                       style: StrokeStyle(lineWidth: 1.0))

            // Bulb
            let tint = band.gain >= 0 ? palette.bandBoost : palette.bandCut
            let bulbSize: CGFloat = 6 + CGFloat(abs(band.gain) / 24) * 4
            let rect = CGRect(x: bulb.x - bulbSize / 2, y: bulb.y - bulbSize / 2,
                              width: bulbSize, height: bulbSize)
            var glow = ctx
            glow.addFilter(.blur(radius: 5))
            glow.fill(Path(ellipseIn: rect.insetBy(dx: -bulbSize, dy: -bulbSize)),
                      with: .color(tint.opacity(0.55)))
            ctx.fill(Path(ellipseIn: rect), with: .color(tint))
            ctx.fill(Path(ellipseIn: rect.insetBy(dx: bulbSize * 0.3, dy: bulbSize * 0.3)),
                     with: .color(palette.handleBulb))
        }
    }

    /// HUD parked in the 6 o'clock void.
    private func drawHUD(ctx: GraphicsContext, center: CGPoint, outerR: CGFloat,
                         bands: [DemoBand], palette: SkinPalette) {
        let active = bands.max(by: { abs($0.gain) < abs($1.gain) })
        let hudCenter = CGPoint(x: center.x, y: center.y + outerR * 0.98)

        let primary: String
        let secondary: String
        if let a = active {
            primary = EtherFormat.frequency(a.frequency) + "   " + EtherFormat.gain(a.gain)
            secondary = "Q " + EtherFormat.q(a.q) + "   ·   " + skin.rawValue.uppercased()
        } else {
            primary = "ETHER · EXPERIMENTAL"
            secondary = skin.rawValue.uppercased()
        }

        let primaryText = Text(primary)
            .font(.system(size: 13, weight: .semibold, design: palette.hudFontDesign))
            .foregroundColor(palette.hudText)
        let secondaryText = Text(secondary)
            .font(.system(size: 9, weight: .regular, design: palette.hudFontDesign))
            .tracking(1.8)
            .foregroundColor(palette.hudDim)

        ctx.draw(primaryText, at: CGPoint(x: hudCenter.x, y: hudCenter.y - 6), anchor: .center)
        ctx.draw(secondaryText, at: CGPoint(x: hudCenter.x, y: hudCenter.y + 10), anchor: .center)
    }

    // MARK: - Helix layout
    // Two spectrum rings straddling the unity ring, with opposite rotational drift.

    private func drawHelix(ctx: GraphicsContext, center: CGPoint, outerR: CGFloat,
                           spectrum: [Float], palette: SkinPalette, time: TimeInterval) {
        drawVoidWedge(ctx: ctx, center: center, outerR: outerR, palette: palette)

        let outerRingR = outerR * 0.95
        let innerRingR = outerR * 0.70
        let unityR = (outerRingR + innerRingR) / 2
        let driftDeg = time * 6.0

        drawHelixRing(ctx: ctx, center: center, radius: outerRingR, spectrum: spectrum,
                      palette: palette, angleOffset: driftDeg, invertGradient: false)
        drawHelixRing(ctx: ctx, center: center, radius: innerRingR, spectrum: spectrum,
                      palette: palette, angleOffset: -driftDeg, invertGradient: true)

        // Spine (unity) ring between the two
        drawUnityRing(ctx: ctx, center: center, radius: unityR, bands: bands, palette: palette, time: time)
    }

    private func drawHelixRing(ctx: GraphicsContext, center: CGPoint, radius: CGFloat,
                               spectrum: [Float], palette: SkinPalette,
                               angleOffset: Double, invertGradient: Bool) {
        guard !spectrum.isEmpty else { return }
        let baseR = radius * 0.97
        let maxExtra = radius * 0.08
        var path = Path()
        let steps = 240
        var first = true
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let sweepDeg = RadialMath.sweepStart + t * RadialMath.sweepSpan
            let drawDeg = sweepDeg + angleOffset
            let binIdx = Int(t * Double(spectrum.count - 1))
            let db = spectrum[binIdx]
            let energy = max(0, min(1, (db + 60) / 60))
            let r = baseR + CGFloat(energy) * maxExtra
            let p = RadialMath.point(center: center, radius: r, angleDeg: drawDeg)
            if first { path.move(to: p); first = false } else { path.addLine(to: p) }
        }
        let colors = invertGradient
            ? [palette.traceHigh, palette.traceMid, palette.traceLow, palette.traceHigh]
            : [palette.traceLow, palette.traceMid, palette.traceHigh, palette.traceLow]
        ctx.stroke(path, with: .conicGradient(Gradient(colors: colors),
                                              center: center, angle: .degrees(angleOffset)),
                   style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
        var glow = ctx
        glow.addFilter(.blur(radius: 5))
        glow.stroke(path, with: .color(palette.ringGlow.opacity(0.35)),
                    style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
    }

    /// Helix handles bridge between inner and outer rings.
    private func drawHelixHandles(ctx: GraphicsContext, center: CGPoint, outerR: CGFloat,
                                  bands: [DemoBand], palette: SkinPalette, time: TimeInterval) {
        let outerRingR = outerR * 0.95
        let innerRingR = outerR * 0.70
        for band in bands {
            let deg = RadialMath.angleForFreq(band.frequency)
            // Bulb position between rings, biased by gain
            let t = Double(band.gain / 18) * 0.45 + 0.5   // 0.05..0.95
            let bulbR = innerRingR + CGFloat(t) * (outerRingR - innerRingR)
            let bulb = RadialMath.point(center: center, radius: bulbR, angleDeg: deg)
            let inner = RadialMath.point(center: center, radius: innerRingR, angleDeg: deg)
            let outer = RadialMath.point(center: center, radius: outerRingR, angleDeg: deg)

            var stalk = Path()
            stalk.move(to: inner)
            stalk.addLine(to: outer)
            ctx.stroke(stalk, with: .color(palette.handleStalk.opacity(0.8)),
                       style: StrokeStyle(lineWidth: 0.8))

            let tint = band.gain >= 0 ? palette.bandBoost : palette.bandCut
            let bulbSize: CGFloat = 7 + CGFloat(abs(band.gain) / 24) * 4
            let rect = CGRect(x: bulb.x - bulbSize / 2, y: bulb.y - bulbSize / 2,
                              width: bulbSize, height: bulbSize)
            var glow = ctx
            glow.addFilter(.blur(radius: 6))
            glow.fill(Path(ellipseIn: rect.insetBy(dx: -bulbSize, dy: -bulbSize)),
                      with: .color(tint.opacity(0.6)))
            ctx.fill(Path(ellipseIn: rect), with: .color(tint))
            ctx.fill(Path(ellipseIn: rect.insetBy(dx: bulbSize * 0.3, dy: bulbSize * 0.3)),
                     with: .color(palette.handleBulb))
        }
    }

    // MARK: - Tide Pool layout
    // Top-down view of a shallow ellipse; void is a central whirlpool.

    private static let poolYScale: CGFloat = 0.58

    private func poolPoint(center: CGPoint, radius: CGFloat, angleDeg: Double) -> CGPoint {
        let p = RadialMath.point(center: center, radius: radius, angleDeg: angleDeg)
        return CGPoint(x: p.x, y: center.y + (p.y - center.y) * Self.poolYScale)
    }

    private func drawTidePool(ctx: GraphicsContext, center: CGPoint, outerR: CGFloat,
                              spectrum: [Float], bands: [DemoBand], palette: SkinPalette, time: TimeInterval) {
        // Water disc with subtle vignette
        let rim = outerR * 0.95
        let rimRect = CGRect(x: center.x - rim, y: center.y - rim * Self.poolYScale,
                             width: rim * 2, height: rim * 2 * Self.poolYScale)
        let waterGrad = Gradient(colors: [palette.ringBase.opacity(0.35),
                                          palette.background])
        ctx.fill(Path(ellipseIn: rimRect),
                 with: .radialGradient(waterGrad, center: center,
                                       startRadius: 0, endRadius: rim))

        // Central whirlpool — dark well with slow rotation hint
        let wellR = outerR * 0.22
        let wellRect = CGRect(x: center.x - wellR, y: center.y - wellR * Self.poolYScale,
                              width: wellR * 2, height: wellR * 2 * Self.poolYScale)
        let wellGrad = Gradient(colors: [palette.background, palette.ringBase.opacity(0.2)])
        ctx.fill(Path(ellipseIn: wellRect),
                 with: .radialGradient(wellGrad, center: center, startRadius: 0, endRadius: wellR))
        // Spiral arms
        for armIdx in 0..<3 {
            var spiral = Path()
            let armStart = Double(armIdx) * 120 + time * 15
            var firstPt = true
            for s in 0...60 {
                let t = Double(s) / 60
                let r = wellR * CGFloat(t)
                let deg = armStart + t * 200
                let p = poolPoint(center: center, radius: r, angleDeg: deg)
                if firstPt { spiral.move(to: p); firstPt = false } else { spiral.addLine(to: p) }
            }
            ctx.stroke(spiral, with: .color(palette.ringGlow.opacity(0.15)),
                       style: StrokeStyle(lineWidth: 0.8, lineCap: .round))
        }

        // Full-360 spectrum trace on the water surface (no void wedge)
        var tracePath = Path()
        let steps = 300
        var first = true
        let baseR = rim * 0.88
        let maxExtra = rim * 0.08
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let deg = t * 360
            let binIdx = Int(t * Double(spectrum.count - 1))
            let db = spectrum[binIdx]
            let energy = max(0, min(1, (db + 60) / 60))
            let r = baseR + CGFloat(energy) * maxExtra
            let p = poolPoint(center: center, radius: r, angleDeg: deg)
            if first { tracePath.move(to: p); first = false } else { tracePath.addLine(to: p) }
        }
        let grad = Gradient(colors: [palette.traceLow, palette.traceMid, palette.traceHigh, palette.traceLow])
        ctx.stroke(tracePath, with: .conicGradient(grad, center: center, angle: .degrees(0)),
                   style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
        var glow = ctx
        glow.addFilter(.blur(radius: 6))
        glow.stroke(tracePath, with: .color(palette.ringGlow.opacity(0.4)),
                    style: StrokeStyle(lineWidth: 2.8, lineCap: .round))

        // Ripples from each band outward toward the rim
        for band in bands where abs(band.gain) > 0.5 {
            let deg = poolAngleForFreq(band.frequency)
            let ringR = outerR * 0.55
            for ripple in 0..<3 {
                let phase = time * 0.9 + Double(ripple) * 0.5
                let progress = fract(phase)
                let rippleR = ringR * (0.4 + CGFloat(progress) * 0.9)
                let alpha = (1 - progress) * Double(abs(band.gain) / 18) * 0.6
                let center2 = poolPoint(center: center, radius: rippleR, angleDeg: deg)
                let size = rippleR * 0.25
                let rect = CGRect(x: center2.x - size, y: center2.y - size * Self.poolYScale,
                                  width: size * 2, height: size * 2 * Self.poolYScale)
                ctx.stroke(Path(ellipseIn: rect),
                           with: .color((band.gain >= 0 ? palette.bandBoost : palette.bandCut).opacity(alpha)),
                           style: StrokeStyle(lineWidth: 1.0))
            }
        }
    }

    /// Full 360° log sweep (no void) — void is the central well instead.
    private func poolAngleForFreq(_ hz: Float) -> Double {
        let t = log10(max(hz, 20) / 20) / log10(20000 / 20)
        return Double(t) * 360
    }
    private func poolFreqForAngle(_ deg: Double) -> Float {
        var d = deg.truncatingRemainder(dividingBy: 360)
        if d < 0 { d += 360 }
        let t = d / 360
        return 20 * pow(Float(20000 / 20), Float(t))
    }

    private func drawTidePoolParticles(ctx: GraphicsContext, center: CGPoint, outerR: CGFloat,
                                       spectrum: [Float], palette: SkinPalette, time: TimeInterval) {
        let count = 160
        let rim = outerR * 0.94
        for i in 0..<count {
            let seed = Double(i)
            // Each particle spirals inward toward the whirlpool, loops on reaching center
            let lifeSpeed = 0.08 + fract(seed * 0.174) * 0.05
            let phase = fract(time * lifeSpeed + fract(seed * 0.6180339887))
            let birthAngle = fract(seed * 0.415) * 360
            let inwardSpin = phase * 320     // spiral tightens as it sinks
            let deg = birthAngle + inwardSpin
            let t = 1 - phase                  // 1 at birth (rim), 0 at sink
            let r = rim * CGFloat(pow(t, 1.4)) * 0.9 + outerR * 0.18

            // Energy pull based on the particle's current frequency-angle
            let angleNorm = (deg.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
            let binIdx = Int(angleNorm / 360 * Double(spectrum.count - 1))
            let db = spectrum[max(0, min(spectrum.count - 1, binIdx))]
            let energy = max(0, min(1, (db + 55) / 55))

            let p = poolPoint(center: center, radius: r, angleDeg: deg)
            let coreSize: CGFloat = 1.0 + CGFloat(energy) * 2.4
            let rect = CGRect(x: p.x - coreSize, y: p.y - coreSize, width: coreSize * 2, height: coreSize * 2)

            var halo = ctx
            halo.addFilter(.blur(radius: 2.5))
            halo.fill(Path(ellipseIn: rect.insetBy(dx: -coreSize, dy: -coreSize)),
                      with: .color(palette.particleHalo.opacity(0.35 + Double(energy) * 0.3)))
            ctx.fill(Path(ellipseIn: rect),
                     with: .color(palette.particleCore.opacity(0.7 * (0.3 + t))))
        }
    }

    private func drawTidePoolHandles(ctx: GraphicsContext, center: CGPoint, outerR: CGFloat,
                                     bands: [DemoBand], palette: SkinPalette) {
        let rim = outerR * 0.88
        for band in bands {
            let deg = poolAngleForFreq(band.frequency)
            let bulbR = rim + CGFloat(band.gain / 18) * outerR * 0.08
            let bulb = poolPoint(center: center, radius: bulbR, angleDeg: deg)
            let ringP = poolPoint(center: center, radius: rim, angleDeg: deg)

            var stalk = Path()
            stalk.move(to: ringP)
            stalk.addLine(to: bulb)
            ctx.stroke(stalk, with: .color(palette.handleStalk.opacity(0.8)),
                       style: StrokeStyle(lineWidth: 1.0))

            let tint = band.gain >= 0 ? palette.bandBoost : palette.bandCut
            let bulbSize: CGFloat = 7 + CGFloat(abs(band.gain) / 24) * 4
            // Lily-pad: ellipse with the pool's perspective
            let rect = CGRect(x: bulb.x - bulbSize / 2, y: bulb.y - bulbSize / 2 * Self.poolYScale,
                              width: bulbSize, height: bulbSize * Self.poolYScale)
            var glow = ctx
            glow.addFilter(.blur(radius: 5))
            glow.fill(Path(ellipseIn: rect.insetBy(dx: -bulbSize * 0.8, dy: -bulbSize * 0.8)),
                      with: .color(tint.opacity(0.6)))
            ctx.fill(Path(ellipseIn: rect), with: .color(tint))
            ctx.fill(Path(ellipseIn: rect.insetBy(dx: bulbSize * 0.3, dy: bulbSize * 0.3 * Self.poolYScale)),
                     with: .color(palette.handleBulb))
        }
    }

    // MARK: - Stacked Octaves layout
    // Ten concentric full-circle rings, one per octave.

    private static let octaveCount = 10

    private func octaveForFreq(_ hz: Float) -> Int {
        let t = log2(max(hz, 20) / 20) / log2(20000 / 20)
        return max(0, min(Self.octaveCount - 1, Int(t * Float(Self.octaveCount))))
    }

    private func octaveCenter(_ idx: Int) -> Float {
        let t = (Float(idx) + 0.5) / Float(Self.octaveCount)
        return 20 * pow(Float(20000 / 20), t)
    }

    /// Map a frequency to its angular position *within* its octave ring (0..360°).
    private func angleInOctave(_ hz: Float) -> Double {
        let idx = octaveForFreq(hz)
        let lo = 20.0 * pow(20000.0 / 20.0, Double(idx) / Double(Self.octaveCount))
        let hi = 20.0 * pow(20000.0 / 20.0, Double(idx + 1) / Double(Self.octaveCount))
        let t = log(Double(hz) / lo) / log(hi / lo)
        return max(0, min(1, t)) * 360
    }

    private func stackedRingRadius(_ idx: Int, outerR: CGFloat) -> CGFloat {
        let innerR = outerR * 0.30
        let range = outerR * 0.65 - innerR
        return innerR + CGFloat(idx) / CGFloat(Self.octaveCount - 1) * range
    }

    private func drawStackedOctaves(ctx: GraphicsContext, center: CGPoint, outerR: CGFloat,
                                    spectrum: [Float], bands: [DemoBand],
                                    palette: SkinPalette, time: TimeInterval) {
        // Per-octave energy
        var octEnergy = [Double](repeating: 0, count: Self.octaveCount)
        let binsPerOct = spectrum.count / Self.octaveCount
        for oct in 0..<Self.octaveCount {
            let start = oct * binsPerOct
            let end = min(spectrum.count, start + binsPerOct)
            var peak: Float = -120
            for i in start..<end { peak = max(peak, spectrum[i]) }
            octEnergy[oct] = max(0, min(1, Double((peak + 60) / 60)))
        }

        for oct in 0..<Self.octaveCount {
            let r = stackedRingRadius(oct, outerR: outerR)
            let energy = octEnergy[oct]
            let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)

            // Base ring
            ctx.stroke(Path(ellipseIn: rect),
                       with: .color(palette.ringBase.opacity(0.45)),
                       style: StrokeStyle(lineWidth: 0.6))

            // Energy glow — thickness + alpha scale with energy
            var glow = ctx
            glow.addFilter(.blur(radius: 3 + CGFloat(energy) * 4))
            glow.stroke(Path(ellipseIn: rect),
                        with: .color(palette.ringGlow.opacity(0.18 + energy * 0.5)),
                        style: StrokeStyle(lineWidth: 1.0 + CGFloat(energy) * 2.8))

            // Tick marks at octave center frequencies (text for low octaves)
            let freqLabel = octaveCenter(oct)
            let labelAngle: Double = 200 + Double(oct) * 2    // staggered down the left
            let labelPoint = RadialMath.point(center: center, radius: r + 10, angleDeg: labelAngle)
            let label = Text(EtherFormat.frequency(freqLabel))
                .font(.system(size: 7, weight: .regular, design: palette.hudFontDesign))
                .foregroundColor(palette.hudDim)
            ctx.draw(label, at: labelPoint, anchor: .leading)

            // Band indicator arcs — if a band lives on this ring, draw a glowing arc span
            for band in bands where octaveForFreq(band.frequency) == oct {
                let centerDeg = angleInOctave(band.frequency)
                let span = 60.0 / Double(band.q)           // Q=1 → 60°, Q=2 → 30°
                var arc = Path()
                arc.addArc(center: center, radius: r,
                           startAngle: .degrees(centerDeg - span / 2 - 90),
                           endAngle:   .degrees(centerDeg + span / 2 - 90),
                           clockwise: false)
                let tint = band.gain >= 0 ? palette.bandBoost : palette.bandCut
                var arcGlow = ctx
                arcGlow.addFilter(.blur(radius: 5))
                arcGlow.stroke(arc, with: .color(tint.opacity(0.55 * Double(abs(band.gain) / 18))),
                               style: StrokeStyle(lineWidth: 3 + CGFloat(abs(band.gain) / 18) * 4, lineCap: .round))
                ctx.stroke(arc, with: .color(tint.opacity(0.85)),
                           style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
            }
        }
    }

    private func drawStackedHandles(ctx: GraphicsContext, center: CGPoint, outerR: CGFloat,
                                    bands: [DemoBand], palette: SkinPalette) {
        for band in bands {
            let oct = octaveForFreq(band.frequency)
            let r = stackedRingRadius(oct, outerR: outerR)
            let deg = angleInOctave(band.frequency) - 90   // addArc convention → top
            // Convert "math angle" (counterclockwise from 3 o'clock) to our top-clockwise convention
            let drawDeg = deg + 90
            let bulb = RadialMath.point(center: center, radius: r, angleDeg: drawDeg)
            let tint = band.gain >= 0 ? palette.bandBoost : palette.bandCut
            let bulbSize: CGFloat = 7 + CGFloat(abs(band.gain) / 24) * 4
            let rect = CGRect(x: bulb.x - bulbSize / 2, y: bulb.y - bulbSize / 2,
                              width: bulbSize, height: bulbSize)
            var glow = ctx
            glow.addFilter(.blur(radius: 5))
            glow.fill(Path(ellipseIn: rect.insetBy(dx: -bulbSize, dy: -bulbSize)),
                      with: .color(tint.opacity(0.6)))
            ctx.fill(Path(ellipseIn: rect), with: .color(tint))
            ctx.fill(Path(ellipseIn: rect.insetBy(dx: bulbSize * 0.3, dy: bulbSize * 0.3)),
                     with: .color(palette.handleBulb))
        }
    }

    // MARK: - Field layout
    // A 2D plane: X = frequency (log), Y = stereo field (top=L, bottom=R).
    // Paint gain blooms directly onto the plane. No ring, no radial anything.

    private static let fieldMarginX: CGFloat = 48
    private static let fieldMarginY: CGFloat = 36

    private func fieldRect(in size: CGSize) -> CGRect {
        CGRect(x: Self.fieldMarginX, y: Self.fieldMarginY,
               width: size.width - Self.fieldMarginX * 2,
               height: size.height - Self.fieldMarginY * 2 - 40)
    }
    private func fieldX(freq: Float, in rect: CGRect) -> CGFloat {
        let t = log10(max(freq, 20) / 20) / log10(20000 / 20)
        return rect.minX + CGFloat(t) * rect.width
    }
    private func fieldFreq(x: CGFloat, in rect: CGRect) -> Float {
        let t = max(0, min(1, (x - rect.minX) / rect.width))
        return 20 * pow(Float(20000 / 20), Float(t))
    }
    private func fieldY(stereo: Float, in rect: CGRect) -> CGFloat {
        rect.minY + CGFloat((stereo + 1) / 2) * rect.height
    }
    private func fieldStereo(y: CGFloat, in rect: CGRect) -> Float {
        let t = max(0, min(1, (y - rect.minY) / rect.height))
        return Float(t) * 2 - 1
    }

    private func drawField(ctx: GraphicsContext, size: CGSize, spectrum: [Float],
                           bands: [DemoBand], palette: SkinPalette, time: TimeInterval) {
        let rect = fieldRect(in: size)

        // Plate with subtle top/bottom darkening (so extremes of the stereo field pull the eye)
        let plateGrad = Gradient(colors: [palette.ringBase.opacity(0.18),
                                          palette.background.opacity(0),
                                          palette.ringBase.opacity(0.18)])
        ctx.fill(Path(rect),
                 with: .linearGradient(plateGrad,
                                       startPoint: CGPoint(x: rect.midX, y: rect.minY),
                                       endPoint: CGPoint(x: rect.midX, y: rect.maxY)))

        // Stereo horizon lines + L/MONO/R labels
        for (label, stereo) in [("L", Float(-1)), ("MONO", Float(0)), ("R", Float(1))] {
            let y = fieldY(stereo: stereo, in: rect)
            var line = Path()
            line.move(to: CGPoint(x: rect.minX, y: y))
            line.addLine(to: CGPoint(x: rect.maxX, y: y))
            ctx.stroke(line, with: .color(palette.hudDim.opacity(stereo == 0 ? 0.5 : 0.22)),
                       style: StrokeStyle(lineWidth: stereo == 0 ? 0.8 : 0.5,
                                          dash: stereo == 0 ? [] : [2, 4]))
            let t = Text(label)
                .font(.system(size: 8, weight: .regular, design: palette.hudFontDesign))
                .tracking(1.4)
                .foregroundColor(palette.hudDim)
            ctx.draw(t, at: CGPoint(x: rect.minX - 18, y: y), anchor: .center)
        }

        // Frequency grid (log decades)
        for freq: Float in [20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000] {
            let x = fieldX(freq: freq, in: rect)
            var line = Path()
            line.move(to: CGPoint(x: x, y: rect.minY))
            line.addLine(to: CGPoint(x: x, y: rect.maxY))
            ctx.stroke(line, with: .color(palette.hudDim.opacity(0.15)),
                       style: StrokeStyle(lineWidth: 0.5))
            let label = Text(EtherFormat.frequency(freq))
                .font(.system(size: 7, weight: .regular, design: palette.hudFontDesign))
                .foregroundColor(palette.hudDim)
            ctx.draw(label, at: CGPoint(x: x, y: rect.maxY + 10), anchor: .top)
        }

        // Live spectrum energy as vertical fans radiating from the MONO line
        drawFieldSpectrum(ctx: ctx, rect: rect, spectrum: spectrum, palette: palette, time: time)

        // The blooms
        drawFieldBlooms(ctx: ctx, rect: rect, bands: bands, palette: palette, time: time)

        // Interference stress marks where blooms overlap
        drawFieldInterference(ctx: ctx, rect: rect, bands: bands, palette: palette, time: time)

        // Footer readout
        drawFieldHUD(ctx: ctx, size: size, rect: rect, bands: bands, palette: palette)
    }

    private func drawFieldSpectrum(ctx: GraphicsContext, rect: CGRect, spectrum: [Float],
                                   palette: SkinPalette, time: TimeInterval) {
        guard !spectrum.isEmpty else { return }
        let monoY = fieldY(stereo: 0, in: rect)
        let fanHeight = rect.height * 0.42
        let bars = 160
        let step = rect.width / CGFloat(bars - 1)
        for i in 0..<bars {
            let srcIdx = i * spectrum.count / bars
            let db = spectrum[srcIdx]
            let energy = max(0, min(1, (db + 55) / 55))
            let x = rect.minX + CGFloat(i) * step
            let h = fanHeight * CGFloat(energy)
            let upRect = CGRect(x: x - step * 0.45, y: monoY - h, width: step * 0.9, height: h)
            let dnRect = CGRect(x: x - step * 0.45, y: monoY, width: step * 0.9, height: h)
            let fanGrad = Gradient(colors: [palette.traceMid.opacity(0.55 * Double(energy)),
                                            palette.traceMid.opacity(0)])
            ctx.fill(Path(upRect),
                     with: .linearGradient(fanGrad,
                                           startPoint: CGPoint(x: upRect.midX, y: upRect.maxY),
                                           endPoint: CGPoint(x: upRect.midX, y: upRect.minY)))
            ctx.fill(Path(dnRect),
                     with: .linearGradient(fanGrad,
                                           startPoint: CGPoint(x: dnRect.midX, y: dnRect.minY),
                                           endPoint: CGPoint(x: dnRect.midX, y: dnRect.maxY)))
        }
    }

    private func drawFieldBlooms(ctx: GraphicsContext, rect: CGRect, bands: [DemoBand],
                                 palette: SkinPalette, time: TimeInterval) {
        for band in bands {
            let cx = fieldX(freq: band.frequency, in: rect)
            let cy = fieldY(stereo: band.stereo, in: rect)
            let intensity = Double(abs(band.gain) / 18)
            if intensity < 0.01 {
                ctx.fill(Path(ellipseIn: CGRect(x: cx - 3, y: cy - 3, width: 6, height: 6)),
                         with: .color(palette.hudDim.opacity(0.8)))
                continue
            }
            let rx = CGFloat(28 + intensity * 100) / CGFloat(max(0.7, Double(band.q)))
            let ry = CGFloat(18 + intensity * 80) / CGFloat(max(0.7, Double(band.q)))
            let pulse = 1.0 + 0.05 * sin(time * 1.8 + Double(band.id.hashValue % 100))
            let bRect = CGRect(x: cx - rx * CGFloat(pulse),
                               y: cy - ry * CGFloat(pulse),
                               width: rx * 2 * CGFloat(pulse),
                               height: ry * 2 * CGFloat(pulse))

            let tint = band.gain >= 0 ? palette.bandBoost : palette.bandCut
            let grad: Gradient
            if band.gain >= 0 {
                grad = Gradient(colors: [tint.opacity(0.75 * intensity),
                                         tint.opacity(0.25 * intensity),
                                         .clear])
            } else {
                grad = Gradient(colors: [palette.background.opacity(0.85 * intensity),
                                         tint.opacity(0.35 * intensity),
                                         .clear])
            }
            var glow = ctx
            glow.addFilter(.blur(radius: 8))
            glow.fill(Path(ellipseIn: bRect),
                      with: .radialGradient(grad,
                                            center: CGPoint(x: cx, y: cy),
                                            startRadius: 0,
                                            endRadius: max(rx, ry)))

            let pinSize: CGFloat = 4 + CGFloat(intensity) * 3
            let pinRect = CGRect(x: cx - pinSize / 2, y: cy - pinSize / 2,
                                 width: pinSize, height: pinSize)
            ctx.fill(Path(ellipseIn: pinRect), with: .color(palette.handleBulb))
            if band.gain < -0.5 {
                let rimRect = bRect.insetBy(dx: rx * 0.1, dy: ry * 0.1)
                ctx.stroke(Path(ellipseIn: rimRect),
                           with: .color(tint.opacity(0.9 * intensity)),
                           style: StrokeStyle(lineWidth: 0.8, dash: [2, 3]))
            }
        }
    }

    private func drawFieldInterference(ctx: GraphicsContext, rect: CGRect, bands: [DemoBand],
                                       palette: SkinPalette, time: TimeInterval) {
        guard bands.count >= 2 else { return }
        for i in 0..<bands.count {
            for j in (i + 1)..<bands.count {
                let a = bands[i], b = bands[j]
                let ax = fieldX(freq: a.frequency, in: rect), ay = fieldY(stereo: a.stereo, in: rect)
                let bx = fieldX(freq: b.frequency, in: rect), by = fieldY(stereo: b.stereo, in: rect)
                let dist = hypot(ax - bx, ay - by)
                let aR = 28 + Double(abs(a.gain) / 18) * 100 / max(0.7, Double(a.q))
                let bR = 28 + Double(abs(b.gain) / 18) * 100 / max(0.7, Double(b.q))
                let overlap = (aR + bR) - Double(dist)
                guard overlap > 0 else { continue }
                let midX = (ax + bx) / 2, midY = (ay + by) / 2
                let ux = (bx - ax) / CGFloat(max(1, dist))
                let uy = (by - ay) / CGFloat(max(1, dist))
                let spanLen = min(40, overlap * 0.7)
                var line = Path()
                line.move(to: CGPoint(x: midX - ux * CGFloat(spanLen),
                                      y: midY - uy * CGFloat(spanLen)))
                line.addLine(to: CGPoint(x: midX + ux * CGFloat(spanLen),
                                         y: midY + uy * CGFloat(spanLen)))
                let flicker = 0.6 + 0.4 * sin(time * 6 + Double(i * j))
                ctx.stroke(line,
                           with: .color(palette.bandCut.opacity(min(0.85, overlap / 120) * flicker)),
                           style: StrokeStyle(lineWidth: 0.8, dash: [1.5, 2.5]))
            }
        }
    }

    private func drawFieldHUD(ctx: GraphicsContext, size: CGSize, rect: CGRect,
                              bands: [DemoBand], palette: SkinPalette) {
        let active = bands.max(by: { abs($0.gain) < abs($1.gain) })
        let hudY = rect.maxY + 28
        let primary: String
        let secondary: String
        if let a = active, abs(a.gain) > 0.05 {
            let panLabel: String
            if abs(a.stereo) < 0.08 { panLabel = "C" }
            else if a.stereo < 0 { panLabel = String(format: "L%.0f", abs(a.stereo) * 100) }
            else { panLabel = String(format: "R%.0f", a.stereo * 100) }
            primary = EtherFormat.frequency(a.frequency) + "   " + EtherFormat.gain(a.gain) + "   " + panLabel
            secondary = "Q " + EtherFormat.q(a.q) + "   ·   FIELD"
        } else {
            primary = "ETHER · FIELD"
            secondary = "CLICK TO PAINT · DRAG UP = BOOST · DRAG DOWN = CUT"
        }
        ctx.draw(Text(primary)
                    .font(.system(size: 13, weight: .semibold, design: palette.hudFontDesign))
                    .foregroundColor(palette.hudText),
                 at: CGPoint(x: size.width / 2, y: hudY), anchor: .center)
        ctx.draw(Text(secondary)
                    .font(.system(size: 8, weight: .regular, design: palette.hudFontDesign))
                    .tracking(1.8)
                    .foregroundColor(palette.hudDim),
                 at: CGPoint(x: size.width / 2, y: hudY + 14), anchor: .center)
    }

    private func drawScanlines(ctx: GraphicsContext, size: CGSize, palette: SkinPalette) {
        var path = Path()
        var y: CGFloat = 0
        while y < size.height {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            y += 3
        }
        ctx.stroke(path, with: .color(.black.opacity(0.18)), style: StrokeStyle(lineWidth: 1))
    }

    // MARK: Gesture

    private func dragGesture(geo: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let size = geo.size
                let side = min(size.width, size.height) - 40
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let outerR = side / 2

                if draggingBandID == nil {
                    if let hit = hitTest(loc: value.location, center: center, outerR: outerR, size: size) {
                        draggingBandID = hit
                        if layout == .field { fieldDragAnchor = value.location }
                    } else if layout == .field {
                        let rect = fieldRect(in: size)
                        guard rect.insetBy(dx: -20, dy: -20).contains(value.location) else { return }
                        let freq = fieldFreq(x: max(rect.minX, min(rect.maxX, value.location.x)), in: rect)
                        let stereo = fieldStereo(y: max(rect.minY, min(rect.maxY, value.location.y)), in: rect)
                        let newBand = DemoBand(frequency: freq, gain: 0, q: 1.1, stereo: stereo)
                        bands.append(newBand)
                        draggingBandID = newBand.id
                        fieldDragAnchor = value.location
                    }
                }
                guard let id = draggingBandID,
                      let idx = bands.firstIndex(where: { $0.id == id }) else { return }

                switch layout {
                case .ring:
                    let unityR = outerR * 0.70
                    let deg = RadialMath.angleForPoint(value.location, center: center)
                    let rFromCenter = hypot(value.location.x - center.x, value.location.y - center.y)
                    let delta = (rFromCenter - unityR) / (unityR * 0.28)
                    bands[idx].gain = max(-18, min(18, Float(delta) * 18))
                    bands[idx].frequency = RadialMath.freqForAngle(deg)

                case .helix:
                    let outerRingR = outerR * 0.95
                    let innerRingR = outerR * 0.70
                    let deg = RadialMath.angleForPoint(value.location, center: center)
                    let rFromCenter = hypot(value.location.x - center.x, value.location.y - center.y)
                    let t = (rFromCenter - innerRingR) / (outerRingR - innerRingR)
                    let clamped = max(0, min(1, t))
                    bands[idx].gain = max(-18, min(18, Float(clamped - 0.5) * 36))
                    bands[idx].frequency = RadialMath.freqForAngle(deg)

                case .tidePool:
                    let dx = value.location.x - center.x
                    let dy = (value.location.y - center.y) / Self.poolYScale
                    var deg = atan2(Double(dx), -Double(dy)) * 180 / .pi
                    if deg < 0 { deg += 360 }
                    let rim = outerR * 0.88
                    let rNorm = hypot(dx, dy)
                    let delta = (rNorm - rim) / (outerR * 0.08)
                    bands[idx].gain = max(-18, min(18, Float(delta) * 18))
                    bands[idx].frequency = poolFreqForAngle(deg)

                case .field:
                    let rect = fieldRect(in: size)
                    let anchor = fieldDragAnchor ?? value.location
                    // Anchor defines the bloom position (freq + stereo). Vertical drag
                    // away from the anchor sets gain; horizontal drag tightens Q.
                    bands[idx].frequency = fieldFreq(x: max(rect.minX, min(rect.maxX, anchor.x)), in: rect)
                    bands[idx].stereo = fieldStereo(y: max(rect.minY, min(rect.maxY, anchor.y)), in: rect)
                    let dy = Float(anchor.y - value.location.y)        // up = positive
                    let dx = Float(abs(value.location.x - anchor.x))
                    bands[idx].gain = max(-18, min(18, dy / Float(rect.height) * 36))
                    bands[idx].q = max(0.6, min(4.0, 1.0 + dx / Float(rect.width) * 4.0))

                case .stacked:
                    let rFromCenter = hypot(value.location.x - center.x, value.location.y - center.y)
                    var bestOct = 0
                    var bestDist = CGFloat.greatestFiniteMagnitude
                    for oct in 0..<Self.octaveCount {
                        let r = stackedRingRadius(oct, outerR: outerR)
                        let d = abs(r - rFromCenter)
                        if d < bestDist { bestDist = d; bestOct = oct }
                    }
                    let dx = Double(value.location.x - center.x)
                    let dy = Double(value.location.y - center.y)
                    var deg = atan2(dx, -dy) * 180 / .pi
                    if deg < 0 { deg += 360 }
                    let lo = 20.0 * pow(20000.0 / 20.0, Double(bestOct) / Double(Self.octaveCount))
                    let hi = 20.0 * pow(20000.0 / 20.0, Double(bestOct + 1) / Double(Self.octaveCount))
                    let t = deg / 360
                    bands[idx].frequency = Float(lo * pow(hi / lo, t))
                    // In stacked, radial position is ring-pick, not gain. Keep gain stable.
                }
                idleSince = .now
            }
            .onEnded { _ in
                draggingBandID = nil
                fieldDragAnchor = nil
            }
    }

    private func hitTest(loc: CGPoint, center: CGPoint, outerR: CGFloat, size: CGSize) -> UUID? {
        var best: (id: UUID, dist: CGFloat)?
        for band in bands {
            let p: CGPoint
            switch layout {
            case .ring:
                let unityR = outerR * 0.70
                let deg = RadialMath.angleForFreq(band.frequency)
                let bulbR = unityR + CGFloat(band.gain / 18) * unityR * 0.28 + unityR * 0.06
                p = RadialMath.point(center: center, radius: bulbR, angleDeg: deg)
            case .helix:
                let outerRingR = outerR * 0.95
                let innerRingR = outerR * 0.70
                let deg = RadialMath.angleForFreq(band.frequency)
                let t = Double(band.gain / 18) * 0.45 + 0.5
                let bulbR = innerRingR + CGFloat(t) * (outerRingR - innerRingR)
                p = RadialMath.point(center: center, radius: bulbR, angleDeg: deg)
            case .tidePool:
                let rim = outerR * 0.88
                let deg = poolAngleForFreq(band.frequency)
                let bulbR = rim + CGFloat(band.gain / 18) * outerR * 0.08
                p = poolPoint(center: center, radius: bulbR, angleDeg: deg)
            case .stacked:
                let oct = octaveForFreq(band.frequency)
                let r = stackedRingRadius(oct, outerR: outerR)
                let deg = angleInOctave(band.frequency)
                p = RadialMath.point(center: center, radius: r, angleDeg: deg)
            case .field:
                let rect = fieldRect(in: size)
                p = CGPoint(x: fieldX(freq: band.frequency, in: rect),
                            y: fieldY(stereo: band.stereo, in: rect))
            }
            let d = hypot(p.x - loc.x, p.y - loc.y)
            if d < 32, d < (best?.dist ?? .greatestFiniteMagnitude) {
                best = (band.id, d)
            }
        }
        return best?.id
    }

    private func fract(_ x: Double) -> Double { x - floor(x) }
}
