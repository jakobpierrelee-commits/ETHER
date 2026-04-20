import SwiftUI
import SceneKit

struct SphereVisualizerView: NSViewRepresentable {
    @ObservedObject var analyzer: SpectrumAnalyzer
    var tint: Color

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .black
        view.antialiasingMode = .multisampling4X
        view.isPlaying = true
        view.delegate = context.coordinator

        let scene = SCNScene()
        view.scene = scene

        // Camera — HDR bloom gives the wireframe its glow
        let cam = SCNCamera()
        cam.wantsHDR = true
        cam.bloomIntensity = 2.0
        cam.bloomThreshold = 0.35
        cam.bloomBlurRadius = 12.0
        cam.fieldOfView = 50
        cam.zNear = 0.1
        cam.zFar = 50
        let camNode = SCNNode()
        camNode.camera = cam
        camNode.position = SCNVector3(0, 0.2, 2.8)
        scene.rootNode.addChildNode(camNode)

        let sphereNode = SCNNode()
        scene.rootNode.addChildNode(sphereNode)
        context.coordinator.setup(sphereNode: sphereNode, analyzer: analyzer)

        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        context.coordinator.updateTint(tint)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, SCNSceneRendererDelegate {
        private var sphereNode: SCNNode?
        private var analyzer: SpectrumAnalyzer?
        private let material = SCNMaterial()

        private let lonSegs = 72   // longitude → frequency resolution
        private let latSegs = 36   // latitude divisions
        private var vertexCount = 0
        private var vertexBuffer = Data()
        private var indexElement: SCNGeometryElement?
        private let baseRadius: Float = 1.0

        private var yaw: Double = 0
        private var overallEnergy: Double = 0

        func setup(sphereNode: SCNNode, analyzer: SpectrumAnalyzer) {
            self.sphereNode = sphereNode
            self.analyzer = analyzer

            let lonCount = lonSegs + 1
            vertexCount = lonCount * (latSegs + 1)
            vertexBuffer = Data(count: vertexCount * MemoryLayout<SIMD3<Float>>.stride)

            // Index buffer never changes — build once
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
                primitiveType: .triangles,
                primitiveCount: indices.count / 3,
                bytesPerIndex: 4
            )

            material.fillMode = .lines
            material.lightingModel = .constant
            material.isDoubleSided = true
        }

        func updateTint(_ color: Color) {
            let ns = NSColor(color)
            material.diffuse.contents = ns
            material.emission.contents = ns
        }

        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            guard let node = sphereNode,
                  let bins = analyzer?.magnitudes,
                  let element = indexElement,
                  !bins.isEmpty else { return }

            // Vibe-adaptive rotation speed (matches MiniVisualizerView logic)
            let allAvg = Double(bins.reduce(0, +)) / Double(bins.count)
            overallEnergy = overallEnergy * 0.92 + max(0, min(1, (allAvg + 60) / 45)) * 0.08
            yaw += 0.004 + overallEnergy * 0.006
            // Slow organic pitch wobble
            let pitch = sin(yaw * 0.13) * 0.14
            node.eulerAngles = SCNVector3(Float(pitch), Float(yaw), 0)

            let lonCount = lonSegs + 1

            // Mutate vertex buffer in-place — no allocation per frame
            vertexBuffer.withUnsafeMutableBytes { ptr in
                let verts = ptr.bindMemory(to: SIMD3<Float>.self)
                for lat in 0...latSegs {
                    let phi = Float(lat) / Float(latSegs) * .pi
                    let sinPhi = sin(phi)
                    let cosPhi = cos(phi)
                    for lon in 0...lonSegs {
                        let theta = Float(lon) / Float(lonSegs) * 2 * .pi
                        let nx = sinPhi * cos(theta)
                        let ny = cosPhi
                        let nz = sinPhi * sin(theta)

                        // Map longitude to frequency bin
                        let t = Double(lon) / Double(lonSegs)
                        let binIdx = min(bins.count - 1, Int(t * Double(bins.count) * 0.75))
                        let rawMag = max(0.0, (Double(bins[binIdx]) + 58) / 48)
                        // Power curve: quiet regions stay tight, peaks pop outward
                        let mag = Float(min(1.0, pow(rawMag, 1.5)))
                        let disp = baseRadius + mag * 0.55

                        verts[lat * lonCount + lon] = SIMD3<Float>(nx * disp, ny * disp, nz * disp)
                    }
                }
            }

            let vertSource = SCNGeometrySource(
                data: vertexBuffer,
                semantic: .vertex,
                vectorCount: vertexCount,
                usesFloatComponents: true,
                componentsPerVector: 3,
                bytesPerComponent: 4,
                dataOffset: 0,
                dataStride: MemoryLayout<SIMD3<Float>>.stride
            )
            let geo = SCNGeometry(sources: [vertSource], elements: [element])
            geo.materials = [material]
            node.geometry = geo
        }
    }
}

// MARK: - Window wrapper (mirrors VisualizerView pattern)

struct SphereVisualizerWindowView: View {
    @EnvironmentObject var engine: EngineManager
    @StateObject private var nowPlaying = NowPlayingManager()

    private var tint: Color {
        Color(nsColor: nowPlaying.dominantColor.blended(withFraction: 0.05, of: .white) ?? .white)
    }

    var body: some View {
        SphereVisualizerView(analyzer: engine.postSpectrum, tint: tint)
            .ignoresSafeArea()
            .onAppear { engine.postSpectrum.isActive = true }
    }
}
