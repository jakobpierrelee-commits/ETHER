import SwiftUI
import AppKit

// MARK: - Ethereal Waveform (overlays album art, blends in)

private struct EtherealWaveform: View {
    @ObservedObject var analyzer: SpectrumAnalyzer
    var tint: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !analyzer.isActive)) { _ in
            Canvas { ctx, size in
                let bins = analyzer.magnitudes
                guard bins.count > 1 else { return }
                let w = size.width, h = size.height

                var points: [CGPoint] = []
                let steps = 48
                for i in 0..<steps {
                    let binIndex = Int(Float(i) / Float(steps) * Float(bins.count))
                    let t = Float(i) / Float(steps - 1) // 0 = bass, 1 = treble
                    // Visual gain ramp: boost treble end so it looks more even
                    let tiltGain: Float = 1.0 + t * 0.6
                    let raw = max(0, min(1, (bins[min(binIndex, bins.count - 1)] + 60) / 60))
                    let mag = min(1, raw * tiltGain)
                    let x = CGFloat(i) / CGFloat(steps - 1) * w
                    let y = h - CGFloat(mag) * h * 0.8
                    points.append(CGPoint(x: x, y: y))
                }

                // Smooth closed path
                var path = Path()
                path.move(to: CGPoint(x: 0, y: h))
                if let first = points.first { path.addLine(to: first) }
                for i in 1..<points.count {
                    let prev = points[i - 1], curr = points[i]
                    let midX = (prev.x + curr.x) / 2
                    path.addCurve(to: curr,
                                  control1: CGPoint(x: midX, y: prev.y),
                                  control2: CGPoint(x: midX, y: curr.y))
                }
                path.addLine(to: CGPoint(x: w, y: h))
                path.closeSubpath()

                // Glow
                var glow = ctx
                glow.addFilter(.blur(radius: 8))
                glow.fill(path, with: .color(tint.opacity(0.45)))

                // Fill
                ctx.fill(path, with: .linearGradient(
                    Gradient(colors: [tint.opacity(0.5), tint.opacity(0.08)]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: 0, y: h)
                ))

                // Edge
                var edge = Path()
                if let first = points.first { edge.move(to: first) }
                for i in 1..<points.count {
                    let prev = points[i - 1], curr = points[i]
                    let midX = (prev.x + curr.x) / 2
                    edge.addCurve(to: curr,
                                  control1: CGPoint(x: midX, y: prev.y),
                                  control2: CGPoint(x: midX, y: curr.y))
                }
                ctx.stroke(edge, with: .color(tint.opacity(0.8)), lineWidth: 1)
            }
        }
        .blendMode(.screen)
    }
}

// MARK: - Glass Waveform Bar

private struct GlassWaveform: View {
    @ObservedObject var analyzer: SpectrumAnalyzer
    var tint: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !analyzer.isActive)) { _ in
            Canvas { ctx, size in
                let bins = analyzer.magnitudes
                guard bins.count > 1 else { return }
                let w = size.width, h = size.height
                let barCount = 24
                let gap: CGFloat = 1.5
                let barW = (w - gap * CGFloat(barCount - 1)) / CGFloat(barCount)

                for i in 0..<barCount {
                    let binIndex = Int(Float(i) / Float(barCount) * Float(bins.count))
                    let mag = max(0, min(1, (bins[min(binIndex, bins.count - 1)] + 60) / 60))
                    let barH = max(1, CGFloat(mag) * h)
                    let x = CGFloat(i) * (barW + gap)
                    let rect = CGRect(x: x, y: h - barH, width: barW, height: barH)

                    // Glass: white fill with low opacity + brighter at top
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 1),
                             with: .linearGradient(
                                Gradient(colors: [
                                    .white.opacity(Double(mag) * 0.5 + 0.08),
                                    .white.opacity(Double(mag) * 0.15 + 0.03)
                                ]),
                                startPoint: CGPoint(x: 0, y: rect.minY),
                                endPoint: CGPoint(x: 0, y: rect.maxY)
                             ))
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(.ultraThinMaterial)
                .opacity(0.5)
        )
    }
}

// MARK: - Mini Player

struct MiniPlayerView: View {
    @EnvironmentObject var engine: EngineManager
    @ObservedObject var controller: EQController
    @ObservedObject var profileStore: ProfileStore
    @StateObject private var nowPlaying = NowPlayingManager()
    @ObservedObject private var theme = ThemeManager.shared
    @Environment(\.openWindow) private var openWindow
    @State private var isWindowHovered = false

    private var bgDark: Color {
        Color(nsColor: nowPlaying.dominantColor.blended(withFraction: 0.75, of: .black) ?? .black)
    }
    private var tint: Color {
        Color(nsColor: nowPlaying.dominantColor.blended(withFraction: 0.3, of: .white) ?? .white)
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width

            VStack(spacing: 0) {
                // Album art with overlaid ethereal waveform
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        if let art = nowPlaying.albumArt {
                            Image(nsImage: art)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: w, height: w * 0.82)
                                .clipped()
                        } else {
                            Rectangle()
                                .fill(bgDark)
                                .frame(width: w, height: w * 0.82)
                                .overlay(
                                    Image(systemName: "music.note")
                                        .font(.system(size: w * 0.14))
                                        .foregroundColor(.white.opacity(0.12))
                                )
                        }

                        // Gradient to black
                        VStack {
                            Spacer()
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0),
                                    .init(color: Color.black.opacity(0.3), location: 0.2),
                                    .init(color: Color.black.opacity(0.65), location: 0.4),
                                    .init(color: Color.black.opacity(0.88), location: 0.6),
                                    .init(color: .black, location: 0.75),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: w * 0.65)
                        }

                        // Ethereal waveform — on top of gradient, bottom masked away
                        VStack {
                            Spacer()
                            EtherealWaveform(analyzer: engine.postSpectrum, tint: tint)
                                .frame(width: w, height: w * 0.4)
                                .opacity(0.4)
                                .mask(
                                    LinearGradient(
                                        stops: [
                                            .init(color: .clear, location: 0),
                                            .init(color: .white, location: 0.15),
                                            .init(color: .white, location: 0.5),
                                            .init(color: .clear, location: 1.0),
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .offset(y: w * 0.12)
                        }
                        .allowsHitTesting(false)
                    }

                    // Close — only visible on hover
                    if isWindowHovered {
                        Button {
                            MiniPlayerPanel.shared.close()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white.opacity(0.6))
                                .frame(width: 16, height: 16)
                                .background(Color.black.opacity(0.4))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .padding(6)
                        .transition(.opacity)
                    }
                }
                .frame(width: w, height: w * 0.82)

                // Track info + controls — on top of everything
                VStack(spacing: 2) {
                    Text(nowPlaying.title.isEmpty ? "Not Playing" : nowPlaying.title)
                        .font(.etherMono(max(9, w * 0.045), weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .shadow(color: .black.opacity(0.7), radius: 4)

                    if !nowPlaying.artist.isEmpty {
                        Text(nowPlaying.artist)
                            .font(.etherMono(max(7, w * 0.035)))
                            .foregroundColor(.white.opacity(0.55))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .shadow(color: .black.opacity(0.7), radius: 4)
                    }

                    // Media controls
                    HStack(spacing: w * 0.08) {
                        Spacer()
                        Button { nowPlaying.previousTrack() } label: {
                            Image(systemName: "backward.fill")
                                .font(.system(size: max(10, w * 0.05)))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .buttonStyle(.plain)

                        Button { nowPlaying.togglePlayPause() } label: {
                            Image(systemName: nowPlaying.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: max(14, w * 0.075)))
                                .foregroundColor(.white)
                                .frame(width: max(28, w * 0.14), height: max(28, w * 0.14))
                                .background(
                                    Circle()
                                        .fill(tint.opacity(0.25))
                                        .overlay(Circle().strokeBorder(.white.opacity(0.15), lineWidth: 1))
                                )
                        }
                        .buttonStyle(.plain)

                        Button { nowPlaying.nextTrack() } label: {
                            Image(systemName: "forward.fill")
                                .font(.system(size: max(10, w * 0.05)))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .padding(.vertical, 2)

                    // Ether strip
                    HStack(spacing: 4) {
                        Circle().fill(statusColor).frame(width: 4, height: 4)
                        Text("ETHER")
                            .font(.etherMono(6, weight: .bold))
                            .tracking(1.5)
                            .foregroundColor(.white.opacity(0.35))
                        Spacer()
                        Button { controller.toggleGlobalBypass() } label: {
                            Text(controller.bypassed ? "BYP" : "EQ")
                                .font(.etherMono(6, weight: .bold))
                                .foregroundColor(controller.bypassed ? .etherWarning : .white.opacity(0.45))
                        }
                        .buttonStyle(.plain)
                        Button {
                            openWindow(id: "main")
                            NSApp.activate(ignoringOtherApps: true)
                        } label: {
                            Image(systemName: "macwindow")
                                .font(.system(size: 7))
                                .foregroundColor(.white.opacity(0.25))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 2)
                .padding(.bottom, 6)
            }
            .background(.black)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .overlay(WindowDragHandle())
            .onHover { isWindowHovered = $0 }
            .animation(.easeOut(duration: 0.2), value: isWindowHovered)
            .shadow(color: .black.opacity(0.5), radius: 15, y: 5)
            .padding(1)
        }
        .frame(minWidth: 160, idealWidth: 220, maxWidth: 320,
               minHeight: 200, idealHeight: 280, maxHeight: 420)
        .aspectRatio(4.0/5.0, contentMode: .fit)
        .animation(.easeOut(duration: 0.6), value: nowPlaying.title)
    }

    private var statusColor: Color {
        switch engine.status {
        case .running:              return .etherPositive
        case .error, .driverNotInstalled: return .etherClip
        case .starting:             return .etherWarning
        case .stopped:              return .white.opacity(0.2)
        }
    }

}
