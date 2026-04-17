import SwiftUI

// MARK: - Mini Player Visualizer

private struct FloatParticle {
    var x, y: Double
    var vx, vy: Double
    var phase: Double
    var spin: Double      // +1 CCW, -1 CW — fixed at birth
    var colorMix: Double  // 0 = tint, 1 = tint2
}

private let kickBinLo = 20
private let kickBinHi = 72

struct MiniVisualizerView: View {
    @ObservedObject var analyzer: SpectrumAnalyzer
    var tint: Color
    var tint2: Color
    var isFullScreen: Bool = false

    private static let segs = 64

    @State private var env0 = [Float](repeating: 0, count: 64)
    @State private var env1 = [Float](repeating: 0, count: 64)
    @State private var bassEnergy: Double = 0
    @State private var kickFast: Double = 0
    @State private var rotation: Double = 0
    @State private var breathPhase: Double = 0
    @State private var particles: [FloatParticle] = MiniVisualizerView.makeParticles()
    @State private var renderTint: Color = .white
    @State private var renderTint2: Color = .white

    private static func makeParticles() -> [FloatParticle] {
        (0..<42).map { _ in
            let angle = Double.random(in: 0..<(.pi * 2))
            let r = Double.random(in: 0.01...0.12)
            return FloatParticle(
                x: cos(angle) * r, y: sin(angle) * r,
                vx: Double.random(in: -0.003...0.003),
                vy: Double.random(in: -0.003...0.003),
                phase: Double.random(in: 0..<(.pi * 2)),
                spin: Bool.random() ? 1.0 : -1.0,
                colorMix: Double.random(in: 0...1)
            )
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !analyzer.isActive)) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let w = size.width, h = size.height
                let cx = w / 2, cy = isFullScreen ? h / 2 : w * 0.44
                let half = min(w, h) / 2
                let maxR = half * 0.84
                let segs = Self.segs
                let outerActivity = Double(env1.max() ?? 0)

                // — Background: deep black + bass atmosphere —
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
                var atmo = ctx
                atmo.addFilter(.blur(radius: 45))
                atmo.fill(
                    Path(CGRect(origin: .zero, size: size)),
                    with: .radialGradient(
                        Gradient(stops: [
                            .init(color: renderTint.opacity(0.07 + bassEnergy * 0.10), location: 0),
                            .init(color: renderTint2.opacity(0.03 + bassEnergy * 0.05), location: 0.5),
                            .init(color: .clear, location: 1.0),
                        ]),
                        center: CGPoint(x: cx, y: cy),
                        startRadius: 0, endRadius: max(w, h) * 0.65
                    )
                )

                // — Border glow: inward from edges, driven by bass + kick —
                var borderGlow = ctx
                borderGlow.addFilter(.blur(radius: 18))
                borderGlow.stroke(
                    Path(CGRect(origin: .zero, size: size)),
                    with: .color(renderTint.opacity(0.06 + bassEnergy * 0.10 + kickFast * 0.08)),
                    lineWidth: 28
                )

                // — Rings: outer first, inner on top — both tint —
                for ringIdx in [1, 0] {
                    let envData = ringIdx == 0 ? env0 : env1
                    let baseR = maxR * (ringIdx == 0 ? 0.54 : 0.86)
                    let rot = rotation * (ringIdx == 0 ? 1.0 : -0.65)
                    let cosR = cos(rot), sinR = sin(rot)
                    let breathe = sin(breathPhase + Double(ringIdx) * 1.3) * baseR * 0.018

                    var pts = [CGPoint](repeating: .zero, count: segs)
                    for s in 0..<segs {
                        let t = Double(s) / Double(segs)
                        // Power curve: quiet regions sink toward baseline, active peaks stay prominent
                        let mag = pow(Double(envData[s]), 1.35)
                        let expansion = ringIdx == 0 ? bassEnergy * baseR * 0.06 : 0
                        let r = baseR + breathe + mag * baseR * (ringIdx == 0 ? 0.58 : 0.40) + expansion
                        let angle = t * .pi * 2
                        let ux = cos(angle), uy = sin(angle)
                        let rx = ux * cosR - uy * sinR
                        let ry = ux * sinR + uy * cosR
                        pts[s] = CGPoint(x: cx + CGFloat(rx * r), y: cy + CGFloat(ry * r))
                    }

                    let startMid = CGPoint(x: (pts[segs-1].x + pts[0].x) / 2,
                                           y: (pts[segs-1].y + pts[0].y) / 2)
                    var path = Path()
                    path.move(to: startMid)
                    for i in 0..<segs {
                        let curr = pts[i], next = pts[(i + 1) % segs]
                        path.addQuadCurve(
                            to: CGPoint(x: (curr.x + next.x) / 2, y: (curr.y + next.y) / 2),
                            control: curr
                        )
                    }
                    path.closeSubpath()

                    if ringIdx == 1 {
                        var fog = ctx
                        fog.addFilter(.blur(radius: 38))
                        fog.stroke(path, with: .color(renderTint.opacity(0.12 + kickFast * 0.08 + outerActivity * 0.14)), lineWidth: 20)
                        var soft = ctx
                        soft.addFilter(.blur(radius: 7))
                        soft.stroke(path, with: .color(renderTint.opacity(0.26 + kickFast * 0.10 + outerActivity * 0.18)), lineWidth: 3)
                        ctx.stroke(path, with: .color(renderTint.opacity(0.38 + kickFast * 0.08 + outerActivity * 0.10)), lineWidth: 0.75)
                    } else {
                        var halo = ctx
                        halo.addFilter(.blur(radius: 16))
                        halo.stroke(path, with: .color(renderTint.opacity(0.32 + kickFast * 0.18)), lineWidth: 10)
                        var edge = ctx
                        edge.addFilter(.blur(radius: 4))
                        edge.stroke(path, with: .color(renderTint.opacity(0.58 + kickFast * 0.20)), lineWidth: 3)
                        ctx.stroke(path, with: .color(renderTint.opacity(0.84 + kickFast * 0.12)), lineWidth: 2.0)
                    }
                }

                // — Particles: glow pass then sharp core, both driven by per-particle energy —
                var glowCtx = ctx
                glowCtx.addFilter(.blur(radius: 1.5))
                for p in particles {
                    let speed = sqrt(p.vx * p.vx + p.vy * p.vy)
                    let energy = min(1.0, speed * 25.0 + kickFast * 0.35)
                    let glowOp = energy * 0.26
                    guard glowOp > 0.02 else { continue }
                    let px = cx + CGFloat(p.x) * half
                    let py = cy + CGFloat(p.y) * half
                    let pMass = 0.80 + (1.0 - p.colorMix) * 0.82
                    let szBase = 0.5 + pMass * 0.55 + sin(p.phase) * 0.18 + bassEnergy * 0.35
                    let glowSz = CGFloat(szBase) * 2.2
                    glowCtx.fill(
                        Path(ellipseIn: CGRect(x: px - glowSz/2, y: py - glowSz/2, width: glowSz, height: glowSz)),
                        with: .color((p.colorMix < 0.5 ? renderTint : renderTint2).opacity(glowOp))
                    )
                }

                for p in particles {
                    let speed = sqrt(p.vx * p.vx + p.vy * p.vy)
                    let energy = min(1.0, speed * 25.0 + kickFast * 0.35)
                    let brightness = 0.50 + energy * 0.30
                    let px = cx + CGFloat(p.x) * half
                    let py = cy + CGFloat(p.y) * half
                    let pMass = 0.80 + (1.0 - p.colorMix) * 0.82
                    let szBase = 0.5 + pMass * 0.55 + sin(p.phase) * 0.18 + bassEnergy * 0.35
                    let sz = CGFloat(szBase)
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: px - sz/2, y: py - sz/2, width: sz, height: sz)),
                        with: .color((p.colorMix < 0.5 ? renderTint : renderTint2).opacity(brightness))
                    )
                }

                // — Center orb: purely soft, no hard edges anywhere —
                let cr = CGFloat(half) * CGFloat(0.070 + bassEnergy * 0.040 + kickFast * 0.095)

                func orb(_ radius: CGFloat) -> Path {
                    Path(ellipseIn: CGRect(x: cx - radius, y: cy - radius,
                                           width: radius * 2, height: radius * 2))
                }

                var g4 = ctx; g4.addFilter(.blur(radius: 30))
                g4.fill(orb(cr * 4.2), with: .color(renderTint.opacity(0.18 + kickFast * 0.22)))

                var g3 = ctx; g3.addFilter(.blur(radius: 14))
                g3.fill(orb(cr * 2.4), with: .color(renderTint.opacity(0.42 + kickFast * 0.20)))

                var g2 = ctx; g2.addFilter(.blur(radius: 5))
                g2.fill(orb(cr * 1.3), with: .color(renderTint.opacity(0.70 + kickFast * 0.15)))

                var g1 = ctx; g1.addFilter(.blur(radius: 2))
                g1.fill(orb(cr * 0.48), with: .color(.white.opacity(0.78 + kickFast * 0.22)))
            }
            .drawingGroup()
            .onChange(of: now) { _, _ in
                let bins = analyzer.magnitudes
                guard bins.count > kickBinHi else { return }

                rotation += 0.007
                breathPhase += 0.006

                // Adaptive decay: fast when active, slow toward silence
                var next0 = env0, next1 = env1
                for s in 0..<Self.segs {
                    let frac = Double(s) / Double(Self.segs)
                    let binIdx = min(bins.count - 1, Int(frac * Double(bins.count) * 0.78))
                    let raw = Float(max(0, min(1, (Double(bins[binIdx]) + 60) / 55)))
                    if raw >= next0[s] {
                        next0[s] = raw; next1[s] = raw
                    } else {
                        let d0 = 0.36 + (1.0 - raw) * 0.46
                        let d1 = 0.46 + (1.0 - raw) * 0.36
                        next0[s] = next0[s] * d0 + raw * (1.0 - d0)
                        next1[s] = next1[s] * d1 + raw * (1.0 - d1)
                    }
                }
                for _ in 0..<3 {
                    var s0 = next0, s1 = next1
                    for i in 0..<Self.segs {
                        let p = (i - 1 + Self.segs) % Self.segs
                        let n = (i + 1) % Self.segs
                        s0[i] = next0[p] * 0.25 + next0[i] * 0.5 + next0[n] * 0.25
                        s1[i] = next1[p] * 0.25 + next1[i] * 0.5 + next1[n] * 0.25
                    }
                    next0 = s0; next1 = s1
                }
                env0 = next0; env1 = next1

                let bassSlice = bins[0..<min(85, bins.count)]
                let bassAvg = Double(bassSlice.reduce(0, +)) / Double(bassSlice.count)
                let bassMag = max(0.0, min(1.0, (bassAvg + 62) / 42))
                bassEnergy = bassEnergy * (0.80 + (1.0 - bassMag) * 0.14) + bassMag * (0.20 - (1.0 - bassMag) * 0.14)

                let kickPeakDB = Double(bins[kickBinLo..<kickBinHi].max() ?? -80)
                kickFast = kickFast * 0.28 + max(0.0, min(1.0, (kickPeakDB + 52) / 38)) * 0.72

                // Particle physics
                let innerRingPeak = Double(env0.max() ?? 0)
                for i in particles.indices {
                    let dist = max(0.001, (particles[i].x * particles[i].x + particles[i].y * particles[i].y).squareRoot())
                    let nx = particles[i].x / dist
                    let ny = particles[i].y / dist

                    // Orange (colorMix<0.5) = heavy, teal = lighter but still substantial
                    let massVar = 0.80 + (1.0 - particles[i].colorMix) * 0.82  // 0.80–1.62
                    // Gravity: steeper pull when bass drops so particles sink faster to silence
                    // Asymmetric gravity: normal pull when moving outward, gentle drift back when returning
                    let radV = particles[i].vx * nx + particles[i].vy * ny
                    let gravityStr = radV > 0
                        ? (0.0055 + (1.0 - bassEnergy) * 0.0095) * massVar
                        : (0.0018 + (1.0 - bassEnergy) * 0.0030) * massVar
                    particles[i].vx -= nx * gravityStr * dist
                    particles[i].vy -= ny * gravityStr * dist

                    // Orbital force — slowed down, per-particle speed variance from colorMix
                    let orbEnergy = max(0, bassEnergy - 0.10)
                    let orbSpeed = 0.25 + particles[i].colorMix * 0.75  // 0.25–1.0x, fixed at birth
                    let orbProfile = (0.00015 + orbEnergy * 0.0016 * min(1.0, dist * 1.8)) * orbSpeed
                    let orbOffset = (particles[i].colorMix - 0.5) * 0.45
                    let tangX = -ny * cos(orbOffset) - nx * sin(orbOffset)
                    let tangY =  nx * cos(orbOffset) - ny * sin(orbOffset)
                    particles[i].vx += tangX * orbProfile * particles[i].spin
                    particles[i].vy += tangY * orbProfile * particles[i].spin

                    // Inner ring collision: particles near the inner ring get scattered outward
                    let innerR = 0.48
                    if dist > innerR - 0.10 && dist < innerR + 0.16 {
                        let proximity = 1.0 - abs(dist - innerR) / 0.16
                        let impactForce = innerRingPeak * 0.016 * proximity
                        let scatterAngle = atan2(ny, nx) + Double.random(in: -1.2...1.2)
                        particles[i].vx += cos(scatterAngle) * impactForce
                        particles[i].vy += sin(scatterAngle) * impactForce
                    }

                    // Kick: steeper power curve — only hard hits break particles far from center
                    let kickImpulse = pow(kickFast, 2.1) * 0.036 / massVar
                    particles[i].vx += nx * kickImpulse
                    particles[i].vy += ny * kickImpulse

                    // Bass lift — higher threshold so only heavy sustained bass expels them
                    let liftStr = 0.0032 / massVar
                    let liftEnergy = max(0, bassEnergy - 0.52)
                    particles[i].vx += nx * liftEnergy * liftStr
                    particles[i].vy += ny * liftEnergy * liftStr

                    // Asymmetric friction: fast outward, slow inward return
                    let friction = radV > 0 ? 0.86 + dist * 0.06 : 0.97 + dist * 0.02
                    particles[i].vx *= friction
                    particles[i].vy *= friction

                    particles[i].x += particles[i].vx
                    particles[i].y += particles[i].vy
                    particles[i].phase += particles[i].colorMix < 0.5 ? 0.025 : 0.0125

                    // Wall matches mass: heavy orange stays near center, light teal can drift far
                    let wallR = 0.38 + particles[i].colorMix * 0.52  // orange=0.38–0.64, teal=0.64–0.90
                    let nd = (particles[i].x * particles[i].x + particles[i].y * particles[i].y).squareRoot()
                    if nd > wallR {
                        let bnx = particles[i].x / nd, bny = particles[i].y / nd
                        let t = min(1.0, (nd - wallR) / 0.28)
                        let repForce = t * t * 0.022
                        particles[i].vx -= bnx * repForce
                        particles[i].vy -= bny * repForce
                    }
                    // Hard clamp only if truly off-screen
                    if nd > 1.10 {
                        let bnx = particles[i].x / nd, bny = particles[i].y / nd
                        particles[i].x = bnx * 1.04
                        particles[i].y = bny * 1.04
                        particles[i].vx *= 0.35
                        particles[i].vy *= 0.35
                    }
                }
            }
        }
        .background(.black)
        .onAppear {
            renderTint = tint
            renderTint2 = tint2
        }
        .onChange(of: tint) { _, newVal in
            withAnimation(.easeInOut(duration: 1.2)) { renderTint = newVal }
        }
        .onChange(of: tint2) { _, newVal in
            withAnimation(.easeInOut(duration: 1.2)) { renderTint2 = newVal }
        }
    }
}
