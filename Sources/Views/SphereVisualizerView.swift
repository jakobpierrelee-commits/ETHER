import SwiftUI
import SceneKit
import simd

// MARK: - View

struct SphereVisualizerView: NSViewRepresentable {
    @ObservedObject var analyzer: SpectrumAnalyzer
    var tint: Color
    var tint2: Color

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.backgroundColor   = .black
        scnView.antialiasingMode  = .multisampling4X
        scnView.isPlaying         = true
        scnView.delegate          = context.coordinator

        let scene = SCNScene()
        scnView.scene = scene

        let cam = SCNCamera()
        cam.wantsHDR        = true
        cam.bloomIntensity  = 0.45
        cam.bloomThreshold  = 0.30
        cam.bloomBlurRadius = 12.0
        cam.fieldOfView     = 50
        cam.zNear = 0.1; cam.zFar = 50
        let camNode = SCNNode()
        camNode.camera   = cam
        camNode.position = SCNVector3(0, 0.15, 4.2)
        scene.rootNode.addChildNode(camNode)

        let starNode = makeStarfield()
        scene.rootNode.addChildNode(starNode)

        // Fill renders behind wire so back-faces are darkened
        let fillNode = SCNNode()
        let wireNode = SCNNode()
        scene.rootNode.addChildNode(fillNode)
        scene.rootNode.addChildNode(wireNode)

        context.coordinator.setup(
            camNode:  camNode,
            wireNode: wireNode,
            fillNode: fillNode,
            starNode: starNode,
            analyzer: analyzer
        )
        return scnView
    }

    func updateNSView(_ view: SCNView, context: Context) {
        context.coordinator.updateTints(tint, tint2)
    }

    // MARK: - Starfield

    private func makeStarfield() -> SCNNode {
        let container = SCNNode()
        var positions:  [SCNVector3]    = []
        var colors:     [SIMD4<Float>]  = []

        func add(_ pos: SCNVector3, r: Float, g: Float, b: Float, a: Float) {
            positions.append(pos)
            colors.append(SIMD4(r, g, b, a))
        }

        func sphere(rMin: Float, rMax: Float) -> SCNVector3 {
            let u = Float.random(in: -1...1)
            let t = Float.random(in: 0 ..< 2 * .pi)
            let r = Float.random(in: rMin...rMax)
            let s = sqrt(max(0, 1 - u * u))
            return SCNVector3(r * s * cos(t), r * u, r * s * sin(t))
        }

        // Scattered field
        for _ in 0..<600 {
            let a   = Float.random(in: 0.3...1.0)
            let pos = sphere(rMin: 18, rMax: 40)
            switch Int.random(in: 0..<9) {
            case 0:  add(pos, r: 0.70, g: 0.82, b: 1.00, a: a)   // blue-white
            case 1:  add(pos, r: 1.00, g: 0.92, b: 0.70, a: a)   // warm
            default: add(pos, r: 1.00, g: 1.00, b: 1.00, a: a)
            }
        }

        // Galaxy arm
        let tilt = Float.pi / 5.5
        for _ in 0..<250 {
            let t = Float.random(in: 0 ..< 2 * .pi)
            let b = Float.random(in: -0.22...0.22)
            let r = Float.random(in: 20...42)
            let cold = Int.random(in: 0..<3) == 0
            add(SCNVector3(r * cos(t),
                           r * (sin(t) * sin(tilt) + b * cos(tilt)),
                           r * (sin(t) * cos(tilt) - b * sin(tilt))),
                r: cold ? 0.72 : 1.0, g: cold ? 0.85 : 1.0, b: 1.0,
                a: Float.random(in: 0.25...0.85))
        }

        // Dense core cluster
        for _ in 0..<130 {
            let spread = Float.random(in: 0...3.5)
            let angle  = Float.random(in: 0 ..< 2 * .pi)
            add(SCNVector3(-22 + spread * cos(angle), 10 + spread * sin(angle), -28),
                r: 0.85, g: 0.90, b: 1.0, a: Float.random(in: 0.5...1.0))
        }

        // Single-draw-call point cloud
        let posSource   = SCNGeometrySource(vertices: positions)
        let colBytes    = colors.withUnsafeBytes { Data($0) }
        let colSource   = SCNGeometrySource(data: colBytes, semantic: .color,
                              vectorCount: positions.count, usesFloatComponents: true,
                              componentsPerVector: 4, bytesPerComponent: 4,
                              dataOffset: 0, dataStride: MemoryLayout<SIMD4<Float>>.stride)
        var idx         = (0..<Int32(positions.count)).map { $0 }
        let idxData     = Data(bytes: &idx, count: idx.count * 4)
        let element     = SCNGeometryElement(data: idxData, primitiveType: .point,
                              primitiveCount: positions.count, bytesPerIndex: 4)
        element.pointSize                    = 2.5
        element.minimumPointScreenSpaceRadius = 0.5
        element.maximumPointScreenSpaceRadius = 5.0

        let mat = SCNMaterial()
        mat.lightingModel    = .constant
        mat.diffuse.contents = NSColor.white

        let geo = SCNGeometry(sources: [posSource, colSource], elements: [element])
        geo.materials = [mat]
        container.addChildNode(SCNNode(geometry: geo))
        container.runAction(.repeatForever(.rotateBy(x: 0.015, y: 0.04, z: 0, duration: 120)))
        return container
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, SCNSceneRendererDelegate {

        // ── Nodes ─────────────────────────────────────────────────────────
        private var camNode:  SCNNode?
        private var wireNode: SCNNode?
        private var fillNode: SCNNode?
        private var starNode: SCNNode?

        // ── Materials (persistent — don't recreate every frame) ───────────
        private let wireMat = SCNMaterial()
        private let fillMat = SCNMaterial()

        // ── Mesh constants ────────────────────────────────────────────────
        private let lonSegs    = 80
        private let latSegs    = 40
        private let baseRadius: Float = 1.0

        // ── Geometry buffers ──────────────────────────────────────────────
        private var vertexCount  = 0
        private var vertexBuffer = Data()
        private var colorBuffer  = Data()
        private var tempColors:  [SIMD4<Float>] = []
        private var indexElement: SCNGeometryElement?

        // ── Per-vertex data ───────────────────────────────────────────────
        private var noisePhase:     [Float] = []
        private var noiseFreq:      [Float] = []
        private var noisePhase2:    [Float] = []
        private var noiseFreq2:     [Float] = []
        private var vertexDecay:    [Float] = []  // random 0.55–0.88 per vertex
        private var smoothedAudio:  [Float] = []
        private var tensionedAudio: [Float] = []
        private var vertexColorT:   [Float] = []

        // ── Audio sources ─────────────────────────────────────────────────
        private let numSources = 48
        private var sourceDirs:     [SIMD3<Float>] = []
        private var sourceBins:     [Int]   = []
        private var sourceK:        [Float] = []   // exp sharpness: bass=40 wide, treble=160 tight
        private var sourceAmpScale: [Float] = []   // height: bass=0.55, treble=0.28
        private var lastSwapTime: TimeInterval = 0

        // ── Tints ─────────────────────────────────────────────────────────
        private var tint1Vec = SIMD3<Float>(0.3, 0.8, 1.0)
        private var tint2Vec = SIMD3<Float>(1.0, 0.3, 0.6)

        // ── Rotation physics ──────────────────────────────────────────────
        private var yaw:    Double = 0
        private var angVelX: Double = 0, angVelZ: Double = 0
        private var eulerX:  Double = 0, eulerZ:  Double = 0

        // ── Energy + effects ──────────────────────────────────────────────
        private var overallEnergy: Double = 0
        private var prevEnergy:    Double = 0
        private var bloomFlash:    Float  = 0
        private var starScale:     Float  = 1.0

        // MARK: Setup

        func setup(camNode: SCNNode, wireNode: SCNNode, fillNode: SCNNode,
                   starNode: SCNNode, analyzer: SpectrumAnalyzer) {
            self.camNode   = camNode
            self.wireNode  = wireNode
            self.fillNode  = fillNode
            self.starNode  = starNode
            self.analyzer  = analyzer

            // Slight axis warp — real organisms aren't perfect spheres
            let warp = SCNVector3(1.04, 0.96, 1.02)
            wireNode.scale = warp
            fillNode.scale = warp

            let lonCount = lonSegs + 1
            vertexCount  = lonCount * (latSegs + 1)
            vertexBuffer = Data(count: vertexCount * MemoryLayout<SIMD3<Float>>.stride)
            colorBuffer  = Data(count: vertexCount * MemoryLayout<SIMD4<Float>>.stride)
            tempColors      = [SIMD4<Float>](repeating: .zero, count: vertexCount)
            smoothedAudio   = [Float](repeating: 0,   count: vertexCount)
            tensionedAudio  = [Float](repeating: 0,   count: vertexCount)
            vertexColorT    = [Float](repeating: 0.5, count: vertexCount)

            // Tectonic surface noise — slow enough to feel geological (5–25s cycles)
            noisePhase  = (0..<vertexCount).map { _ in Float.random(in: 0 ..< 2 * .pi) }
            noiseFreq   = (0..<vertexCount).map { _ in Float.random(in: 0.04...0.18) }
            noisePhase2 = (0..<vertexCount).map { _ in Float.random(in: 0 ..< 2 * .pi) }
            noiseFreq2  = (0..<vertexCount).map { _ in Float.random(in: 0.11...0.35) }
            vertexDecay = (0..<vertexCount).map { _ in Float.random(in: 0.55...0.88) }

            // Fibonacci sphere source placement — avoids poles
            let golden = Float.pi * (3 - sqrt(5))
            for i in 0..<numSources {
                let y     = 1 - (2 * Float(i) + 1) / Float(2 * numSources)
                let r     = sqrt(max(0, 1 - y * y))
                let theta = golden * Float(i)
                sourceDirs.append(normalize(SIMD3(r * cos(theta), y, r * sin(theta))))
                let t = Double(i) / Double(numSources - 1)
                sourceBins.append(min(255, Int(pow(t, 1.3) * 200)))
            }
            // Randomize which frequency lives where on the globe
            sourceBins.shuffle()

            // Frequency character per position — bass wide/tall, treble tight/short
            sourceK = sourceBins.map { bin in
                let t = min(1, Float(bin) / 200.0)
                return 40 + t * 120        // k=40 (bass, wide) → k=160 (treble, tight)
            }
            sourceAmpScale = sourceBins.map { bin in
                let t = min(1, Float(bin) / 200.0)
                return 0.55 - t * 0.27     // 0.55 (bass) → 0.28 (treble)
            }

            // Build index buffer once — reused every frame
            var indices = [Int32]()
            indices.reserveCapacity(latSegs * lonSegs * 6)
            for lat in 0..<latSegs {
                for lon in 0..<lonSegs {
                    let a = Int32(lat * lonCount + lon)
                    let b = a + 1
                    let c = Int32((lat + 1) * lonCount + lon)
                    let d = c + 1
                    indices += [a, b, c, b, d, c]
                }
            }
            indexElement = SCNGeometryElement(
                data: Data(bytes: indices, count: indices.count * 4),
                primitiveType: .triangles, primitiveCount: indices.count / 3, bytesPerIndex: 4)

            wireMat.fillMode         = .lines
            wireMat.lightingModel    = .constant
            wireMat.isDoubleSided    = true
            wireMat.diffuse.contents = NSColor.white

            fillMat.fillMode         = .fill
            fillMat.lightingModel    = .constant
            fillMat.isDoubleSided    = false
            fillMat.diffuse.contents = NSColor.black
            fillMat.transparency     = 0.45   // ~55% opaque — gives depth without killing wireframe
            fillMat.blendMode        = .alpha
        }

        func updateTints(_ t1: Color, _ t2: Color) {
            func toVec(_ c: Color) -> SIMD3<Float> {
                let ns = NSColor(c)
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
                ns.getRed(&r, green: &g, blue: &b, alpha: nil)
                return SIMD3(Float(r), Float(g), Float(b))
            }
            tint1Vec = toVec(t1)
            tint2Vec = toVec(t2)
        }

        // MARK: Render loop

        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            guard let wire    = wireNode,
                  let fill    = fillNode,
                  let bins    = analyzer?.magnitudes,
                  let element = indexElement,
                  bins.count > 64 else { return }

            let ft = Float(time)

            // ── Rewire: continuously swap which frequency lives at which globe position ──
            if time - lastSwapTime > 0.3 {
                let i = Int.random(in: 0..<numSources)
                let j = (i + Int.random(in: 1..<numSources)) % numSources
                sourceBins.swapAt(i, j)
                sourceK.swapAt(i, j)
                sourceAmpScale.swapAt(i, j)
                lastSwapTime = time
            }

            // ── Energy ────────────────────────────────────────────────────
            let allAvg = Double(bins.reduce(0, +)) / Double(bins.count)
            overallEnergy = overallEnergy * 0.92 + max(0, min(1, (allAvg + 60) / 45)) * 0.08
            let energyDelta = overallEnergy - prevEnergy
            prevEnergy = overallEnergy

            // ── Bloom flash on transients ─────────────────────────────────
            if energyDelta > 0.12 { bloomFlash = min(1.0, bloomFlash + Float(energyDelta) * 2.5) }
            bloomFlash = max(0, bloomFlash * 0.88)
            camNode?.camera?.bloomIntensity = CGFloat(0.45 + bloomFlash * 0.55)

            // ── Camera micro-drift (Lissajous) ────────────────────────────
            camNode?.position = SCNVector3(
                sin(ft * 0.07) * 0.08,
                0.15 + sin(ft * 0.11) * 0.05,
                4.2)

            // ── Starfield scale pulse on bass hits ────────────────────────
            if energyDelta > 0.12 { starScale = min(1.012, starScale + Float(energyDelta) * 0.04) }
            starScale = 1.0 + (starScale - 1.0) * 0.93
            starNode?.scale = SCNVector3(starScale, starScale, starScale)

            // ── Rotation physics: angular velocity + restoring force + transient kick ──
            yaw += 0.003 + overallEnergy * 0.004
            let restoreX = -eulerX * 0.004, restoreZ = -eulerZ * 0.004
            if energyDelta > 0.12 {
                angVelX += Double.random(in: -0.003...0.003)
                angVelZ += Double.random(in: -0.002...0.002)
            }
            angVelX = (angVelX + restoreX) * 0.992
            angVelZ = (angVelZ + restoreZ) * 0.992
            eulerX  = max(-0.4, min(0.4, eulerX + angVelX))
            eulerZ  = max(-0.2, min(0.2, eulerZ + angVelZ))
            let euler = SCNVector3(Float(eulerX), Float(yaw), Float(eulerZ))
            wire.eulerAngles = euler
            fill.eulerAngles = euler

            // ── Source magnitudes ─────────────────────────────────────────
            var sourceMags = [Float](repeating: 0, count: numSources)
            for i in 0..<numSources {
                let bin = min(bins.count - 1, sourceBins[i])
                let raw = max(0.0, (Double(bins[bin]) + 55) / 50)
                sourceMags[i] = Float(min(1.0, pow(raw, 1.3)))
            }

            // ── Autonomous breath — three irrational-ratio sines ──────────
            // Frequencies chosen so the pattern never repeats within a listening session
            let autoBreathe = sin(ft * 0.33) * 0.07
                            + sin(ft * 0.17) * 0.035
                            + sin(ft * 0.07) * 0.018
            let breathe = Float(overallEnergy) * 0.04 + autoBreathe

            let lonCount = lonSegs + 1
            let t1 = tint1Vec, t2 = tint2Vec

            // ── Pass 1: per-vertex audio envelope ─────────────────────────
            for lat in 0...latSegs {
                let phi    = Float(lat) / Float(latSegs) * Float.pi
                let sinPhi = sin(phi), cosPhi = cos(phi)
                for lon in 0...lonSegs {
                    let theta  = Float(lon) / Float(lonSegs) * 2 * Float.pi
                    let normal = SIMD3<Float>(sinPhi * cos(theta), cosPhi, sinPhi * sin(theta))
                    let idx    = lat * lonCount + lon

                    var maxContrib = Float(0)
                    var colorT     = Float(0.5)
                    var winnerAmp  = Float(0.4)

                    for s in 0..<numSources {
                        let dot = simd_dot(normal, sourceDirs[s])
                        guard dot > 0.85 else { continue }
                        // Exponential falloff: fine needle point, not a parabolic bowl
                        let contrib = expf(-sourceK[s] * (1 - dot)) * sourceMags[s]
                        if contrib > maxContrib {
                            maxContrib = contrib
                            colorT     = Float(s) / Float(numSources - 1)
                            winnerAmp  = sourceAmpScale[s]
                        }
                    }

                    // Asymmetric envelope: instant attack, randomized decay per vertex
                    let target = min(maxContrib, 1.0) * winnerAmp
                    let prev   = smoothedAudio[idx]
                    let decay  = vertexDecay[idx]
                    smoothedAudio[idx] = target > prev
                        ? target
                        : prev * decay + target * (1 - decay)
                    vertexColorT[idx] = colorT
                }
            }

            // ── Tension pass: peaks tent neighbors up, valleys dip between spikes ──
            for lat in 1..<latSegs {
                for lon in 0...lonSegs {
                    let idx  = lat * lonCount + lon
                    let idxN = (lat - 1) * lonCount + lon
                    let idxS = (lat + 1) * lonCount + lon
                    let idxW = lat * lonCount + (lon == 0      ? lonSegs : lon - 1)
                    let idxE = lat * lonCount + (lon == lonSegs ? 0       : lon + 1)
                    let neighborPeak = max(max(smoothedAudio[idxN], smoothedAudio[idxS]),
                                          max(smoothedAudio[idxW], smoothedAudio[idxE]))
                    let self_ = smoothedAudio[idx]
                    let tented = max(self_, neighborPeak * 0.42)
                    // Membrane counter-depression: quiet skin between spikes dips inward
                    let valley = (self_ < 0.05 && neighborPeak > 0.25) ? -neighborPeak * 0.08 : Float(0)
                    tensionedAudio[idx] = tented + valley
                }
            }

            // ── Pass 2: write vertex positions + colors ───────────────────
            vertexBuffer.withUnsafeMutableBytes { vPtr in
                let verts = vPtr.bindMemory(to: SIMD3<Float>.self)
                for lat in 0...latSegs {
                    let phi    = Float(lat) / Float(latSegs) * Float.pi
                    let sinPhi = sin(phi), cosPhi = cos(phi)
                    for lon in 0...lonSegs {
                        let theta  = Float(lon) / Float(lonSegs) * 2 * Float.pi
                        let normal = SIMD3<Float>(sinPhi * cos(theta), cosPhi, sinPhi * sin(theta))
                        let idx    = lat * lonCount + lon

                        // Tectonic surface noise — slow individual oscillators per vertex
                        let noise = sin(ft * noiseFreq[idx]  + noisePhase[idx])  * 0.030
                                  + sin(ft * noiseFreq2[idx] + noisePhase2[idx]) * 0.015

                        // Hard-zero top/bottom 3 lat bands; smooth ramp through the next few
                        let poleDamp: Float = lat <= 3 || lat >= latSegs - 3
                            ? 0
                            : min(1.0, sinPhi * 12.0)

                        let d = baseRadius + (breathe + tensionedAudio[idx] + noise) * poleDamp
                        verts[idx] = normal * d

                        // Smoothstep colorT away from the gray complementary midzone
                        let rawT   = vertexColorT[idx]
                        let colorT = rawT < 0.5
                            ? 2 * rawT * rawT * (1.5 - rawT)
                            : 1 - 2 * (1 - rawT) * (1 - rawT) * (1.5 - (1 - rawT))

                        let disp       = max(0, d - baseRadius)
                        let brightness = 0.55 + min(disp, 1.1) * 0.40
                        var rgb        = (t1 * (1 - colorT) + t2 * colorT) * brightness

                        // Anisotropic color temperature: cool at rest, warm at spike tips
                        let tempT = min(1.0, disp * 1.4)
                        rgb.x = min(1, rgb.x + tempT * 0.06)
                        rgb.y = max(0, rgb.y - tempT * 0.02)
                        rgb.z = max(0, rgb.z - tempT * 0.05)

                        tempColors[idx] = SIMD4(rgb.x, rgb.y, rgb.z, 1.0)
                    }
                }
            }

            colorBuffer.withUnsafeMutableBytes { cPtr in
                let cols = cPtr.bindMemory(to: SIMD4<Float>.self)
                for i in 0..<vertexCount { cols[i] = tempColors[i] }
            }

            // ── Upload geometry — materials + index element are persistent ─
            let vertSrc = SCNGeometrySource(data: vertexBuffer, semantic: .vertex,
                vectorCount: vertexCount, usesFloatComponents: true,
                componentsPerVector: 3, bytesPerComponent: 4,
                dataOffset: 0, dataStride: MemoryLayout<SIMD3<Float>>.stride)
            let colSrc = SCNGeometrySource(data: colorBuffer, semantic: .color,
                vectorCount: vertexCount, usesFloatComponents: true,
                componentsPerVector: 4, bytesPerComponent: 4,
                dataOffset: 0, dataStride: MemoryLayout<SIMD4<Float>>.stride)

            let wGeo = SCNGeometry(sources: [vertSrc, colSrc], elements: [element])
            wGeo.materials = [wireMat]
            wire.geometry  = wGeo

            let fGeo = SCNGeometry(sources: [vertSrc], elements: [element])
            fGeo.materials = [fillMat]
            fill.geometry  = fGeo
        }

        private var analyzer: SpectrumAnalyzer?
    }
}

// MARK: - Window wrapper

struct SphereVisualizerWindowView: View {
    @EnvironmentObject var engine: EngineManager
    @StateObject private var nowPlaying = NowPlayingManager()

    private var tint: Color {
        Color(nsColor: nowPlaying.dominantColor.blended(withFraction: 0.05, of: .white) ?? .white)
    }

    private var tint2: Color {
        guard let rgb = nowPlaying.dominantColor.usingColorSpace(.deviceRGB) else { return tint }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        rgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        guard s > 0.15 && b > 0.12 else { return tint }
        let h2 = (h + 0.5).truncatingRemainder(dividingBy: 1.0)
        let c2 = NSColor(hue: h2, saturation: min(1, s * 1.05), brightness: min(1, b), alpha: 1.0)
        return Color(nsColor: c2.blended(withFraction: 0.03, of: .white) ?? .white)
    }

    var body: some View {
        SphereVisualizerView(analyzer: engine.postSpectrum, tint: tint, tint2: tint2)
            .ignoresSafeArea()
            .onAppear { engine.postSpectrum.isActive = true }
    }
}
