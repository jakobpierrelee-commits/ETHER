import SwiftUI
import AppKit

// MARK: - Mini Player

struct MiniPlayerView: View {
    @EnvironmentObject var engine: EngineManager
    @ObservedObject var controller: EQController
    @ObservedObject var profileStore: ProfileStore
    @StateObject private var nowPlaying = NowPlayingManager()
    @ObservedObject private var theme = ThemeManager.shared
    @Environment(\.openWindow) private var openWindow
    @State private var isWindowHovered = false
    @State private var showingVisualizer = false
    @State private var isArtHovered = false
    @State private var bassEnergy: CGFloat = 0
    @State private var overallEnergy: CGFloat = 0
    @State private var hoveredButton: String?

    private var bgDark: Color {
        Color(nsColor: nowPlaying.dominantColor.blended(withFraction: 0.75, of: .black) ?? .black)
    }
    private var tint: Color {
        Color(nsColor: nowPlaying.dominantColor.blended(withFraction: 0.3, of: .white) ?? .white)
    }
    private var tint2: Color {
        guard let rgb = nowPlaying.dominantColor.usingColorSpace(.deviceRGB) else { return tint }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        rgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        // Only split into two hues when the art has enough saturation to justify it.
        // Muted, grayscale, or very dark art gets a single coherent color.
        guard s > 0.22 && b > 0.15 else { return tint }
        let h2 = (h + 0.42).truncatingRemainder(dividingBy: 1.0)
        let c2 = NSColor(hue: h2, saturation: min(1, s * 1.4), brightness: min(1, b * 1.1), alpha: 1.0)
        return Color(nsColor: c2.blended(withFraction: 0.25, of: .white) ?? .white)
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width

            ZStack(alignment: .bottom) {
                albumArtSection(w: w, h: showingVisualizer ? geo.size.height : w * 0.82)
                    .frame(width: w, height: showingVisualizer ? geo.size.height : w * 0.82)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                trackInfoSection(w: w)
                    .background(showingVisualizer ? Color.clear : Color.black)
            }
            .background(.black)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .overlay(WindowDragHandle())
            .overlay(energyTracker)
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

    // MARK: - Album Art

    private func albumArtSection(w: CGFloat, h: CGFloat) -> some View {
        ZStack(alignment: .topTrailing) {
            // Swappable: album art ↔ radial visualizer
            ZStack {
                if showingVisualizer {
                    MiniVisualizerView(analyzer: engine.postSpectrum, tint: tint, tint2: tint2)
                        .frame(width: w, height: h)
                        .transition(.opacity)
                } else {
                    albumArtContent(w: w)
                        .transition(.opacity)
                }

                // Hover hint — pinned to art area center regardless of canvas height
                if isArtHovered {
                    Image(systemName: showingVisualizer ? "photo" : "waveform")
                        .font(.system(size: 13, weight: .light))
                        .foregroundColor(.white.opacity(0.55))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.black.opacity(0.45)))
                        .transition(.opacity)
                        .position(x: w / 2, y: showingVisualizer ? w * 0.44 : h / 2)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.35)) { showingVisualizer.toggle() }
            }
            .onHover { isArtHovered = $0 }
            .animation(.easeOut(duration: 0.15), value: isArtHovered)

            // Close button
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
    }

    private func albumArtContent(w: CGFloat) -> some View {
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
                        .init(color: Color.black.opacity(0.1), location: 0.3),
                        .init(color: Color.black.opacity(0.45), location: 0.55),
                        .init(color: Color.black.opacity(0.8), location: 0.75),
                        .init(color: .black, location: 0.9),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: w * 0.55)
            }

            // Ethereal waveform — luminance reacts to energy
            VStack {
                Spacer()
                EtherealWaveform(analyzer: engine.postSpectrum, tint: tint)
                    .frame(width: w, height: w * 0.4)
                    .opacity(0.3 + overallEnergy * 0.35)
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
    }

    // MARK: - Track Info + Controls

    private func trackInfoSection(w: CGFloat) -> some View {
        ZStack(alignment: .top) {
            // Reflection
            if !showingVisualizer {
                EtherealWaveform(analyzer: engine.postSpectrum, tint: tint)
                    .frame(width: w, height: w * 0.18)
                    .scaleEffect(x: 1, y: -1)
                    .opacity(0.22 + overallEnergy * 0.20)
                    .mask(
                        LinearGradient(colors: [.white.opacity(0.75), .clear], startPoint: .top, endPoint: .bottom)
                    )
                    .allowsHitTesting(false)
            }

            VStack(spacing: 2) {
                Text(nowPlaying.title.isEmpty ? "Not Playing" : nowPlaying.title)
                    .font(.etherMono(max(9, w * 0.045), weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .shadow(color: tint.opacity(0.15 + overallEnergy * 0.3), radius: 6)
                    .shadow(color: .black.opacity(0.7), radius: 3)

                if !nowPlaying.artist.isEmpty {
                    Text(nowPlaying.artist)
                        .font(.etherMono(max(7, w * 0.035)))
                        .foregroundColor(.white.opacity(0.45))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .shadow(color: .black.opacity(0.7), radius: 3)
                }

                transportButtons(w: w)
                etherStrip
            }
            .padding(.horizontal, 10)
            .padding(.top, 4)
            .padding(.bottom, 6)
        }
    }

    // MARK: - Transport

    private func transportButtons(w: CGFloat) -> some View {
        HStack(spacing: w * 0.08) {
            Spacer()
            transportIcon("backward.fill", id: "prev", w: w) { nowPlaying.previousTrack() }
            playButton(w: w)
            transportIcon("forward.fill", id: "next", w: w) { nowPlaying.nextTrack() }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    private func transportIcon(_ icon: String, id: String, w: CGFloat, action: @escaping () -> Void) -> some View {
        let isHovered = hoveredButton == id
        return Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: max(10, w * 0.05)))
                .foregroundColor(.white.opacity(isHovered ? 1.0 : 0.65))
                .frame(width: max(24, w * 0.12), height: max(24, w * 0.12))
                .background(
                    Circle()
                        .fill(Color.white.opacity(isHovered ? 0.1 : 0))
                        .overlay(
                            Circle().fill(
                                LinearGradient(
                                    colors: [.white.opacity(isHovered ? 0.15 : 0), .clear],
                                    startPoint: .top, endPoint: .center
                                )
                            )
                        )
                )
                .scaleEffect(isHovered ? 1.05 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.8), value: hoveredButton)
        }
        .buttonStyle(.plain)
        .onHover { hoveredButton = $0 ? id : (hoveredButton == id ? nil : hoveredButton) }
    }

    private func playButton(w: CGFloat) -> some View {
        let isHovered = hoveredButton == "play"
        return Button { nowPlaying.togglePlayPause() } label: {
            Image(systemName: nowPlaying.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: max(14, w * 0.075)))
                .foregroundColor(.white)
                .frame(width: max(28, w * 0.14), height: max(28, w * 0.14))
                .background(
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(isHovered ? 0.08 : 0))
                            .frame(width: max(32, w * 0.16), height: max(32, w * 0.16))
                        Circle()
                            .fill(tint.opacity(isHovered ? 0.18 : 0.12 + overallEnergy * 0.1))
                            .overlay(
                                Circle().strokeBorder(
                                    LinearGradient(
                                        colors: [.white.opacity(isHovered ? 0.25 : 0.10), .white.opacity(isHovered ? 0.06 : 0.03)],
                                        startPoint: .top, endPoint: .bottom
                                    ), lineWidth: 1
                                )
                            )
                            .overlay(
                                Circle().fill(
                                    LinearGradient(
                                        colors: [.white.opacity(isHovered ? 0.2 : 0), .clear],
                                        startPoint: .top, endPoint: .center
                                    )
                                ).scaleEffect(0.92)
                            )
                    }
                )
                .scaleEffect(isHovered ? 1.05 : 1.0)
                .shadow(color: isHovered ? tint.opacity(0.3) : .clear, radius: 8)
                .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isHovered)
                .animation(.easeOut(duration: 0.1), value: overallEnergy)
        }
        .buttonStyle(.plain)
        .onHover { hoveredButton = $0 ? "play" : (hoveredButton == "play" ? nil : hoveredButton) }
    }

    // MARK: - Ether Strip

    private var etherStrip: some View {
        HStack(spacing: 4) {
            Circle().fill(statusColor).frame(width: 4, height: 4)
            Text("ETHER")
                .font(.etherValue(6, weight: .bold))
                .tracking(1.5)
                .foregroundColor(.white.opacity(0.35))
            Spacer()
            stripButton("eq", label: controller.bypassed ? "BYP" : "EQ",
                        color: controller.bypassed ? .etherWarning : .white.opacity(0.45)) {
                controller.toggleGlobalBypass()
            }
            stripButton("win", icon: "macwindow") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    private func stripButton(_ id: String, label: String? = nil, icon: String? = nil, color: Color = .white.opacity(0.25), action: @escaping () -> Void) -> some View {
        let isHovered = hoveredButton == id
        return Button(action: action) {
            Group {
                if let label = label {
                    Text(label)
                        .font(.etherValue(6, weight: .bold))
                        .foregroundColor(isHovered ? .white.opacity(0.8) : color)
                } else if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 7))
                        .foregroundColor(.white.opacity(isHovered ? 0.6 : 0.25))
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Capsule().fill(isHovered ? Color.white.opacity(0.08) : .clear))
            .animation(.easeOut(duration: 0.15), value: hoveredButton)
        }
        .buttonStyle(.plain)
        .onHover { hoveredButton = $0 ? id : (hoveredButton == id ? nil : hoveredButton) }
    }

    // MARK: - Energy Tracking

    private var energyTracker: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !engine.postSpectrum.isActive)) { _ in
            Color.clear.onAppear { updateEnergy() }.onChange(of: engine.postSpectrum.magnitudes.first) { _, _ in updateEnergy() }
        }
        .allowsHitTesting(false)
    }

    private func updateEnergy() {
        let bins = engine.postSpectrum.magnitudes
        guard bins.count > 8 else { return }

        let bassEnd = bins.count / 7
        let bassAvg = bins[0..<bassEnd].reduce(Float(0), +) / Float(bassEnd)
        let bassMag = CGFloat(max(0, min(1, (bassAvg + 50) / 35)))

        let allAvg = bins.reduce(Float(0), +) / Float(bins.count)
        let allMag = CGFloat(max(0, min(1, (allAvg + 55) / 35)))

        bassEnergy = max(bassMag, bassEnergy * 0.85)
        overallEnergy = max(min(1, allMag), overallEnergy * 0.88)
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
