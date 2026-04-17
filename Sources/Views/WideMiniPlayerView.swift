import SwiftUI
import AppKit

struct WideMiniPlayerView: View {
    @EnvironmentObject var engine: EngineManager
    @ObservedObject var controller: EQController
    @StateObject private var nowPlaying = NowPlayingManager()
    @Environment(\.openWindow) private var openWindow
    @State private var isWindowHovered = false
    @State private var hoveredButton: String?
    @State private var overallEnergy: CGFloat = 0

    private var bgColor: Color {
        Color(nsColor: nowPlaying.dominantColor.blended(withFraction: 0.86, of: .black) ?? .black)
    }
    private var tint: Color {
        Color(nsColor: nowPlaying.dominantColor.blended(withFraction: 0.3, of: .white) ?? .white)
    }

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let w = geo.size.width
            let thumbSize = h - 14

            ZStack(alignment: .bottom) {
                // Background
                bgColor

                // Waveform — HStack spacer pins the start to the art's right edge,
                // the waveform fills naturally to the container's right edge.
                let artOffset = thumbSize + 16
                HStack(spacing: 0) {
                    Spacer().frame(width: artOffset)
                    EtherealWaveform(analyzer: engine.postSpectrum, tint: tint)
                        .frame(height: h * 0.75)
                        .frame(maxWidth: .infinity)
                        .opacity(0.52 + overallEnergy * 0.22)
                        .mask(
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0),
                                    .init(color: .white.opacity(0.15), location: 0.10),
                                    .init(color: .white.opacity(0.55), location: 0.22),
                                    .init(color: .white, location: 0.35),
                                    .init(color: .white, location: 0.82),
                                    .init(color: .clear, location: 1.0),
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
                .frame(maxWidth: .infinity)
                .allowsHitTesting(false)

                // Content layer
                HStack(spacing: 0) {
                    // Album art
                    Group {
                        if let art = nowPlaying.albumArt {
                            Image(nsImage: art)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: thumbSize, height: thumbSize)
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                        } else {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(tint.opacity(0.10))
                                .frame(width: thumbSize, height: thumbSize)
                                .overlay(
                                    Image(systemName: "music.note")
                                        .font(.system(size: thumbSize * 0.28))
                                        .foregroundColor(.white.opacity(0.12))
                                )
                        }
                    }
                    .padding(.leading, 8)
                    .onTapGesture { nowPlaying.openCurrentPlayer() }

                    // Title + artist — top aligned with album art
                    VStack(alignment: .leading, spacing: 2) {
                        Text(nowPlaying.title.isEmpty ? "Not Playing" : nowPlaying.title)
                            .font(.etherMono(11, weight: .semibold))
                            .foregroundColor(.white.opacity(0.90))
                            .lineLimit(1)
                        Text(nowPlaying.artist.isEmpty ? " " : nowPlaying.artist)
                            .font(.etherMono(9))
                            .foregroundColor(.white.opacity(0.40))
                            .lineLimit(1)
                    }
                    .padding(.leading, 11)
                    .padding(.top, (h - thumbSize) / 2)
                    .frame(minWidth: 100, maxWidth: 210, maxHeight: .infinity, alignment: .topLeading)

                    Spacer()

                    // Transport — centered, more room to breathe
                    HStack(spacing: 14) {
                        transportIcon("backward.fill", id: "prev", size: 11) { nowPlaying.previousTrack() }
                        playButton(h: h)
                        transportIcon("forward.fill", id: "next", size: 11) { nowPlaying.nextTrack() }
                    }

                    Spacer()

                    // Status + controls — fixed, never shifts
                    HStack(spacing: 6) {
                        Circle().fill(statusColor).frame(width: 4, height: 4)
                        stripButton("eq",
                                    label: controller.bypassed ? "BYP" : "EQ",
                                    color: controller.bypassed ? .etherWarning : .white.opacity(0.40)) {
                            controller.toggleGlobalBypass()
                        }
                    }
                    .padding(.trailing, 10)
                }
                .frame(maxHeight: .infinity)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .topTrailing) {
                if isWindowHovered {
                    HStack(spacing: 6) {
                        stripButton("win", icon: "macwindow") {
                            openWindow(id: "main")
                            NSApp.activate(ignoringOtherApps: true)
                        }
                        Button { WideMiniPlayerPanel.shared.close() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundColor(.white.opacity(0.5))
                                .frame(width: 14, height: 14)
                                .background(Color.black.opacity(0.35))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 6)
                    .padding(.trailing, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.18), value: isWindowHovered)
            .overlay(WindowDragHandle())
            .overlay(energyTracker)
            .onHover { isWindowHovered = $0 }
            .shadow(color: .black.opacity(0.45), radius: 14, y: 5)
            .padding(2)
        }
        .frame(minWidth: 340, idealWidth: 460, maxWidth: 680,
               minHeight: 64, idealHeight: 76, maxHeight: 92)
        .animation(.easeOut(duration: 0.6), value: nowPlaying.title)
    }

    // MARK: - Transport

    private func transportIcon(_ icon: String, id: String, size: CGFloat = 10, action: @escaping () -> Void) -> some View {
        let isHovered = hoveredButton == id
        return Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .medium))
                .foregroundColor(.white.opacity(isHovered ? 0.90 : 0.55))
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.white.opacity(isHovered ? 0.08 : 0)))
                .scaleEffect(isHovered ? 1.06 : 1.0)
                .animation(.spring(response: 0.2, dampingFraction: 0.8), value: hoveredButton)
        }
        .buttonStyle(.plain)
        .onHover { hoveredButton = $0 ? id : (hoveredButton == id ? nil : hoveredButton) }
    }

    private func playButton(h: CGFloat) -> some View {
        let isHovered = hoveredButton == "play"
        return Button { nowPlaying.togglePlayPause() } label: {
            Image(systemName: nowPlaying.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(tint.opacity(isHovered ? 0.24 : 0.15 + overallEnergy * 0.08))
                        .overlay(Circle().strokeBorder(.white.opacity(isHovered ? 0.22 : 0.08), lineWidth: 0.75))
                )
                .scaleEffect(isHovered ? 1.06 : 1.0)
                .shadow(color: isHovered ? tint.opacity(0.30) : .clear, radius: 8)
                .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hoveredButton = $0 ? "play" : (hoveredButton == "play" ? nil : hoveredButton) }
    }

    // MARK: - Strip button

    private func stripButton(_ id: String, label: String? = nil, icon: String? = nil,
                              color: Color = .white.opacity(0.3), action: @escaping () -> Void) -> some View {
        let isHovered = hoveredButton == id
        return Button(action: action) {
            Group {
                if let label {
                    Text(label)
                        .font(.etherValue(6, weight: .bold))
                        .foregroundColor(isHovered ? .white.opacity(0.8) : color)
                } else if let icon {
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

    // MARK: - Energy tracking

    private var energyTracker: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !engine.postSpectrum.isActive)) { _ in
            Color.clear
                .onAppear { updateEnergy() }
                .onChange(of: engine.postSpectrum.magnitudes.first) { _, _ in updateEnergy() }
        }
        .allowsHitTesting(false)
    }

    private func updateEnergy() {
        let bins = engine.postSpectrum.magnitudes
        guard bins.count > 8 else { return }
        let allAvg = bins.reduce(Float(0), +) / Float(bins.count)
        let allMag = CGFloat(max(0, min(1, (allAvg + 55) / 35)))
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
